extends Node
## Store prices, purchases, restore, and promo unlocks.
## Tests replace `store`. Prices come from the store and are never hard-coded.

const CREDIT := "orehruoy.sewlens.credit"
const UNLIMITED := "orehruoy.sewlens.unlimited"
const PRICE_TIMEOUT := 15.0
## The Play or App Store sheet stays open while the person confirms a purchase.
const SHEET_TIMEOUT := 600.0

var store: Object
var prices := {}
var credits := 0
var unlimited := false
## "idle", "loading", "ready" or "failed", so screens can show a placeholder or a retry.
var price_state := "idle"
## Turn this off before release. While it is on, a failed price load shows the store's own error.
var show_price_diagnostic := true
var price_diagnostic := ""

signal updated


func _ready() -> void:
	if store == null:
		var native := NativeStore.new()
		native.name = "NativeStore"
		add_child(native)
		store = native


func price_text(product_id: String) -> String:
	return str(prices.get(product_id, ""))


func refresh_prices() -> void:
	if store == null:
		return
	if prices.is_empty():
		price_state = "loading"
		updated.emit()
	var loaded: Dictionary = await store.load_prices()
	var got: Dictionary = loaded.get("prices", {}) if loaded.get("ok", false) else {}
	var invalid := _id_list(loaded.get("unfetchedProductIds", []))
	if invalid.is_empty():
		invalid = _id_list(loaded.get("invalidProductIds", []))
	var none_returned: bool = loaded.has("productCount") and int(loaded.get("productCount", -1)) == 0
	var failed: bool = got.is_empty() or not invalid.is_empty() or not bool(loaded.get("ok", false)) or none_returned
	if failed:
		price_diagnostic = diagnostic_line(loaded)
		_log_billing_error(loaded)
	else:
		price_diagnostic = ""
	if not got.is_empty() and not none_returned:
		prices = got
		price_state = "ready"
	elif prices.is_empty():
		price_state = "failed"
	updated.emit()


func buy(product_id: String, api: ApiClient) -> Dictionary:
	var receipt: Dictionary = await store.purchase(product_id)
	if not receipt.get("ok", false):
		return receipt
	return await _verify(api, receipt)


func restore(api: ApiClient) -> Dictionary:
	var found: Dictionary = await store.restore()
	if not found.get("ok", false):
		return found
	var receipts: Array = found.get("receipts", [])
	if receipts.is_empty():
		return {"ok": true, "empty": true}
	var last := {"ok": true}
	for receipt in receipts:
		if typeof(receipt) != TYPE_DICTIONARY:
			continue
		last = await _verify(api, receipt)
		if not last.get("ok", false):
			return last
	return last


func redeem(code: String, api: ApiClient) -> Dictionary:
	var result: Dictionary = await api.redeem_promo(code)
	if result.get("ok", false):
		_remember(result)
		NativeBridge.log_event("purchase", {"product": "promo"})
	return result


func _verify(api: ApiClient, receipt: Dictionary) -> Dictionary:
	var result: Dictionary = await api.verify_purchase(receipt)
	if result.get("ok", false):
		_remember(result)
		if not bool(receipt.get("revoked", false)):
			NativeBridge.log_event("purchase", {"product": str(receipt.get("productId", ""))})
		var transaction := str(receipt.get("transactionId", ""))
		if transaction != "":
			store.finish(transaction)
	return result


func diagnostic_line(loaded: Dictionary) -> String:
	var valid := _ids_text(loaded.get("validProductIds", []))
	var invalid := _ids_text(loaded.get("unfetchedProductIds", []))
	if invalid == "":
		invalid = _ids_text(loaded.get("invalidProductIds", []))
	if invalid == "" and not loaded.get("ok", true):
		invalid = _ids_text(loaded.get("productIds", [CREDIT, UNLIMITED]))
	var parts: PackedStringArray = [
		str(loaded.get("platform", _store_platform())),
		str(loaded.get("stage", "query")),
		str(loaded.get("responseCode", loaded.get("error", loaded.get("status", "")))),
		str(loaded.get("message", loaded.get("error", ""))),
		"valid: " + (valid if valid != "" else "none"),
		"invalid: " + (invalid if invalid != "" else "none"),
	]
	if loaded.has("productCount"):
		parts.append("count: " + str(int(loaded.get("productCount", 0))))
	if str(loaded.get("bundleId", "")) != "":
		parts.append("bundle: " + str(loaded.get("bundleId", "")))
	return " · ".join(parts)


func _log_billing_error(loaded: Dictionary) -> void:
	var ids = loaded.get("unfetchedProductIds", [])
	if _id_list(ids).is_empty():
		ids = loaded.get("invalidProductIds", [])
	if _id_list(ids).is_empty():
		ids = loaded.get("productIds", [CREDIT, UNLIMITED])
	var code = loaded.get("responseCode", loaded.get("error", loaded.get("status", "unavailable")))
	var message := str(loaded.get("message", loaded.get("error", "")))
	var params := {
		"platform": str(loaded.get("platform", _store_platform())),
		"stage": str(loaded.get("stage", "query")),
		"response_code": str(code),
		"message": message.substr(0, 100),
		"product_ids": _ids_text(ids),
		"valid_ids": _ids_text(loaded.get("validProductIds", [])),
		"invalid_ids": _ids_text(ids),
	}
	if loaded.has("productCount"):
		params["product_count"] = int(loaded.get("productCount", 0))
	if str(loaded.get("bundleId", "")) != "":
		params["bundle_id"] = str(loaded.get("bundleId", ""))
	print("SewLens billing_error %s" % JSON.stringify(params))
	NativeBridge.log_event("billing_error", params)


static func _store_platform() -> String:
	if OS.has_feature("ios") or OS.get_name() == "iOS":
		return "ios"
	if OS.has_feature("android") or OS.get_name() == "Android":
		return "android"
	return OS.get_name().to_lower()


static func _id_list(value) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


static func _ids_text(value) -> String:
	var parts: PackedStringArray = []
	for item in _id_list(value):
		parts.append(str(item))
	return ",".join(parts)


func _remember(result: Dictionary) -> void:
	credits = int(result.get("credits", 0))
	unlimited = bool(result.get("unlimited", false))
	Profile.remember_entitlement(credits, unlimited)
	updated.emit()


class NativeStore extends Node:
	var _generation := 0

	func load_prices() -> Dictionary:
		var payload := await _request("products", {}, Billing.PRICE_TIMEOUT)
		var status := str(payload.get("status", ""))
		var result := {
			"ok": status == "ok" and int(payload.get("productCount", 1)) != 0,
			"prices": payload.get("prices", {}),
			"platform": str(payload.get("platform", Billing._store_platform())),
			"stage": str(payload.get("stage", "query")),
			"responseCode": payload.get("responseCode", ""),
			"message": str(payload.get("message", "")),
			"productIds": payload.get("productIds", [Billing.CREDIT, Billing.UNLIMITED]),
			"unfetchedProductIds": payload.get("unfetchedProductIds", []),
			"invalidProductIds": payload.get("invalidProductIds", []),
			"validProductIds": payload.get("validProductIds", []),
			"bundleId": str(payload.get("bundleId", "")),
			"error": "",
		}
		if payload.has("productCount"):
			result["productCount"] = int(payload.get("productCount", 0))
		if status != "ok":
			result.ok = false
			result.error = status if status != "" else "unavailable"
			if str(result.responseCode) == "":
				result.responseCode = result.error
			if str(result.message) == "":
				result.message = str(result.error)
		return result

	func purchase(product_id: String) -> Dictionary:
		var payload := await _request("purchase", {"productId": product_id}, Billing.SHEET_TIMEOUT)
		return _receipt(payload)

	func restore() -> Dictionary:
		var payload := await _request("restore", {}, Billing.SHEET_TIMEOUT)
		if str(payload.get("status", "")) != "ok":
			return {"ok": false, "error": str(payload.get("status", "error"))}
		return {"ok": true, "receipts": payload.get("receipts", [])}

	func finish(transaction_id: String) -> void:
		NativeBridge.billing_request("finish", {"transactionId": transaction_id})

	func _request(action: String, extra: Dictionary = {}, timeout: float = Billing.PRICE_TIMEOUT) -> Dictionary:
		var payload := {}
		var done := false
		var generation := _generation
		var on_result := func(reply: Dictionary) -> void:
			if generation != _generation:
				return
			payload = reply
			done = true
		NativeBridge.billing_finished.connect(on_result, CONNECT_ONE_SHOT)
		NativeBridge.billing_request(action, extra)
		var waited := 0.0
		while not done and waited < timeout:
			await get_tree().create_timer(0.05).timeout
			waited += 0.05
		if done:
			return payload
		_generation += 1
		if NativeBridge.billing_finished.is_connected(on_result):
			NativeBridge.billing_finished.disconnect(on_result)
		NativeBridge.abandon_billing()
		return {
			"status": "timeout",
			"stage": "timeout",
			"platform": Billing._store_platform(),
			"responseCode": "timeout",
			"message": "timeout after 15s waiting for the store" if action == "products" else "The store did not respond",
			"productIds": [Billing.CREDIT, Billing.UNLIMITED],
			"productCount": 0,
		}

	func _receipt(payload: Dictionary) -> Dictionary:
		if str(payload.get("status", "")) != "ok":
			return {"ok": false, "error": str(payload.get("status", "error"))}
		payload["ok"] = true
		return payload
