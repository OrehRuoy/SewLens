extends GutTest
## The purchase screen is reachable from home, the draft limit and Settings,
## shows a placeholder until the store price arrives, and offers a retry when it fails.

const Fixture := preload("res://test/support/screen_fixture.gd")


class PriceStore:
	extends RefCounted
	var ok := true

	func load_prices() -> Dictionary:
		if not ok:
			return {"ok": false, "error": "unavailable"}
		return {"ok": true, "prices": {"orehruoy.sewlens.credit": "R$ 14,90", "orehruoy.sewlens.unlimited": "R$ 119,90"}}

	func purchase(_product_id: String) -> Dictionary:
		return {"ok": false, "error": "cancelled"}

	func restore() -> Dictionary:
		return {"ok": true, "receipts": []}

	func finish(_transaction_id: String) -> void:
		pass


var store: PriceStore


func before_each() -> void:
	store = PriceStore.new()
	Billing.store = store
	Billing.prices = {}
	Billing.price_state = "idle"
	Billing.credits = 0
	Billing.unlimited = false
	Fixture.prepare_profile()
	TranslationServer.set_locale("en")


func after_each() -> void:
	Billing.prices = {}
	Billing.price_state = "idle"
	Billing.store = Billing.get_node_or_null("NativeStore")
	Fixture.restore_profile()


func test_prices_fill_in_from_the_store() -> void:
	var main := Fixture.make_main(self)
	Fixture.open(main, ["paywall", {}])
	await _frames(2)
	assert_eq((main.find_child("CreditPrice", true, false) as Label).text, "R$ 14,90")
	assert_eq((main.find_child("UnlimitedPrice", true, false) as Label).text, "R$ 119,90")
	assert_false((main.find_child("BuyCredit", true, false) as Button).disabled)
	assert_false((main.find_child("PricesFailed", true, false) as Control).visible)
	assert_has(Fixture.visible_texts(main), "Pay once. No subscription.")
	main.queue_free()


func test_a_store_failure_shows_a_retry_and_no_price() -> void:
	store.ok = false
	var main := Fixture.make_main(self)
	Fixture.open(main, ["paywall", {}])
	await _frames(2)
	assert_eq(Billing.price_state, "failed")
	assert_true((main.find_child("PricesFailed", true, false) as Control).visible)
	assert_has(Fixture.visible_texts(main), "Prices unavailable, tap to retry")
	assert_eq((main.find_child("CreditPrice", true, false) as Label).text, "—")
	assert_true((main.find_child("BuyUnlimited", true, false) as Button).disabled)
	store.ok = true
	(main.find_child("PricesRetry", true, false) as Button).pressed.emit()
	await _frames(2)
	assert_eq(Billing.price_state, "ready")
	assert_false((main.find_child("PricesFailed", true, false) as Control).visible)
	main.queue_free()


func test_drags_scroll_past_buttons_and_sliders() -> void:
	var main := Fixture.make_main(self)
	Fixture.open(main, ["paywall", {}])
	var paywall: Screen = main.current()
	var scroll := paywall.get_child(0) as ScrollContainer
	assert_eq(scroll.scroll_deadzone, Screen.DRAG_DEADZONE)
	assert_eq((paywall.find_child("BuyCredit", true, false) as Button).mouse_filter, Control.MOUSE_FILTER_PASS)
	var labels: Array = paywall.find_children("*", "Label", true, false)
	assert_gt(labels.size(), 0)
	assert_eq((labels[0] as Control).mouse_filter, Control.MOUSE_FILTER_IGNORE)
	main.queue_free()
	main = Fixture.make_main(self)
	Fixture.open(main, ["result", {}])
	var sliders := main.find_children("*", "HSlider", true, false)
	assert_gt(sliders.size(), 0)
	assert_eq((sliders[0] as HSlider).mouse_filter, Control.MOUSE_FILTER_PASS)
	main.queue_free()
	main = Fixture.make_main(self)
	Fixture.open(main, ["measure", {"keys": ["chest"], "then": "back"}])
	assert_eq((main.find_child("ValueInput", true, false) as LineEdit).mouse_filter, Control.MOUSE_FILTER_STOP)
	main.queue_free()


func test_the_paywall_has_restore_and_legal_links() -> void:
	var main := Fixture.make_main(self)
	Fixture.open(main, ["paywall", {}])
	await _frames(2)
	assert_true((main.find_child("RestoreButton", true, false) as Button).is_visible_in_tree())
	assert_true((main.find_child("TermsLink", true, false) as Button).is_visible_in_tree())
	assert_true((main.find_child("PrivacyLink", true, false) as Button).is_visible_in_tree())
	main.queue_free()


func test_home_points_to_the_options_after_the_free_pattern() -> void:
	var main := Fixture.make_main(self)
	Fixture.open(main, ["home", {}])
	assert_null(main.find_child("PatternsCard", true, false))
	Profile.successful_patterns = 1
	Fixture.open(main, ["home", {}])
	(main.find_child("SeeOptionsButton", true, false) as Button).pressed.emit()
	assert_eq(main.current().name, "paywall")
	main.queue_free()


func test_a_known_credit_hides_the_home_card_until_it_is_used() -> void:
	Profile.successful_patterns = 1
	Profile.remember_entitlement(1, false)
	assert_false(Profile.needs_patterns())
	Profile.note_successful_pattern()
	assert_true(Profile.needs_patterns())
	Profile.remember_entitlement(0, true)
	assert_false(Profile.needs_patterns())


func test_settings_opens_the_purchase_screen() -> void:
	var main := Fixture.make_main(self)
	Fixture.open(main, ["settings", {}])
	(main.find_child("PatternsButton", true, false) as Button).pressed.emit()
	assert_eq(main.current().name, "paywall")
	main.queue_free()


func test_the_larger_text_switch_saves_the_setting() -> void:
	var main := Fixture.make_main(self)
	Fixture.open(main, ["settings", {}])
	var toggle := main.find_child("TextSizeButton", true, false) as Button
	assert_false(toggle.button_pressed)
	toggle.button_pressed = true
	await _frames(2)
	assert_true(Profile.large_text)
	Profile.large_text = false
	main.apply_text_size()
	main.queue_free()


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame
