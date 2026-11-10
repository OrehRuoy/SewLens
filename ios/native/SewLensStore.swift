import Foundation
import StoreKit
import UIKit

// StoreKit 2 for the two SewLens products. GDScript writes the same request
// file as the share/photo bridge. This file owns the billing actions and
// leaves share and photo for SewLensNative.m. Prices are Product.displayPrice.

private let sewlensCredit = "orehruoy.sewlens.credit"
private let sewlensUnlimited = "orehruoy.sewlens.unlimited"
private let sewlensRequestName = "sewlens_native_request.json"
private let sewlensBilling: Set<String> = ["products", "purchase", "restore", "finish", "offer"]

private let sewlensStoreBoot: Void = {
    DispatchQueue.main.async {
        Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            Task { await SewLensStore.poll() }
        }
    }
}()

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
        do {
            let products = try await Product.products(for: [sewlensCredit, sewlensUnlimited])
            var prices: [String: String] = [:]
            for product in products {
                prices[product.id] = product.displayPrice
            }
            write(request, ["status": "ok", "prices": prices])
        } catch {
            write(request, ["status": "error"])
        }
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
