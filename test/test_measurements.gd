extends GutTest

const PATH := "user://test_measurements_profile.json"


func before_each() -> void:
	Profile.path = PATH
	Profile.load_profile()


func after_each() -> void:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	Profile.path = Profile.DEFAULT_PATH
	Profile.load_profile()


func test_catalog_lists_every_design_with_measurements() -> void:
	var names := DesignCatalog.design_names()
	assert_eq(names.size(), 20)
	for name in names:
		assert_gt(DesignCatalog.required_measurements(name).size(), 0, name)
		assert_true(DesignCatalog.design(name).get("category", "") in DesignCatalog.categories(), name)
		for key in DesignCatalog.required_measurements(name):
			assert_false(DesignCatalog.measurement(key).is_empty(), "%s needs %s" % [name, key])
			assert_true(BodyDiagram.has_spec(key), "diagram for %s" % key)


func test_typical_values_pass_validation() -> void:
	for key in DesignCatalog.measurement_keys():
		var typical := float(DesignCatalog.measurement(key).typical)
		assert_eq(DesignCatalog.validate(key, typical), "", key)


func test_out_of_range_values_fail() -> void:
	assert_eq(DesignCatalog.validate("chest", 96.0), "err_too_small", "96 mm is a cm typo")
	assert_eq(DesignCatalog.validate("chest", 9600.0), "err_too_large")
	assert_eq(DesignCatalog.validate("chest", NAN), "err_not_number")
	assert_eq(DesignCatalog.validate("shoulderSlope", 45.0), "err_too_large")
	assert_eq(DesignCatalog.validate("noSuchThing", 10.0), "err_unknown_measurement")


func test_ordered_pairs() -> void:
	var errors := DesignCatalog.validate_all({"waistToSeat": 300.0, "waistToUpperLeg": 250.0, "waist": 800.0})
	assert_eq(errors.get("waistToSeat", ""), "err_order")
	assert_false(errors.has("waist"))
	assert_true(DesignCatalog.validate_all({"waistToSeat": 200.0, "waistToUpperLeg": 280.0}).is_empty())


func test_missing_measurements_for_a_design() -> void:
	Profile.measurements = {"chest": 1000.0, "neck": 380.0, "hips": 10.0}
	var missing := Profile.missing_for("aaron")
	assert_false("chest" in missing)
	assert_true("hips" in missing, "an invalid stored value counts as missing")
	assert_true("biceps" in missing)
	assert_eq(Profile.missing_for("florent"), ["head"])


func test_profile_round_trip_and_overrides() -> void:
	assert_eq(Profile.set_measurement("chest", 1000.0), "")
	assert_eq(Profile.set_measurement("waist", 5.0), "err_too_small")
	Profile.onboarded = true
	Profile.set_units_override("inch")
	Profile.set_paper_override("Letter")
	assert_true(Profile.save())
	Profile.measurements = {}
	Profile.set_units_override("")
	Profile.load_profile()
	assert_eq(Profile.measurements, {"chest": 1000.0})
	assert_true(Profile.onboarded)
	assert_eq(LocaleService.units(), "inch")
	assert_eq(LocaleService.paper(), "Letter")
	Profile.set_units_override("feet")
	assert_eq(Profile.units_override, "", "unknown units fall back to automatic")


func test_corrupt_profile_loads_empty() -> void:
	var file := FileAccess.open(PATH, FileAccess.WRITE)
	file.store_string("{not json")
	file.close()
	Profile.load_profile()
	assert_eq(Profile.measurements, {})
	assert_false(Profile.onboarded)


func test_slider_defaults_are_fractions_and_clamped() -> void:
	var options := ResultFit.defaults_with("aaron", {"chestEase": 5.0, "necklineDrop": 0.2})
	assert_almost_eq(float(options.hipsEase), 0.08, 0.0001)
	assert_almost_eq(float(options.chestEase), 0.2, 0.0001, "clamped to the 20% max")
	assert_almost_eq(float(options.necklineDrop), 0.2, 0.0001, "other suggested options pass through")
