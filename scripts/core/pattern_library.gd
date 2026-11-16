class_name PatternLibrary
extends RefCounted
## Saved pattern PDFs in user://patterns, with a JSON sidecar so the list
## does not depend on the file name.

const DEFAULT_DIR := "user://patterns"

static var directory := DEFAULT_DIR


static func list_entries() -> Array:
	_migrate()
	var dir := DirAccess.open(directory)
	if dir == null:
		return []
	var items: Array = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.get_extension().to_lower() == "pdf":
			items.append(read_meta(directory.path_join(name)))
		name = dir.get_next()
	dir.list_dir_end()
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("date", "")) > str(b.get("date", ""))
	)
	return items


static func write_meta(pdf_path: String, meta: Dictionary) -> void:
	var stored := {
		"design": str(meta.get("design", "")),
		"date": str(meta.get("date", "")),
		"paper": str(meta.get("paper", "")),
		"summary": str(meta.get("summary", "")),
	}
	var file := FileAccess.open(_meta_path(pdf_path), FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(stored))
	file.close()


static func read_meta(pdf_path: String) -> Dictionary:
	var meta := {"design": "", "date": "", "paper": "", "summary": ""}
	var side := _meta_path(pdf_path)
	if FileAccess.file_exists(side):
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(side)) == OK and typeof(json.data) == TYPE_DICTIONARY:
			var data: Dictionary = json.data
			meta.design = str(data.get("design", ""))
			meta.date = str(data.get("date", ""))
			meta.paper = str(data.get("paper", ""))
			meta.summary = str(data.get("summary", ""))
	if meta.design == "":
		meta.design = design_from_filename(pdf_path.get_file())
	if meta.date == "" and FileAccess.file_exists(pdf_path):
		meta.date = Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(pdf_path), true)
	meta.path = pdf_path
	return meta


static func remove(pdf_path: String) -> void:
	if FileAccess.file_exists(pdf_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(pdf_path))
	var side := _meta_path(pdf_path)
	if FileAccess.file_exists(side):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(side))


static func summary(measurements_mm: Dictionary, unit: String) -> String:
	var keys: Array = measurements_mm.keys()
	keys.sort()
	var parts: PackedStringArray = []
	for key in keys:
		if parts.size() >= 3:
			break
		var kind := DesignCatalog.kind(str(key))
		parts.append("%s %s" % [DesignCatalog.measurement_name(str(key)), Units.format(float(measurements_mm[key]), unit, kind)])
	return " · ".join(parts)


static func suggested_filename(design: String, date: String = "") -> String:
	var stamp := date.substr(0, 10)
	if stamp == "":
		stamp = Time.get_date_string_from_system()
	var clean := design if design != "" else "pattern"
	return "SewLens-%s-%s.pdf" % [clean, stamp]


static func paper_label(paper: String) -> String:
	var lower := paper.to_lower()
	if lower == "a4":
		return TranslationServer.translate("paper_a4")
	if lower == "letter":
		return TranslationServer.translate("paper_letter")
	return TranslationServer.translate("patterns_paper_unknown")


static func design_from_filename(file_name: String) -> String:
	var stem := file_name.get_basename()
	var parts := stem.split("-")
	if parts.size() >= 2 and parts[0] == "SewLens":
		return parts[1]
	return stem


static func _meta_path(pdf_path: String) -> String:
	return pdf_path.trim_suffix(".pdf") + ".json"


static func _migrate() -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.get_extension().to_lower() == "pdf":
			var pdf_path := directory.path_join(name)
			if not FileAccess.file_exists(_meta_path(pdf_path)):
				var meta := read_meta(pdf_path)
				write_meta(pdf_path, meta)
		name = dir.get_next()
	dir.list_dir_end()
