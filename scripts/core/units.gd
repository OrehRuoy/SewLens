class_name Units
## Converts between stored millimetres and the cm / inch values people type.
## Shoulder slope is in degrees and never converted.

const MM_PER_INCH := 25.4
const MM_PER_CM := 10.0


static func to_display(mm: float, unit: String, kind: String = "length") -> float:
	if kind == "degree":
		return mm
	return mm / (MM_PER_INCH if unit == "inch" else MM_PER_CM)


static func from_display(value: float, unit: String, kind: String = "length") -> float:
	if kind == "degree":
		return value
	return value * (MM_PER_INCH if unit == "inch" else MM_PER_CM)


static func suffix(unit: String, kind: String = "length") -> String:
	if kind == "degree":
		return "°"
	return TranslationServer.translate("unit_in_short" if unit == "inch" else "unit_cm_short")


## Inches keep 2 decimals so 1/8 in survives; cm keeps 1 decimal (1 mm).
static func number_text(mm: float, unit: String, kind: String = "length") -> String:
	var value := to_display(mm, unit, kind)
	var decimals := 1
	if kind == "length" and unit == "inch":
		decimals = 2
	var text := String.num(value, decimals)
	if text.contains("."):
		text = text.rstrip("0").rstrip(".")
	return text


static func format(mm: float, unit: String, kind: String = "length") -> String:
	var number := number_text(mm, unit, kind)
	if kind == "degree":
		return number + "°"
	return "%s %s" % [number, suffix(unit, kind)]


## Accepts "96.5", "96,5", "38 1/4", "3/4". Returns NAN when the text is not a number.
static func parse(text: String) -> float:
	var clean := text.strip_edges().replace(",", ".")
	for strip in ["cm", "in", "°", "\""]:
		clean = clean.trim_suffix(strip).strip_edges()
	if clean.is_empty():
		return NAN
	var parts := clean.split(" ", false)
	if parts.size() > 2:
		return NAN
	var total := 0.0
	for index in parts.size():
		var part := parts[index]
		if part.contains("/"):
			var pieces := part.split("/")
			if pieces.size() != 2 or not pieces[0].is_valid_int() or not pieces[1].is_valid_int():
				return NAN
			var denominator := pieces[1].to_float()
			if denominator == 0.0:
				return NAN
			total += pieces[0].to_float() / denominator
		elif part.is_valid_float() and index == 0:
			total += part.to_float()
		else:
			return NAN
	return total


static func api_units(unit: String) -> String:
	return "imperial" if unit == "inch" else "metric"


static func api_paper(paper: String) -> String:
	return "letter" if paper == "Letter" else "a4"
