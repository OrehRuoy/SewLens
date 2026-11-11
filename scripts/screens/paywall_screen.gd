extends Screen
## Buys a pattern credit or unlimited, restores purchases, and redeems a creator code.
## The price labels use the store string only; until it arrives they show a dash.

const MARK := preload("res://assets/branding/logo_mark_256.png")
const PRICE_PLACEHOLDER := "—"


func title_key() -> String:
	return "title_paywall"


func shows_back() -> bool:
	return true


func enter(_params: Dictionary) -> void:
	NativeBridge.log_event("paywall_shown", {})
	var page := build_page()
	var mark := TextureRect.new()
	mark.texture = MARK
	mark.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.custom_minimum_size = Vector2(0, 64)
	page.add_child(mark)
	var heading := UI.heading(tr("pay_heading"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(heading)
	var body := UI.caption(tr("pay_body"))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(body)
	var entitlement := UI.notice_label()
	entitlement.name = "Entitlement"
	page.add_child(entitlement)

	var loading := UI.spinner(tr("pay_price_loading"))
	loading.name = "PriceLoading"
	loading.visible = false
	page.add_child(loading)
	var live := UI.caption("")
	live.name = "PriceStage"
	live.add_theme_font_size_override("font_size", 13)
	live.add_theme_color_override("font_color", Color(0.4, 0.43, 0.47))
	live.visible = false
	page.add_child(live)
	var failed := UI.card()
	failed.add_child(UI.bullet(tr("pay_prices_failed"), "alert"))
	var diagnostic := UI.caption("")
	diagnostic.name = "PriceDiagnostic"
	diagnostic.add_theme_font_size_override("font_size", 13)
	diagnostic.add_theme_color_override("font_color", Color(0.4, 0.43, 0.47))
	diagnostic.visible = false
	failed.add_child(diagnostic)
	var copy := UI.flat_button("Copy", "TextLink")
	copy.name = "PriceDiagnosticCopy"
	copy.visible = false
	copy.pressed.connect(func() -> void: DisplayServer.clipboard_set(Billing.price_diagnostic))
	failed.add_child(copy)
	var retry := UI.flat_button(tr("btn_retry"), "TextLink")
	retry.name = "PricesRetry"
	retry.pressed.connect(func() -> void: Billing.refresh_prices())
	failed.add_child(retry)
	var failed_panel := UI.card_panel(failed)
	failed_panel.name = "PricesFailed"
	failed_panel.visible = false
	page.add_child(failed_panel)

	page.add_child(_product("Credit", tr("pay_credit"), tr("pay_credit_kind"), ["pay_credit_point1", "pay_credit_point2"], _buy_credit))
	page.add_child(_product("Unlimited", tr("pay_unlimited"), tr("pay_unlimited_kind"), ["pay_unlimited_point1", "pay_unlimited_point2", "pay_unlimited_point3"], _buy_unlimited))

	var status := UI.notice_label()
	status.name = "PayStatus"
	page.add_child(status)
	var error := UI.error_label()
	error.name = "PayError"
	page.add_child(error)
	var restore := UI.icon_button(tr("btn_restore"), "restore")
	restore.name = "RestoreButton"
	restore.pressed.connect(_restore)
	page.add_child(restore)

	page.add_child(UI.spacer(4))
	var promo := UI.card()
	var promo_title := UI.row(10)
	promo_title.add_child(LineIcon.new("tag", UI.GOLD))
	var promo_label := UI.label(tr("pay_promo_heading"), "TitleLabel")
	promo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	promo_title.add_child(promo_label)
	promo.add_child(promo_title)
	var entry := _flow_row(10)
	var code := LineEdit.new()
	code.name = "PromoCode"
	code.placeholder_text = tr("pay_promo_placeholder")
	code.custom_minimum_size = Vector2(0, UI.button_height())
	code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code.size_flags_stretch_ratio = 3.0
	entry.add_child(code)
	var redeem := UI.button(tr("btn_redeem"))
	redeem.name = "RedeemButton"
	redeem.autowrap_mode = TextServer.AUTOWRAP_OFF
	redeem.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	redeem.pressed.connect(func() -> void: _redeem(code.text))
	entry.add_child(redeem)
	promo.add_child(entry)
	if OS.has_feature("ios"):
		var offer := UI.flat_button(tr("btn_offer_code"), "TextLink")
		offer.name = "OfferButton"
		offer.pressed.connect(func() -> void: NativeBridge.billing_request("offer"))
		promo.add_child(offer)
	page.add_child(UI.card_panel(promo))

	var legal := UI.caption(tr("pay_legal"))
	legal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(legal)
	var links := VBoxContainer.new()
	links.add_theme_constant_override("separation", 0)
	var terms := UI.link(tr("link_terms"), UI.TERMS_URL)
	terms.name = "TermsLink"
	links.add_child(terms)
	var privacy := UI.link(tr("btn_privacy_policy"), UI.PRIVACY_URL)
	privacy.name = "PrivacyLink"
	links.add_child(privacy)
	page.add_child(links)

	if not Billing.updated.is_connected(_refresh):
		Billing.updated.connect(_refresh)
	_refresh()
	Billing.refresh_prices()


## A row that moves its last item onto a new line when long text (German, Larger text) needs the width.
func _flow_row(separation: int) -> HFlowContainer:
	var node := HFlowContainer.new()
	node.add_theme_constant_override("h_separation", separation)
	node.add_theme_constant_override("v_separation", 8)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


func _product(node_name: String, title: String, kind: String, points: Array, handler: Callable) -> Control:
	var card := UI.card()
	card.name = node_name + "Card"
	card.add_theme_constant_override("separation", 10)
	var top := _flow_row(12)
	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.add_theme_constant_override("separation", 6)
	names.add_child(UI.label(title, "TitleLabel"))
	names.add_child(UI.badge(kind))
	top.add_child(names)
	var price := Label.new()
	price.name = node_name + "Price"
	price.theme_type_variation = "PriceLabel"
	price.text = PRICE_PLACEHOLDER
	price.size_flags_horizontal = Control.SIZE_SHRINK_END
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(price)
	card.add_child(top)
	card.add_child(UI.divider())
	for point in points:
		card.add_child(UI.bullet(tr(point)))
	var buy := UI.button(tr("btn_buy"), true)
	buy.name = "Buy" + node_name
	buy.disabled = true
	buy.pressed.connect(handler)
	card.add_child(buy)
	return UI.card_panel(card)


func _refresh() -> void:
	if not is_inside_tree():
		return
	_price("Credit", Billing.CREDIT)
	_price("Unlimited", Billing.UNLIMITED)
	var state := Billing.price_state
	(find_child("PriceLoading", true, false) as Control).visible = state == "loading"
	(find_child("PricesFailed", true, false) as Control).visible = state == "failed"
	var diagnostic := find_child("PriceDiagnostic", true, false) as Label
	var copy := find_child("PriceDiagnosticCopy", true, false) as Button
	var show_detail := Billing.show_price_diagnostic and state == "failed" and Billing.price_diagnostic != ""
	if diagnostic:
		diagnostic.text = Billing.price_diagnostic
		diagnostic.visible = show_detail
	if copy:
		copy.visible = show_detail
	var live := find_child("PriceStage", true, false) as Label
	if live:
		live.text = Billing.price_diagnostic
		live.visible = Billing.show_price_diagnostic and state == "loading" and Billing.price_diagnostic != ""
	var entitlement := find_child("Entitlement", true, false) as Label
	var text := ""
	if Billing.unlimited:
		text = tr("pay_status_unlimited")
	elif Billing.credits > 0:
		text = tr("pay_status_credits") % Billing.credits
	elif Profile.successful_patterns >= 1:
		text = tr("pay_status_used")
	entitlement.text = text
	entitlement.visible = text != ""
	var unlimited_buy := find_child("BuyUnlimited", true, false) as Button
	if Billing.unlimited:
		unlimited_buy.disabled = true


func _price(node_name: String, product_id: String) -> void:
	var label := find_child(node_name + "Price", true, false) as Label
	var buy := find_child("Buy" + node_name, true, false) as Button
	if label == null:
		return
	var text := Billing.price_text(product_id)
	label.text = text if text != "" else PRICE_PLACEHOLDER
	if buy:
		buy.disabled = text == ""


func _buy_credit() -> void:
	await _buy(Billing.CREDIT)


func _buy_unlimited() -> void:
	await _buy(Billing.UNLIMITED)


func _buy(product_id: String) -> void:
	var result: Dictionary = await Billing.buy(product_id, router.api)
	if result.get("ok", false):
		_done("pay_bought")
	else:
		_fail(result)


func _restore() -> void:
	var result: Dictionary = await Billing.restore(router.api)
	if result.get("empty", false):
		_note("pay_nothing")
	elif result.get("ok", false):
		_done("pay_restored" if Billing.unlimited or Billing.credits > 0 else "pay_revoked")
	else:
		_fail(result)


func _redeem(code: String) -> void:
	var result: Dictionary = await Billing.redeem(code, router.api)
	if result.get("ok", false):
		_done("pay_bought")
	else:
		_fail(result)


func _done(key: String) -> void:
	_note(key)
	if session().get("awaiting_purchase", false):
		session().retry_draft = true
		session().erase("awaiting_purchase")
		router.back()


func _note(key: String) -> void:
	var status := find_child("PayStatus", true, false) as Label
	if status:
		status.text = tr(key)
		status.visible = key != ""
	show_error(find_child("PayError", true, false), "")


func _fail(result: Dictionary) -> void:
	var key := "err_pay_code" if str(result.get("error", "")) == "input" else "err_pay_verify"
	if str(result.get("error", "")) == "cancelled":
		key = ""
	show_error(find_child("PayError", true, false), key)
