extends Node
## Share sheet, camera / photo library, and analytics on each platform.
## Android: the SewLensNative and SewLensAnalytics plugins (addons/sewlens_android).
## iOS: ios/native/SewLensNative.m polls for REQUEST_FILE in the user folder.
## Desktop: a file dialog for photos and the system viewer for PDFs.

signal photo_finished(status: String, path: String)
signal share_finished(status: String)
signal billing_finished(payload: Dictionary)

const REQUEST_FILE := "sewlens_native_request.json"
const RESULT_FILE := "sewlens_native_result.json"
const PHOTO_FILE := "user://photo.jpg"
const IOS_POLL_SECONDS := 0.25
## A price query gives up after this. Photo, share, and the store sheet use the longer wait.
const IOS_TIMEOUT_SECONDS := 15.0
const IOS_USER_TIMEOUT_SECONDS := 600.0

var _android: Object
var _analytics: Object
var _request_id := 0
var _pending_action := ""
## Recent events, including locale, so tests can read the funnel without Firebase.
var events: Array = []
var _poll_elapsed := 0.0
var _poll_timer: Timer
var _ios_action := ""


func _ready() -> void:
	if Engine.has_singleton("SewLensNative"):
		_android = Engine.get_singleton("SewLensNative")
		_android.connect("photo_finished", _on_android_photo)
		_android.connect("share_finished", _on_android_share)
		if _android.has_signal("billing_finished"):
			_android.connect("billing_finished", _on_android_billing)
	if Engine.has_singleton("SewLensAnalytics"):
		_analytics = Engine.get_singleton("SewLensAnalytics")
	_poll_timer = Timer.new()
	_poll_timer.wait_time = IOS_POLL_SECONDS
	_poll_timer.timeout.connect(_poll_ios_result)
	add_child(_poll_timer)


func is_busy() -> bool:
	return _pending_action != ""


func can_use_camera() -> bool:
	return _android != null or OS.has_feature("ios")


func log_event(event_name: String, params: Dictionary) -> void:
	var payload := params.duplicate()
	if not payload.has("locale"):
		payload["locale"] = ApiClient.request_locale()
	events.append({"name": event_name, "params": payload})
	if events.size() > 40:
		events.pop_front()
	print("SewLens analytics %s %s" % [event_name, JSON.stringify(payload)])
	if _analytics:
		_analytics.logEvent(event_name, payload)
		if _analytics.has_method("setCustomKey"):
			_analytics.setCustomKey("locale", str(payload.get("locale", "")))
	if OS.has_feature("ios"):
		_append_ios_event(event_name, payload)


## The store review sheet. The pattern screen also shows a localized prompt.
func request_review() -> void:
	if _android and _android.has_method("requestReview"):
		_android.requestReview()
	elif OS.has_feature("ios"):
		_send_ios_request({"action": "review"})


## Debug builds only. Five taps on the version line call this.
func test_crash() -> void:
	if not OS.is_debug_build():
		return
	if _analytics and _analytics.has_method("testCrash"):
		_analytics.testCrash()
	elif OS.has_feature("ios"):
		_send_ios_request({"action": "crash"})
	else:
		push_error("SewLens test crash")


func _append_ios_event(event_name: String, payload: Dictionary) -> void:
	var path := OS.get_user_data_dir().path_join("sewlens_events.jsonl")
	var file := FileAccess.open(path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(JSON.stringify({"name": event_name, "params": payload}))
	file.close()


## source is "camera" or "library". Emits photo_finished(status, path) with
## status ok, cancelled, unavailable or error; path is a user:// JPEG on ok.
func pick_photo(source: String) -> void:
	if is_busy():
		return
	_pending_action = "photo"
	var output := ProjectSettings.globalize_path(PHOTO_FILE)
	if FileAccess.file_exists(PHOTO_FILE):
		DirAccess.remove_absolute(output)
	if _android:
		_android.pickPhoto(source, output)
	elif OS.has_feature("ios"):
		_send_ios_request({"action": "photo", "source": source, "output": output})
	elif DisplayServer.get_name() != "headless" and source == "library":
		_desktop_pick_photo()
	else:
		_finish_photo("unavailable", "")


## Emits share_finished(status) with ok, cancelled or error.
func share_file(path: String, mime: String, title: String) -> void:
	if is_busy():
		return
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(path):
		share_finished.emit("error")
		return
	_pending_action = "share"
	if _android:
		_android.shareFile(absolute, mime, title)
	elif OS.has_feature("ios"):
		_send_ios_request({"action": "share", "path": absolute, "title": title})
	else:
		_pending_action = ""
		share_finished.emit("ok" if OS.shell_open(absolute) == OK else "error")


func open_url(url: String) -> void:
	OS.shell_open(url)


## StoreKit 2 on iOS and Play Billing on Android. Emits billing_finished.
## Desktop and a plugin without billing methods finish as unavailable.
func billing_request(action: String, extra: Dictionary = {}) -> void:
	if action != "finish" and is_busy():
		billing_finished.emit({"status": "error", "action": action})
		return
	_pending_action = "billing"
	if _android and _android.has_method("queryProducts"):
		match action:
			"products":
				_android.queryProducts()
			"purchase":
				_android.purchase(str(extra.get("productId", "")))
			"restore":
				_android.restorePurchases()
			"finish":
				_android.finishPurchase(str(extra.get("transactionId", "")))
			_:
				_finish_billing({"status": "unavailable", "action": action})
		return
	if OS.has_feature("ios"):
		var request := {"action": action}
		request.merge(extra)
		_send_ios_request(request)
		return
	_finish_billing({"status": "unavailable", "action": action})


## Drops a store request that did not answer, so a retry can start a new one.
func abandon_billing() -> void:
	if _pending_action != "billing":
		return
	_pending_action = ""
	_request_id += 1
	if _poll_timer:
		_poll_timer.stop()


func _on_android_billing(payload_json: String) -> void:
	if _pending_action != "billing":
		return
	var json := JSON.new()
	var parsed = json.data if json.parse(payload_json) == OK else null
	if typeof(parsed) != TYPE_DICTIONARY:
		_finish_billing({"status": "error"})
		return
	_finish_billing(parsed)


func _finish_billing(payload: Dictionary) -> void:
	_pending_action = ""
	billing_finished.emit(payload)


func _finish_photo(status: String, path: String) -> void:
	_pending_action = ""
	photo_finished.emit(status, path)


func _on_android_photo(status: String, _absolute_path: String) -> void:
	_finish_photo(status, PHOTO_FILE if status == "ok" else "")


func _on_android_share(status: String) -> void:
	_pending_action = ""
	share_finished.emit(status)


func _desktop_pick_photo() -> void:
	var filters := PackedStringArray(["*.jpg, *.jpeg, *.png, *.webp ; Images"])
	var callback := func(status: bool, paths: PackedStringArray, _filter: int) -> void:
		if not status or paths.is_empty():
			_finish_photo("cancelled", "")
			return
		var image := Image.load_from_file(paths[0])
		if image == null or image.is_empty():
			_finish_photo("error", "")
			return
		_finish_photo("ok", save_photo(image))
	var error := DisplayServer.file_dialog_show("", "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters, callback)
	if error != OK:
		_finish_photo("unavailable", "")


## Downscales to at most 1600 px and writes PHOTO_FILE. Returns the path or "".
static func save_photo(image: Image) -> String:
	var longest := maxi(image.get_width(), image.get_height())
	if longest > 1600:
		var scale := 1600.0 / float(longest)
		image.resize(int(image.get_width() * scale), int(image.get_height() * scale), Image.INTERPOLATE_LANCZOS)
	return PHOTO_FILE if image.save_jpg(PHOTO_FILE, 0.85) == OK else ""


func _ios_dir() -> String:
	return OS.get_user_data_dir()


func _send_ios_request(request: Dictionary) -> void:
	_request_id += 1
	_ios_action = str(request.get("action", ""))
	request.id = _request_id
	request.result = _ios_dir().path_join(RESULT_FILE)
	if FileAccess.file_exists(request.result):
		DirAccess.remove_absolute(request.result)
	var target := _ios_dir().path_join(REQUEST_FILE)
	var file := FileAccess.open(target + ".tmp", FileAccess.WRITE)
	if file == null:
		_fail_ios_request()
		return
	file.store_string(JSON.stringify(request))
	file.close()
	if DirAccess.rename_absolute(target + ".tmp", target) != OK:
		_fail_ios_request()
		return
	_poll_elapsed = 0.0
	_poll_timer.start()


func _ios_needs_short_timeout() -> bool:
	return _ios_action == "products"


func _poll_ios_result() -> void:
	_poll_elapsed += IOS_POLL_SECONDS
	var path := _ios_dir().path_join(RESULT_FILE)
	if not FileAccess.file_exists(path):
		var limit := IOS_TIMEOUT_SECONDS if _ios_needs_short_timeout() else IOS_USER_TIMEOUT_SECONDS
		if _poll_elapsed > limit:
			_fail_ios_request()
		return
	var json := JSON.new()
	var parsed = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	DirAccess.remove_absolute(path)
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("id", -1)) != _request_id:
		return
	_poll_timer.stop()
	var status := str(parsed.get("status", "error"))
	if _pending_action == "photo":
		_finish_photo(status, PHOTO_FILE if status == "ok" else "")
	elif _pending_action == "billing":
		_finish_billing(parsed)
	else:
		_pending_action = ""
		share_finished.emit(status)


func _fail_ios_request() -> void:
	_poll_timer.stop()
	if _pending_action == "photo":
		_finish_photo("error", "")
	elif _pending_action == "billing":
		_finish_billing({"status": "error"})
	else:
		_pending_action = ""
		share_finished.emit("error")
