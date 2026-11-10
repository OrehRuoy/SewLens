class_name Screen
extends Control
## Base for every screen the router in scenes/main.gd shows.

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
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 24)
	scroll.add_child(margin)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	margin.add_child(content)
	return content


func show_error(target: Label, key: String) -> void:
	target.text = tr(key)
	target.visible = key != ""
