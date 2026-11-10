class_name ApiClient
extends Node
## Calls the pickDesign and draftPattern callable functions.
## Tests swap `transport` for a mock with the same `post(url, body)` coroutine.

const INSTALL_PATH := "user://install_id"
const EMULATOR_BASE := "http://10.0.2.2:5001/sewlens-app/us-central1/"
const PRODUCTION_BASE := "https://us-central1-sewlens-app.cloudfunctions.net/"
const PATTERN_DIR := "user://patterns"

var transport: Object
var install_path := INSTALL_PATH
var pattern_dir := PATTERN_DIR


func _ready() -> void:
	if transport == null:
		var http := HttpTransport.new()
		add_child(http)
		transport = http


## Result: {ok, design, designName, options, closest, manualPicker, unsupported,
## message, explanation, latency_ms, locale} or {ok: false, error}.
func pick_design(photo: PackedByteArray, mime: String) -> Dictionary:
	var locale := request_locale()
	var started := Time.get_ticks_msec()
	var response := await call_function("pickDesign", {
		"photo": {"mimeType": mime, "data": Marshalls.raw_to_base64(photo)},
		"locale": locale,
		"installId": install_id(),
	})
	if not response.ok:
		return response
	var result: Dictionary = response.result
	result.ok = true
	var design = result.get("design")
	result.design = str(design) if design != null else ""
	result.latency_ms = _latency(result, started)
	if result.design != "":
		NativeBridge.log_event("pick_design", {
			"latency_ms": result.latency_ms,
			"design": result.design,
			"locale": str(result.get("locale", locale)),
		})
	return result


## Measurements are millimetres; they are sent in the unit the PDF should print.
func draft_pattern(design: String, measurements_mm: Dictionary, options: Dictionary, unit: String, paper: String, fit_adjustment: bool = false, complaint: String = "") -> Dictionary:
	var locale := request_locale()
	var started := Time.get_ticks_msec()
	var converted := {}
	for key in measurements_mm:
		var value := Units.to_display(float(measurements_mm[key]), unit, DesignCatalog.kind(key))
		converted[key] = snappedf(value, 0.001)
	var response := await call_function("draftPattern", build_draft_payload(design, converted, options, unit, paper, locale, fit_adjustment, complaint))
	if not response.ok:
		return response
	var result: Dictionary = response.result
	result.ok = true
	result.latency_ms = _latency(result, started)
	var pdf_base64 := str(result.get("pdfBase64", ""))
	if pdf_base64 != "":
		result.pdf_path = save_pdf(design, Marshalls.base64_to_raw(pdf_base64))
	result.erase("pdfBase64")
	NativeBridge.log_event("pattern_drafted", {
		"latency_ms": result.latency_ms,
		"design": str(result.get("design", design)),
		"locale": str(result.get("locale", locale)),
	})
	return result


func verify_purchase(receipt: Dictionary) -> Dictionary:
	var response := await call_function("verifyPurchase", {
		"installId": install_id(),
		"receipt": receipt,
	})
	if not response.ok:
		return response
	response.result.ok = true
	response.result.revoked = bool(receipt.get("revoked", false))
	return response.result


func redeem_promo(code: String) -> Dictionary:
	var response := await call_function("redeemPromo", {
		"installId": install_id(),
		"code": code,
		"locale": request_locale(),
	})
	if not response.ok:
		return response
	response.result.ok = true
	return response.result


func build_draft_payload(design: String, converted: Dictionary, options: Dictionary, unit: String, paper: String, locale: String, fit_adjustment: bool = false, complaint: String = "") -> Dictionary:
	var payload := {
		"design": design,
		"measurements": converted,
		"options": options,
		"units": Units.api_units(unit),
		"paper": Units.api_paper(paper),
		"locale": locale,
		"installId": install_id(),
	}
	if fit_adjustment:
		payload["fitAdjustment"] = true
		payload["complaint"] = complaint
	return payload


func call_function(function_name: String, data: Dictionary) -> Dictionary:
	var reply: Dictionary = await transport.post(endpoint(function_name), JSON.stringify({"data": data}))
	var code := int(reply.get("code", 0))
	var json := JSON.new()
	var parsed = json.data if json.parse(str(reply.get("body", ""))) == OK else null
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "code": code, "error": "network" if code == 0 else "http"}
	if parsed.has("error"):
		var detail = parsed.error
		var status := ""
		var message := ""
		if typeof(detail) == TYPE_DICTIONARY:
			status = str(detail.get("status", ""))
			message = str(detail.get("message", ""))
		else:
			message = str(detail)
		return {"ok": false, "code": code, "error": _error_kind(status), "message": message}
	if code < 200 or code >= 300:
		return {"ok": false, "code": code, "error": "http"}
	var result = parsed.get("result")
	if typeof(result) != TYPE_DICTIONARY:
		return {"ok": false, "code": code, "error": "empty"}
	return {"ok": true, "code": code, "result": result}


func endpoint(function_name: String) -> String:
	if OS.is_debug_build() and OS.get_name() == "Android":
		return EMULATOR_BASE + function_name
	return PRODUCTION_BASE + function_name


func save_pdf(design: String, bytes: PackedByteArray) -> String:
	DirAccess.make_dir_recursive_absolute(pattern_dir)
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "").replace("-", "").replace("T", "-")
	var file_path := "%s/SewLens-%s-%s.pdf" % [pattern_dir, design, stamp]
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_buffer(bytes)
	file.close()
	return file_path


func install_id() -> String:
	if FileAccess.file_exists(install_path):
		var existing := FileAccess.get_file_as_string(install_path).strip_edges()
		if existing.length() >= 8:
			return existing
	var id := "install" + str(int(Time.get_unix_time_from_system())) + "sewlens"
	var file := FileAccess.open(install_path, FileAccess.WRITE)
	if file:
		file.store_string(id)
		file.close()
	return id


static func request_locale() -> String:
	var lower := TranslationServer.get_locale().replace("_", "-").to_lower()
	if lower.begins_with("pt"):
		return "pt-BR"
	for language in ["en", "de", "fr", "es", "ja", "it", "nl"]:
		if lower.begins_with(language):
			return language
	return "en"


## Maps callable error statuses to string keys under err_api_*.
static func _error_kind(status: String) -> String:
	match status:
		"RESOURCE_EXHAUSTED":
			return "limit"
		"INVALID_ARGUMENT", "FAILED_PRECONDITION":
			return "input"
		"UNAVAILABLE", "DEADLINE_EXCEEDED":
			return "unavailable"
		_:
			return "server"


func _latency(result: Dictionary, started_msec: int) -> float:
	var reported = result.get("latency_ms")
	if typeof(reported) == TYPE_FLOAT or typeof(reported) == TYPE_INT:
		return float(reported)
	return float(Time.get_ticks_msec() - started_msec)
