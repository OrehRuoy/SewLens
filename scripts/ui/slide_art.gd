class_name SlideArt
extends Control
## Onboarding and home pictures on a 100 x 100 grid, in the same flat figure
## style as BodyDiagram: "photo", "measure" or "print".

const PAPER_DARK := Color(0.086275, 0.188235, 0.301961)

var kind := "photo"


func _init(art_kind: String = "photo", height: float = 280.0) -> void:
	kind = art_kind
	custom_minimum_size = Vector2(0, height)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	if kind != "measure":
		return
	var diagram := BodyDiagram.new()
	diagram.unit = LocaleService.units()
	diagram.measurement = "chest"
	diagram.custom_minimum_size = Vector2.ZERO
	diagram.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	diagram.offset_top = 16
	diagram.offset_bottom = -16
	add_child(diagram)


func _unit() -> float:
	return minf(size.x, size.y) / 100.0


func _at(x: float, y: float) -> Vector2:
	var unit := _unit()
	return (size - Vector2(100, 100) * unit) / 2.0 + Vector2(x, y) * unit


func _poly(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point in points:
		out.append(_at(point[0], point[1]))
	return out


func _curve(from: Vector2, control: Vector2, to: Vector2, steps: int = 8) -> Array:
	var out: Array = []
	for step in range(1, steps + 1):
		var t := float(step) / steps
		var point := from.lerp(control, t).lerp(control.lerp(to, t), t)
		out.append([point.x, point.y])
	return out


func _shape(points: PackedVector2Array, fill: Color, edge: Color, width: float) -> void:
	draw_colored_polygon(points, fill)
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, edge, width, true)


func _rounded(rect: Rect2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var corners := [
		[rect.position + Vector2(rect.size.x - radius, radius), -PI / 2.0],
		[rect.end - Vector2(radius, radius), 0.0],
		[rect.position + Vector2(radius, rect.size.y - radius), PI / 2.0],
		[rect.position + Vector2(radius, radius), PI],
	]
	for corner in corners:
		for step in 7:
			var angle: float = corner[1] + PI / 2.0 * step / 6.0
			var point: Vector2 = corner[0] + Vector2(cos(angle), sin(angle)) * radius
			out.append(_at(point.x, point.y))
	return out


func _draw() -> void:
	var unit := _unit()
	draw_circle(_at(50, 50), 47.0 * unit, Color(BodyDiagram.BODY_FILL, 0.28))
	draw_arc(_at(50, 50), 47.0 * unit, 0.0, TAU, 64, Color(BodyDiagram.BODY_EDGE, 0.35), 1.0, true)
	if kind == "photo":
		_draw_photo(unit)
	elif kind == "print":
		_draw_print(unit)


func _draw_photo(unit: float) -> void:
	var edge := maxf(1.5, unit * 0.8)
	_shape(_rounded(Rect2(29, 7, 42, 86), 7), PAPER_DARK, BodyDiagram.BODY_EDGE, edge)
	draw_colored_polygon(_rounded(Rect2(33, 15, 34, 64), 2.5), UI.NAVY)
	var tee: Array = [[44, 28], [38, 30.5], [34.8, 38], [39, 40.5], [40.5, 38], [40.5, 64], [59.5, 64], [59.5, 38], [61, 40.5], [65.2, 38], [62, 30.5], [56, 28]]
	tee.append_array(_curve(Vector2(56, 28), Vector2(50, 34), Vector2(44, 28), 8))
	_shape(_poly(tee), BodyDiagram.BODY_FILL, BodyDiagram.BODY_EDGE, edge)
	var bracket := maxf(2.5, unit * 1.3)
	for corner in [[36, 19, 1, 1], [64, 19, -1, 1], [36, 75, 1, -1], [64, 75, -1, -1]]:
		var tip := Vector2(corner[0], corner[1])
		var line := _poly([[tip.x, tip.y + 6 * corner[3]], [tip.x, tip.y], [tip.x + 6 * corner[2], tip.y]])
		draw_polyline(line, UI.GOLD, bracket, true)
	draw_line(_at(36.5, 46), _at(63.5, 46), Color(UI.GOLD, 0.85), maxf(1.5, unit * 0.7), true)
	for x in [36.5, 63.5]:
		draw_circle(_at(x, 46), maxf(2.0, unit * 1.1), UI.GOLD)
	draw_arc(_at(50, 86), 3.2 * unit, 0.0, TAU, 32, UI.CREAM, edge, true)


func _draw_print(unit: float) -> void:
	var edge := maxf(1.5, unit * 0.8)
	_shape(_rounded(Rect2(21, 12, 58, 76), 3), BodyDiagram.BODY_FILL, BodyDiagram.BODY_EDGE, edge)
	var tile := Color(BodyDiagram.BODY_EDGE, 0.9)
	draw_dashed_line(_at(50, 12), _at(50, 88), tile, maxf(1.0, unit * 0.5), unit * 2.2, true)
	draw_dashed_line(_at(21, 50), _at(79, 50), tile, maxf(1.0, unit * 0.5), unit * 2.2, true)
	var piece: Array = [[40, 21]]
	piece.append([58, 25])
	piece.append_array(_curve(Vector2(58, 25), Vector2(55, 40), Vector2(63, 44), 8))
	piece.append_array([[61, 77], [33, 79], [33, 33]])
	piece.append_array(_curve(Vector2(33, 33), Vector2(40, 32), Vector2(40, 21), 8))
	var outline := _poly(piece)
	draw_colored_polygon(outline, Color(UI.GOLD, 0.12))
	var closed := outline.duplicate()
	closed.append(outline[0])
	draw_polyline(closed, UI.GOLD, maxf(2.5, unit * 1.2), true)
	var stroke := maxf(1.5, unit * 0.7)
	for notch in [[[61.6, 58], [58.6, 58.2]], [[33, 56], [36, 56]]]:
		draw_line(_at(notch[0][0], notch[0][1]), _at(notch[1][0], notch[1][1]), UI.GOLD, stroke, true)
	draw_line(_at(46, 38), _at(46, 68), UI.CREAM, stroke, true)
	for tip in [[46, 38, -1], [46, 68, 1]]:
		draw_polyline(_poly([[tip[0] - 2.4, tip[1] - 3 * tip[2]], [tip[0], tip[1]], [tip[0] + 2.4, tip[1] - 3 * tip[2]]]), UI.CREAM, stroke, true)
	draw_polyline(_poly([[66, 16], [74, 16], [74, 24], [66, 24], [66, 16]]), UI.CREAM, stroke, true)
	var blade := maxf(2.0, unit * 1.0)
	for line in [[[79, 92], [62, 70]], [[85, 86], [62, 76]]]:
		draw_line(_at(line[0][0], line[0][1]), _at(line[1][0], line[1][1]), PAPER_DARK, blade + 3.0, true)
		draw_line(_at(line[0][0], line[0][1]), _at(line[1][0], line[1][1]), UI.CREAM, blade, true)
	for loop in [[80.5, 94], [87.5, 87]]:
		draw_circle(_at(loop[0], loop[1]), 3.6 * unit, PAPER_DARK)
		draw_arc(_at(loop[0], loop[1]), 3.6 * unit, 0.0, TAU, 32, UI.CREAM, blade, true)
