class_name FitRules
## Fit complaints from data/fit_feedback.json, the same table the functions use.
## A positive delta adds ease. A tight stretch complaint is a negative delta.

const PATH := "res://data/fit_feedback.json"

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var parsed := JSON.new()
		if FileAccess.file_exists(PATH) and parsed.parse(FileAccess.get_file_as_string(PATH)) == OK:
			if typeof(parsed.data) == TYPE_DICTIONARY:
				_data = parsed.data
	return _data


## Complaints for options this design shows as sliders, in table order.
static func complaints_for(design: String) -> Array:
	var known := {}
	for slider in DesignCatalog.sliders(design):
		known[str(slider.get("key", ""))] = true
	var out: Array = []
	for item in data().get("complaints", []):
		if typeof(item) == TYPE_DICTIONARY and known.has(str(item.get("option", ""))):
			out.append(item)
	return out
