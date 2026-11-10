extends Screen
## The picked design, fit sliders, and the way on to measuring and drafting.

var _sliders := {}
var _value_labels := {}


func title_key() -> String:
	return "title_result"


func enter(_params: Dictionary) -> void:
	_render()


func resumed() -> void:
	_render()


func _render() -> void:
	_sliders.clear()
	_value_labels.clear()
	var page := build_page()
	var pick: Dictionary = session().get("pick", {})
	var design := str(session().get("design", ""))
	var photo := str(session().get("photo_path", ""))
	if photo != "":
		page.add_child(UI.photo_rect(photo, 180))
	if design == "":
		var unsupported := str(pick.get("unsupported", ""))
		var key := "result_unsupported_polo" if unsupported == "polo" else "result_unsupported_shorts" if unsupported == "shorts" else "result_none"
		page.add_child(UI.label(tr(key)))
		var choose := UI.button(tr("btn_choose_other"), true)
		choose.name = "ChooseButton"
		choose.pressed.connect(func() -> void: router.go("designs"))
		page.add_child(choose)
		return
	var card := UI.card()
	page.add_child(UI.card_panel(card))
	card.add_child(UI.badge(tr("cat_" + str(DesignCatalog.design(design).get("category", "tops")))))
	card.add_child(UI.heading(DesignCatalog.display_name(design)))
	if pick.get("closest", false) and str(pick.get("design", "")) == design:
		card.add_child(UI.label(tr("result_closest")))
	var explanation := str(pick.get("explanation", ""))
	if explanation != "" and str(pick.get("design", "")) == design:
		card.add_child(UI.caption(explanation))
	var other := UI.flat_button(tr("btn_choose_other"), "TextLink")
	other.name = "ChooseButton"
	other.pressed.connect(func() -> void: router.go("designs"))
	card.add_child(other)
	var sliders := DesignCatalog.sliders(design)
	if not sliders.is_empty():
		var fit := UI.card()
		fit.add_theme_constant_override("separation", 10)
		fit.add_child(UI.label(tr("result_fit_heading"), "TitleLabel"))
		fit.add_child(UI.caption(tr("result_fit_body")))
		for slider in sliders:
			fit.add_child(_slider_row(design, slider))
		var reset := UI.flat_button(tr("btn_reset_fit"), "TextLink")
		reset.name = "ResetButton"
		reset.pressed.connect(_reset_fit.bind(design))
		fit.add_child(reset)
		page.add_child(UI.card_panel(fit))
	var required := DesignCatalog.required_measurements(design)
	var missing := Profile.missing_for(design)
	page.add_child(UI.bullet(tr("fmt_measurements_saved") % [required.size() - missing.size(), required.size()], "tape"))
	var go_on := UI.button(tr("btn_continue_measure") if not missing.is_empty() else tr("btn_draft"), true)
	go_on.name = "ContinueButton"
	go_on.pressed.connect(_continue.bind(design))
	page.add_child(go_on)


func _slider_row(design: String, slider: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var top := UI.row()
	var name_label := UI.label(tr("opt_" + str(slider.key)))
	top.add_child(name_label)
	var options: Dictionary = session().get("options", {})
	var fraction := float(options.get(slider.key, float(slider.default) / 100.0))
	var value := UI.label(ResultFit.percent_text(fraction))
	value.add_theme_color_override("font_color", UI.GOLD)
	value.size_flags_horizontal = Control.SIZE_SHRINK_END
	value.autowrap_mode = TextServer.AUTOWRAP_OFF
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(value)
	box.add_child(top)
	var control := HSlider.new()
	control.name = "Slider_" + str(slider.key)
	control.min_value = float(slider.min)
	control.max_value = float(slider.max)
	control.step = 0.5
	control.value = fraction * 100.0
	control.custom_minimum_size = Vector2(0, 40)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.value_changed.connect(_on_slider.bind(design, str(slider.key)))
	box.add_child(control)
	_sliders[slider.key] = control
	_value_labels[slider.key] = value
	return box


func _on_slider(points: float, design: String, key: String) -> void:
	var options: Dictionary = session().get("options", {})
	options[key] = points / 100.0
	session().options = ResultFit.clamp_sliders(design, options)
	_value_labels[key].text = ResultFit.percent_text(session().options[key])


func _reset_fit(design: String) -> void:
	session().options = ResultFit.defaults_with(design, {})
	for key in _sliders:
		_sliders[key].set_value_no_signal(float(session().options[key]) * 100.0)
		_value_labels[key].text = ResultFit.percent_text(session().options[key])


func _continue(design: String) -> void:
	var missing := Profile.missing_for(design)
	if missing.is_empty():
		router.go("draft")
	else:
		router.go("measure", {"keys": missing, "then": "draft"})
