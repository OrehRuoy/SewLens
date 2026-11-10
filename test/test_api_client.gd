extends GutTest

const MockTransport := preload("res://test/support/mock_transport.gd")
const PATTERN_DIR := "user://test_patterns"
const INSTALL := "user://test_install_id"

var api: ApiClient
var transport


func before_each() -> void:
	transport = MockTransport.new()
	api = ApiClient.new()
	api.transport = transport
	api.pattern_dir = PATTERN_DIR
	api.install_path = INSTALL
	add_child_autofree(api)
	TranslationServer.set_locale("de")


func after_each() -> void:
	TranslationServer.set_locale("en")
	if DirAccess.dir_exists_absolute(PATTERN_DIR):
		for name in DirAccess.get_files_at(PATTERN_DIR):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(PATTERN_DIR.path_join(name)))
	if FileAccess.file_exists(INSTALL):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(INSTALL))


func test_pick_design_sends_photo_and_reads_result() -> void:
	transport.queue_result({"design": "aaron", "designName": "Aaron", "options": {"chestEase": 0.1}, "confidence": 0.9, "closest": false, "locale": "de", "latency_ms": 812})
	var result: Dictionary = await api.pick_design(PackedByteArray([1, 2, 3]), "image/jpeg")
	assert_true(result.ok)
	assert_eq(result.design, "aaron")
	assert_eq(result.latency_ms, 812.0)
	var request: Dictionary = transport.requests[0]
	assert_string_ends_with(request.url, "/pickDesign")
	assert_eq(request.body.data.photo, {"mimeType": "image/jpeg", "data": "AQID"})
	assert_eq(request.body.data.locale, "de")
	assert_string_starts_with(str(request.body.data.installId), "install")


func test_pick_design_with_no_design() -> void:
	transport.queue_result({"design": null, "unsupported": "shorts", "manualPicker": true})
	var result: Dictionary = await api.pick_design(PackedByteArray([1]), "image/png")
	assert_true(result.ok)
	assert_eq(result.design, "")
	assert_eq(result.unsupported, "shorts")


func test_callable_errors_map_to_string_keys() -> void:
	var cases := [
		["RESOURCE_EXHAUSTED", 429, "limit"],
		["INVALID_ARGUMENT", 400, "input"],
		["UNAVAILABLE", 503, "unavailable"],
		["INTERNAL", 500, "server"],
	]
	for entry in cases:
		transport.queue_error(entry[0], "detail", entry[1])
		var result: Dictionary = await api.pick_design(PackedByteArray([1]), "image/jpeg")
		assert_false(result.ok)
		assert_eq(result.error, entry[2], entry[0])
		assert_eq(result.code, entry[1])


func test_network_and_bad_bodies() -> void:
	var result: Dictionary = await api.pick_design(PackedByteArray([1]), "image/jpeg")
	assert_eq(result.error, "network", "no reply queued means the request never completed")
	transport.queue_raw(502, "<html>bad gateway</html>")
	result = await api.pick_design(PackedByteArray([1]), "image/jpeg")
	assert_eq(result.error, "http")
	transport.queue_raw(200, "{\"result\": 5}")
	result = await api.draft_pattern("aaron", {}, {}, "cm", "A4")
	assert_eq(result.error, "empty")


func test_draft_converts_to_inches_and_saves_the_pdf() -> void:
	var pdf := "%PDF-1.4 test".to_utf8_buffer()
	transport.queue_result({"design": "aaron", "locale": "de", "pdfBase64": Marshalls.raw_to_base64(pdf), "paper": "letter", "units": "imperial"})
	var result: Dictionary = await api.draft_pattern("aaron", {"chest": 1016.0, "shoulderSlope": 13.0}, {"chestEase": 0.08}, "inch", "Letter")
	assert_true(result.ok)
	var data: Dictionary = transport.last_data()
	assert_eq(data.design, "aaron")
	assert_almost_eq(float(data.measurements.chest), 40.0, 0.001)
	assert_eq(float(data.measurements.shoulderSlope), 13.0, "degrees stay degrees")
	assert_eq(data.units, "imperial")
	assert_eq(data.paper, "letter")
	assert_eq(data.locale, "de")
	assert_eq(data.options, {"chestEase": 0.08})
	assert_false(result.has("pdfBase64"))
	assert_true(FileAccess.file_exists(result.pdf_path))
	assert_eq(FileAccess.get_file_as_bytes(result.pdf_path), pdf)


func test_draft_metric_sends_centimetres() -> void:
	transport.queue_result({"design": "florent"})
	await api.draft_pattern("florent", {"head": 575.0}, {}, "cm", "A4")
	var data: Dictionary = transport.last_data()
	assert_almost_eq(float(data.measurements.head), 57.5, 0.001)
	assert_eq(data.units, "metric")
	assert_eq(data.paper, "a4")


func test_fit_adjustment_is_sent_with_the_draft() -> void:
	transport.queue_result({"design": "aaron", "options": {"chestEase": 0.1}})
	var result: Dictionary = await api.draft_pattern("aaron", {}, {"chestEase": 0.08}, "cm", "A4", true, "chest_tight")
	assert_true(result.ok)
	var data: Dictionary = transport.last_data()
	assert_true(data.fitAdjustment)
	assert_eq(data.complaint, "chest_tight")
	assert_eq(data.options, {"chestEase": 0.08})
	assert_string_starts_with(str(data.installId), "install")


func test_install_id_is_stable() -> void:
	var first := api.install_id()
	assert_eq(api.install_id(), first)


func test_request_locale_maps_portuguese() -> void:
	TranslationServer.set_locale("pt_BR")
	assert_eq(ApiClient.request_locale(), "pt-BR")
	TranslationServer.set_locale("ja")
	assert_eq(ApiClient.request_locale(), "ja")
