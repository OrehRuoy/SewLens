extends GutTest


func test_cm_round_trip_keeps_millimetres() -> void:
	for mm in [3.0, 96.5, 1000.0, 1234.5, 1700.0]:
		var text := Units.number_text(mm, "cm")
		var back := Units.from_display(Units.parse(text), "cm")
		assert_almost_eq(back, mm, 0.5, "cm round trip of %s mm via '%s'" % [mm, text])


func test_inch_round_trip_keeps_an_eighth_inch() -> void:
	for mm in [25.4, 96.5, 431.8, 1000.0, 1219.2]:
		var text := Units.number_text(mm, "inch")
		var back := Units.from_display(Units.parse(text), "inch")
		assert_almost_eq(back, mm, 0.13, "inch round trip of %s mm via '%s'" % [mm, text])


func test_degrees_are_not_converted() -> void:
	assert_eq(Units.to_display(13.0, "inch", "degree"), 13.0)
	assert_eq(Units.from_display(13.0, "cm", "degree"), 13.0)
	assert_eq(Units.format(13.0, "inch", "degree"), "13°")


func test_display_values() -> void:
	assert_eq(Units.number_text(1000.0, "cm"), "100")
	assert_eq(Units.number_text(965.0, "cm"), "96.5")
	assert_eq(Units.number_text(965.2, "inch"), "38")
	assert_eq(Units.number_text(971.55, "inch"), "38.25")


func test_parse_accepts_comma_fractions_and_suffixes() -> void:
	assert_eq(Units.parse("96,5"), 96.5)
	assert_eq(Units.parse(" 96.5 cm "), 96.5)
	assert_eq(Units.parse("38 1/4"), 38.25)
	assert_eq(Units.parse("3/4"), 0.75)
	assert_eq(Units.parse("38\""), 38.0)
	assert_eq(Units.parse("13°"), 13.0)


func test_parse_rejects_text() -> void:
	for text in ["", "abc", "38 39", "1/0", "1/2/3", "38 1/4 5"]:
		assert_true(is_nan(Units.parse(text)), "'%s' is not a number" % text)


func test_api_names() -> void:
	assert_eq(Units.api_units("inch"), "imperial")
	assert_eq(Units.api_units("cm"), "metric")
	assert_eq(Units.api_paper("Letter"), "letter")
	assert_eq(Units.api_paper("A4"), "a4")


func test_suffix_is_translated() -> void:
	TranslationServer.set_locale("fr")
	assert_eq(Units.suffix("inch"), "po")
	TranslationServer.set_locale("en")
	assert_eq(Units.suffix("inch"), "in")
	assert_eq(Units.format(1000.0, "cm"), "100 cm")
