extends Node
## Units and paper from the device locale.
## Inches: en_US, en_CA, en_LR. Centimeters everywhere else.
## Letter: US, CA, MX, PH, CL, CO, VE. A4 everywhere else.
## Settings can override either value later.


const INCH_LOCALES: PackedStringArray = ["en_US", "en_CA", "en_LR"]
const LETTER_REGIONS: PackedStringArray = ["US", "CA", "MX", "PH", "CL", "CO", "VE"]

var units_override: String = ""
var paper_override: String = ""
## Stands in for the OS locale when set (tests and screenshots of other regions).
var device_locale: String = ""


func current_locale() -> String:
	return device_locale if device_locale != "" else OS.get_locale()


func units() -> String:
	if units_override != "":
		return units_override
	return units_for(current_locale())


func paper() -> String:
	if paper_override != "":
		return paper_override
	return paper_for(current_locale())


func units_for(locale: String) -> String:
	var parts := _split_locale(locale)
	if parts.size() >= 2:
		var tag := parts[0].to_lower() + "_" + parts[1].to_upper()
		if tag in INCH_LOCALES:
			return "inch"
	return "cm"


func paper_for(locale: String) -> String:
	var parts := _split_locale(locale)
	if parts.size() >= 2 and parts[1].to_upper() in LETTER_REGIONS:
		return "Letter"
	return "A4"


## "" follows the device. Otherwise one of the eight app languages.
func apply_language() -> void:
	var chosen := Profile.language_override
	if chosen == "":
		var device := current_locale()
		TranslationServer.set_locale(device if device != "" else "en")
	else:
		TranslationServer.set_locale(chosen)


func _split_locale(locale: String) -> PackedStringArray:
	return locale.replace("-", "_").split("_", false)
