class_name DesignCatalog
## Reads res://data/designs.json, which functions/scripts/client-catalog.mjs
## generates from the FreeSewing designs the functions draft.

const PATH := "res://data/designs.json"

## The smaller measurement of each pair must stay below the larger one.
const ORDERED_PAIRS := [
	["waistToHips", "waistToSeat"],
	["waistToSeat", "waistToUpperLeg"],
	["waistToUpperLeg", "waistToKnee"],
	["waistToKnee", "waistToFloor"],
	["crossSeamFront", "crossSeam"],
	["waist", "seat"],
	["wrist", "biceps"],
	["ankle", "knee"],
	["knee", "upperLeg"],
	["underbust", "chest"],
	["hpsToBust", "hpsToWaistBack"],
	["waistToArmpit", "hpsToWaistBack"],
]

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var resource: JSON = load(PATH)
		_data = resource.data if resource and typeof(resource.data) == TYPE_DICTIONARY else {}
	return _data


static func design_names() -> Array:
	var names: Array = data().get("designs", {}).keys()
	names.sort()
	return names


static func categories() -> Array:
	return data().get("categories", [])


static func designs_in(category: String) -> Array:
	var names: Array = []
	for name in design_names():
		if design(name).get("category", "") == category:
			names.append(name)
	return names


static func has_design(name: String) -> bool:
	return data().get("designs", {}).has(name)


static func design(name: String) -> Dictionary:
	return data().get("designs", {}).get(name, {})


static func required_measurements(name: String) -> Array:
	return design(name).get("measurements", [])


static func sliders(name: String) -> Array:
	return design(name).get("sliders", [])


static func measurement_keys() -> Array:
	var keys: Array = data().get("measurements", {}).keys()
	keys.sort()
	return keys


static func measurement(key: String) -> Dictionary:
	return data().get("measurements", {}).get(key, {})


static func kind(key: String) -> String:
	return measurement(key).get("kind", "length")


static func display_name(name: String) -> String:
	return TranslationServer.translate("design_" + name)


static func measurement_name(key: String) -> String:
	return TranslationServer.translate("meas_" + key)


## Returns "" when the value is acceptable, otherwise an error string key.
static func validate(key: String, value_mm: float) -> String:
	var spec := measurement(key)
	if spec.is_empty():
		return "err_unknown_measurement"
	if is_nan(value_mm) or is_inf(value_mm):
		return "err_not_number"
	if value_mm < float(spec.min):
		return "err_too_small"
	if value_mm > float(spec.max):
		return "err_too_large"
	return ""


## Checks every value and the ordered pairs. Returns {key: error string key}.
static func validate_all(values_mm: Dictionary) -> Dictionary:
	var errors := {}
	for key in values_mm:
		var error := validate(key, float(values_mm[key]))
		if error != "":
			errors[key] = error
	for pair in ORDERED_PAIRS:
		var small: String = pair[0]
		var large: String = pair[1]
		if errors.has(small) or errors.has(large):
			continue
		if values_mm.has(small) and values_mm.has(large):
			if float(values_mm[small]) >= float(values_mm[large]):
				errors[small] = "err_order"
	return errors


static func missing(name: String, values_mm: Dictionary) -> Array:
	var keys: Array = []
	for key in required_measurements(name):
		if not values_mm.has(key) or validate(key, float(values_mm[key])) != "":
			keys.append(key)
	return keys
