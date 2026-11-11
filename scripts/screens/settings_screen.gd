extends Screen
## Language, text size, units and paper overrides, purchases, the intro,
## licenses, legal links and the privacy summary, in grouped sections.


func title_key() -> String:
	return "title_settings"


func shows_settings() -> bool:
	return false


func enter(_params: Dictionary) -> void:
	_render()


func resumed() -> void:
	_render()


func _render() -> void:
	var page := build_page()
	page.add_theme_constant_override("separation", 10)
	page.add_child(UI.section(tr("section_display")))
	var language := UI.picker_row(tr("settings_language"), "globe", _choice("LanguageOption", [
		[tr("lang_system"), ""],
		["English", "en"],
		["Deutsch", "de"],
		["Français", "fr"],
		["Español", "es"],
		["Português (Brasil)", "pt_BR"],
		["日本語", "ja"],
		["Italiano", "it"],
		["Nederlands", "nl"],
	], Profile.language_override, _on_language))
	var text_size := UI.list_row(tr("btn_large_text"), "text", "switch")
	text_size.name = "TextSizeButton"
	text_size.toggle_mode = true
	text_size.set_pressed_no_signal(Profile.large_text)
	text_size.toggled.connect(_on_text_size)
	page.add_child(UI.group([language, text_size]))

	page.add_child(_gap())
	page.add_child(UI.section(tr("section_measuring")))
	var auto_unit := tr("units_inch_long" if LocaleService.units_for(LocaleService.current_locale()) == "inch" else "units_cm_long")
	var units := UI.picker_row(tr("settings_units"), "ruler", _choice("UnitsOption", [
		[tr("fmt_automatic") % auto_unit, ""],
		[tr("units_cm_long"), "cm"],
		[tr("units_inch_long"), "inch"],
	], Profile.units_override, _on_units))
	var auto_paper := tr("paper_letter" if LocaleService.paper_for(LocaleService.current_locale()) == "Letter" else "paper_a4")
	var paper := UI.picker_row(tr("settings_paper"), "page", _choice("PaperOption", [
		[tr("fmt_automatic") % auto_paper, ""],
		[tr("paper_a4"), "A4"],
		[tr("paper_letter"), "Letter"],
	], Profile.paper_override, _on_paper))
	var measurements := UI.list_row(tr("btn_my_measurements"), "tape")
	measurements.name = "MeasurementsButton"
	measurements.pressed.connect(func() -> void: router.go("measurements"))
	page.add_child(UI.group([units, paper, measurements]))

	page.add_child(_gap())
	page.add_child(UI.section(tr("section_purchases")))
	var patterns := UI.list_row(tr("btn_get_unlimited"), "star")
	patterns.name = "PatternsButton"
	patterns.pressed.connect(func() -> void: router.go("paywall"))
	var purchase_rows: Array = [patterns]
	var status := _entitlement_text()
	if status != "":
		var note := MarginContainer.new()
		for side in ["left", "right"]:
			note.add_theme_constant_override("margin_" + side, 16)
		note.add_theme_constant_override("margin_top", 12)
		note.add_theme_constant_override("margin_bottom", 12)
		note.add_child(UI.bullet(status, "check"))
		purchase_rows.push_front(note)
	page.add_child(UI.group(purchase_rows))

	page.add_child(_gap())
	page.add_child(UI.section(tr("section_about")))
	var intro := UI.list_row(tr("btn_show_intro"), "replay")
	intro.name = "IntroButton"
	intro.pressed.connect(func() -> void: router.go("onboarding", {}, true))
	var licenses := UI.list_row(tr("btn_licenses"), "code")
	licenses.name = "LicensesButton"
	licenses.pressed.connect(func() -> void: router.go("licenses"))
	var privacy := UI.list_row(tr("btn_privacy_policy"), "shield", "")
	privacy.name = "PrivacyButton"
	privacy.pressed.connect(func() -> void: NativeBridge.open_url(UI.PRIVACY_URL))
	var terms := UI.list_row(tr("link_terms"), "doc", "")
	terms.name = "TermsButton"
	terms.pressed.connect(func() -> void: NativeBridge.open_url(UI.TERMS_URL))
	page.add_child(UI.group([intro, licenses, privacy, terms]))

	page.add_child(_gap())
	var card := UI.card()
	var heading := UI.row(12)
	heading.add_child(LineIcon.new("lock", UI.GOLD))
	var title := UI.label(tr("settings_privacy_heading"), "TitleLabel")
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	heading.add_child(title)
	card.add_child(heading)
	card.add_child(UI.caption(tr("settings_privacy_body")))
	page.add_child(UI.card_panel(card))
	var version := UI.caption(tr("fmt_version") % str(ProjectSettings.get_setting("application/config/version", "")))
	version.name = "Version"
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.mouse_filter = Control.MOUSE_FILTER_STOP
	version.gui_input.connect(_on_version_tap)
	page.add_child(version)


func _gap() -> Control:
	return UI.spacer(6)


func _entitlement_text() -> String:
	if Billing.has_unlimited():
		return tr("pay_status_unlimited")
	var credits := Billing.pattern_credits()
	if credits > 0:
		return tr("pay_status_credits") % credits
	return ""


func _choice(node_name: String, items: Array, selected: String, handler: Callable) -> OptionButton:
	var option := OptionButton.new()
	option.name = node_name
	option.custom_minimum_size = Vector2(0, UI.button_height() - 4.0)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.fit_to_longest_item = false
	option.clip_text = true
	for index in items.size():
		option.add_item(items[index][0], index)
		option.set_item_metadata(index, items[index][1])
		if items[index][1] == selected:
			option.select(index)
	option.item_selected.connect(func(index: int) -> void: handler.call(str(option.get_item_metadata(index))))
	return option


func _on_units(unit: String) -> void:
	Profile.set_units_override(unit)
	Profile.save()


func _on_paper(paper: String) -> void:
	Profile.set_paper_override(paper)
	Profile.save()


func _on_language(language: String) -> void:
	Profile.set_language(language)
	Profile.save()
	router.reload_current.call_deferred()


func _on_text_size(enabled: bool) -> void:
	Profile.set_large_text(enabled)
	Profile.save()
	router.reload_current.call_deferred()


var _version_taps := 0


func _on_version_tap(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventMouseButton and event.pressed:
		_version_taps += 1
		if _version_taps >= 5:
			NativeBridge.test_crash()
