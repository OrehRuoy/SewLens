extends Screen
## Calls draftPattern, previews the pieces, and shares the PDF.

const MAX_PREVIEW_SIDE := 1400.0
## Taller drawings get cream side margins, so the preview is at most 1.25 times as tall as wide.
const MAX_PREVIEW_TALL := 1.25
const API_ERRORS := {
	"network": "err_api_network",
	"unavailable": "err_api_unavailable",
	"limit": "err_api_limit",
	"input": "err_api_input",
}

var _status: Control
var _error: Label
var _retry: Button
var _patterns: Button
var _limit_card: Control
var _result_box: VBoxContainer
var _busy := false


func title_key() -> String:
	return "title_draft"


func shows_back() -> bool:
	return not _busy


func resumed() -> void:
	if session().get("redraft", false):
		session().erase("redraft")
		_start()
	elif session().get("retry_draft", false):
		session().erase("retry_draft")
		_start()


func enter(params: Dictionary) -> void:
	var page := build_page()
	page.add_child(UI.heading(DesignCatalog.display_name(str(session().get("design", "")))))
	_status = UI.spinner(tr("draft_working"))
	page.add_child(_status)
	_error = UI.error_label()
	page.add_child(_error)
	_retry = UI.icon_button(tr("btn_retry"), "replay", true)
	_retry.name = "RetryButton"
	_retry.visible = false
	_retry.pressed.connect(_start)
	page.add_child(_retry)
	var limit := UI.card()
	var limit_top := UI.row(12)
	var limit_icon := LineIcon.new("tag", UI.GOLD, 26.0)
	limit_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	limit_top.add_child(limit_icon)
	limit_top.add_child(UI.label(tr("home_out_title"), "TitleLabel"))
	limit.add_child(limit_top)
	limit.add_child(UI.label(tr("home_out_body")))
	_patterns = UI.button(tr("btn_see_options"), true)
	_patterns.name = "PatternsButton"
	_patterns.visible = false
	_patterns.pressed.connect(func() -> void:
		session().awaiting_purchase = true
		router.go("paywall")
	)
	limit.add_child(_patterns)
	_limit_card = UI.card_panel(limit)
	_limit_card.name = "LimitCard"
	_limit_card.visible = false
	page.add_child(_limit_card)
	_result_box = VBoxContainer.new()
	_result_box.add_theme_constant_override("separation", 14)
	page.add_child(_result_box)
	if session().has("draft"):
		_show_result(session().draft)
	elif params.get("autostart", true):
		_start()


func _start() -> void:
	if _busy:
		return
	var design := str(session().get("design", ""))
	var values := {}
	for key in DesignCatalog.required_measurements(design):
		if Profile.measurements.has(key):
			values[key] = Profile.measurements[key]
	_busy = true
	_status.visible = true
	_retry.visible = false
	_patterns.visible = false
	_limit_card.visible = false
	show_error(_error, "")
	for child in _result_box.get_children():
		child.queue_free()
	var result: Dictionary = await router.api.draft_pattern(design, values, session().get("options", {}), LocaleService.units(), LocaleService.paper(), bool(session().get("fit_adjustment", false)), str(session().get("complaint", "")))
	if not is_inside_tree():
		return
	_busy = false
	_status.visible = false
	if not result.get("ok", false):
		var limited := str(result.get("error", "")) == "limit"
		show_error(_error, "" if limited else API_ERRORS.get(str(result.get("error", "")), "err_api_server"))
		_retry.visible = not limited
		_patterns.visible = limited
		_limit_card.visible = limited
		return
	var was_adjustment := bool(session().get("fit_adjustment", false))
	session().draft = result
	var adjusted = result.get("options")
	if typeof(adjusted) == TYPE_DICTIONARY and not adjusted.is_empty():
		session().options = adjusted
	session().erase("complaint")
	session().erase("fit_adjustment")
	_show_result(result)
	if not was_adjustment and Profile.note_successful_pattern() == 2:
		_show_review()


func _show_review() -> void:
	var card := UI.card()
	card.name = "ReviewCard"
	card.add_child(UI.label(tr("review_title"), "TitleLabel"))
	card.add_child(UI.label(tr("review_body")))
	var rate := UI.button(tr("btn_review"), true)
	rate.name = "ReviewButton"
	rate.pressed.connect(func() -> void: NativeBridge.request_review())
	card.add_child(rate)
	var later := UI.flat_button(tr("btn_not_now"))
	later.name = "ReviewLater"
	later.pressed.connect(func() -> void:
		var panel := card.get_parent()
		if panel:
			panel.queue_free()
	)
	card.add_child(later)
	_result_box.add_child(UI.card_panel(card))


func _show_result(result: Dictionary) -> void:
	_status.visible = false
	for child in _result_box.get_children():
		child.queue_free()
	_result_box.add_child(UI.bullet(tr("draft_ready"), "check"))
	var fresh := UI.bullet(tr("label_new_fit"), "sparkle")
	var fresh_label := fresh.get_child(1) as Label
	fresh_label.name = "NewLabel"
	fresh_label.theme_type_variation = "CaptionLabel"
	_result_box.add_child(fresh)
	var preview := _preview(str(result.get("svg", "")))
	if preview:
		_result_box.add_child(preview)
	var card := UI.card()
	_result_box.add_child(UI.card_panel(card))
	card.add_child(UI.label(tr("draft_details"), "TitleLabel"))
	var pieces: Array = result.get("labels", {}).get("pieces", [])
	card.add_child(UI.bullet(tr("fmt_pieces") % pieces.size(), "scissors"))
	var paper := str(result.get("paper", "a4"))
	card.add_child(UI.bullet(tr("fmt_paper") % tr("paper_letter" if paper == "letter" else "paper_a4"), "page"))
	var yardage: Array = result.get("yardage", [])
	if not yardage.is_empty():
		card.add_child(UI.divider())
		card.add_child(UI.label(tr("draft_yardage"), "TitleLabel"))
		var unit := LocaleService.units()
		for row in yardage:
			var width := Units.format(float(row.get("fabricCm", 0)) * 10.0, unit)
			if unit == "inch":
				width = Units.format(float(row.get("fabricIn", 0)) * 25.4, unit)
			card.add_child(UI.bullet(tr("fmt_yardage") % [width, length_text(float(row.get("lengthMm", 0)), unit)], "ruler"))
	var banner := UI.label(tr("guide_banner_test_fabric"), "NoticeLabel")
	_result_box.add_child(banner)
	var pdf_path := str(result.get("pdf_path", ""))
	var share := UI.icon_button(tr("btn_share_pdf"), "share", true)
	share.name = "ShareButton"
	share.disabled = pdf_path == ""
	share.pressed.connect(_share.bind(pdf_path))
	_result_box.add_child(share)
	_result_box.add_child(UI.caption(tr("draft_print_tip")))
	_result_box.add_child(UI.spacer(4))
	_result_box.add_child(UI.section(tr("draft_next")))
	var steps := UI.list_row(tr("btn_sewing_steps"), "scissors")
	steps.name = "SewingButton"
	steps.pressed.connect(func() -> void: router.go("guide"))
	var fit := UI.list_row(tr("btn_fit_feedback"), "chat")
	fit.name = "FitButton"
	fit.pressed.connect(func() -> void: router.go("fit"))
	var again := UI.list_row(tr("btn_new_pattern"), "plus")
	again.name = "NewPatternButton"
	again.pressed.connect(func() -> void: router.go("home", {}, true))
	_result_box.add_child(UI.group([steps, fit, again]))


## Fabric length in metres (cm) or yards (inch), one decimal.
static func length_text(length_mm: float, unit: String) -> String:
	if unit == "inch":
		return "%s %s" % [String.num(length_mm / 914.4, 1), TranslationServer.translate("unit_yd_short")]
	return "%s %s" % [String.num(length_mm / 1000.0, 1), TranslationServer.translate("unit_m_short")]


## The pieces on a cream sheet, sized to the drawing so there are no empty bands.
func _preview(svg: String) -> Control:
	if svg == "":
		return null
	var image := Image.new()
	if image.load_svg_from_string(svg, 1.0) != OK or image.is_empty():
		return null
	var longest := maxf(image.get_width(), image.get_height())
	if longest > MAX_PREVIEW_SIDE:
		image.resize(int(image.get_width() * MAX_PREVIEW_SIDE / longest), int(image.get_height() * MAX_PREVIEW_SIDE / longest))
	var canvas := Vector2i(maxi(image.get_width(), int(image.get_height() / MAX_PREVIEW_TALL)), image.get_height())
	var backdrop := Image.create(canvas.x, canvas.y, false, Image.FORMAT_RGBA8)
	backdrop.fill(UI.CREAM)
	backdrop.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i((canvas.x - image.get_width()) / 2, 0))
	backdrop.generate_mipmaps()
	var rect := TextureRect.new()
	rect.name = "Preview"
	rect.texture = ImageTexture.create_from_image(backdrop)
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rect.expand_mode = TextureRect.EXPAND_FIT_HEIGHT_PROPORTIONAL
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sheet := PanelContainer.new()
	sheet.theme_type_variation = "PaperPanel"
	sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.add_child(rect)
	return sheet


func _share(pdf_path: String) -> void:
	show_error(_error, "")
	if not NativeBridge.share_finished.is_connected(_on_shared):
		NativeBridge.share_finished.connect(_on_shared, CONNECT_ONE_SHOT)
	NativeBridge.share_file(pdf_path, "application/pdf", DesignCatalog.display_name(str(session().get("design", ""))))


func _on_shared(status: String) -> void:
	if status == "error" and is_inside_tree():
		show_error(_error, "share_failed")
