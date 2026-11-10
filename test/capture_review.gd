extends SceneTree
## Saves the App Store / Play in-app purchase review screenshot to
## store/iap/review.png: the English purchase screen at iPhone 6.1" size
## (1170 x 2532, 3x) with sample store prices and the notch safe area.
## The prices come from a mock store, the same way the real store string arrives.
## The page is scrolled so both purchase cards are fully in view.
##
##   godot --path . -s res://test/capture_review.gd
##   ... -- --screen=settings --out=build/review_settings.png   (any other screen)
##   ... -- --scroll-to=NodeName                                 (scroll a node to the top)

const SIZE := Vector2i(1170, 2532)
const LOGICAL := Vector2i(390, 844)
const IPHONE_INSETS := Vector4(47, 0, 34, 0)


class SampleStore:
	extends RefCounted
	var prices := {
		"orehruoy.sewlens.credit": "$2.99",
		"orehruoy.sewlens.unlimited": "$24.99",
	}

	func load_prices() -> Dictionary:
		return {"ok": true, "prices": prices}

	func purchase(_product_id: String) -> Dictionary:
		return {"ok": false, "error": "cancelled"}

	func restore() -> Dictionary:
		return {"ok": true, "receipts": []}

	func finish(_transaction_id: String) -> void:
		pass


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	if DisplayServer.get_name() == "headless":
		printerr("capture_review needs a window: run it without --headless")
		quit(1)
		return
	var screen := "paywall"
	var scroll_to := "CreditCard"
	var out := ProjectSettings.globalize_path("res://store/iap/review.png")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screen="):
			screen = arg.trim_prefix("--screen=")
			scroll_to = ""
		elif arg.begins_with("--scroll-to="):
			scroll_to = arg.trim_prefix("--scroll-to=")
		elif arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var fixture: Script = load("res://test/support/screen_fixture.gd")
	var profile := root.get_node("Profile")
	var billing := root.get_node("Billing")
	fixture.prepare_profile()
	fixture.use_locale("en")
	profile.successful_patterns = 1
	var native: Object = billing.store
	billing.store = SampleStore.new()
	billing.prices = {}
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.size_2d_override = LOGICAL
	viewport.size_2d_override_stretch = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_2d = Viewport.MSAA_4X
	root.add_child(viewport)
	var main: Control = fixture.make_main(viewport)
	main.simulate_insets(IPHONE_INSETS)
	fixture.open(main, [screen, {}])
	for frame in 4:
		await process_frame
	var target := main.find_child(scroll_to, true, false) as Control if scroll_to != "" else null
	var scroll := (main.current() as Node).get_child(0) as ScrollContainer
	if target and scroll:
		var panel := target.get_parent() as Control
		scroll.scroll_vertical = int(panel.global_position.y - scroll.global_position.y + scroll.scroll_vertical - 12.0)
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var saved := image.save_png(out)
	main.queue_free()
	viewport.queue_free()
	billing.store = native
	billing.prices = {}
	fixture.use_locale("")
	fixture.restore_profile()
	print("capture_review: %s %dx%d -> %s" % [screen, image.get_width(), image.get_height(), out if saved == OK else "FAILED"])
	quit(0 if saved == OK else 1)
