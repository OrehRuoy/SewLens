extends Control
## App shell and router: a header and a stack of screens from scenes/screens.

const SCREENS := {
	"onboarding": "res://scenes/screens/onboarding.tscn",
	"home": "res://scenes/screens/home.tscn",
	"analyze": "res://scenes/screens/analyze.tscn",
	"result": "res://scenes/screens/result.tscn",
	"designs": "res://scenes/screens/designs.tscn",
	"measure": "res://scenes/screens/measure.tscn",
	"measurements": "res://scenes/screens/measurements.tscn",
	"draft": "res://scenes/screens/draft.tscn",
	"guide": "res://scenes/screens/guide.tscn",
	"fit": "res://scenes/screens/fit.tscn",
	"paywall": "res://scenes/screens/paywall.tscn",
	"licenses": "res://scenes/screens/licenses.tscn",
	"settings": "res://scenes/screens/settings.tscn",
}
const HEADER_HEIGHT := 60.0
## The header title stays two lines tall with Larger text, so long German titles still fit.
const HEADER_LARGE_FONT := 24

## Flow state shared by the screens: photo_path, pick, design, options, draft.
var session: Dictionary = {}
var api: ApiClient
var _stack: Array[Screen] = []

## Safe-area insets in viewport units (top, right, bottom, left). Screenshots set these
## to preview notched phones on desktop; leave negative to read them from the device.
var simulated_insets := Vector4(-1, -1, -1, -1)

@onready var _title: Label = $Title
@onready var _logo: TextureRect = $Logo
@onready var _line: ColorRect = $HeaderLine
@onready var _back: Button = $BackButton
@onready var _settings: Button = $SettingsButton
@onready var _host: Control = $ScreenHost


func _ready() -> void:
	api = ApiClient.new()
	add_child(api)
	_back.pressed.connect(back)
	_settings.pressed.connect(func() -> void: go("settings"))
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	apply_text_size()
	go("home" if Profile.onboarded else "onboarding", {}, true)
	if OS.has_feature("android") or OS.get_name() == "Android":
		Billing.recover_owned(api)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _stack.size() > 1:
			back()
		else:
			get_tree().quit()
	elif what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_refresh_header()


func current() -> Screen:
	return _stack.back() if not _stack.is_empty() else null


func screen_names() -> Array:
	return _stack.map(func(screen: Screen) -> String: return screen.name)


func go(screen_name: String, params: Dictionary = {}, reset: bool = false) -> Screen:
	if reset:
		for screen in _stack:
			screen.queue_free()
		_stack.clear()
	elif current():
		current().visible = false
	var packed: PackedScene = load(SCREENS[screen_name])
	var screen: Screen = packed.instantiate()
	screen.name = screen_name
	screen.router = self
	screen.params = params.duplicate(true)
	_host.add_child(screen)
	_stack.append(screen)
	screen.enter(params)
	_refresh_header()
	return screen


func replace(screen_name: String, params: Dictionary = {}) -> Screen:
	if not _stack.is_empty():
		var top: Screen = _stack.pop_back()
		top.queue_free()
	return go(screen_name, params)


func back() -> void:
	if _stack.size() <= 1:
		return
	var top: Screen = _stack.pop_back()
	top.queue_free()
	current().visible = true
	current().resumed()
	_refresh_header()


## Pops screens until `screen_name` is on top. Returns false when it is not in the stack.
func back_to(screen_name: String) -> bool:
	if not screen_name in screen_names():
		return false
	while current().name != screen_name:
		back()
	return true


func reload_current() -> void:
	apply_text_size()
	_refresh_header()
	var screen := current()
	if screen:
		screen.reload()


func apply_text_size() -> void:
	var base: Theme = load("res://assets/theme/sewlens_theme.tres")
	if Profile.large_text:
		_title.add_theme_font_size_override("font_size", HEADER_LARGE_FONT)
	else:
		_title.remove_theme_font_size_override("font_size")
	if not Profile.large_text:
		theme = base
		return
	var bigger := base.duplicate(true) as Theme
	bigger.default_font_size = 24
	bigger.set_font_size("font_size", "CaptionLabel", 20)
	bigger.set_font_size("font_size", "ErrorLabel", 22)
	bigger.set_font_size("font_size", "HeadingLabel", 34)
	bigger.set_font_size("font_size", "TitleLabel", 28)
	bigger.set_font_size("font_size", "PrimaryButton", 26)
	bigger.set_font_size("font_size", "LineEdit", 28)
	bigger.set_font_size("font_size", "SectionLabel", 18)
	bigger.set_font_size("font_size", "NoticeLabel", 22)
	bigger.set_font_size("font_size", "BadgeLabel", 18)
	bigger.set_font_size("font_size", "PriceLabel", 30)
	bigger.set_font_size("font_size", "TextLink", 22)
	theme = bigger


func _refresh_header() -> void:
	var screen := current()
	_title.text = tr(screen.title_key()) if screen else tr("app_name")
	var branded := screen == null or screen.title_key() == "app_name"
	_logo.visible = branded
	_title.visible = not branded
	_back.visible = screen != null and screen.shows_back() and _stack.size() > 1
	_settings.visible = screen != null and screen.shows_settings()
	_back.tooltip_text = tr("nav_back")
	_settings.tooltip_text = tr("nav_settings")


## Previews a notched phone on desktop. Pass Vector4(-1, -1, -1, -1) to use the device again.
func simulate_insets(insets: Vector4) -> void:
	simulated_insets = insets
	_apply_safe_area()


func _apply_safe_area() -> void:
	var insets := Vector4.ZERO
	if simulated_insets.x >= 0.0:
		insets = simulated_insets
	elif OS.has_feature("mobile"):
		var window := DisplayServer.window_get_size()
		var safe := DisplayServer.get_display_safe_area()
		var ratio := get_viewport_rect().size.y / maxf(1.0, float(window.y))
		insets = Vector4(
			safe.position.y,
			maxf(0.0, float(window.x - safe.end.x)),
			maxf(0.0, float(window.y - safe.end.y)),
			safe.position.x
		) * ratio
	var top := insets.x
	var right := insets.y
	var left := insets.w
	_title.offset_top = top
	_title.offset_bottom = top + HEADER_HEIGHT
	_title.offset_left = left + 60.0
	_title.offset_right = -right - 60.0
	_logo.offset_top = top + 12.0
	_logo.offset_bottom = top + 48.0
	_line.offset_top = top + HEADER_HEIGHT - 1.0
	_line.offset_bottom = top + HEADER_HEIGHT
	_back.offset_top = top + 4.0
	_back.offset_bottom = top + 56.0
	_back.offset_left = left + 4.0
	_back.offset_right = left + 56.0
	_settings.offset_top = top + 4.0
	_settings.offset_bottom = top + 56.0
	_settings.offset_left = -right - 56.0
	_settings.offset_right = -right - 4.0
	_host.offset_top = top + HEADER_HEIGHT
	_host.offset_bottom = -insets.z
	_host.offset_left = left
	_host.offset_right = -right
