extends Screen
## Guided measuring, one measurement per page, in the person's units.
## params.keys: measurements to take. params.then: "draft" or "back".

var keys: Array = []
var then := "back"
var index := 0
var _input: LineEdit
var _error: Label
var _diagram: BodyDiagram


func title_key() -> String:
	return "title_measure"


func enter(params: Dictionary) -> void:
	keys = params.get("keys", []).duplicate()
	then = str(params.get("then", "back"))
	index = 0
	if keys.is_empty():
		keys = DesignCatalog.measurement_keys()
	_render()


func current_key() -> String:
	return str(keys[index])


func _render() -> void:
	var page := build_page()
	var key := current_key()
	var unit := LocaleService.units()
	var kind := DesignCatalog.kind(key)
	page.add_child(UI.caption(tr("fmt_step") % [index + 1, keys.size()]))
	page.add_child(UI.progress(float(index + 1) / keys.size()))
	page.add_child(UI.heading(DesignCatalog.measurement_name(key)))
	_diagram = BodyDiagram.new()
	_diagram.name = "Diagram"
	_diagram.unit = unit
	_diagram.measurement = key
	_diagram.value_mm = float(Profile.measurements.get(key, NAN))
	page.add_child(_diagram)
	page.add_child(UI.label(tr("how_" + key)))
	if index == 0:
		page.add_child(UI.caption(tr("measure_tip")))
	var row := UI.row()
	_input = LineEdit.new()
	_input.name = "ValueInput"
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	_input.custom_minimum_size = Vector2(0, 56)
	var typical := float(DesignCatalog.measurement(key).get("typical", 0))
	_input.placeholder_text = Units.number_text(typical, unit, kind)
	if Profile.measurements.has(key):
		_input.text = Units.number_text(float(Profile.measurements[key]), unit, kind)
	_input.text_changed.connect(_on_text_changed)
	_input.text_submitted.connect(func(_text: String) -> void: _next())
	row.add_child(_input)
	var suffix := UI.label(Units.suffix(unit, kind), "TitleLabel")
	suffix.size_flags_horizontal = Control.SIZE_SHRINK_END
	suffix.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(suffix)
	page.add_child(row)
	page.add_child(UI.caption(tr("fmt_typical") % Units.format(typical, unit, kind)))
	_error = UI.error_label()
	_error.name = "Error"
	page.add_child(_error)
	var buttons := UI.row()
	if index > 0:
		var previous := UI.button(tr("btn_previous"))
		previous.name = "PreviousButton"
		previous.pressed.connect(_previous)
		buttons.add_child(previous)
	var last := index == keys.size() - 1
	var next := UI.button(tr("btn_save") if last else tr("btn_next"), true)
	next.name = "NextButton"
	next.pressed.connect(_next)
	buttons.add_child(next)
	page.add_child(buttons)


func _on_text_changed(text: String) -> void:
	_error.visible = false
	var value := Units.parse(text)
	_diagram.value_mm = NAN if is_nan(value) else Units.from_display(value, LocaleService.units(), DesignCatalog.kind(current_key()))


## Validates and stores the typed value. Returns the error string key or "".
func commit() -> String:
	var key := current_key()
	var parsed := Units.parse(_input.text)
	if is_nan(parsed):
		return "err_not_number"
	var value_mm := Units.from_display(parsed, LocaleService.units(), DesignCatalog.kind(key))
	var error := DesignCatalog.validate(key, value_mm)
	if error != "":
		return error
	var trial := Profile.measurements.duplicate()
	trial[key] = value_mm
	var related: Dictionary = DesignCatalog.validate_all(trial)
	if related.get(key, "") == "err_order":
		return "err_order"
	return Profile.set_measurement(key, value_mm)


func _show(error: String) -> void:
	if error == "err_order":
		_error.text = tr("err_order") % _related_name(current_key())
		_error.visible = true
	else:
		show_error(_error, error)


func _related_name(key: String) -> String:
	for pair in DesignCatalog.ORDERED_PAIRS:
		if pair[0] == key:
			return DesignCatalog.measurement_name(pair[1])
	return ""


func _next() -> void:
	var error := commit()
	if error != "":
		_show(error)
		return
	Profile.save()
	if index < keys.size() - 1:
		index += 1
		_render()
		return
	NativeBridge.log_event("measure_done", {})
	if then == "draft":
		router.replace("draft")
	else:
		router.back()


func _previous() -> void:
	if index > 0:
		index -= 1
		_render()
