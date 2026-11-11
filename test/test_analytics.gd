extends GutTest
## Funnel events carry a locale, a language change redraws the screen,
## and the review prompt appears after the second pattern.

const Fixture := preload("res://test/support/screen_fixture.gd")
const MockTransport := preload("res://test/support/mock_transport.gd")


func before_each() -> void:
	NativeBridge.events.clear()
	Fixture.prepare_profile()
	Profile.successful_patterns = 0
	Profile.set_language("")
	Profile.set_large_text(false)
	TranslationServer.set_locale("en")


func after_each() -> void:
	Profile.set_language("")
	Profile.set_large_text(false)
	TranslationServer.set_locale("en")
	Fixture.restore_profile()


func test_funnel_events_include_locale() -> void:
	var main := Fixture.make_main(self)
	main.go("onboarding", {}, true)
	(main.find_child("SkipButton", true, false) as Button).pressed.emit()
	_assert_event("onboarding_done")
	main.session = Fixture.session()
	main.go("measure", {"keys": ["chest"], "then": "back"})
	(main.current().find_child("NextButton", true, false) as Button).pressed.emit()
	_assert_event("measure_done")
	main.go("home", {}, true)
	(main.find_child("SampleButton", true, false) as Button).pressed.emit()
	_assert_event("photo_submitted", {"source": "sample"})
	var api := ApiClient.new()
	var transport := MockTransport.new()
	api.transport = transport
	api.install_path = "user://test_analytics_install"
	add_child_autofree(api)
	transport.queue_result({"design": "aaron", "designName": "Aaron", "options": {}, "locale": "en", "latency_ms": 4})
	var picked: Dictionary = await api.pick_design(PackedByteArray([1]), "image/jpeg")
	assert_true(picked.ok)
	_assert_event("pick_design", {"design": "aaron"})
	transport.queue_result({"design": "aaron", "paper": "a4", "svg": "", "labels": {"pieces": []}, "yardage": [], "latency_ms": 5})
	var drafted: Dictionary = await api.draft_pattern("aaron", {"chest": 1000.0}, {}, "cm", "A4")
	assert_true(drafted.ok)
	_assert_event("pattern_drafted", {"design": "aaron"})
	main.session = Fixture.session()
	main.go("fit", {}, true)
	(main.find_child("Fit_chest_tight", true, false) as Button).pressed.emit()
	_assert_event("fit_feedback", {"complaint": "chest_tight"})
	main.queue_free()


func test_a_purchase_event_includes_the_product() -> void:
	var store := _Store.new()
	store.purchase_result = {"ok": true, "productId": "orehruoy.sewlens.credit", "transactionId": "tx-1"}
	Billing.store = store
	var api := ApiClient.new()
	var transport := MockTransport.new()
	api.transport = transport
	api.install_path = "user://test_analytics_install"
	add_child_autofree(api)
	transport.queue_result({"patternCount": 1, "credits": 1, "unlimited": false})
	var result: Dictionary = await Billing.buy("orehruoy.sewlens.credit", api)
	assert_true(result.ok)
	_assert_event("purchase", {"product": "orehruoy.sewlens.credit"})
	Billing.store = Billing.get_node_or_null("NativeStore")


func test_paywall_and_billing_errors_are_logged() -> void:
	var store := _Store.new()
	Billing.store = store
	Billing.prices = {}
	Billing.price_state = "idle"
	var main := Fixture.make_main(self)
	Fixture.open(main, ["paywall", {}])
	await _frames(2)
	_assert_event("paywall_shown")
	_assert_event("billing_error", {
		"platform": Billing._store_platform(),
		"response_code": "unavailable",
		"message": "",
		"product_ids": "orehruoy.sewlens.credit,orehruoy.sewlens.unlimited",
	})
	main.queue_free()
	Billing.prices = {}
	Billing.price_state = "idle"
	Billing.price_diagnostic = ""
	Billing.store = Billing.get_node_or_null("NativeStore")


func test_zero_products_logs_billing_error_and_shows_the_store_text() -> void:
	var store := _Store.new()
	store.load_result = {
		"ok": true,
		"prices": {},
		"stage": "query",
		"platform": "ios",
		"responseCode": "0",
		"message": "0 products, invalid: orehruoy.sewlens.credit, orehruoy.sewlens.unlimited",
		"productCount": 0,
		"invalidProductIds": ["orehruoy.sewlens.credit", "orehruoy.sewlens.unlimited"],
		"validProductIds": [],
		"bundleId": "com.sewlens.app",
	}
	Billing.store = store
	Billing.prices = {}
	Billing.price_state = "idle"
	var main := Fixture.make_main(self)
	Fixture.open(main, ["paywall", {}])
	await _frames(2)
	assert_eq(Billing.price_state, "failed")
	var detail := main.find_child("PriceDiagnostic", true, false) as Label
	assert_true(detail.visible)
	assert_true(detail.text.contains("0 products, invalid: orehruoy.sewlens.credit, orehruoy.sewlens.unlimited"))
	assert_true(detail.text.contains("bundle: com.sewlens.app"))
	_assert_event("billing_error", {
		"platform": "ios",
		"stage": "query",
		"response_code": "0",
		"message": "0 products, invalid: orehruoy.sewlens.credit, orehruoy.sewlens.unlimited",
		"product_count": 0,
		"bundle_id": "com.sewlens.app",
	})
	main.queue_free()
	Billing.prices = {}
	Billing.price_state = "idle"
	Billing.price_diagnostic = ""
	Billing.store = Billing.get_node_or_null("NativeStore")


func test_a_timeout_reports_the_last_billing_stage() -> void:
	NativeBridge.events.clear()
	var loaded := Billing.timeout_result("products", {"stage": "connecting", "platform": "android", "message": "calling startConnection"})
	assert_eq(loaded["stage"], "connecting")
	assert_eq(loaded["message"], "setup timeout, onBillingSetupFinished never called")
	var line := Billing.diagnostic_line(loaded)
	assert_true(line.begins_with("android · connecting · timeout"))
	assert_true(line.contains("setup timeout, onBillingSetupFinished never called"))
	var missing := {
		"ok": false,
		"stage": "plugin_missing",
		"platform": "android",
		"responseCode": "plugin_missing",
		"message": "SewLensNative singleton is not loaded",
		"productIds": ["orehruoy.sewlens.credit", "orehruoy.sewlens.unlimited"],
		"productCount": 0,
	}
	assert_true(Billing.diagnostic_line(missing).contains("plugin_missing"))
	Billing._log_billing_error(missing)
	_assert_event("billing_error", {
		"platform": "android",
		"stage": "plugin_missing",
		"response_code": "plugin_missing",
		"message": "SewLensNative singleton is not loaded",
	})


func test_an_ios_timeout_names_the_storekit_stage() -> void:
	var loaded := Billing.timeout_result("products", {"stage": "requesting", "platform": "ios", "message": "Product.products", "bundleId": "com.sewlens.app"})
	assert_eq(loaded["stage"], "requesting")
	assert_eq(loaded["message"], "StoreKit Product.products did not return")
	var line := Billing.diagnostic_line(loaded)
	assert_true(line.begins_with("ios · requesting"))
	assert_true(line.contains("StoreKit Product.products did not return"))
	assert_true(line.contains("bundle: com.sewlens.app"))
	var missing := Billing.timeout_result("products", {"stage": "native_missing", "platform": "ios", "message": "waiting for SewLensStore"})
	assert_eq(missing["message"], "SewLensStore poller never started")
	assert_eq(missing["responseCode"], "native_missing")


func test_language_switch_rerenders_the_open_screen() -> void:
	var main := Fixture.make_main(self)
	Fixture.open(main, ["home", {}])
	Profile.set_language("de")
	main.reload_current()
	await get_tree().process_frame
	var texts := Fixture.visible_texts(main)
	assert_has(texts, "Schnittmuster erstellen")
	for text in texts:
		assert_eq(Fixture.looks_like_key(text), false, text)
	main.queue_free()


func test_review_prompt_appears_after_the_second_pattern() -> void:
	var main := Fixture.make_main(self)
	main.session = Fixture.session()
	main.session.erase("draft")
	var draft := {"design": "aaron", "paper": "a4", "svg": "", "labels": {"pieces": []}, "yardage": []}
	main.api.transport.queue_result(draft)
	main.api.transport.queue_result(draft)
	main.go("draft", {"autostart": true}, true)
	await _frames(6)
	assert_null(main.find_child("ReviewCard", true, false))
	var screen: Screen = main.current()
	screen._start()
	await _frames(6)
	assert_not_null(main.find_child("ReviewCard", true, false))
	assert_has(Fixture.visible_texts(main), "Enjoying SewLens?")
	assert_eq(Profile.successful_patterns, 2)
	main.queue_free()


func test_licenses_keep_the_english_mit_notice() -> void:
	Profile.set_language("fr")
	var main := Fixture.make_main(self)
	Fixture.open(main, ["licenses", {}])
	var texts := Fixture.visible_texts(main)
	assert_has(texts, "Basé sur FreeSewing")
	assert_has(texts, "Licences open source")
	var notice := ""
	for text in texts:
		if "MIT License" in text:
			notice = text
	assert_true(notice.contains("Permission is hereby granted"))
	assert_true(notice.contains("FreeSewing"))
	var font_notice := ""
	for text in texts:
		if "SIL Open Font License" in text:
			font_notice = text
	assert_true(font_notice.contains("Copyright 2022 The Noto Project Authors"))
	assert_true(font_notice.contains("SIL OPEN FONT LICENSE Version 1.1"))
	assert_true(font_notice.contains("THE FONT SOFTWARE IS PROVIDED"))
	main.queue_free()


func _assert_event(event_name: String, expected: Dictionary = {}) -> void:
	var found := false
	for event in NativeBridge.events:
		if str(event.get("name", "")) != event_name:
			continue
		found = true
		var params: Dictionary = event.get("params", {})
		assert_eq(str(params.get("locale", "")), "en")
		for key in expected:
			assert_eq(params.get(key), expected[key])
	assert_true(found, event_name)


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame


class _Store:
	extends RefCounted
	var purchase_result := {"ok": false}
	var load_result: Dictionary = {}
	func load_prices() -> Dictionary:
		if not load_result.is_empty():
			return load_result
		return {"ok": false}
	func purchase(_product_id: String) -> Dictionary:
		return purchase_result
	func restore() -> Dictionary:
		return {"ok": true, "receipts": []}
	func finish(_transaction_id: String) -> void:
		pass
