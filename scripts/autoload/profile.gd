extends Node
## The body profile and settings, saved on the device only.
## Measurements are stored in millimetres (degrees for shoulder slope).

signal changed

const DEFAULT_PATH := "user://profile.json"
const UNIT_CHOICES := ["", "cm", "inch"]
const PAPER_CHOICES := ["", "A4", "Letter"]
const LANGUAGE_CHOICES := ["", "en", "de", "fr", "es", "pt_BR", "ja", "it", "nl"]

var path := DEFAULT_PATH
var measurements: Dictionary = {}
var onboarded := false
var units_override := ""
var paper_override := ""
var language_override := ""
var large_text := false
var successful_patterns := 0
## Last balance the server confirmed. Only used to point people to the purchase
## screen; the server still decides whether a pattern can be drafted.
var known_credits := 0
var known_unlimited := false


func _ready() -> void:
	load_profile()


func load_profile() -> void:
	measurements = {}
	onboarded = false
	units_override = ""
	paper_override = ""
	language_override = ""
	large_text = false
	successful_patterns = 0
	known_credits = 0
	known_unlimited = false
	if FileAccess.file_exists(path):
		var json := JSON.new()
		if json.parse(FileAccess.get_file_as_string(path)) == OK and typeof(json.data) == TYPE_DICTIONARY:
			_apply(json.data)
	_push_overrides()


func save() -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Profile could not be saved to %s" % path)
		return false
	file.store_string(JSON.stringify(to_dict(), "\t"))
	file.close()
	changed.emit()
	return true


func to_dict() -> Dictionary:
	return {
		"version": 1,
		"measurements": measurements.duplicate(),
		"onboarded": onboarded,
		"unitsOverride": units_override,
		"paperOverride": paper_override,
		"languageOverride": language_override,
		"largeText": large_text,
		"successfulPatterns": successful_patterns,
		"knownCredits": known_credits,
		"knownUnlimited": known_unlimited,
	}


func set_measurement(key: String, value_mm: float) -> String:
	var error := DesignCatalog.validate(key, value_mm)
	if error == "":
		measurements[key] = snappedf(value_mm, 0.01)
	return error


func clear_measurements() -> void:
	measurements = {}


func set_units_override(unit: String) -> void:
	units_override = unit if unit in UNIT_CHOICES else ""
	_push_overrides()


func set_paper_override(paper: String) -> void:
	paper_override = paper if paper in PAPER_CHOICES else ""
	_push_overrides()


func set_language(language: String) -> void:
	language_override = language if language in LANGUAGE_CHOICES else ""
	LocaleService.apply_language()


func set_large_text(enabled: bool) -> void:
	large_text = enabled


## Counts a finished pattern. The review prompt uses the second one.
## Every pattern after the free first one uses a known credit unless unlimited.
func note_successful_pattern() -> int:
	successful_patterns += 1
	var spent := false
	if successful_patterns > 1 and not known_unlimited and not Billing.has_unlimited():
		var balance := maxi(Billing.credits, known_credits)
		known_credits = maxi(0, balance - 1)
		Billing.credits = known_credits
		spent = true
	save()
	if spent:
		Billing.updated.emit()
	return successful_patterns


func remember_entitlement(credits: int, unlimited: bool) -> void:
	known_credits = maxi(0, credits)
	known_unlimited = unlimited
	save()


## True when the free pattern is used and no credit or unlimited unlock is known.
func needs_patterns() -> bool:
	return successful_patterns >= 1 and not known_unlimited and known_credits <= 0


func units() -> String:
	return LocaleService.units()


func paper() -> String:
	return LocaleService.paper()


func missing_for(design: String) -> Array:
	return DesignCatalog.missing(design, measurements)


func _apply(source: Dictionary) -> void:
	var stored = source.get("measurements", {})
	if typeof(stored) == TYPE_DICTIONARY:
		for key in stored:
			var value = stored[key]
			if (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and DesignCatalog.validate(key, float(value)) == "":
				measurements[key] = float(value)
	onboarded = bool(source.get("onboarded", false))
	var unit := str(source.get("unitsOverride", ""))
	units_override = unit if unit in UNIT_CHOICES else ""
	var paper_choice := str(source.get("paperOverride", ""))
	paper_override = paper_choice if paper_choice in PAPER_CHOICES else ""
	var language := str(source.get("languageOverride", ""))
	language_override = language if language in LANGUAGE_CHOICES else ""
	large_text = bool(source.get("largeText", false))
	successful_patterns = maxi(0, int(source.get("successfulPatterns", 0)))
	known_credits = maxi(0, int(source.get("knownCredits", 0)))
	known_unlimited = bool(source.get("knownUnlimited", false))


func _push_overrides() -> void:
	LocaleService.units_override = units_override
	LocaleService.paper_override = paper_override
	LocaleService.apply_language()
