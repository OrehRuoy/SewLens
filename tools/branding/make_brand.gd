extends SceneTree
## Writes the SewLens logo, app icons, and splash from one set of shapes, so
## every size matches. The mark is a lens whose handle is a sewing needle,
## with a running stitch seen through the glass.
##
##   godot --headless --path . -s res://tools/branding/make_brand.gd

const NAVY := "#1C3A5C"
const NAVY_LIGHT := "#264B73"
const NAVY_DARK := "#16304D"
const GLASS := "#2B537E"
const GOLD := "#E8C47A"
const CREAM := "#F4F0E6"
const WHITE := "#FFFFFF"

## Mark geometry on a 100 x 100 grid.
const CENTER := Vector2(43, 43)
const RADIUS := 25.0
const AXIS := Vector2(0.70710678, 0.70710678)
const NORMAL := Vector2(-0.70710678, 0.70710678)
const STITCH_SPAN := Vector2(23.5, 62.5)
const STITCH_WAVE := 5.0
const NEEDLE_START := 27.0
const NEEDLE_HALF := 5.4

## Noto Sans capital height as a fraction of the font size.
const CAP_HEIGHT := 0.714
const IOS_SIZES := [40, 58, 60, 76, 80, 87, 114, 120, 128, 136, 152, 167, 180, 192]
const SMALL_ICON := 90

var _font: FontFile


func _initialize() -> void:
	_font = load("res://assets/fonts/NotoSans-Regular.ttf")
	for dir in ["res://assets/branding/ios", "res://assets/branding/android", "res://store/icons"]:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_write("res://assets/branding/logo_mark.svg", _mark_svg(256, {}))
	for size in [64, 128, 256, 512, 1024]:
		_png(_mark_svg(size, {}), "res://assets/branding/logo_mark_%d.png" % size)
	var wordmark := _wordmark_svg(192)
	_write("res://assets/branding/logo_wordmark.svg", wordmark)
	for scale in [1, 2, 3]:
		_png(_wordmark_svg(40 * scale), "res://assets/branding/logo_wordmark@%dx.png" % scale)
	_png(_splash_svg(1200), "res://assets/branding/splash.png")
	var icon := _icon_svg(1024, true, false)
	_png(icon, "res://assets/icon_1024.png", true)
	_png(icon, "res://store/icons/app_store_1024.png", true)
	_png(_icon_svg(512, true, false), "res://store/icons/play_store_512.png", true)
	for size in IOS_SIZES:
		_png(_icon_svg(size, size > SMALL_ICON, false), "res://assets/branding/ios/icon_%d.png" % size, true)
	_png(_bare_svg(1024, {"ring": GOLD, "glass": GLASS, "stitch": CREAM, "needle": GOLD}, 0.62), "res://assets/branding/ios/icon_1024_dark.png")
	_png(_bare_svg(1024, {"ring": "#E6E6E6", "glass": "", "stitch": "#9A9A9A", "needle": "#E6E6E6"}, 0.62), "res://assets/branding/ios/icon_1024_tinted.png")
	_png(_icon_svg(256, true, true), "res://assets/icon.png")
	_png(_icon_svg(192, true, true), "res://assets/branding/android/icon_192.png")
	_png(_adaptive_background(432), "res://assets/branding/android/adaptive_background_432.png", true)
	_png(_bare_svg(432, {"ring": GOLD, "glass": GLASS, "stitch": CREAM, "needle": GOLD}, 0.5), "res://assets/branding/android/adaptive_foreground_432.png")
	_png(_bare_svg(432, {"ring": WHITE, "glass": "", "stitch": WHITE, "needle": WHITE}, 0.5), "res://assets/branding/android/adaptive_monochrome_432.png")
	print("make_brand: wrote logo, wordmark, splash, %d iOS sizes, Android layers, store icons" % (IOS_SIZES.size() + 3))
	quit()


## The mark on a transparent square, sized to `size` pixels.
func _mark_svg(size: int, colors: Dictionary) -> String:
	return _bare_svg(size, colors, 0.92)


## The mark centred on a transparent square, filling `fill` of its width.
func _bare_svg(size: int, colors: Dictionary, fill: float) -> String:
	var body := _mark(colors, size * fill > 60.0, 1.0)
	return _svg(size, size, _place(body, size, fill))


## A full-bleed app icon: navy background with a soft highlight, mark on top.
## `rounded` cuts the corners for desktop and the legacy Android launcher.
func _icon_svg(size: int, detail: bool, rounded: bool) -> String:
	var defs := _background_gradient()
	var corner := size * 0.2237 if rounded else 0.0
	var background := "<rect width=\"%d\" height=\"%d\" rx=\"%s\" fill=\"url(#bg)\"/>" % [size, size, _n(corner)]
	var weight := 1.0 if detail else 1.25
	var mark := _place(_mark({}, detail, weight), size, 0.64 if not rounded else 0.6)
	return _svg(size, size, defs + background + mark)


func _adaptive_background(size: int) -> String:
	return _svg(size, size, _background_gradient() + "<rect width=\"%d\" height=\"%d\" fill=\"url(#bg)\"/>" % [size, size])


func _background_gradient() -> String:
	return "<defs><radialGradient id=\"bg\" cx=\"0.3\" cy=\"0.22\" r=\"0.95\"><stop offset=\"0\" stop-color=\"%s\"/><stop offset=\"0.6\" stop-color=\"%s\"/><stop offset=\"1\" stop-color=\"%s\"/></radialGradient></defs>" % [NAVY_LIGHT, NAVY, NAVY_DARK]


## Mark plus "SewLens" set in the app font, `height` pixels tall.
func _wordmark_svg(height: int) -> String:
	var box := _mark_bounds()
	var scale := height / box.size.y
	var text_size := height * 0.66
	var text := _text_paths("SewLens", text_size, [CREAM, CREAM, CREAM, GOLD, GOLD, GOLD, GOLD])
	var gap := height * 0.14
	var mark_width := box.size.x * scale
	var width: float = mark_width + gap + float(text.width) + text_size * 0.06
	var detail := height >= 60
	var mark := "<g transform=\"translate(%s %s) scale(%s)\">%s</g>" % [_n(-box.position.x * scale), _n(-box.position.y * scale), _n(scale), _mark({}, detail, 1.0 if detail else 1.2)]
	var baseline := (CENTER.y - box.position.y) * scale + text_size * CAP_HEIGHT / 2.0
	var words := "<g transform=\"translate(%s %s)\">%s</g>" % [_n(mark_width + gap), _n(baseline), text.svg]
	return _svg(int(ceil(width)), height, mark + words)


## Logo stacked over the name, centred on a transparent square for the boot splash.
func _splash_svg(size: int) -> String:
	var box := _mark_bounds()
	var mark_height := size * 0.24
	var scale := mark_height / box.size.y
	var text_size := size * 0.09
	var text := _text_paths("SewLens", text_size, [CREAM, CREAM, CREAM, GOLD, GOLD, GOLD, GOLD])
	var gap := size * 0.05
	var top := size * 0.5 - (mark_height + gap + text_size * CAP_HEIGHT) / 2.0
	var left := (size - box.size.x * scale) / 2.0
	var mark := "<g transform=\"translate(%s %s) scale(%s)\">%s</g>" % [_n(left - box.position.x * scale), _n(top - box.position.y * scale), _n(scale), _mark({}, true, 1.0)]
	var baseline := top + mark_height + gap + text_size * CAP_HEIGHT
	var words := "<g transform=\"translate(%s %s)\">%s</g>" % [_n((size - float(text.width)) / 2.0), _n(baseline), text.svg]
	return _svg(size, size, mark + words)


## Scales the 100-unit mark so its outline fills `fill` of the square and is centred.
func _place(body: String, size: int, fill: float) -> String:
	var box := _mark_bounds()
	var scale := size * fill / maxf(box.size.x, box.size.y)
	var offset := Vector2(size, size) / 2.0 - box.get_center() * scale
	return "<g transform=\"translate(%s %s) scale(%s)\">%s</g>" % [_n(offset.x), _n(offset.y), _n(scale), body]


func _mark_bounds() -> Rect2:
	var outer := RADIUS + 4.25
	var box := Rect2(CENTER - Vector2(outer, outer), Vector2(outer, outer) * 2.0)
	for point in _needle_outline():
		box = box.expand(point)
	return box


## SVG elements for the mark on the 100 grid. Empty colour strings skip a part.
func _mark(colors: Dictionary, detail: bool, weight: float) -> String:
	var ring_color: String = colors.get("ring", GOLD)
	var glass: String = colors.get("glass", GLASS)
	var stitch: String = colors.get("stitch", CREAM)
	var needle: String = colors.get("needle", GOLD)
	var ring := 8.5 * weight
	var out := ""
	if glass != "":
		out += "<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"%s\"/>" % [_n(CENTER.x), _n(CENTER.y), _n(RADIUS), glass]
	if stitch != "":
		out += _stitches(stitch, detail, weight)
	out += "<circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"none\" stroke=\"%s\" stroke-width=\"%s\"/>" % [_n(CENTER.x), _n(CENTER.y), _n(RADIUS), ring_color, _n(ring)]
	out += "<path fill-rule=\"evenodd\" fill=\"%s\" d=\"%s %s\"/>" % [needle, _poly(_needle_outline()), _poly(_needle_eye(weight))]
	return out


## Running stitch along a wavy seam across the glass. Small icons get three thick stitches.
func _stitches(color: String, detail: bool, weight: float) -> String:
	var samples := PackedVector2Array()
	for index in 121:
		var t := index / 120.0
		var x := lerpf(STITCH_SPAN.x, STITCH_SPAN.y, t)
		samples.append(Vector2(x, CENTER.y + 1.0 - sin(t * TAU) * STITCH_WAVE))
	var lengths := PackedFloat32Array([0.0])
	for index in range(1, samples.size()):
		lengths.append(lengths[index - 1] + samples[index].distance_to(samples[index - 1]))
	var total := lengths[lengths.size() - 1]
	var count := 4 if detail else 3
	var inset := 3.0
	var usable := total - inset * 2.0
	var dash := usable * (0.58 if detail else 0.62) / count
	var gap := (usable - dash * count) / maxf(1, count - 1)
	var width := (4.4 if detail else 6.0) * weight
	var out := ""
	for stitch in count:
		var start := inset + stitch * (dash + gap)
		var points := PackedVector2Array()
		for index in samples.size():
			if lengths[index] >= start and lengths[index] <= start + dash:
				points.append(samples[index])
		out += "<path d=\"%s\" fill=\"none\" stroke=\"%s\" stroke-width=\"%s\" stroke-linecap=\"round\"/>" % [_poly(points, false), color, _n(width)]
	return out


## Needle along the 45° axis: rounded eye end at the ring, tapering to a point.
func _needle_outline() -> PackedVector2Array:
	var start := CENTER + AXIS * NEEDLE_START
	var half := NEEDLE_HALF
	var body := 25.0
	var tip := 42.0
	var points := PackedVector2Array()
	for index in 13:
		var angle := PI / 2.0 + PI * index / 12.0
		points.append(_frame(start, cos(angle) * half, sin(angle) * half))
	for index in 13:
		var t := index / 12.0
		points.append(_frame(start, lerpf(body, tip, t), -half * pow(1.0 - t, 0.85)))
	for index in range(11, -1, -1):
		var t := index / 12.0
		points.append(_frame(start, lerpf(body, tip, t), half * pow(1.0 - t, 0.85)))
	return points


func _needle_eye(weight: float) -> PackedVector2Array:
	var start := CENTER + AXIS * NEEDLE_START
	var half := 1.8 / clampf(weight, 1.0, 1.3)
	var points := PackedVector2Array()
	for index in 9:
		var angle := PI / 2.0 + PI * index / 8.0
		points.append(_frame(start, 7.5 + cos(angle) * half, sin(angle) * half))
	for index in 9:
		var angle := -PI / 2.0 + PI * index / 8.0
		points.append(_frame(start, 15.5 + cos(angle) * half, sin(angle) * half))
	return points


func _frame(origin: Vector2, along: float, across: float) -> Vector2:
	return origin + AXIS * along + NORMAL * across


## Outlines of `text` in the app font as SVG paths, with a same-colour stroke
## for a bolder weight. Returns {svg, width}.
func _text_paths(text: String, font_size: float, colors: Array) -> Dictionary:
	var server := TextServerManager.get_primary_interface()
	var rid: RID = _font.get_rids()[0]
	var size := 128
	var scale := font_size / size
	var shaped := server.create_shaped_text()
	server.shaped_text_add_string(shaped, text, [rid], size)
	var x := 0.0
	var out := ""
	var glyphs := server.shaped_text_get_glyphs(shaped)
	for index in glyphs.size():
		var glyph: Dictionary = glyphs[index]
		var contours: Dictionary = server.font_get_glyph_contours(rid, size, int(glyph.index))
		var color: String = colors[mini(index, colors.size() - 1)]
		var path := _glyph_path(contours, Vector2(x + float(glyph.offset.x), float(glyph.offset.y)), scale)
		if path != "":
			out += "<path d=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%s\" stroke-linejoin=\"round\"/>" % [path, color, color, _n(font_size * 0.045)]
		x += float(glyph.advance)
	server.free_rid(shaped)
	return {"svg": out, "width": x * scale}


## Converts FreeType contours (on-curve, conic and cubic points) to SVG path data.
func _glyph_path(contours: Dictionary, offset: Vector2, scale: float) -> String:
	var points: PackedVector3Array = contours.get("points", PackedVector3Array())
	var ends: PackedInt32Array = contours.get("contours", PackedInt32Array())
	var d := ""
	var first := 0
	for end in ends:
		var ring: Array = []
		for index in range(first, end + 1):
			var p := points[index]
			ring.append({"at": (Vector2(p.x, p.y) + offset) * scale, "tag": int(p.z)})
		first = end + 1
		d += _contour(ring)
	return d


func _contour(ring: Array) -> String:
	if ring.is_empty():
		return ""
	var start := -1
	for index in ring.size():
		if ring[index].tag == 1:
			start = index
			break
	var origin: Vector2
	if start == -1:
		origin = (ring[0].at + ring[1].at) / 2.0
		start = 0
	else:
		origin = ring[start].at
	var d := "M%s %s" % [_n(origin.x), _n(origin.y)]
	var control = null
	var cubic: Array = []
	for step in range(1, ring.size() + 1):
		var item: Dictionary = ring[(start + step) % ring.size()]
		var at: Vector2 = item.at if step < ring.size() else origin
		var tag: int = item.tag if step < ring.size() else 1
		if tag == 1:
			if not cubic.is_empty():
				d += "C%s %s %s %s %s %s" % [_n(cubic[0].x), _n(cubic[0].y), _n(cubic[1].x), _n(cubic[1].y), _n(at.x), _n(at.y)]
				cubic.clear()
			elif control != null:
				d += "Q%s %s %s %s" % [_n(control.x), _n(control.y), _n(at.x), _n(at.y)]
			else:
				d += "L%s %s" % [_n(at.x), _n(at.y)]
			control = null
		elif tag == 2:
			cubic.append(at)
		else:
			if control != null:
				var middle: Vector2 = (control + at) / 2.0
				d += "Q%s %s %s %s" % [_n(control.x), _n(control.y), _n(middle.x), _n(middle.y)]
			control = at
	return d + "Z"


func _poly(points: PackedVector2Array, closed: bool = true) -> String:
	var d := ""
	for index in points.size():
		d += ("M" if index == 0 else "L") + "%s %s" % [_n(points[index].x), _n(points[index].y)]
	return d + ("Z" if closed else "")


func _svg(width: int, height: int, body: String) -> String:
	return "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"%d\" height=\"%d\" viewBox=\"0 0 %d %d\">%s</svg>\n" % [width, height, width, height, body]


func _n(value: float) -> String:
	return String.num(value, 2)


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## Rasterizes an SVG string. `opaque` drops the alpha channel (App Store icon rule).
func _png(svg: String, path: String, opaque: bool = false) -> void:
	var image := Image.new()
	var error := image.load_svg_from_string(svg, 1.0)
	if error != OK:
		push_error("SVG failed for %s" % path)
		return
	if opaque:
		image.convert(Image.FORMAT_RGB8)
	image.save_png(path)
