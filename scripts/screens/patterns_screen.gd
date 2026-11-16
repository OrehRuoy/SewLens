extends Screen
## Saved PDFs already on the phone. Opening, sharing, or printing one
## never calls the server and never uses a credit.

var _status: Label


func title_key() -> String:
	return "title_my_patterns"


func enter(_params: Dictionary) -> void:
	var page := build_page()
	_status = UI.error_label()
	_status.name = "PatternStatus"
	page.add_child(_status)
	var entries := PatternLibrary.list_entries()
	if entries.is_empty():
		var heading := UI.heading(tr("patterns_empty_title"))
		heading.name = "EmptyTitle"
		page.add_child(heading)
		page.add_child(UI.label(tr("patterns_empty_body")))
		return
	page.add_child(UI.caption(tr("draft_print_tip")))
	for entry in entries:
		page.add_child(_card(entry))


func _card(entry: Dictionary) -> Control:
	var card := UI.card()
	var title := UI.label(DesignCatalog.display_name(str(entry.get("design", ""))), "TitleLabel")
	title.name = "PatternTitle"
	card.add_child(title)
	var when := str(entry.get("date", "")).substr(0, 16)
	card.add_child(UI.caption("%s · %s" % [when, PatternLibrary.paper_label(str(entry.get("paper", "")))]))
	var summary := str(entry.get("summary", ""))
	if summary != "":
		card.add_child(UI.caption(summary))
	var path := str(entry.get("path", ""))
	var open := UI.button(tr("btn_open_pattern"))
	open.name = "OpenButton"
	open.pressed.connect(_open.bind(path))
	card.add_child(open)
	var share := UI.button(tr("btn_share_pdf"))
	share.name = "ShareButton"
	share.pressed.connect(_share.bind(path, str(entry.get("design", ""))))
	card.add_child(share)
	var print_button := UI.button(tr("btn_print"))
	print_button.name = "PrintButton"
	print_button.pressed.connect(_print.bind(path, str(entry.get("design", ""))))
	card.add_child(print_button)
	if _on_android():
		var save := UI.button(tr("btn_save_device"))
		save.name = "SaveButton"
		save.pressed.connect(_save.bind(path, str(entry.get("design", "")), str(entry.get("date", ""))))
		card.add_child(save)
	var delete := UI.flat_button(tr("btn_delete_pattern"))
	delete.name = "DeleteButton"
	delete.pressed.connect(_confirm_delete.bind(path))
	card.add_child(delete)
	return UI.card_panel(card)


func _open(path: String) -> void:
	_clear_status()
	if not NativeBridge.open_finished.is_connected(_on_opened):
		NativeBridge.open_finished.connect(_on_opened, CONNECT_ONE_SHOT)
	NativeBridge.open_file(path)


func _share(path: String, design: String) -> void:
	NativeBridge.export_counts_for_review = true
	_clear_status()
	if not NativeBridge.share_finished.is_connected(_on_shared):
		NativeBridge.share_finished.connect(_on_shared, CONNECT_ONE_SHOT)
	NativeBridge.share_file(path, "application/pdf", DesignCatalog.display_name(design))


func _print(path: String, design: String) -> void:
	NativeBridge.export_counts_for_review = true
	_clear_status()
	if not NativeBridge.print_finished.is_connected(_on_printed):
		NativeBridge.print_finished.connect(_on_printed, CONNECT_ONE_SHOT)
	NativeBridge.print_file(path, DesignCatalog.display_name(design))


func _save(path: String, design: String, date: String) -> void:
	NativeBridge.export_counts_for_review = true
	_clear_status()
	if not NativeBridge.save_finished.is_connected(_on_saved):
		NativeBridge.save_finished.connect(_on_saved, CONNECT_ONE_SHOT)
	NativeBridge.save_file(path, PatternLibrary.suggested_filename(design, date))


func _confirm_delete(path: String) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.name = "DeleteDialog"
	dialog.title = tr("patterns_delete_title")
	dialog.dialog_text = tr("patterns_delete_body")
	dialog.ok_button_text = tr("btn_delete_confirm")
	dialog.confirmed.connect(func() -> void:
		PatternLibrary.remove(path)
		enter(params)
	)
	add_child(dialog)
	dialog.popup_centered()


func _on_opened(status: String) -> void:
	if status == "error" and is_inside_tree():
		_show("patterns_open_failed", true)


func _on_shared(status: String) -> void:
	if status == "error" and is_inside_tree():
		_show("share_failed", true)


func _on_printed(status: String) -> void:
	if (status == "error" or status == "unavailable") and is_inside_tree():
		_show("patterns_print_failed", true)


func _on_saved(status: String) -> void:
	if not is_inside_tree():
		return
	if status == "ok":
		_show("patterns_saved", false)
	elif status == "cancelled":
		_show("patterns_save_cancelled", true)
	elif status == "error":
		_show("patterns_save_failed", true)


func _clear_status() -> void:
	if _status:
		_status.visible = false
		_status.text = ""


func _show(key: String, problem: bool) -> void:
	_status.theme_type_variation = "ErrorLabel" if problem else "CaptionLabel"
	_status.text = tr(key)
	_status.visible = true


func _on_android() -> bool:
	return OS.has_feature("android") or OS.get_name() == "Android"
