class_name Screen
extends Control
## Base for every screen the router in scenes/main.gd shows.

const DRAG_DEADZONE := 16

var router: Node
var content: VBoxContainer
var params: Dictionary = {}


func title_key() -> String:
	return "app_name"


func shows_back() -> bool:
	return true


func shows_settings() -> bool:
	return true


## Called once after the router adds the screen.
func enter(_params: Dictionary) -> void:
	pass


## Called when a screen above this one is popped.
func resumed() -> void:
	pass


## Rebuilds after a language or text-size change.
func reload() -> void:
	enter(params)


func session() -> Dictionary:
	return router.session


func build_page() -> VBoxContainer:
	for child in get_children():
		child.queue_free()
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = DRAG_DEADZONE
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 24)
	scroll.add_child(margin)
	content = VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	content.child_entered_tree.connect(_pass_scroll_drags)
	margin.add_child(content)
	return content


## Buttons and sliders keep taps, but a drag continues into this scroll view.
## Other controls ignore the pointer so the drag is not swallowed.
func _pass_scroll_drags(node: Node) -> void:
	if node is LineEdit or node is TextEdit:
		return
	if node is BaseButton or node is Slider:
		var control := node as Control
		control.mouse_filter = Control.MOUSE_FILTER_PASS
		if node is Slider:
			_follow_slider(node as Slider)
	elif node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not node.child_entered_tree.is_connected(_pass_scroll_drags):
		node.child_entered_tree.connect(_pass_scroll_drags)


func _follow_slider(slider: Slider) -> void:
	var scroll := _scroll_ancestor(slider)
	if scroll == null:
		return
	slider.drag_started.connect(func() -> void:
		slider.set_meta("scroll_snapshot", slider.value)
	)
	var tracked: Array = scroll.get_meta("scroll_sliders", [])
	tracked.append(slider)
	scroll.set_meta("scroll_sliders", tracked)
	if scroll.has_meta("scroll_hooks"):
		return
	scroll.set_meta("scroll_hooks", true)
	scroll.scroll_started.connect(_freeze_sliders.bind(scroll))
	scroll.scroll_ended.connect(_thaw_sliders.bind(scroll))


func _scroll_ancestor(node: Node) -> ScrollContainer:
	var parent := node.get_parent()
	while parent:
		if parent is ScrollContainer:
			return parent
		parent = parent.get_parent()
	return null


func _freeze_sliders(scroll: ScrollContainer) -> void:
	for slider in scroll.get_meta("scroll_sliders", []):
		if not is_instance_valid(slider):
			continue
		if slider.has_meta("scroll_snapshot"):
			slider.value = float(slider.get_meta("scroll_snapshot"))
			slider.remove_meta("scroll_snapshot")
		slider.editable = false


func _thaw_sliders(scroll: ScrollContainer) -> void:
	for slider in scroll.get_meta("scroll_sliders", []):
		if is_instance_valid(slider):
			slider.editable = true


func show_error(target: Label, key: String) -> void:
	target.text = tr(key)
	target.visible = key != ""
