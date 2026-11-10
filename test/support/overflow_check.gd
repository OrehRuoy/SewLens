extends RefCounted
## Flags text that does not fit its Control: text wider than an unwrapped
## Label or Button, wrapped text cut off by max_lines_visible, or a text
## control that sticks out past the screen or its container sideways.

const TOLERANCE := 1.0


static func find(root: Node, screen: Rect2) -> Array:
	var problems: Array = []
	_walk(root, screen, problems)
	return problems


static func _walk(node: Node, screen: Rect2, problems: Array) -> void:
	if node is CanvasItem and not node.is_visible_in_tree():
		return
	if node is Control and _has_text(node):
		var problem := _check(node, screen)
		if problem != "":
			problems.append("%s: %s" % [node.get_path(), problem])
	for child in node.get_children():
		_walk(child, screen, problems)


static func _has_text(node: Control) -> bool:
	return (node is Label or node is Button or node is LineEdit) and str(node.get("text")) != ""


static func _check(node: Control, screen: Rect2) -> String:
	var rect := node.get_global_rect()
	if rect.position.x < screen.position.x - TOLERANCE or rect.end.x > screen.end.x + TOLERANCE:
		return "outside the screen (%s)" % rect
	var parent := node.get_parent() as Control
	if parent and not parent is ScrollContainer:
		var bounds := parent.get_global_rect()
		if rect.position.x < bounds.position.x - TOLERANCE or rect.end.x > bounds.end.x + TOLERANCE:
			return "wider than its container"
	if node is Label:
		var label := node as Label
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF and not label.clip_text and label.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
			if _text_width(label, label.text) > rect.size.x + TOLERANCE:
				return "text wider than the label"
		if label.max_lines_visible > 0 and label.get_line_count() > label.max_lines_visible:
			return "text cut after %d lines" % label.max_lines_visible
	elif node is Button and not node is OptionButton:
		var button := node as Button
		if button.autowrap_mode == TextServer.AUTOWRAP_OFF and not button.clip_text and button.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
			var style := button.get_theme_stylebox("normal")
			var needed := _text_width(button, button.text) + (style.get_margin(SIDE_LEFT) + style.get_margin(SIDE_RIGHT) if style else 0.0)
			if needed > rect.size.x + TOLERANCE:
				return "text wider than the button"
	return ""


static func _text_width(node: Control, text: String) -> float:
	var font := node.get_theme_font("font")
	var font_size := node.get_theme_font_size("font_size")
	return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
