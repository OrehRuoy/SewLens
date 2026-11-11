extends GutTest
## Mocked store: the free pattern, a credit, unlimited, restore, and a refund.
## The paywall shows the store's price string and never a hard-coded dollar price.

const Fixture := preload("res://test/support/screen_fixture.gd")


class MockStore:
	extends RefCounted
	var prices := {
		"orehruoy.sewlens.credit": "2,99 €",
		"orehruoy.sewlens.unlimited": "24,99 €",
	}
	var purchase_result := {"ok": false, "error": "cancelled"}
	var restore_result := {"ok": true, "receipts": []}
	var finished: Array = []

	func load_prices() -> Dictionary:
		return {"ok": true, "prices": prices}

	func purchase(_product_id: String) -> Dictionary:
		return purchase_result

	func restore() -> Dictionary:
		return restore_result

	func finish(transaction_id: String) -> void:
		finished.append(transaction_id)


var store: MockStore


func before_each() -> void:
	store = MockStore.new()
	Billing.store = store
	Billing.prices = {}
	Billing.credits = 0
	Billing.unlimited = false
	Fixture.prepare_profile()
	TranslationServer.set_locale("en")


func after_each() -> void:
	Billing.prices = {}
	Billing.credits = 0
	Billing.unlimited = false
	Billing.store = Billing.get_node_or_null("NativeStore")
	Fixture.restore_profile()
	TranslationServer.set_locale("en")


func test_paywall_shows_the_store_price() -> void:
	var main := Fixture.make_main(self)
	Fixture.open(main, ["paywall", {}])
	await _frames(4)
	var texts := Fixture.visible_texts(main)
	assert_has(texts, "2,99 €")
	assert_has(texts, "24,99 €")
	assert_has(texts, "Creator code")
	for text in texts:
		assert_eq(text.contains("$"), false, text)
	main.queue_free()


func test_free_cap_offers_the_paywall() -> void:
	var main := _draft_main()
	main.api.transport.queue_error("RESOURCE_EXHAUSTED", "free pattern already used", 429)
	main.go("draft", {"autostart": true}, true)
	await _frames(4)
	var patterns := main.find_child("PatternsButton", true, false) as Button
	var retry := main.find_child("RetryButton", true, false) as Button
	assert_true(patterns.visible)
	assert_false(retry.visible)
	main.queue_free()


func test_a_credit_is_verified_and_the_draft_retries() -> void:
	var main := _draft_main()
	main.go("draft", {"autostart": false}, true)
	main.session.awaiting_purchase = true
	store.purchase_result = {
		"ok": true,
		"platform": "ios",
		"productId": Billing.CREDIT,
		"transactionId": "tx-credit",
		"signedTransaction": "fix.credit",
	}
	main.api.transport.queue_result({"patternCount": 1, "credits": 1, "unlimited": false})
	main.api.transport.queue_result({"design": "aaron", "paper": "a4", "svg": "", "labels": {"pieces": []}, "yardage": []})
	main.go("paywall")
	await _frames(2)
	(main.find_child("BuyCredit", true, false) as Button).pressed.emit()
	await _frames(8)
	assert_eq(Billing.credits, 1)
	assert_eq(store.finished, ["tx-credit"])
	var sent: Dictionary = main.api.transport.requests[0].body.data
	assert_eq(sent.receipt.transactionId, "tx-credit")
	assert_string_starts_with(str(sent.installId), "install")
	assert_false(main.session.has("awaiting_purchase"))
	main.queue_free()


func test_unlimited_restore_and_refund() -> void:
	var main := Fixture.make_main(self)
	Fixture.open(main, ["paywall", {}])
	await _frames(2)
	store.restore_result = {"ok": true, "receipts": [{
		"platform": "android",
		"productId": Billing.UNLIMITED,
		"transactionId": "GPA.1",
		"purchaseToken": "token-1",
		"revoked": false,
	}]}
	main.api.transport.queue_result({"patternCount": 1, "credits": 0, "unlimited": true})
	(main.find_child("RestoreButton", true, false) as Button).pressed.emit()
	await _frames(6)
	assert_true(Billing.unlimited)
	assert_eq(main.api.transport.requests[0].body.data.receipt.purchaseToken, "token-1")
	store.restore_result = {"ok": true, "receipts": [{
		"platform": "android",
		"productId": Billing.UNLIMITED,
		"transactionId": "GPA.1",
		"purchaseToken": "token-1",
		"revoked": true,
	}]}
	main.api.transport.queue_result({"patternCount": 1, "credits": 0, "unlimited": false})
	(main.find_child("RestoreButton", true, false) as Button).pressed.emit()
	await _frames(6)
	assert_false(Billing.unlimited)
	assert_has(Fixture.visible_texts(main), "That purchase was refunded.")
	main.queue_free()


func test_pattern_credit_balance_shows_zero_three_and_unlimited() -> void:
	var main := Fixture.make_main(self)
	Profile.successful_patterns = 0
	Profile.known_credits = 0
	Profile.known_unlimited = false
	Fixture.open(main, ["paywall", {}])
	await _frames(2)
	var balance := main.find_child("CreditBalance", true, false) as Label
	assert_false(balance.visible)
	assert_has(Fixture.visible_texts(main), "Your first pattern is free. Choose how you want to make more.")
	Profile.successful_patterns = 1
	Profile.save()
	await _frames(2)
	assert_true(balance.visible)
	assert_eq(balance.text, "Pattern credits: 0")
	store.purchase_result = {
		"ok": true,
		"platform": "android",
		"productId": Billing.CREDIT,
		"transactionId": "tx-three",
		"purchaseToken": "token-three",
	}
	main.api.transport.queue_result({"patternCount": 1, "credits": 3, "unlimited": false})
	(main.find_child("BuyCredit", true, false) as Button).pressed.emit()
	await _frames(8)
	assert_eq(balance.text, "Pattern credits: 3")
	Profile.note_successful_pattern()
	await _frames(2)
	assert_eq(balance.text, "Pattern credits: 2")
	Profile.remember_entitlement(0, true)
	Billing.unlimited = true
	Billing.credits = 0
	Billing.updated.emit()
	await _frames(2)
	assert_eq(balance.text, "Unlimited")
	main.queue_free()


func test_a_creator_code_is_sent_to_the_server() -> void:
	var main := Fixture.make_main(self)
	Fixture.open(main, ["paywall", {}])
	await _frames(2)
	main.api.transport.queue_result({"patternCount": 0, "credits": 0, "unlimited": true})
	(main.find_child("PromoCode", true, false) as LineEdit).text = "creator"
	(main.find_child("RedeemButton", true, false) as Button).pressed.emit()
	await _frames(6)
	assert_eq(main.api.transport.last_data().code, "creator")
	assert_true(Billing.unlimited)
	main.queue_free()


func _draft_main() -> Control:
	var main := Fixture.make_main(self)
	main.session = Fixture.session()
	main.session.erase("draft")
	return main


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame
