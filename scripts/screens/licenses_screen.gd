extends Screen
## Open-source notices. The heading is translated. The license texts stay English.

const MIT_NOTICE := "SewLens uses FreeSewing.\n\nFreeSewing is licensed under the MIT License.\n\nCopyright (c) 2016-present FreeSewing contributors\n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:\n\nThe above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.\n\nTHE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE."

## Copyright lines come from the name tables of the two fonts shipped in assets/fonts.
const FONT_NOTICE := "SewLens uses Noto Sans and Noto Sans JP.\n\nThese fonts are licensed under the SIL Open Font License, Version 1.1.\n\nCopyright 2022 The Noto Project Authors (https://github.com/notofonts/latin-greek-cyrillic)\n\nNoto Sans JP: Copyright 2014-2021 Adobe (http://www.adobe.com/).\n\n"


func title_key() -> String:
	return "title_licenses"


func enter(_params: Dictionary) -> void:
	var page := build_page()
	page.add_child(UI.heading(tr("licenses_heading")))
	page.add_child(UI.bullet(tr("licenses_credit"), "code"))
	page.add_child(_notice_card("MitNotice", MIT_NOTICE))
	var font_text := FONT_NOTICE + FileAccess.get_file_as_string("res://assets/fonts/OFL.txt").strip_edges()
	page.add_child(_notice_card("FontNotice", font_text))


func _notice_card(node_name: String, text: String) -> Control:
	var card := UI.card()
	var notice := UI.caption(text)
	notice.name = node_name
	card.add_child(notice)
	return UI.card_panel(card)
