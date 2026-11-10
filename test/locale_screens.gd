extends SceneTree
## Opens every screen in all 8 locales, saves a PNG of each one to
## build/screens/<locale>/<screen>.png, and exits 1 when any text overflows
## its Control at normal length, (de, fr) at 130% length, or (de) at 130%
## length with the Larger text setting on.
##
##   godot --path . -s res://test/locale_screens.gd            (PNGs + overflow)
##   godot --headless --path . -s res://test/locale_screens.gd (overflow only)
##   ... -- --out=some/dir                                     (other PNG folder)
##   ... -- --only=en,de                                       (some locales)

const EXPANDED_LOCALES := ["de", "fr"]
const LARGE_TEXT_LOCALES := ["de"]

var _fixture: Script
var _overflow: Script


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	_fixture = load("res://test/support/screen_fixture.gd")
	_overflow = load("res://test/support/overflow_check.gd")
	var out_dir := ProjectSettings.globalize_path("res://build/screens")
	var only: Array = []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--only="):
			only = Array(arg.trim_prefix("--only=").split(","))
	var capture := DisplayServer.get_name() != "headless"
	_fixture.prepare_profile()
	var main: Control = _fixture.make_main(root)
	var screen_rect: Rect2 = _fixture.screen_rect()
	var problems: Array = []
	var saved := 0
	var checked := 0
	for locale in _fixture.LOCALES:
		if not only.is_empty() and not locale in only:
			continue
		var passes := ["normal"]
		if locale in EXPANDED_LOCALES:
			passes.append("expanded")
		if locale in LARGE_TEXT_LOCALES:
			passes.append("large")
		for mode in passes:
			_fixture.use_locale(locale)
			_fixture.set_expanded(mode != "normal")
			_fixture.set_large_text(main, mode == "large")
			var suffix: String = {"normal": "", "expanded": "_130", "large": "_large"}[mode]
			var tag: String = {"normal": "", "expanded": " 130%", "large": " 130% large text"}[mode]
			var folder := out_dir.path_join(locale + suffix)
			if capture:
				DirAccess.make_dir_recursive_absolute(folder)
			for entry in _fixture.SCREENS:
				_fixture.open(main, entry)
				for frame in 3:
					await process_frame
				checked += 1
				var label: String = _fixture.screen_label(entry)
				for problem in _overflow.find(main, screen_rect):
					problems.append("%s%s / %s: %s" % [locale, tag, label, problem])
				if capture:
					await RenderingServer.frame_post_draw
					var image := root.get_texture().get_image()
					if image and image.save_png(folder.path_join(label + ".png")) == OK:
						saved += 1
	_fixture.set_expanded(false)
	_fixture.set_large_text(main, false)
	_fixture.use_locale("")
	main.queue_free()
	_fixture.restore_profile()
	for problem in problems:
		printerr("overflow: ", problem)
	print("locale_screens: %d screen checks, %d PNGs in %s, %d overflow problems" % [checked, saved, out_dir if capture else "(headless, none)", problems.size()])
	quit(1 if problems.size() > 0 else 0)
