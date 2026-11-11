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
## Debug builds can show the store's own error. Release exports never do.
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


## The line under "Prices unavailable", and the live stage line while prices load.
## A release export passes debug_build false, so the line stays hidden even if the flag is on.
static func price_diagnostic_allowed(debug_build: bool, enabled: bool, state: String, line: String, loading: bool) -> bool:
	if not debug_build or not enabled or line == "":
		return false
	if loading:
		return state == "loading"
	return state == "failed"


## The balance Settings and the Patterns screen both show.
func pattern_credits() -> int:
	return maxi(credits, Profile.known_credits)


func has_unlimited() -> bool:
	return unlimited or Profile.known_unlimited


func refresh_prices() -> void:
	if store == null:
		return
	if prices.is_empty():
		price_diagnostic = ""
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


func note_billing_progress(loaded: Dictionary) -> void:
	price_diagnostic = diagnostic_line(loaded)
	updated.emit()


## Grants any Play purchase that is still owned. A credit is consumed only after this succeeds.
func recover_owned(api: ApiClient) -> void:
	if store == null:
		return
	await restore(api)


func buy(product_id: String, api: ApiClient) -> Dictionary:
	var receipt: Dictionary = await store.purchase(product_id)
	if not receipt.get("ok", false):
		_log_billing_error(receipt)
		return receipt
	return await _verify(api, receipt)


func restore(api: ApiClient) -> Dictionary:
	var found: Dictionary = await store.restore()
	if not found.get("ok", false):
		_log_billing_error(found)
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
	var product := str(receipt.get("productId", ""))
	if result.get("ok", false):
		_remember(result)
		NativeBridge.log_event("purchase_granted", {"product": product})
		if not bool(receipt.get("revoked", false)):
			NativeBridge.log_event("purchase", {"product": product})
		var transaction := str(receipt.get("transactionId", ""))
		if transaction != "" and store != null:
			store.finish(transaction)
	else:
		var reason := str(result.get("message", result.get("error", "verify")))
		NativeBridge.log_event("purchase_grant_failed", {"product": product, "error": reason.substr(0, 100)})
	return result


func diagnostic_line(loaded: Dictionary) -> String:
	var valid := _ids_text(loaded.get("validProductIds", []))
	var invalid := _ids_text(loaded.get("unfetchedProductIds", []))
	if invalid == "":
		invalid = _ids_text(loaded.get("invalidProductIds", []))
	if invalid == "" and not loaded.get("ok", true):
		invalid = _ids_text(loaded.get("productIds", [CREDIT, UNLIMITED]))
	var code := str(loaded.get("responseCode", loaded.get("error", loaded.get("status", ""))))
	var code_name := str(loaded.get("responseName", ""))
	if code_name != "" and not code.contains(code_name):
		code = code + " " + code_name
	var parts: PackedStringArray = [
		str(loaded.get("platform", _store_platform())),
		str(loaded.get("stage", "query")),
		code,
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
	if str(loaded.get("responseName", "")) != "":
		params["response_name"] = str(loaded.get("responseName", ""))
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
		var prices := Billing._store_prices(payload)
		var result := {
			"ok": status == "ok" and int(payload.get("productCount", 1)) != 0 and not prices.is_empty(),
			"prices": prices,
			"platform": str(payload.get("platform", Billing._store_platform())),
			"stage": str(payload.get("stage", "query")),
			"responseCode": payload.get("responseCode", ""),
			"responseName": str(payload.get("responseName", "")),
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
		# A lambda captures bool and Dictionary by value. The reply object is shared,
		# so the signal can finish this wait instead of leaving it to time out.
		var reply := _Reply.new()
		var generation := _generation
		var on_result := func(payload: Dictionary) -> void:
			if generation != _generation:
				return
			reply.accept(payload)
		NativeBridge.billing_finished.connect(on_result, CONNECT_ONE_SHOT)
		NativeBridge.billing_request(action, extra)
		var waited := 0.0
		while not reply.done and waited < timeout:
			await get_tree().create_timer(0.05).timeout
			waited += 0.05
			if not reply.done:
				reply.accept(Billing.finished_store_result(NativeBridge.billing_trace))
		if not reply.done:
			await get_tree().process_frame
			reply.accept(Billing.finished_store_result(NativeBridge.billing_trace))
		if NativeBridge.billing_finished.is_connected(on_result):
			NativeBridge.billing_finished.disconnect(on_result)
		if reply.done:
			return reply.payload
		_generation += 1
		NativeBridge.abandon_billing()
		return Billing.timeout_result(action, NativeBridge.billing_trace)

	class _Reply:
		extends RefCounted
		var done := false
		var payload: Dictionary = {}

		func accept(next: Dictionary) -> void:
			if done or next.is_empty():
				return
			payload = next
			done = true

	func _receipt(payload: Dictionary) -> Dictionary:
		if str(payload.get("status", "")) != "ok":
			var failed := payload.duplicate()
			failed["ok"] = false
			failed["error"] = str(payload.get("message", payload.get("status", "error")))
			return failed
		payload["ok"] = true
		return payload


## A StoreKit or Play result that should end the price wait. Progress updates do not.
static func finished_store_result(payload: Dictionary) -> Dictionary:
	var status := str(payload.get("status", ""))
	if status == "" or status == "progress":
		return {}
	return payload


## Product id to the store's localized displayPrice. Also accepts a products list.
static func _store_prices(payload: Dictionary) -> Dictionary:
	var found := {}
	var prices = payload.get("prices", {})
	if typeof(prices) == TYPE_DICTIONARY:
		for key in prices.keys():
			var amount := str(prices[key]).strip_edges()
			if str(key) != "" and amount != "":
				found[str(key)] = amount
	var products = payload.get("products", [])
	if typeof(products) == TYPE_ARRAY:
		for item in products:
			if typeof(item) != TYPE_DICTIONARY:
				continue
			var product_id := str(item.get("id", item.get("productId", ""))).strip_edges()
			var amount := str(item.get("displayPrice", item.get("price", ""))).strip_edges()
			if product_id != "" and amount != "":
				found[product_id] = amount
	return found


static func timeout_result(action: String, trace: Dictionary) -> Dictionary:
	var platform := str(trace.get("platform", _store_platform()))
	var stage := str(trace.get("stage", ""))
	if stage == "":
		if platform == "ios" and action == "products":
			stage = "native_missing"
		else:
			stage = "connecting" if action == "products" else "timeout"
	var message := str(trace.get("message", ""))
	var code := str(trace.get("responseCode", ""))
	if code == "":
		code = "native_missing" if stage == "native_missing" else "timeout"
	if platform == "ios" and action == "products":
		if stage == "native_missing" and message in ["", "waiting for SewLensStore"]:
			message = "SewLensStore poller never started"
		elif stage == "native_missing" and message == "poller booted, waiting for the request to be read":
			message = "poller booted but did not read the product request"
		elif stage == "requesting" and message in ["", "Product.products"]:
			message = "StoreKit Product.products did not return"
		elif stage == "response_received" and (message == "" or message.begins_with("count ")):
			message = "StoreKit responded but the result was not parsed"
	else:
		var service_note := ""
		var services_at := message.find("services=")
		if services_at >= 0:
			service_note = message.substr(services_at).strip_edges()
			message = message.substr(0, services_at).strip_edges()
		if message in ["", "calling startConnection", "startConnection", "Play Billing connected", "Play Billing already connected", "queryProductDetailsAsync"]:
			if action == "products" and stage == "connecting":
				message = "setup timeout, onBillingSetupFinished never called"
				if service_note != "":
					message += " (" + service_note + ")"
			elif action == "products":
				message = "timeout after 15s waiting for the store"
			else:
				message = "The store did not respond"
		elif service_note != "":
			message = message + " " + service_note
	return {
		"status": "timeout",
		"stage": stage,
		"platform": platform,
		"responseCode": code,
		"responseName": str(trace.get("responseName", "")),
		"message": message,
		"productIds": trace.get("productIds", [CREDIT, UNLIMITED]),
		"productCount": int(trace.get("productCount", 0)),
		"validProductIds": trace.get("validProductIds", []),
		"unfetchedProductIds": trace.get("unfetchedProductIds", []),
		"invalidProductIds": trace.get("invalidProductIds", []),
		"bundleId": str(trace.get("bundleId", "")),
	}
