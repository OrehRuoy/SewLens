extends Screen
## Asks before a garment photo is sent for design matching.
## Declining returns to the previous screen and does not upload.


func title_key() -> String:
	return "title_consent"


func enter(_params: Dictionary) -> void:
	var page := build_page()
	page.add_child(UI.heading(tr("consent_heading")))
	var body := UI.label(tr("consent_body"))
	body.name = "ConsentBody"
	page.add_child(body)
	var agree := UI.icon_button(tr("btn_consent_agree"), "check", true)
	agree.name = "AcceptButton"
	agree.pressed.connect(_accept)
	page.add_child(agree)
	var decline := UI.icon_button(tr("btn_consent_decline"), "replay")
	decline.name = "DeclineButton"
	decline.pressed.connect(_decline)
	page.add_child(decline)


func _accept() -> void:
	Profile.accept_photo_consent()
	NativeBridge.log_event("photo_submitted", {"source": str(session().get("photo_source", ""))})
	router.replace("analyze")


func _decline() -> void:
	session().erase("photo_path")
	session().erase("photo_source")
	router.back()
