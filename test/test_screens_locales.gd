extends GutTest
## Every screen loads in all 8 locales with every string translated, and
## German and French still fit at 130% length.

const Fixture := preload("res://test/support/screen_fixture.gd")
const Overflow := preload("res://test/support/overflow_check.gd")
const SCRIPT_DIRS := ["res://scripts", "res://scenes"]

var main: Control


func before_all() -> void:
	Fixture.prepare_profile()


func after_all() -> void:
	Fixture.restore_profile()
	TranslationServer.set_locale("en")


func before_each() -> void:
	main = Fixture.make_main(self)


func after_each() -> void:
	Fixture.use_locale("")
	Fixture.set_expanded(false)
	Profile.large_text = false
	main.queue_free()
	await get_tree().process_frame


func _csv_keys() -> Array:
	var keys: Array = []
	var file := FileAccess.open("res://i18n/strings.csv", FileAccess.READ)
	file.get_csv_line()
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() > 1 and row[0] != "":
			keys.append(row[0])
	return keys


func test_every_key_is_translated_in_every_locale() -> void:
	var keys := _csv_keys()
	assert_gt(keys.size(), 150)
	for locale in Fixture.LOCALES:
		TranslationServer.set_locale(locale)
		var missing: Array = []
		for key in keys:
			if key.begins_with("units_") or key.begins_with("unit_") or key.begins_with("paper_") or key == "app_name":
				continue
			if TranslationServer.translate(key) == key:
				missing.append(key)
		assert_eq(missing, [], "untranslated in %s" % locale)


func test_every_literal_key_in_code_exists() -> void:
	var keys := _csv_keys()
	var pattern := RegEx.create_from_string("(?:\\btr|translate)\\(\"([a-z][a-z0-9_]*)\"\\)")
	var missing: Array = []
	for dir in SCRIPT_DIRS:
		for path in _scripts_under(dir):
			for found in pattern.search_all(FileAccess.get_file_as_string(path)):
				var key := found.get_string(1)
				if not key in keys:
					missing.append("%s: %s" % [path, key])
	assert_eq(missing, [])


func _scripts_under(dir: String) -> Array:
	var out: Array = []
	for name in DirAccess.get_files_at(dir):
		if name.ends_with(".gd"):
			out.append(dir.path_join(name))
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_scripts_under(dir.path_join(sub)))
	return out


func test_every_screen_loads_in_every_locale() -> void:
	for locale in Fixture.LOCALES:
		Fixture.use_locale(locale)
		for entry in Fixture.SCREENS:
			var screen := Fixture.open(main, entry)
			await get_tree().process_frame
			var where := "%s / %s" % [locale, Fixture.screen_label(entry)]
			assert_not_null(screen, where)
			var texts := Fixture.visible_texts(main)
			assert_gt(texts.size(), 2, where)
			var raw := texts.filter(func(text: String) -> bool: return Fixture.looks_like_key(text))
			assert_eq(raw, [], "raw keys on %s" % where)
	assert_eq(main.get_node("Title").text, tr("title_settings"))


func test_header_title_follows_the_screen() -> void:
	TranslationServer.set_locale("de")
	Fixture.open(main, ["designs", {}])
	assert_eq(main.get_node("Title").text, "Design wählen")
	Fixture.open(main, ["home", {}])
	assert_eq(main.get_node("Title").text, "SewLens")


func test_text_fits_in_every_locale() -> void:
	await _assert_fits(Fixture.LOCALES, false)


func test_german_and_french_fit_at_130_percent() -> void:
	await _assert_fits(["de", "fr"], true)


func test_german_fits_at_130_percent_with_larger_text() -> void:
	Fixture.set_large_text(main, true)
	await _assert_fits(["de"], true)


func test_overflow_check_catches_text_that_does_not_fit() -> void:
	var long_text := "Oberweite unter der Brust messen, waagerecht rund um den Körper und nicht zu fest"
	var unwrapped := Label.new()
	var clipped := Label.new()
	clipped.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clipped.max_lines_visible = 1
	var fits := Label.new()
	fits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var boxes: Array = []
	for label in [unwrapped, clipped, fits]:
		var box := VBoxContainer.new()
		box.size = Vector2(120, 400)
		add_child_autofree(box)
		label.text = long_text
		box.add_child(label)
		boxes.append(box)
	await get_tree().process_frame
	var screen := Rect2(0, 0, 390, 844)
	assert_eq(Overflow.find(boxes[0], screen).size(), 1, "unwrapped text runs off the screen")
	assert_eq(Overflow.find(boxes[1], screen).size(), 1, "wrapped text cut after one line")
	assert_eq(Overflow.find(boxes[2], screen), [], "wrapped text fits")


func _assert_fits(locales: Array, expanded: bool) -> void:
	var screen_rect := Fixture.screen_rect()
	for locale in locales:
		Fixture.use_locale(locale)
		Fixture.set_expanded(false)
		var plain := tr("btn_pick_design_manual")
		Fixture.set_expanded(expanded)
		if expanded:
			assert_gte(tr("btn_pick_design_manual").length(), int(plain.length() * 1.3), "pseudolocalization adds 30%% in %s" % locale)
		for entry in Fixture.SCREENS:
			Fixture.open(main, entry)
			for frame in 3:
				await get_tree().process_frame
			var problems := Overflow.find(main, screen_rect)
			assert_eq(problems, [], "overflow on %s / %s%s" % [locale, Fixture.screen_label(entry), " at 130%" if expanded else ""])


func test_measuring_diagram_uses_locale_units() -> void:
	LocaleService.units_override = "inch"
	var screen := Fixture.open(main, ["measure", {"keys": ["chest"]}])
	var diagram: BodyDiagram = screen.find_child("Diagram", true, false)
	assert_eq(diagram.value_text(), "39.37 in", "saved 1000 mm chest shown in inches")
	LocaleService.units_override = "cm"
	screen = Fixture.open(main, ["measure", {"keys": ["chest"]}])
	diagram = screen.find_child("Diagram", true, false)
	assert_eq(diagram.value_text(), "100 cm")
	LocaleService.units_override = ""


func test_units_follow_the_device_region() -> void:
	Fixture.use_locale("ja")
	var screen := Fixture.open(main, ["measure", {"keys": ["chest"]}])
	assert_eq(screen.find_child("Diagram", true, false).value_text(), "100 cm")
	Fixture.use_locale("en")
	screen = Fixture.open(main, ["measure", {"keys": ["chest"]}])
	assert_eq(screen.find_child("Diagram", true, false).value_text(), "39.37 in")
	Fixture.use_locale("de")
	Fixture.open(main, ["settings", {}])
	var texts := Fixture.visible_texts(main)
	assert_has(texts, "Automatisch (Zentimeter)")
	assert_has(texts, "Automatisch (A4)")


func test_measure_screen_validates_and_saves() -> void:
	LocaleService.units_override = "cm"
	var screen := Fixture.open(main, ["measure", {"keys": ["waistToKnee"], "then": "back"}])
	var input: LineEdit = screen.find_child("ValueInput", true, false)
	input.text = "5"
	assert_eq(screen.commit(), "err_too_small")
	input.text = "58,5"
	assert_eq(screen.commit(), "")
	assert_almost_eq(float(Profile.measurements.waistToKnee), 585.0, 0.01)
	LocaleService.units_override = ""
