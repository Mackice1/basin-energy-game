extends RefCounted
## V22 shared presentation only. No scene, solver or persistence state.
const INK := Color("edf3f6")
const MUTED := Color("a5b7c4")
const SURFACE := Color("14212b")
const RAISED := Color("1c2d3a")
const BORDER := Color("344b59")
const ACCENT := Color("69d1bd")
const AMBER := Color("efbc68")
const ERROR := Color("ff9790")

static func panel(fill: Color = SURFACE, padding: int = 12, radius: int = 8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	for side in ["left", "right", "top", "bottom"]: box.set("content_margin_" + side, padding)
	return box

static func create(font: Font) -> Theme:
	var theme := Theme.new()
	theme.default_font = font
	theme.default_font_size = 15
	for kind in ["Label", "RichTextLabel", "Button", "OptionButton", "MenuButton", "LineEdit", "TextEdit", "CheckBox", "CheckButton", "PopupMenu", "SpinBox"]:
		for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]: theme.set_color(state, kind, INK)
		theme.set_color("font_disabled_color", kind, Color("748795"))
	for kind in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", kind, panel(RAISED, 9, 6))
		theme.set_stylebox("hover", kind, panel(Color("2b4352"), 9, 6))
		var active := panel(Color("254e4e"), 9, 6)
		active.border_color = ACCENT
		theme.set_stylebox("pressed", kind, active)
		theme.set_stylebox("disabled", kind, panel(Color("17242e"), 9, 6))
		var focus := panel(Color(0, 0, 0, 0), 9, 6)
		focus.border_color = ACCENT
		focus.set_border_width_all(2)
		theme.set_stylebox("focus", kind, focus)
	for kind in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", kind, panel(Color("0c1720"), 8, 5))
		var edit_focus := panel(Color("0c1720"), 8, 5)
		edit_focus.border_color = ACCENT
		theme.set_stylebox("focus", kind, edit_focus)
		theme.set_color("caret_color", kind, ACCENT)
		theme.set_color("selection_color", kind, Color("356b71"))
	for kind in ["PanelContainer", "Panel", "PopupMenu", "Window", "AcceptDialog"]: theme.set_stylebox("panel", kind, panel())
	theme.set_stylebox("hover", "PopupMenu", panel(Color("254e4e"), 6, 3))
	theme.set_color("font_hover_color", "PopupMenu", INK)
	theme.set_stylebox("panel", "TooltipPanel", panel(Color("07111a"), 10, 5))
	theme.set_color("font_color", "TooltipLabel", INK)
	theme.set_font_size("font_size", "TooltipLabel", 14)
	for kind in ["TabContainer", "TabBar"]:
		for state in ["font_selected_color", "font_unselected_color", "font_hovered_color", "font_focus_color"]: theme.set_color(state, kind, INK)
		theme.set_stylebox("panel", kind, panel(SURFACE, 8, 6))
		for entry in [["tab_selected", Color("254e4e")], ["tab_unselected", RAISED], ["tab_hovered", Color("2b4352")], ["tab_disabled", SURFACE]]: theme.set_stylebox(entry[0], kind, panel(entry[1], 9, 5))
	for kind in ["HSeparator", "VSeparator"]:
		var line := StyleBoxLine.new()
		line.color = BORDER
		line.thickness = 1
		line.vertical = kind == "VSeparator"
		theme.set_stylebox("separator", kind, line)
	return theme
