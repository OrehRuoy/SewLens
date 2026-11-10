extends Screen
## Start of the flow: take or choose a photo, or skip straight to the design list.

const SAMPLE_PHOTO := "res://assets/sample_garment.jpg"

var _error: Label
var _photo_source := "library"


func enter(_params: Dictionary) -> void:
	var page := build_page()
	page.add_child(SlideArt.new("photo", 168.0))
	var tagline := UI.label(tr("app_tagline"), "SectionLabel")
	tagline.uppercase = true
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(tagline)
	var heading := UI.heading(tr("home_heading"))
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(heading)
	var body := UI.label(tr("home_body"), "CaptionLabel")
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(body)
	if Profile.needs_patterns():
		page.add_child(_patterns_card())
	_error = UI.error_label()
	page.add_child(_error)
	if NativeBridge.can_use_camera():
		var camera := UI.icon_button(tr("btn_take_photo"), "camera", true)
		camera.name = "CameraButton"
		camera.pressed.connect(_pick.bind("camera"))
		page.add_child(camera)
	var library := UI.icon_button(tr("btn_choose_photo"), "image", not NativeBridge.can_use_camera())
	library.name = "LibraryButton"
	library.pressed.connect(_pick.bind("library"))
	page.add_child(library)
	var sample := UI.icon_button(tr("btn_sample_photo"), "sparkle")
	sample.name = "SampleButton"
	sample.pressed.connect(_use_photo.bind(SAMPLE_PHOTO))
	page.add_child(sample)
	page.add_child(UI.spacer(4))
	var manual := UI.list_row(tr("btn_pick_design_manual"), "grid")
	manual.name = "ManualButton"
	manual.pressed.connect(_choose_manually)
	var profile := UI.list_row(tr("btn_my_measurements"), "tape")
	profile.name = "MeasurementsButton"
	profile.pressed.connect(func() -> void: router.go("measurements"))
	page.add_child(UI.group([manual, profile]))
	var privacy := UI.bullet(tr("onb_privacy"), "lock")
	(privacy.get_child(1) as Label).theme_type_variation = "CaptionLabel"
	page.add_child(privacy)
	if not NativeBridge.photo_finished.is_connected(_on_photo):
		NativeBridge.photo_finished.connect(_on_photo)


## Shown once the free pattern is used and no credit or unlock is known.
func _patterns_card() -> Control:
	var card := UI.card()
	var top := UI.row(12)
	var glyph := LineIcon.new("tag", UI.GOLD, 26.0)
	glyph.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(glyph)
	top.add_child(UI.label(tr("home_out_title"), "TitleLabel"))
	card.add_child(top)
	card.add_child(UI.label(tr("home_out_body")))
	var options := UI.button(tr("btn_see_options"), true)
	options.name = "SeeOptionsButton"
	options.pressed.connect(func() -> void: router.go("paywall"))
	card.add_child(options)
	var panel := UI.card_panel(card)
	panel.name = "PatternsCard"
	return panel


func _exit_tree() -> void:
	if NativeBridge.photo_finished.is_connected(_on_photo):
		NativeBridge.photo_finished.disconnect(_on_photo)


func _pick(source: String) -> void:
	show_error(_error, "")
	_photo_source = source
	NativeBridge.pick_photo(source)


func _on_photo(status: String, path: String) -> void:
	if not visible:
		return
	match status:
		"ok":
			_use_photo(path)
		"cancelled":
			pass
		"unavailable":
			show_error(_error, "photo_unavailable")
		_:
			show_error(_error, "photo_failed")


func _use_photo(path: String) -> void:
	var source := "sample" if path.begins_with("res://") else _photo_source
	NativeBridge.log_event("photo_submitted", {"source": source})
	session().clear()
	session().photo_path = path
	router.go("analyze")


func _choose_manually() -> void:
	session().clear()
	router.go("designs")
