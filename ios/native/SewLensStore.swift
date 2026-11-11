import Foundation
import StoreKit
import UIKit

// StoreKit 2 for the two SewLens products. GDScript writes the same request
// file as the share/photo bridge. This file owns the billing actions and
// leaves share and photo for SewLensNative.m. Prices are Product.displayPrice.

private let sewlensCredit = "orehruoy.sewlens.credit"
private let sewlensUnlimited = "orehruoy.sewlens.unlimited"
private let sewlensProductIds = [sewlensCredit, sewlensUnlimited]
private let sewlensRequestName = "sewlens_native_request.json"
private let sewlensBilling: Set<String> = ["products", "purchase", "restore", "finish", "offer"]

private let sewlensStoreBoot: Void = {
    DispatchQueue.main.async {
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            Task { await SewLensStore.poll() }
        }
    }
}()

// Swift globals are lazy. sln_boot in SewLensNative.m calls this, which is what
// actually starts the poller. Without that reference the timer is never created.
@_cdecl("sewlens_store_boot")
public func sewlens_store_boot() {
    _ = sewlensStoreBoot
}

enum SewLensStore {
    private static var busy = false

    static func poll() async {
        if busy { return }
        guard let path = findRequest() else { return }
        guard
            let data = FileManager.default.contents(atPath: path),
            let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let action = request["action"] as? String,
            sewlensBilling.contains(action)
        else { return }
        try? FileManager.default.removeItem(atPath: path)
        busy = true
        defer { busy = false }
        switch action {
        case "products":
            await loadProducts(request)
        case "purchase":
            await purchase(request)
        case "restore":
            await restore(request)
        case "finish":
            await finish(request)
        case "offer":
            await offer(request)
        default:
            write(request, ["status": "error"])
        }
    }

    private static func loadProducts(_ request: [String: Any]) async {
        let runningAs = Bundle.main.bundleIdentifier ?? ""
        do {
            NSLog("SewLens StoreKit bundle %@ requesting products: %@", runningAs, sewlensProductIds.joined(separator: ","))
            let products = try await Product.products(for: sewlensProductIds)
            let returned = Set(products.map(\.id))
            let valid = products.map(\.id)
            let invalid = sewlensProductIds.filter { !returned.contains($0) }
            NSLog("SewLens StoreKit returned %d products, invalid: %@", products.count, invalid.joined(separator: ","))
            var prices: [String: String] = [:]
            for product in products {
                prices[product.id] = product.displayPrice
            }
            if prices.isEmpty {
                let ids = invalid.isEmpty ? sewlensProductIds : invalid
                let message = "0 products, invalid: \(ids.joined(separator: ", "))"
                write(request, productReport("unavailable", "query", "0", message, ids, [], products.count))
                return
            }
            var payload = productReport("ok", "query", "0", invalid.isEmpty ? "" : "invalid product ids", invalid, valid, products.count)
            payload["prices"] = prices
            write(request, payload)
        } catch {
            let ns = error as NSError
            NSLog("SewLens StoreKit error domain=%@ code=%d %@", ns.domain, ns.code, ns.localizedDescription)
            var payload = productReport("error", "query", "\(ns.domain)/\(ns.code)", ns.localizedDescription, sewlensProductIds, [], 0)
            payload["domain"] = ns.domain
            write(request, payload)
        }
    }

    private static func productReport(_ status: String, _ stage: String, _ code: String, _ message: String, _ invalid: [String], _ valid: [String], _ count: Int) -> [String: Any] {
        return [
            "status": status,
            "stage": stage,
            "platform": "ios",
            "bundleId": Bundle.main.bundleIdentifier ?? "",
            "responseCode": code,
            "message": message,
            "productCount": count,
            "productIds": invalid,
            "invalidProductIds": invalid,
            "unfetchedProductIds": invalid,
            "validProductIds": valid,
        ]
    }

    private static func purchase(_ request: [String: Any]) async {
        let productId = request["productId"] as? String ?? ""
        do {
            guard let product = try await Product.products(for: [productId]).first else {
                write(request, ["status": "unavailable"])
                return
            }
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    write(request, ["status": "error"])
                    return
                }
                write(request, receiptFields(transaction, verification.jwsRepresentation, "ok"))
            case .userCancelled:
                write(request, ["status": "cancelled"])
            case .pending:
                write(request, ["status": "error"])
            @unknown default:
                write(request, ["status": "error"])
            }
        } catch {
            write(request, ["status": "error"])
        }
    }

    private static func restore(_ request: [String: Any]) async {
        var receipts: [[String: Any]] = []
        for await result in Transaction.all {
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID != sewlensCredit && transaction.productID != sewlensUnlimited { continue }
            receipts.append(receiptFields(transaction, result.jwsRepresentation, "ok"))
        }
        write(request, ["status": "ok", "receipts": receipts])
    }

    private static func finish(_ request: [String: Any]) async {
        let transactionId = request["transactionId"] as? String ?? ""
        for await result in Transaction.unfinished {
            guard case .verified(let transaction) = result else { continue }
            if String(transaction.id) == transactionId {
                await transaction.finish()
            }
        }
        write(request, ["status": "ok"])
    }

    private static func offer(_ request: [String: Any]) async {
        guard #available(iOS 16.0, *) else {
            write(request, ["status": "unavailable"])
            return
        }
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        guard let scene else {
            write(request, ["status": "unavailable"])
            return
        }
        do {
            try await AppStore.presentOfferCodeRedeemSheet(in: scene)
            write(request, ["status": "ok"])
        } catch {
            write(request, ["status": "error"])
        }
    }

    private static func receiptFields(_ transaction: Transaction, _ jws: String, _ status: String) -> [String: Any] {
        return [
            "status": status,
            "platform": "ios",
            "productId": transaction.productID,
            "transactionId": String(transaction.id),
            "signedTransaction": jws,
            "revoked": transaction.revocationDate != nil,
        ]
    }

    private static func write(_ request: [String: Any], _ fields: [String: Any]) {
        guard let path = request["result"] as? String, !path.isEmpty else { return }
        var payload = fields
        payload["id"] = request["id"] ?? 0
        payload["action"] = request["action"] ?? ""
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        let temporary = path + ".tmp"
        FileManager.default.createFile(atPath: temporary, contents: data)
        try? FileManager.default.removeItem(atPath: path)
        try? FileManager.default.moveItem(atPath: temporary, toPath: path)
    }

    private static func findRequest() -> String? {
        let directories = [
            NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first ?? "",
            NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first ?? "",
        ]
        for directory in directories where !directory.isEmpty {
            let direct = (directory as NSString).appendingPathComponent(sewlensRequestName)
            if FileManager.default.fileExists(atPath: direct) { return direct }
        }
        for directory in directories where !directory.isEmpty {
            if let found = walk(directory, 4) { return found }
        }
        return nil
    }

    private static func walk(_ directory: String, _ depth: Int) -> String? {
        if depth < 0 { return nil }
        let url = URL(fileURLWithPath: directory)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return nil }
        for name in names {
            let path = url.appendingPathComponent(name).path
            if name == sewlensRequestName { return path }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                if let found = walk(path, depth - 1) { return found }
            }
        }
        return nil
    }
}
