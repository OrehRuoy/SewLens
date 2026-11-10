class_name ResultFit
## Slider values. The catalog stores percent points; the API takes fractions.


## Slider defaults for the design, overridden by any options pickDesign suggested.
static func defaults_with(design: String, suggested: Variant) -> Dictionary:
	var options := {}
	for slider in DesignCatalog.sliders(design):
		options[slider.key] = float(slider.default) / 100.0
	if typeof(suggested) == TYPE_DICTIONARY:
		for key in suggested:
			var value = suggested[key]
			if typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT or typeof(value) == TYPE_BOOL:
				options[key] = value
	return clamp_sliders(design, options)


static func clamp_sliders(design: String, options: Dictionary) -> Dictionary:
	var out := options.duplicate()
	for slider in DesignCatalog.sliders(design):
		if out.has(slider.key) and typeof(out[slider.key]) != TYPE_BOOL:
			out[slider.key] = clampf(float(out[slider.key]), float(slider.min) / 100.0, float(slider.max) / 100.0)
	return out


static func percent_text(fraction: float) -> String:
	var points := snappedf(fraction * 100.0, 0.5)
	var text := String.num(points, 1)
	if text.ends_with(".0"):
		text = text.trim_suffix(".0")
	return TranslationServer.translate("fmt_percent") % text
