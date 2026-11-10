extends Screen
## Three slides on first launch: photo, measure, print. Ends on the home screen.

const SLIDES := [
	{"title": "onb_photo_title", "body": "onb_photo_body", "art": "photo"},
	{"title": "onb_measure_title", "body": "onb_measure_body", "art": "measure"},
	{"title": "onb_print_title", "body": "onb_print_body", "art": "print"},
]

var index := 0


func shows_back() -> bool:
	return false


func shows_settings() -> bool:
	return false


func enter(params: Dictionary) -> void:
	index = int(params.get("slide", 0))
	_render()


func _render() -> void:
	var page := build_page()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var slide: Dictionary = SLIDES[index]
	page.add_child(SlideArt.new(slide.art))
	var dots := StepDots.new()
	dots.count = SLIDES.size()
	dots.current = index
	dots.tooltip_text = tr("fmt_step") % [index + 1, SLIDES.size()]
	page.add_child(dots)
	page.add_child(UI.heading(tr(slide.title)))
	page.add_child(UI.label(tr(slide.body)))
	if slide.art == "photo":
		var privacy := UI.bullet(tr("onb_privacy"), "lock")
		(privacy.get_child(1) as Label).theme_type_variation = "CaptionLabel"
		page.add_child(privacy)
	var push := Control.new()
	push.size_flags_vertical = Control.SIZE_EXPAND_FILL
	push.custom_minimum_size = Vector2(0, 8)
	page.add_child(push)
	var last := index == SLIDES.size() - 1
	var next := UI.button(tr("btn_start") if last else tr("btn_next"), true)
	next.name = "NextButton"
	next.pressed.connect(_next)
	page.add_child(next)
	if not last:
		var skip := UI.flat_button(tr("btn_skip"))
		skip.name = "SkipButton"
		skip.pressed.connect(_finish)
		page.add_child(skip)


func _next() -> void:
	if index < SLIDES.size() - 1:
		index += 1
		_render()
	else:
		_finish()


func _finish() -> void:
	Profile.onboarded = true
	Profile.save()
	NativeBridge.log_event("onboarding_done", {})
	router.go("home", {}, true)


class StepDots extends Control:
	var count := 3
	var current := 0

	func _init() -> void:
		custom_minimum_size = Vector2(0, 14)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL

	func _draw() -> void:
		var widths: Array[float] = []
		var total := 0.0
		for dot in count:
			widths.append(24.0 if dot == current else 8.0)
			total += widths[dot] + (8.0 if dot > 0 else 0.0)
		var x := (size.x - total) / 2.0
		var y := size.y / 2.0
		for dot in count:
			var color := UI.GOLD if dot == current else Color(UI.SKY, 0.6)
			draw_circle(Vector2(x + 4.0, y), 4.0, color)
			draw_circle(Vector2(x + widths[dot] - 4.0, y), 4.0, color)
			draw_rect(Rect2(x + 4.0, y - 4.0, widths[dot] - 8.0, 8.0), color)
			x += widths[dot] + 8.0
