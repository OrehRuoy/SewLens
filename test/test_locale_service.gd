extends GutTest

const LETTER_REGIONS := ["US", "CA", "MX", "PH", "CL", "CO", "VE"]


func after_each() -> void:
	LocaleService.units_override = ""
	LocaleService.paper_override = ""


func test_app_boots() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	assert_not_null(packed, "main scene loads")
	var node := packed.instantiate()
	add_child_autofree(node)
	assert_eq(str(LocaleService.get_path()), "/root/LocaleService")
	assert_eq(node.get_node("Title").text, tr("app_name"))


func test_translations_compiled_for_all_eight_locales() -> void:
	var loaded := TranslationServer.get_loaded_locales()
	for code in ["en", "de", "fr", "es", "pt_BR", "ja", "it", "nl"]:
		assert_true(code in loaded, "missing compiled locale %s" % code)


func test_german_tagline() -> void:
	TranslationServer.set_locale("de")
	assert_eq(tr("app_tagline"), "Schnittmuster erstellen")
	TranslationServer.set_locale("en")


func test_de_de_is_cm_a4() -> void:
	assert_eq(LocaleService.units_for("de_DE"), "cm")
	assert_eq(LocaleService.paper_for("de_DE"), "A4")
	assert_eq(LocaleService.units_for("de-DE"), "cm")
	assert_eq(LocaleService.paper_for("de-DE"), "A4")


func test_en_us_is_inch_letter() -> void:
	assert_eq(LocaleService.units_for("en_US"), "inch")
	assert_eq(LocaleService.paper_for("en_US"), "Letter")
	assert_eq(LocaleService.units_for("en-US"), "inch")


func test_inch_locales_and_letter_regions() -> void:
	for tag in ["en_US", "en_CA", "en_LR"]:
		assert_eq(LocaleService.units_for(tag), "inch", tag)
	assert_eq(LocaleService.units_for("en_GB"), "cm")
	assert_eq(LocaleService.units_for("en_PH"), "cm")
	assert_eq(LocaleService.paper_for("en_LR"), "A4")
	assert_eq(LocaleService.paper_for("en_PH"), "Letter")
	assert_eq(LocaleService.units_for("es_MX"), "cm")
	assert_eq(LocaleService.paper_for("es_MX"), "Letter")
	for region in LETTER_REGIONS:
		assert_eq(LocaleService.paper_for("xx_%s" % region), "Letter", region)
	assert_eq(LocaleService.paper_for("fr_FR"), "A4")
	assert_eq(LocaleService.units_for("en"), "cm")
	assert_eq(LocaleService.paper_for("en"), "A4")


func test_settings_override() -> void:
	LocaleService.units_override = "cm"
	LocaleService.paper_override = "A4"
	assert_eq(LocaleService.units(), "cm")
	assert_eq(LocaleService.paper(), "A4")
	LocaleService.units_override = "inch"
	LocaleService.paper_override = "Letter"
	assert_eq(LocaleService.units(), "inch")
	assert_eq(LocaleService.paper(), "Letter")
