class_name IconButton
extends Button
## A header button drawn in code, so it needs no icon files and no text.
## tooltip_text carries the translated name for screen readers.

@export_enum("back", "settings") var kind := "back"


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(52, 52)


func _draw() -> void:
	var color := UI.GOLD if is_hovered() or button_pressed else UI.CREAM
	var side := 30.0
	LineIcon.paint(self, "back" if kind == "back" else "gear", Rect2((size - Vector2(side, side)) / 2.0, Vector2(side, side)), color)
