extends Screen
## Every design grouped by category, for when the photo pick is wrong or skipped.


func title_key() -> String:
	return "title_designs"


func enter(_params: Dictionary) -> void:
	var page := build_page()
	page.add_theme_constant_override("separation", 10)
	page.add_child(UI.label(tr("designs_body")))
	var current := str(session().get("design", ""))
	for category in DesignCatalog.categories():
		page.add_child(UI.spacer(6))
		page.add_child(UI.section(tr("cat_" + category)))
		var rows: Array = []
		for design in DesignCatalog.designs_in(category):
			var chosen: bool = design == current
			var choice := UI.list_row(DesignCatalog.display_name(design), "", "check" if chosen else "chevron")
			choice.name = "Design_" + design
			if chosen:
				choice.add_theme_color_override("font_color", UI.GOLD)
				choice.add_theme_color_override("font_focus_color", UI.GOLD)
			choice.pressed.connect(_choose.bind(design))
			rows.append(choice)
		page.add_child(UI.group(rows))


func _choose(design: String) -> void:
	var pick: Dictionary = session().get("pick", {})
	var suggested = pick.get("options", {}) if str(pick.get("design", "")) == design else {}
	session().design = design
	session().options = ResultFit.defaults_with(design, suggested)
	if router.screen_names().has("result"):
		router.back_to("result")
	else:
		router.replace("result")
