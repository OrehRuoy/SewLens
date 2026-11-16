extends GutTest
## Saved patterns stay on the phone: list, metadata, migration, delete,
## and opening one does not call the server or use a credit.

const Fixture := preload("res://test/support/screen_fixture.gd")
const DIR := "user://test_pattern_library"


func before_each() -> void:
	Fixture.prepare_profile()
	PatternLibrary.directory = DIR
	_clear_dir()
	Profile.successful_patterns = 0
	Profile.known_credits = 3
	TranslationServer.set_locale("en")


func after_each() -> void:
	_clear_dir()
	PatternLibrary.directory = PatternLibrary.DEFAULT_DIR
	NativeBridge.export_result_for_test = ""
	Fixture.restore_profile()


func test_empty_state_and_metadata_round_trip() -> void:
	var main := Fixture.make_main(self)
	main.go("patterns", {}, true)
	await get_tree().process_frame
	assert_not_null(main.find_child("EmptyTitle", true, false))
	assert_has(Fixture.visible_texts(main), "No saved patterns")
	main.queue_free()
	var path := _write_pdf("SewLens-aaron-20261116-120000.pdf", "one")
	PatternLibrary.write_meta(path, {"design": "aaron", "date": "2026-11-16 12:00:00", "paper": "A4", "summary": "Chest 92 cm"})
	var older := _write_pdf("SewLens-teagan-20261101-090000.pdf", "two")
	PatternLibrary.write_meta(older, {"design": "teagan", "date": "2026-11-01 09:00:00", "paper": "Letter", "summary": ""})
	var items := PatternLibrary.list_entries()
	assert_eq(items.size(), 2)
	assert_eq(items[0].design, "aaron")
	assert_eq(items[0].paper, "A4")
	assert_eq(items[0].summary, "Chest 92 cm")
	assert_eq(items[1].design, "teagan")
	var read := PatternLibrary.read_meta(path)
	assert_eq(read.design, "aaron")
	assert_eq(read.paper, "A4")
	assert_eq(PatternLibrary.suggested_filename("aaron", "2026-11-16 12:00:00"), "SewLens-aaron-2026-11-16.pdf")


func test_existing_pdfs_are_migrated_and_can_be_deleted() -> void:
	var path := _write_pdf("SewLens-penelope-20261102-080000.pdf", "old")
	assert_false(FileAccess.file_exists(path.trim_suffix(".pdf") + ".json"))
	var items := PatternLibrary.list_entries()
	assert_eq(items.size(), 1)
	assert_eq(items[0].design, "penelope")
	assert_eq(items[0].paper, "")
	assert_ne(items[0].date, "")
	assert_true(FileAccess.file_exists(path.trim_suffix(".pdf") + ".json"))
	PatternLibrary.remove(path)
	assert_false(FileAccess.file_exists(path))
	assert_false(FileAccess.file_exists(path.trim_suffix(".pdf") + ".json"))
	assert_eq(PatternLibrary.list_entries().size(), 0)


func test_reopening_a_saved_pattern_does_not_call_the_server_or_use_a_credit() -> void:
	var path := _write_pdf("SewLens-aaron-20261116-120000.pdf", "%PDF-1.4 saved")
	PatternLibrary.write_meta(path, {"design": "aaron", "date": "2026-11-16 12:00:00", "paper": "A4", "summary": "Chest 92 cm"})
	var main := Fixture.make_main(self)
	main.go("patterns", {}, true)
	await get_tree().process_frame
	assert_eq(main.api.transport.requests.size(), 0)
	var credits := Profile.known_credits
	NativeBridge.export_result_for_test = "ok"
	(main.find_child("OpenButton", true, false) as Button).pressed.emit()
	(main.find_child("ShareButton", true, false) as Button).pressed.emit()
	NativeBridge.export_result_for_test = "started"
	(main.find_child("PrintButton", true, false) as Button).pressed.emit()
	await get_tree().process_frame
	assert_eq(main.api.transport.requests.size(), 0)
	assert_eq(Profile.known_credits, credits)
	assert_eq(Profile.successful_patterns, 0)
	main.queue_free()


func test_new_pattern_strings_exist_in_every_language() -> void:
	var keys := [
		"btn_my_patterns", "title_my_patterns", "patterns_empty_title", "patterns_empty_body",
		"btn_open_pattern", "btn_print", "btn_save_device", "btn_delete_pattern",
		"patterns_delete_title", "patterns_delete_body", "btn_delete_confirm",
		"patterns_saved", "patterns_save_cancelled", "patterns_save_failed",
		"patterns_print_failed", "patterns_open_failed", "patterns_paper_unknown",
	]
	for locale in Fixture.LOCALES:
		TranslationServer.set_locale(locale)
		for key in keys:
			var text := TranslationServer.translate(key)
			assert_ne(text, key, "%s missing %s" % [locale, key])
			assert_false(text.contains("AI"), "%s %s" % [locale, key])
	TranslationServer.set_locale("en")


func _write_pdf(file_name: String, body: String) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := DIR.path_join(file_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(body)
	file.close()
	return path


func _clear_dir() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	var folder := DirAccess.open(DIR)
	if folder == null:
		return
	folder.list_dir_begin()
	var name := folder.get_next()
	while name != "":
		if not folder.current_is_dir():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(DIR.path_join(name)))
		name = folder.get_next()
	folder.list_dir_end()
