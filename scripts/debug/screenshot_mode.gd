extends RefCounted
## Demo data for store screenshots. Exported builds cannot arm this.
## The capture script in test/ is the only caller.
## Autoloads are reached through the tree so this can load from a SceneTree script.

static var armed := false


static func arm() -> bool:
	if not OS.is_debug_build() or OS.has_feature("template"):
		push_warning("Screenshot mode is not available in exported builds")
		return false
	armed = true
	_billing().show_price_diagnostic = false
	_native().screenshot_camera = true
	return true


static func apply_demo(locale: String, prices: Dictionary) -> void:
	if not armed:
		return
	var catalog = load("res://scripts/core/design_catalog.gd")
	var measurements := {}
	for key in catalog.measurement_keys():
		var spec: Dictionary = catalog.measurement(str(key))
		if spec.has("typical"):
			measurements[str(key)] = float(spec["typical"])
	var profile = _profile()
	profile.measurements = measurements
	profile.onboarded = true
	profile.large_text = false
	profile.language_override = locale
	profile.units_override = ""
	profile.paper_override = ""
	profile.known_credits = 3
	profile.known_unlimited = false
	profile.successful_patterns = 2
	var billing = _billing()
	billing.credits = 3
	billing.unlimited = false
	billing.prices = prices
	billing.price_state = "ready"
	billing.price_diagnostic = ""
	billing.show_price_diagnostic = false
	_locale().apply_language()


static func _billing():
	return Engine.get_main_loop().root.get_node("Billing")


static func _profile():
	return Engine.get_main_loop().root.get_node("Profile")


static func _locale():
	return Engine.get_main_loop().root.get_node("LocaleService")


static func _native():
	return Engine.get_main_loop().root.get_node("NativeBridge")
