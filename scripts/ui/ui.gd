class_name UI
## Builders for the themed controls every screen uses. Text wraps by default
## so German and French strings grow downward instead of past the screen edge.

const CREAM := Color(0.956863, 0.941176, 0.901961)
const GOLD := Color(0.909804, 0.768627, 0.478431)
const NAVY := Color(0.109804, 0.227451, 0.360784)
const SKY := Color(0.380392, 0.529412, 0.682353)
const MUTED := Color(0.756863, 0.807843, 0.866667)
const DIVIDER := Color(0.380392, 0.529412, 0.682353, 0.3)
const PRIVACY_URL := "https://orehruoy.com/SewLens/privacy.html"
const TERMS_URL := "https://orehruoy.com/SewLens/terms.html"
const BUTTON_HEIGHT := 56.0
const LARGE_BUTTON_HEIGHT := 72.0
## Space a button keeps clear on each side for its leading icon.
const ICON_MARGIN := 50.0


static func button_height() -> float:
	return LARGE_BUTTON_HEIGHT if Profile.large_text else BUTTON_HEIGHT


static func label(text: String, variation: String = "") -> Label:
	var node := Label.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if variation != "":
		node.theme_type_variation = variation
	return node


static func heading(text: String) -> Label:
	return label(text, "HeadingLabel")


static func caption(text: String) -> Label:
	return label(text, "CaptionLabel")


static func error_label() -> Label:
	var node := label("", "ErrorLabel")
	node.visible = false
	return node


static func button(text: String, primary: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.custom_minimum_size = Vector2(0, button_height())
	node.focus_mode = Control.FOCUS_ALL
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if primary:
		node.theme_type_variation = "PrimaryButton"
	return node


## A button with a leading line icon. The text stays centred and keeps clear of the icon.
static func icon_button(text: String, icon: String, primary: bool = false) -> Button:
	var node := button(text, primary)
	_pad_styles(node, ICON_MARGIN, ICON_MARGIN)
	var glyph := _pin(LineIcon.new(icon, NAVY if primary else CREAM), true, 18.0)
	node.add_child(glyph)
	return node


## A borderless secondary action, such as Skip or Not now.
static func flat_button(text: String, variation: String = "FlatButton") -> Button:
	var node := button(text)
	node.theme_type_variation = variation
	return node


## A full-width row inside a group card: icon, wrapping label, and a chevron.
## `trailing` is "chevron", "check", "" or "switch".
static func list_row(text: String, icon: String = "", trailing: String = "chevron") -> Button:
	var node := Button.new()
	node.text = text
	node.theme_type_variation = "ListRow"
	node.alignment = HORIZONTAL_ALIGNMENT_LEFT
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.custom_minimum_size = Vector2(0, button_height())
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.focus_mode = Control.FOCUS_ALL
	if icon != "":
		node.add_child(_pin(LineIcon.new(icon, GOLD), true, 18.0))
		node.set_meta("divider_inset", 56.0)
	else:
		_pad_styles(node, 18.0, -1.0)
		node.set_meta("divider_inset", 18.0)
	match trailing:
		"chevron":
			node.add_child(_pin(LineIcon.new("chevron", SKY, 18.0), false, 16.0))
		"check":
			node.add_child(_pin(LineIcon.new("check", GOLD, 22.0), false, 14.0))
		"switch":
			_pad_styles(node, -1.0, 76.0)
			var toggle := Switch.new()
			toggle.name = "Switch"
			node.add_child(_pin(toggle, false, 16.0))
		_:
			_pad_styles(node, -1.0, 18.0)
	return node


## A rounded card that stacks rows with hairline dividers between them.
static func group(rows: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "GroupPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	panel.add_child(box)
	for index in rows.size():
		if index > 0:
			var above: Control = rows[index - 1]
			box.add_child(divider(float(above.get_meta("divider_inset", 16.0))))
		box.add_child(rows[index])
	return panel


## A labelled picker row for a group card: icon and title, then the choice field.
static func picker_row(title: String, icon: String, option: OptionButton) -> Control:
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 14)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	margin.add_child(box)
	var top := row(16)
	top.add_child(LineIcon.new(icon, GOLD))
	var name_label := label(title)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(name_label)
	box.add_child(top)
	option.theme_type_variation = "FieldOption"
	box.add_child(option)
	return margin


## Small uppercase heading above a group card.
static func section(text: String) -> Label:
	var node := label(text, "SectionLabel")
	node.uppercase = true
	return node


static func divider(inset: float = 0.0) -> Control:
	var line := Divider.new()
	line.inset = inset
	return line


## A check mark and a wrapping line of text, for what a purchase includes.
static func bullet(text: String, icon: String = "check") -> HBoxContainer:
	var line := row(10)
	var glyph := LineIcon.new(icon, GOLD, 20.0)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	line.add_child(glyph)
	line.add_child(label(text))
	return line


## A short pill label. Keep the text to a few words: it does not wrap.
static func badge(text: String) -> Label:
	var node := label(text, "BadgeLabel")
	node.autowrap_mode = TextServer.AUTOWRAP_OFF
	node.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return node


## An inline status message with a gold edge, for neutral news such as "Purchase recorded".
static func notice_label() -> Label:
	var node := label("", "NoticeLabel")
	node.visible = false
	return node


## A gold text link that opens `url` in the browser.
static func link(text: String, url: String) -> Button:
	var node := Button.new()
	node.text = text
	node.theme_type_variation = "TextLink"
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.focus_mode = Control.FOCUS_ALL
	node.pressed.connect(func() -> void: NativeBridge.open_url(url))
	return node


## A spinner over a centred status line. Returns the box; the label is named "Status".
## A thin rounded bar, `fraction` (0..1) filled in gold.
static func progress(fraction: float) -> Control:
	var bar := Progress.new()
	bar.fraction = clampf(fraction, 0.0, 1.0)
	return bar


static func spinner(text: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var wheel := Spinner.new()
	wheel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(wheel)
	var status := label(text)
	status.name = "Status"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status)
	return box


static func _pin(control: Control, left: bool, edge: float) -> Control:
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var side := control.custom_minimum_size
	control.anchor_top = 0.5
	control.anchor_bottom = 0.5
	control.anchor_left = 0.0 if left else 1.0
	control.anchor_right = control.anchor_left
	control.offset_top = -side.y / 2.0
	control.offset_bottom = side.y / 2.0
	control.offset_left = edge if left else -edge - side.x
	control.offset_right = control.offset_left + side.x
	return control


## Copies the button's styles with new side margins. -1 keeps a side as it is.
static func _pad_styles(node: Button, left: float, right: float) -> void:
	var type: StringName = node.theme_type_variation if node.theme_type_variation != &"" else &"Button"
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := node.get_theme_stylebox(state, type)
		if style == null:
			continue
		var copy := style.duplicate() as StyleBox
		if left >= 0.0:
			copy.content_margin_left = left
		if right >= 0.0:
			copy.content_margin_right = right
		node.add_theme_stylebox_override(state, copy)


static func card() -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = "CardPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	return box


## The card panel that owns a box returned by card().
static func card_panel(box: VBoxContainer) -> PanelContainer:
	return box.get_parent() as PanelContainer


static func spacer(height: float) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0, height)
	return node


static func row(separation: int = 12) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", separation)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return node


static func photo_rect(path: String, max_height: float) -> TextureRect:
	var rect := TextureRect.new()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.custom_minimum_size = Vector2(0, max_height)
	rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rect.texture = load_photo_texture(path)
	return rect


static func load_photo_texture(path: String) -> Texture2D:
	if path == "":
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	var error := image.load_jpg_from_buffer(bytes)
	if error != OK:
		error = image.load_png_from_buffer(bytes)
	if error != OK:
		error = image.load_webp_from_buffer(bytes)
	if error != OK:
		return null
	return ImageTexture.create_from_image(image)


static func mime_for(path: String) -> String:
	match path.get_extension().to_lower():
		"png":
			return "image/png"
		"webp":
			return "image/webp"
		_:
			return "image/jpeg"


class Divider extends Control:
	var inset := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 1)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_line(Vector2(inset, 0.5), Vector2(size.x, 0.5), UI.DIVIDER, 1.0)


## On/off pill drawn inside a toggle row. It reads its state from the row button.
class Switch extends Control:
	func _init() -> void:
		custom_minimum_size = Vector2(50, 30)

	func _ready() -> void:
		var owner_row := get_parent() as Button
		if owner_row:
			owner_row.toggled.connect(func(_on: bool) -> void: queue_redraw())

	func _draw() -> void:
		var owner_row := get_parent() as Button
		var on := owner_row != null and owner_row.button_pressed
		var radius := size.y / 2.0
		var fill := UI.GOLD if on else Color(UI.SKY, 0.45)
		draw_circle(Vector2(radius, radius), radius, fill)
		draw_circle(Vector2(size.x - radius, radius), radius, fill)
		draw_rect(Rect2(radius, 0, size.x - radius * 2.0, size.y), fill)
		var knob := Vector2(size.x - radius if on else radius, radius)
		draw_circle(knob, radius - 3.0, UI.NAVY if on else UI.CREAM)


class Progress extends Control:
	var fraction := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 6)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var radius := size.y / 2.0
		_pill(size.x, Color(UI.SKY, 0.35), radius)
		if fraction > 0.0:
			_pill(maxf(size.y, size.x * fraction), UI.GOLD, radius)

	func _pill(width: float, color: Color, radius: float) -> void:
		draw_circle(Vector2(radius, radius), radius, color)
		draw_circle(Vector2(width - radius, radius), radius, color)
		draw_rect(Rect2(radius, 0, maxf(0.0, width - radius * 2.0), size.y), color)


## A slow rotating arc for loading states.
class Spinner extends Control:
	var _angle := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(26, 26)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func _process(delta: float) -> void:
		_angle = fmod(_angle + delta * 5.0, TAU)
		queue_redraw()

	func _draw() -> void:
		var center := size / 2.0
		var radius := minf(size.x, size.y) / 2.0 - 2.0
		draw_arc(center, radius, 0.0, TAU, 40, Color(UI.SKY, 0.4), 3.0, true)
		draw_arc(center, radius, _angle, _angle + PI * 0.6, 20, UI.GOLD, 3.0, true)
