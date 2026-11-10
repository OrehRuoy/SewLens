extends GutTest
## Every design has a sewing guide in all 8 languages, and the drafted pattern
## shows the honest new-pattern label.

const Fixture := preload("res://test/support/screen_fixture.gd")


func before_all() -> void:
	Fixture.prepare_profile()


func after_all() -> void:
	Fixture.restore_profile()
	TranslationServer.set_locale("en")


func test_every_design_has_a_guide_in_every_language() -> void:
	var names := DesignCatalog.design_names()
	assert_eq(GuideCatalog.designs_with_guides().size(), names.size())
	for locale in Fixture.LOCALES:
		TranslationServer.set_locale(locale)
		for name in names:
			var guide := GuideCatalog.guide(name)
			var steps: Array = guide.get("steps", [])
			var notes: Array = guide.get("notes", [])
			assert_gt(steps.size(), 0, name)
			assert_eq(notes, ["guide_note_%s" % name])
			for key in steps + notes:
				var text := tr(str(key))
				assert_ne(text, str(key), "%s %s" % [locale, key])


func test_every_fit_complaint_is_translated() -> void:
	var complaints: Array = FitRules.data().get("complaints", [])
	assert_gt(complaints.size(), 0)
	for locale in Fixture.LOCALES:
		TranslationServer.set_locale(locale)
		for item in complaints:
			var key := "fit_%s" % str(item.get("id", ""))
			assert_ne(tr(key), key, "%s %s" % [locale, key])


func test_pattern_screen_shows_the_new_label() -> void:
	TranslationServer.set_locale("en")
	var main := Fixture.make_main(self)
	Fixture.open(main, ["draft", {"autostart": false}])
	await get_tree().process_frame
	var texts := Fixture.visible_texts(main)
	assert_has(texts, "New — tell us how it fit")
	assert_has(texts, "Make a test garment from cheap fabric first.")
	assert_has(texts, "Sewing steps")
	assert_has(texts, "Tell us how it fit")
	main.queue_free()
