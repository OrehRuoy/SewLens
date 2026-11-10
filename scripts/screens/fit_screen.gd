extends Screen
## One tap records what felt wrong. The draft screen redrafts with that change.
## The note is stored with the draft call, so it does not start a second cold function.

func title_key() -> String:
	return "title_fit"


func enter(_params: Dictionary) -> void:
	var page := build_page()
	var fresh := UI.bullet(tr("label_new_fit"), "sparkle")
	(fresh.get_child(1) as Label).theme_type_variation = "CaptionLabel"
	page.add_child(fresh)
	page.add_child(UI.label(tr("fit_body")))
	var design := str(session().get("design", ""))
	var complaints := FitRules.complaints_for(design)
	if complaints.is_empty():
		page.add_child(UI.label(tr("fit_empty"), "NoticeLabel"))
		return
	var rows: Array = []
	for item in complaints:
		var id := str(item.get("id", ""))
		var button := UI.list_row(tr("fit_" + id), "")
		button.name = "Fit_" + id
		button.pressed.connect(_choose.bind(design, id))
		rows.append(button)
	page.add_child(UI.group(rows))


func _choose(design: String, complaint: String) -> void:
	session().complaint = complaint
	session().fit_adjustment = true
	session().redraft = true
	NativeBridge.log_event("fit_feedback", {"design": design, "complaint": complaint, "locale": ApiClient.request_locale()})
	router.back()
