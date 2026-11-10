extends Screen
## The saved body profile: edit one measurement or delete them all.

var _confirming := false


func title_key() -> String:
	return "title_measurements"


func enter(_params: Dictionary) -> void:
	_render()


func resumed() -> void:
	_render()


func _render() -> void:
	_confirming = false
	var page := build_page()
	page.add_child(UI.caption(tr("measurements_saved_note")))
	var unit := LocaleService.units()
	var saved := DesignCatalog.measurement_keys().filter(func(key: String) -> bool: return Profile.measurements.has(key))
	if saved.is_empty():
		var empty := UI.card()
		var art := LineIcon.new("tape", UI.GOLD, 40.0)
		art.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		empty.add_child(art)
		var message := UI.label(tr("measurements_empty"))
		message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_child(message)
		page.add_child(UI.card_panel(empty))
	var rows: Array = []
	for key in saved:
		var value := Units.format(float(Profile.measurements[key]), unit, DesignCatalog.kind(key))
		var entry := UI.list_row(tr("fmt_measurement_row") % [DesignCatalog.measurement_name(key), value])
		entry.name = "Edit_" + key
		entry.pressed.connect(func() -> void: router.go("measure", {"keys": [key], "then": "back"}))
		rows.append(entry)
	if not rows.is_empty():
		page.add_child(UI.group(rows))
	var all := UI.icon_button(tr("btn_measure_all"), "ruler", saved.is_empty())
	all.name = "MeasureAllButton"
	all.pressed.connect(func() -> void: router.go("measure", {"keys": DesignCatalog.measurement_keys(), "then": "back"}))
	page.add_child(all)
	if not saved.is_empty():
		var clear := UI.flat_button(tr("btn_clear_measurements"), "DangerButton")
		clear.name = "ClearButton"
		clear.pressed.connect(_clear.bind(clear))
		page.add_child(clear)


func _clear(button: Button) -> void:
	if not _confirming:
		_confirming = true
		button.text = tr("btn_confirm_clear")
		return
	Profile.clear_measurements()
	Profile.save()
	_render()
