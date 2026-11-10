extends Node
## Store prices, purchases, restore, and promo unlocks.
## Tests replace `store`. Prices come from the store and are never hard-coded.

const CREDIT := "orehruoy.sewlens.credit"
const UNLIMITED := "orehruoy.sewlens.unlimited"

var store: Object
var prices := {}
var credits := 0
var unlimited := false
## "idle", "loading", "ready" or "failed", so screens can show a placeholder or a retry.
var price_state := "idle"

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
	if loaded.get("ok", false):
		prices = loaded.get("prices", {})
		price_state = "ready" if not prices.is_empty() else "failed"
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


func _remember(result: Dictionary) -> void:
	credits = int(result.get("credits", 0))
	unlimited = bool(result.get("unlimited", false))
	Profile.remember_entitlement(credits, unlimited)
	updated.emit()


class NativeStore extends Node:
	func load_prices() -> Dictionary:
		var payload := await _request("products")
		if str(payload.get("status", "")) != "ok":
			return {"ok": false, "error": str(payload.get("status", "unavailable"))}
		return {"ok": true, "prices": payload.get("prices", {})}

	func purchase(product_id: String) -> Dictionary:
		var payload := await _request("purchase", {"productId": product_id})
		return _receipt(payload)

	func restore() -> Dictionary:
		var payload := await _request("restore")
		if str(payload.get("status", "")) != "ok":
			return {"ok": false, "error": str(payload.get("status", "error"))}
		return {"ok": true, "receipts": payload.get("receipts", [])}

	func finish(transaction_id: String) -> void:
		NativeBridge.billing_request("finish", {"transactionId": transaction_id})

	func _request(action: String, extra: Dictionary = {}) -> Dictionary:
		var payload := {}
		var done := false
		var on_result := func(reply: Dictionary) -> void:
			payload = reply
			done = true
		NativeBridge.billing_finished.connect(on_result, CONNECT_ONE_SHOT)
		NativeBridge.billing_request(action, extra)
		var waited := 0.0
		while not done and waited < 600.0:
			await get_tree().create_timer(0.05).timeout
			waited += 0.05
		if not done:
			return {"status": "error"}
		return payload

	func _receipt(payload: Dictionary) -> Dictionary:
		if str(payload.get("status", "")) != "ok":
			return {"ok": false, "error": str(payload.get("status", "error"))}
		payload["ok"] = true
		return payload
