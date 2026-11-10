class_name BodyDiagram
extends Control
## A front-view figure that highlights where one measurement is taken and
## prints the value in the person's units (cm, or inches for en_US).
## Coordinates are on a 100 x 200 grid that is scaled into the control.

const GRID := Vector2(100, 200)
const BODY_FILL := Color(0.215686, 0.392157, 0.572549)
const BODY_EDGE := Color(0.380392, 0.529412, 0.682353)

## circ: [center x, y, width]; line / dash: list of points; angle: shoulder slope.
const SPECS := {
	"head": {"circ": [50, 12, 21]},
	"neck": {"circ": [50, 26, 11]},
	"shoulderToShoulder": {"line": [[28, 32], [72, 32]]},
	"shoulderSlope": {"angle": [[55, 27], [72, 32]]},
	"chest": {"circ": [50, 42, 42]},
	"highBust": {"circ": [50, 37, 41]},
	"underbust": {"circ": [50, 52, 36]},
	"bustSpan": {"line": [[41, 43], [59, 43]]},
	"hpsToBust": {"line": [[56, 26], [59, 43]]},
	"hpsToWaistBack": {"dash": [[50, 24], [50, 78]]},
	"hpsToWaistFront": {"line": [[56, 26], [57, 43], [56, 78]]},
	"waistToArmpit": {"line": [[69, 48], [66, 78]]},
	"waist": {"circ": [50, 78, 32]},
	"waistBack": {"dash": [[34, 78], [66, 78]]},
	"hips": {"circ": [50, 86, 37]},
	"waistToHips": {"line": [[71, 78], [72, 86]]},
	"seat": {"circ": [50, 98, 40]},
	"seatBack": {"dash": [[30, 98], [70, 98]]},
	"waistToSeat": {"line": [[73, 78], [73, 98]]},
	"crossSeam": {"line": [[45, 78], [50, 108]], "dash": [[50, 108], [55, 78]]},
	"crossSeamFront": {"line": [[45, 78], [50, 108]]},
	"waistToUpperLeg": {"line": [[75, 78], [75, 112]]},
	"upperLeg": {"circ": [59, 114, 19]},
	"waistToKnee": {"line": [[77, 78], [74, 146]]},
	"knee": {"circ": [60, 146, 13]},
	"waistToFloor": {"line": [[80, 78], [80, 198]]},
	"ankle": {"circ": [58, 184, 9]},
	"heel": {"circ": [58, 191, 11]},
	"biceps": {"circ": [23, 54, 10]},
	"shoulderToElbow": {"line": [[28, 32], [19, 68]]},
	"shoulderToWrist": {"line": [[28, 32], [19, 68], [15, 96]]},
	"wrist": {"circ": [15, 96, 7]},
}

var measurement := "":
	set(value):
		measurement = value
		queue_redraw()
var value_mm := NAN:
	set(value):
		value_mm = value
		queue_redraw()
var unit := "cm":
	set(value):
		unit = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(0, 300)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


static func has_spec(key: String) -> bool:
	return SPECS.has(key)


## The text drawn next to the highlight, e.g. "96 cm" or "37.75 in".
func value_text() -> String:
	if measurement == "":
		return ""
	var shown := value_mm
	if is_nan(shown):
		shown = float(DesignCatalog.measurement(measurement).get("typical", 0))
	var prefix := "" if not is_nan(value_mm) else "≈ "
	return prefix + Units.format(shown, unit, DesignCatalog.kind(measurement))


func _scale() -> float:
	return minf(size.x / GRID.x, size.y / GRID.y)


func _point(grid: Vector2) -> Vector2:
	var scale := _scale()
	var offset := (size - GRID * scale) / 2.0
	return offset + grid * scale


func _points(list: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for item in list:
		out.append(_point(Vector2(item[0], item[1])))
	return out


func _draw() -> void:
	_draw_body()
	var spec: Dictionary = SPECS.get(measurement, {})
	var scale := _scale()
	var width := maxf(2.5, scale * 1.4)
	var anchor := Vector2.ZERO
	if spec.has("circ"):
		var circ: Array = spec.circ
		var center := _point(Vector2(circ[0], circ[1]))
		var radius := Vector2(circ[2] * scale / 2.0, maxf(3.0, circ[2] * scale / 9.0))
		_draw_ellipse(center, radius, UI.GOLD, width)
		anchor = center + Vector2(radius.x + 6, -radius.y)
	if spec.has("line"):
		var line := _points(spec.line)
		draw_polyline(line, UI.GOLD, width, true)
		for tip in [line[0], line[line.size() - 1]]:
			draw_circle(tip, width * 1.2, UI.GOLD)
		anchor = line[line.size() - 1]
	if spec.has("dash"):
		var dash := _points(spec.dash)
		for index in dash.size() - 1:
			draw_dashed_line(dash[index], dash[index + 1], UI.GOLD, width, width * 3.0, true)
		if not spec.has("line"):
			anchor = dash[dash.size() - 1]
	if spec.has("angle"):
		var angle := _points(spec.angle)
		draw_line(angle[0], Vector2(angle[1].x, angle[0].y), UI.CREAM, maxf(1.5, width * 0.6), true)
		draw_line(angle[0], angle[1], UI.GOLD, width, true)
		anchor = angle[1]
	var text := value_text()
	if text != "":
		_draw_value(anchor, text)


func _draw_body() -> void:
	var torso := _points([[28, 31], [45, 27], [55, 27], [72, 31], [74, 36], [70, 48], [66, 78], [69, 92], [70, 104], [50, 109], [30, 104], [31, 92], [34, 78], [30, 48], [26, 36]])
	var left_arm := _points([[27, 32], [22, 36], [17, 66], [12, 96], [18, 97], [21, 68], [29, 47]])
	var right_arm := _points([[73, 32], [78, 36], [83, 66], [88, 96], [82, 97], [79, 68], [71, 47]])
	var left_leg := _points([[30, 103], [49, 108], [47, 186], [53, 194], [37, 194], [38, 186], [33, 146]])
	var right_leg := _points([[70, 103], [51, 108], [53, 186], [47, 194], [63, 194], [62, 186], [67, 146]])
	for shape in [left_arm, right_arm, left_leg, right_leg, torso]:
		draw_colored_polygon(shape, BODY_FILL)
		var closed: PackedVector2Array = shape.duplicate()
		closed.append(shape[0])
		draw_polyline(closed, BODY_EDGE, 1.5, true)
	var neck := _points([[45, 22], [55, 22], [55, 28], [45, 28]])
	draw_colored_polygon(neck, BODY_FILL)
	var head := _point(Vector2(50, 12))
	draw_circle(head, 10.0 * _scale(), BODY_FILL)
	draw_arc(head, 10.0 * _scale(), 0.0, TAU, 48, BODY_EDGE, 1.5, true)


func _draw_ellipse(center: Vector2, radius: Vector2, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for index in 49:
		var angle := TAU * index / 48.0
		points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
	draw_polyline(points, color, width, true)


func _draw_value(anchor: Vector2, text: String) -> void:
	var font := get_theme_default_font()
	var font_size := 18
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad := Vector2(8, 4)
	var origin := anchor + Vector2(8, -text_size.y / 2.0)
	origin.x = clampf(origin.x, 0.0, maxf(0.0, size.x - text_size.x - pad.x * 2.0))
	origin.y = clampf(origin.y, 0.0, maxf(0.0, size.y - text_size.y - pad.y * 2.0))
	var box := Rect2(origin, text_size + pad * 2.0)
	var tag := StyleBoxFlat.new()
	tag.bg_color = UI.NAVY
	tag.border_color = UI.GOLD
	tag.set_border_width_all(2)
	tag.set_corner_radius_all(8)
	tag.anti_aliasing = true
	draw_style_box(tag, box)
	draw_string(font, origin + Vector2(pad.x, pad.y + font.get_ascent(font_size)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, UI.CREAM)
