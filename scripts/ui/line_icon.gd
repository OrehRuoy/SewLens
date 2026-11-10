class_name LineIcon
extends Control
## One icon set for the whole app, drawn as 2-unit strokes on a 24 x 24 grid,
## so icons stay sharp at any scale and match each other.

const KINDS := [
	"alert", "back", "camera", "chat", "check", "chevron", "code", "doc", "gear",
	"globe", "grid", "image", "lock", "page", "plus", "replay", "restore", "ruler",
	"scissors", "share", "shield", "sparkle", "star", "tag", "tape", "text", "trash",
]

var kind := "chevron":
	set(value):
		kind = value
		queue_redraw()
var color := UI.CREAM:
	set(value):
		color = value
		queue_redraw()


func _init(icon_kind: String = "chevron", icon_color: Color = UI.CREAM, side: float = 24.0) -> void:
	kind = icon_kind
	color = icon_color
	custom_minimum_size = Vector2(side, side)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	paint(self, kind, Rect2(Vector2.ZERO, size), color)


## Draws `icon` into `rect` on any CanvasItem.
static func paint(canvas: CanvasItem, icon: String, rect: Rect2, tint: Color) -> void:
	var side := minf(rect.size.x, rect.size.y)
	var unit := side / 24.0
	var origin := rect.position + (rect.size - Vector2(side, side)) / 2.0
	var stroke := maxf(1.5, 2.0 * unit)
	var pen := _Pen.new(canvas, origin, unit, stroke, tint)
	match icon:
		"back":
			pen.line([[15, 5], [8, 12], [15, 19]])
		"chevron":
			pen.line([[9, 5], [16, 12], [9, 19]])
		"gear":
			pen.circle(12, 12, 6.2)
			pen.circle(12, 12, 2.2)
			for index in 8:
				var direction := Vector2.RIGHT.rotated(TAU * index / 8.0)
				pen.segment(Vector2(12, 12) + direction * 7.6, Vector2(12, 12) + direction * 10.4, 1.6)
		"globe":
			pen.circle(12, 12, 9)
			pen.ellipse(12, 12, 4, 9)
			pen.line([[3, 12], [21, 12]])
		"text":
			pen.line([[3, 6], [13, 6]])
			pen.line([[8, 6], [8, 19]])
			pen.line([[14, 11], [21, 11]])
			pen.line([[17.5, 11], [17.5, 19]])
		"ruler":
			pen.rounded(Rect2(2.5, 7.5, 19, 9), 1.5)
			for tick in [[6.5, 10.5], [10.5, 12.5], [14.5, 10.5], [18.5, 12.5]]:
				pen.line([[tick[0], 7.5], [tick[0], tick[1]]])
		"page":
			pen.line([[6, 3], [14, 3], [19, 8], [19, 21], [6, 21], [6, 3]])
			pen.line([[14, 3], [14, 8], [19, 8]])
		"doc":
			pen.line([[6, 3], [14, 3], [19, 8], [19, 21], [6, 21], [6, 3]])
			pen.line([[14, 3], [14, 8], [19, 8]])
			pen.line([[9, 12], [16, 12]])
			pen.line([[9, 15.5], [16, 15.5]])
		"tape":
			pen.circle(10, 11, 7)
			pen.circle(10, 11, 2)
			pen.line([[10, 18], [21.5, 18]])
			for x in [14.0, 17.0, 20.0]:
				pen.line([[x, 18], [x, 15.5]])
		"star":
			var points: Array = []
			for index in 11:
				var radius := 9.5 if index % 2 == 0 else 4.2
				var angle := -PI / 2.0 + PI * index / 5.0
				points.append([12 + cos(angle) * radius, 12.8 + sin(angle) * radius])
			pen.line(points)
		"replay":
			pen.arc(12, 12, 8.5, deg_to_rad(-80), deg_to_rad(250))
			pen.line([[9.4, 1.6], [13.5, 3.4], [10.6, 6.8]])
			pen.fill([[10, 8.5], [16, 12], [10, 15.5]])
		"restore":
			pen.arc(12, 12, 8.5, deg_to_rad(-80), deg_to_rad(250))
			pen.line([[9.4, 1.6], [13.5, 3.4], [10.6, 6.8]])
			pen.line([[12, 8], [12, 12.5], [15, 14.5]])
		"code":
			pen.line([[8, 7], [3, 12], [8, 17]])
			pen.line([[16, 7], [21, 12], [16, 17]])
			pen.line([[14, 4.5], [10, 19.5]])
		"shield":
			pen.line([[12, 2.5], [19.5, 5.5], [19.5, 11], [17.8, 16], [12, 21.5], [6.2, 16], [4.5, 11], [4.5, 5.5], [12, 2.5]])
			pen.line([[8.6, 12], [11.2, 14.6], [15.6, 9.6]])
		"camera":
			pen.rounded(Rect2(2.5, 7, 19, 13), 2.5)
			pen.line([[8, 7], [9.6, 4.2], [14.4, 4.2], [16, 7]])
			pen.circle(12, 13.5, 3.6)
		"image":
			pen.rounded(Rect2(2.5, 4.5, 19, 15), 2.5)
			pen.line([[3, 17], [8.5, 11.5], [12.5, 15.5], [15.5, 12.5], [21, 17.5]])
			pen.dot(16, 8.8, 1.7)
		"sparkle":
			pen.fill([[11, 3], [12.8, 9.2], [19, 11], [12.8, 12.8], [11, 19], [9.2, 12.8], [3, 11], [9.2, 9.2]])
			pen.fill([[18.5, 15], [19.4, 17.6], [22, 18.5], [19.4, 19.4], [18.5, 22], [17.6, 19.4], [15, 18.5], [17.6, 17.6]])
		"grid":
			for corner in [Vector2(3.5, 3.5), Vector2(13.5, 3.5), Vector2(3.5, 13.5), Vector2(13.5, 13.5)]:
				pen.rounded(Rect2(corner, Vector2(7, 7)), 1.5)
		"check":
			pen.line([[5, 12.5], [10, 17.5], [19, 7]])
		"share":
			pen.line([[8.5, 10], [5, 10], [5, 21], [19, 21], [19, 10], [15.5, 10]])
			pen.line([[12, 3], [12, 15]])
			pen.line([[8, 7], [12, 3], [16, 7]])
		"scissors":
			pen.circle(6, 6.5, 2.8)
			pen.circle(6, 17.5, 2.8)
			pen.line([[8.3, 8.2], [20.5, 16.5]])
			pen.line([[8.3, 15.8], [20.5, 7.5]])
		"chat":
			pen.line([[5, 4], [19, 4], [21, 6], [21, 14], [19, 16], [12, 16], [7.5, 20.5], [7.5, 16], [5, 16], [3, 14], [3, 6], [5, 4]])
		"plus":
			pen.line([[12, 5], [12, 19]])
			pen.line([[5, 12], [19, 12]])
		"alert":
			pen.circle(12, 12, 9)
			pen.line([[12, 7], [12, 13]])
			pen.dot(12, 16.6, 1.3)
		"lock":
			pen.rounded(Rect2(5, 10.5, 14, 10.5), 2)
			pen.arc(12, 10.5, 4.5, PI, TAU)
			pen.dot(12, 15.5, 1.4)
		"tag":
			pen.line([[3, 12], [10, 5], [20.5, 5], [20.5, 19], [10, 19], [3, 12]])
			pen.circle(15.5, 12, 1.8)
		"trash":
			pen.line([[4, 6.5], [20, 6.5]])
			pen.line([[9, 6.5], [9, 3.5], [15, 3.5], [15, 6.5]])
			pen.line([[6, 6.5], [7.2, 21], [16.8, 21], [18, 6.5]])
			pen.line([[10.5, 10.5], [10.5, 17]])
			pen.line([[13.5, 10.5], [13.5, 17]])


class _Pen:
	var canvas: CanvasItem
	var origin: Vector2
	var scale: float
	var width: float
	var tint: Color

	func _init(target: CanvasItem, at: Vector2, factor: float, stroke: float, color: Color) -> void:
		canvas = target
		origin = at
		scale = factor
		width = stroke
		tint = color

	func at(x: float, y: float) -> Vector2:
		return origin + Vector2(x, y) * scale

	func line(points: Array) -> void:
		var out := PackedVector2Array()
		for point in points:
			out.append(at(point[0], point[1]))
		canvas.draw_polyline(out, tint, width, true)
		for point in [out[0], out[out.size() - 1]]:
			canvas.draw_circle(point, width / 2.0, tint)

	func segment(from: Vector2, to: Vector2, weight: float) -> void:
		canvas.draw_line(at(from.x, from.y), at(to.x, to.y), tint, width * weight, true)

	func circle(x: float, y: float, radius: float) -> void:
		canvas.draw_arc(at(x, y), radius * scale, 0.0, TAU, 40, tint, width, true)

	func arc(x: float, y: float, radius: float, from: float, to: float) -> void:
		canvas.draw_arc(at(x, y), radius * scale, from, to, 36, tint, width, true)

	func ellipse(x: float, y: float, rx: float, ry: float) -> void:
		var out := PackedVector2Array()
		for index in 41:
			var angle := TAU * index / 40.0
			out.append(at(x + cos(angle) * rx, y + sin(angle) * ry))
		canvas.draw_polyline(out, tint, width, true)

	func dot(x: float, y: float, radius: float) -> void:
		canvas.draw_circle(at(x, y), radius * scale, tint)

	func fill(points: Array) -> void:
		var out := PackedVector2Array()
		for point in points:
			out.append(at(point[0], point[1]))
		canvas.draw_colored_polygon(out, tint)

	func rounded(rect: Rect2, radius: float) -> void:
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
				out.append(at(point.x, point.y))
		out.append(out[0])
		canvas.draw_polyline(out, tint, width, true)
