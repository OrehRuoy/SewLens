extends GutTest
## A garment photo is not sent until the person accepts, and a withdrawn
## consent makes the next photo ask again.

const Fixture := preload("res://test/support/screen_fixture.gd")


func before_each() -> void:
	NativeBridge.events.clear()
	Fixture.prepare_profile()
	Profile.photo_consent = false
	TranslationServer.set_locale("en")


func after_each() -> void:
	Fixture.use_locale("")
	Fixture.restore_profile()


func test_a_photo_is_not_uploaded_without_consent() -> void:
	var main := _home()
	_sample(main)
	assert_eq(main.current().name, "consent")
	assert_eq(main.api.transport.requests.size(), 0)
	_assert_no_event("photo_submitted")
	await _frames(4)
	assert_eq(main.api.transport.requests.size(), 0)
	main.queue_free()


func test_an_accepted_consent_is_remembered_and_the_photo_is_sent() -> void:
	var main := _home()
	main.api.transport.queue_result({"design": "aaron", "options": {}, "locale": "en"})
	_sample(main)
	(main.find_child("AcceptButton", true, false) as Button).pressed.emit()
	await _frames(4)
	assert_true(Profile.photo_consent)
	assert_eq(main.current().name, "result")
	_assert_event("photo_submitted")
	assert_eq(main.api.transport.requests.size(), 1)
	assert_true(str(main.api.transport.requests[0].url).ends_with("pickDesign"))
	assert_true(main.api.transport.requests[0].body.data.has("photo"))
	Profile.photo_consent = false
	Profile.load_profile()
	assert_true(Profile.photo_consent)
	var sent: int = main.api.transport.requests.size()
	main.api.transport.queue_result({"design": "aaron", "options": {}, "locale": "en"})
	main.go("home", {}, true)
	await _frames(1)
	_sample(main)
	assert_ne(main.current().name, "consent")
	await _frames(4)
	assert_eq(main.current().name, "result")
	assert_gt(main.api.transport.requests.size(), sent)
	main.queue_free()


func test_declining_consent_blocks_the_upload_and_returns_home() -> void:
	var main := _home()
	_sample(main)
	(main.find_child("DeclineButton", true, false) as Button).pressed.emit()
	assert_ne(main.current().name, "consent")
	assert_not_null(main.current().find_child("SampleButton", true, false))
	assert_false(Profile.photo_consent)
	assert_eq(main.api.transport.requests.size(), 0)
	_assert_no_event("photo_submitted")
	assert_false(main.session.has("photo_path"))
	main.queue_free()


func test_withdrawing_consent_blocks_the_next_upload() -> void:
	Profile.accept_photo_consent()
	var main := _home()
	main.api.transport.queue_result({"design": "aaron", "options": {}, "locale": "en"})
	_sample(main)
	await _frames(4)
	var sent: int = main.api.transport.requests.size()
	assert_gt(sent, 0)
	main.go("settings")
	(main.find_child("WithdrawConsentButton", true, false) as Button).pressed.emit()
	await _frames(1)
	assert_false(Profile.photo_consent)
	assert_null(main.find_child("WithdrawConsentButton", true, false))
	Profile.photo_consent = true
	Profile.load_profile()
	assert_false(Profile.photo_consent)
	main.go("home", {}, true)
	_sample(main)
	assert_eq(main.current().name, "consent")
	await _frames(4)
	assert_eq(main.api.transport.requests.size(), sent)
	main.queue_free()


func test_the_consent_prompt_is_localized_and_names_gemini() -> void:
	var main := _home()
	for locale in Fixture.LOCALES:
		Fixture.use_locale(locale)
		var body := tr("consent_body")
		assert_ne(body, "consent_body", locale)
		assert_true(body.contains("Gemini"), locale)
		assert_false(body.contains("AI"), locale)
		assert_ne(tr("btn_consent_agree"), "btn_consent_agree", locale)
		assert_ne(tr("btn_consent_decline"), "btn_consent_decline", locale)
		assert_ne(tr("btn_withdraw_consent"), "btn_withdraw_consent", locale)
	Fixture.use_locale("de")
	_sample(main)
	var texts := Fixture.visible_texts(main)
	assert_has(texts, tr("consent_body"))
	assert_has(texts, "Zustimmen und weiter")
	assert_true(tr("consent_body").contains("Google Gemini"))
	assert_true(tr("consent_body").contains("Maße"))
	main.queue_free()


func _home() -> Control:
	var main := Fixture.make_main(self)
	main.go("home", {}, true)
	return main


func _sample(main: Control) -> void:
	(main.find_child("SampleButton", true, false) as Button).pressed.emit()


func _assert_event(event_name: String) -> void:
	var found := false
	for event in NativeBridge.events:
		if str(event.get("name", "")) == event_name:
			found = true
	assert_true(found, event_name)


func _assert_no_event(event_name: String) -> void:
	for event in NativeBridge.events:
		assert_ne(str(event.get("name", "")), event_name)


func _frames(count: int) -> void:
	for _index in count:
		await get_tree().process_frame
