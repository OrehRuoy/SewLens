extends Screen
## Sends the photo to pickDesign, then hands over to the result screen.

const API_ERRORS := {
	"network": "err_api_network",
	"unavailable": "err_api_unavailable",
	"limit": "err_api_limit",
	"input": "err_api_input",
}

var _status: Control
var _error: Label
var _retry: Button
var _manual: Button
var _busy := false


func title_key() -> String:
	return "title_analyze"


func enter(params: Dictionary) -> void:
	var page := build_page()
	page.add_child(UI.photo_rect(str(session().get("photo_path", "")), 280))
	_status = UI.spinner(tr("analyze_working"))
	page.add_child(_status)
	_error = UI.error_label()
	page.add_child(_error)
	_retry = UI.icon_button(tr("btn_retry"), "replay", true)
	_retry.name = "RetryButton"
	_retry.pressed.connect(_start)
	page.add_child(_retry)
	_manual = UI.icon_button(tr("btn_pick_design_manual"), "grid")
	_manual.name = "ManualButton"
	_manual.pressed.connect(func() -> void: router.replace("designs"))
	page.add_child(_manual)
	_set_busy(false)
	if params.get("autostart", true):
		_start()


func _set_busy(busy: bool) -> void:
	_busy = busy
	_status.visible = busy
	_retry.visible = not busy
	_manual.visible = not busy


func _start() -> void:
	if _busy:
		return
	show_error(_error, "")
	var path := str(session().get("photo_path", ""))
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		show_error(_error, "photo_failed")
		return
	_set_busy(true)
	var result: Dictionary = await router.api.pick_design(bytes, UI.mime_for(path))
	if not is_inside_tree():
		return
	_set_busy(false)
	if not result.get("ok", false):
		show_error(_error, API_ERRORS.get(str(result.get("error", "")), "err_api_server"))
		return
	session().pick = result
	var design := str(result.get("design", ""))
	if design != "" and DesignCatalog.has_design(design):
		session().design = design
		session().options = ResultFit.defaults_with(design, result.get("options", {}))
	else:
		session().design = ""
		session().options = {}
	router.replace("result")
