extends Screen
## Sewing steps for the drafted design, plus the cheap-fabric banner.

func title_key() -> String:
	return "title_guide"


func enter(_params: Dictionary) -> void:
	var page := build_page()
	var design := str(session().get("design", ""))
	page.add_child(UI.heading(DesignCatalog.display_name(design)))
	page.add_child(UI.label(tr("guide_banner_test_fabric"), "NoticeLabel"))
	var guide := GuideCatalog.guide(design)
	var steps: Array = guide.get("steps", [])
	var rows: Array = []
	for index in steps.size():
		var line := MarginContainer.new()
		for side in ["left", "right"]:
			line.add_theme_constant_override("margin_" + side, 16)
		line.add_theme_constant_override("margin_top", 14)
		line.add_theme_constant_override("margin_bottom", 14)
		var content := UI.row(14)
		var number := StepNumber.new()
		number.value = index + 1
		number.tooltip_text = tr("fmt_step") % [index + 1, steps.size()]
		content.add_child(number)
		content.add_child(UI.label(tr(str(steps[index]))))
		line.add_child(content)
		line.set_meta("divider_inset", 60.0)
		rows.append(line)
	if not rows.is_empty():
		page.add_child(UI.group(rows))
	var notes: Array = guide.get("notes", [])
	if not notes.is_empty():
		page.add_child(UI.spacer(4))
		page.add_child(UI.section(tr("guide_notes_heading")))
		var card := UI.card()
		for key in notes:
			card.add_child(UI.bullet(tr(str(key)), "alert"))
		page.add_child(UI.card_panel(card))


## A gold disc with the step number, aligned to the first line of the step text.
class StepNumber extends Control:
	var value := 1

	func _init() -> void:
		custom_minimum_size = Vector2(30, 30)
		size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	func _draw() -> void:
		var radius := minf(size.x, size.y) / 2.0
		draw_circle(size / 2.0, radius, UI.GOLD)
		var font := get_theme_default_font()
		var font_size := int(radius * 1.05)
		var text := str(value)
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		var baseline := size.y / 2.0 + (font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
		draw_string(font, Vector2((size.x - width) / 2.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UI.NAVY)
