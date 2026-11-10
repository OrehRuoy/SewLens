class_name GuideCatalog
## Per-design sewing steps. data/guides/<design>.json lists translation keys.
## Shared steps are reused. Only the note key is specific to the garment.

static var _cache: Dictionary = {}


static func guide(design: String) -> Dictionary:
	if _cache.has(design):
		return _cache[design]
	var path := "res://data/guides/%s.json" % design
	if not FileAccess.file_exists(path):
		return {}
	var parsed := JSON.new()
	if parsed.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}
	if typeof(parsed.data) != TYPE_DICTIONARY:
		return {}
	_cache[design] = parsed.data
	return parsed.data


static func designs_with_guides() -> Array:
	var names: Array = []
	for name in DesignCatalog.design_names():
		if not guide(name).is_empty():
			names.append(name)
	return names
