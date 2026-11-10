extends RefCounted
## Opens every screen of scenes/main.tscn with a filled-in session, so tests and
## tools/locale_screens.gd can walk all screens without network or native calls.

const MAIN := preload("res://scenes/main.tscn")
const MockTransport := preload("res://test/support/mock_transport.gd")
const LOCALES := ["en", "de", "fr", "es", "pt_BR", "ja", "it", "nl"]
## The device region each language is checked with, so units and paper match it.
const REGIONS := {"en": "en_US", "de": "de_DE", "fr": "fr_FR", "es": "es_ES", "pt_BR": "pt_BR", "ja": "ja_JP", "it": "it_IT", "nl": "nl_NL"}
const PHONE := Vector2(390, 844)
const PROFILE_PATH := "user://test_fixture_profile.json"
const PDF_PATH := "user://test_fixture.pdf"
const SVG := "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"120\"><rect x=\"10\" y=\"10\" width=\"80\" height=\"100\" fill=\"none\" stroke=\"#1c3a5c\" stroke-width=\"2\"/><rect x=\"110\" y=\"10\" width=\"80\" height=\"100\" fill=\"none\" stroke=\"#1c3a5c\" stroke-width=\"2\"/></svg>"

## [screen name, params]. "measure_more" opens measuring on its second step.
const SCREENS := [
	["onboarding", {}],
	["onboarding", {"slide": 1}],
	["onboarding", {"slide": 2}],
	["home", {}],
	["analyze", {"autostart": false}],
	["result", {}],
	["designs", {}],
	["measure", {"keys": ["chest", "shoulderSlope", "waistToFloor"]}],
	["measurements", {}],
	["draft", {"autostart": false}],
	["guide", {}],
	["fit", {}],
	["paywall", {}],
	["licenses", {}],
	["settings", {}],
]


static func screen_label(entry: Array) -> String:
	var label: String = entry[0]
	if entry[1].has("slide"):
		label += "_%d" % int(entry[1].slide)
	return label


static func prepare_profile() -> void:
	Profile.path = PROFILE_PATH
	Profile.load_profile()
	Profile.onboarded = true
	Profile.measurements = {"chest": 1000.0, "waist": 820.0, "neck": 380.0, "shoulderSlope": 13.0}
	var file := FileAccess.open(PDF_PATH, FileAccess.WRITE)
	file.store_string("%PDF-1.4 fixture")
	file.close()


static func restore_profile() -> void:
	Profile.path = Profile.DEFAULT_PATH
	Profile.load_profile()
	for path in [PROFILE_PATH, PDF_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


static func session() -> Dictionary:
	return {
		"photo_path": "res://assets/sample_garment.jpg",
		"pick": {"ok": true, "design": "aaron", "closest": true, "explanation": "A sleeveless knit top.", "options": {"chestEase": 0.1}},
		"design": "aaron",
		"options": ResultFit.defaults_with("aaron", {"chestEase": 0.1}),
		"draft": {
			"ok": true,
			"design": "aaron",
			"paper": "a4",
			"svg": SVG,
			"pdf_path": PDF_PATH,
			"labels": {"pieces": [{"id": "front", "label": "Front"}, {"id": "back", "label": "Back"}]},
			"yardage": [
				{"fabricCm": 112, "fabricIn": 45, "lengthMm": 900},
				{"fabricCm": 150, "fabricIn": 60, "lengthMm": 700},
			],
		},
	}


## App language on a device in that language's home region.
## Pass "" to go back to English on the real device locale.
static func use_locale(locale: String) -> void:
	TranslationServer.set_locale(locale if locale != "" else "en")
	LocaleService.device_locale = REGIONS.get(locale, "")


## Pseudolocalization that only pads every string by 30%, for the 130% length check.
static func set_expanded(enabled: bool) -> void:
	ProjectSettings.set_setting("internationalization/pseudolocalization/expansion_ratio", 0.3)
	ProjectSettings.set_setting("internationalization/pseudolocalization/replace_with_accents", false)
	ProjectSettings.set_setting("internationalization/pseudolocalization/double_vowels", false)
	ProjectSettings.set_setting("internationalization/pseudolocalization/fake_bidi", false)
	ProjectSettings.set_setting("internationalization/pseudolocalization/override", false)
	ProjectSettings.set_setting("internationalization/pseudolocalization/skip_placeholders", true)
	TranslationServer.pseudolocalization_enabled = enabled
	TranslationServer.reload_pseudolocalization()


## The Larger text setting from Settings, applied to the whole app theme.
static func set_large_text(main: Control, enabled: bool) -> void:
	Profile.large_text = enabled
	main.apply_text_size()


## Adds main.tscn under `parent` with a mock transport. Returns the main node.
## Main is pinned to the phone size, because the headless window is 844 wide.
static func make_main(parent: Node) -> Control:
	var main: Control = MAIN.instantiate()
	parent.add_child(main)
	main.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	main.size = PHONE
	main.api.transport = MockTransport.new()
	return main


## The phone screen every overflow check measures against.
static func screen_rect() -> Rect2:
	return Rect2(Vector2.ZERO, PHONE)


static func open(main: Control, entry: Array) -> Screen:
	main.session = session()
	return main.go(entry[0], entry[1].duplicate(true), true)


## Every visible string in the header and current screen.
static func visible_texts(main: Control) -> Array:
	var texts: Array = []
	_collect(main, texts)
	return texts


static func _collect(node: Node, texts: Array) -> void:
	if node is CanvasItem and not node.is_visible_in_tree():
		return
	if node is OptionButton:
		for index in node.item_count:
			texts.append(node.get_item_text(index))
	elif node is Label or node is Button:
		texts.append(node.text)
	elif node is LineEdit:
		texts.append(node.placeholder_text)
	for child in node.get_children():
		_collect(child, texts)


## A string that is still a raw key such as "btn_next" or "how_chest".
static func looks_like_key(text: String) -> bool:
	var regex := RegEx.create_from_string("^[a-z]+(_[A-Za-z0-9]+)+$")
	return regex.search(text) != null
