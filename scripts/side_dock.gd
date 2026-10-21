extends Control
## Nonmodal right-side navigation. Only the visible rail/panel captures mouse
## input. Every section starts collapsed; hovering shows the section name only.

signal panel_opened(key: String)

const INK := Color("edf3f6")
const BORDER := Color("344b59")
const ICON_PATHS := {
	"fuel": '<path d="M16 3C19 11 26 13 26 21A10 10 0 0 1 6 21C6 15 12 12 12 8C15 11 17 13 17 16C21 12 16 7 16 3Z"/>',
	"demand": '<circle cx="16" cy="16" r="11"/><path d="M16 5V22M10 16L16 22L22 16M10 27H22"/>',
	"energy": '<path d="M18 4L8 18H15L13 28L25 13H18Z"/>',
	"location": '<circle cx="16" cy="14" r="4"/><path d="M25 14C25 21 16 29 16 29S7 21 7 14A9 9 0 0 1 25 14Z"/>',
	"weather": '<circle cx="12" cy="11" r="5"/><path d="M12 2V4M12 18V20M3 11H5M19 11H21M5 4L7 6M17 4L19 2M5 18L7 16M8 25H24A5 5 0 0 0 24 15A7 7 0 0 0 11 17A4 4 0 0 0 8 25Z"/>',
	"templates": '<path d="M4 5H13V14H4ZM19 5H28V14H19ZM4 20H13V29H4ZM19 20H28V29H19Z"/>',
	"optimization": '<path d="M5 4V27H29M9 21L14 15L20 18L27 7M22 7H27V12"/>'
}

var active_key := ""
var panels: Dictionary = {}
var buttons: Dictionary = {}
var _rail: PanelContainer
var _entries: VBoxContainer

func _ready() -> void:
	name = "RightDock"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rail = PanelContainer.new()
	_rail.name = "DockRail"
	_rail.add_theme_stylebox_override("panel", _style(Color("14212b"), 8, 6))
	add_child(_rail)
	_entries = VBoxContainer.new()
	_entries.add_theme_constant_override("separation", 4)
	_rail.add_child(_entries)
	resized.connect(_layout)
	_layout()

func create_panel(key: String, caption: String) -> VBoxContainer:
	var shell := PanelContainer.new()
	shell.name = "DockPanel_" + key
	shell.add_theme_stylebox_override("panel", _style(Color("14212b"), 10, 12))
	shell.hide()
	add_child(shell)
	panels[key] = shell
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	shell.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = caption
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", INK)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "×"
	close.tooltip_text = "收起" + caption
	close.custom_minimum_size = Vector2(34, 34)
	close.pressed.connect(close_panels)
	header.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 4)
	scroll.add_child(body)
	var entry := Button.new()
	entry.name = "DockToggle_" + key
	entry.tooltip_text = caption
	entry.text = {"energy":"运行", "fuel":"燃料", "demand":"需求", "location":"位置", "weather":"天气", "templates":"场景", "optimization":"优化"}.get(key,caption)
	entry.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	entry.add_theme_font_size_override("font_size",12)
	entry.toggle_mode = true
	entry.icon = _icon(key)
	entry.expand_icon = true
	entry.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	entry.custom_minimum_size = Vector2(62, 42)
	entry.add_theme_constant_override("icon_max_width", 22)
	entry.add_theme_color_override("icon_normal_color", Color.WHITE)
	entry.add_theme_color_override("icon_hover_color", Color.WHITE)
	entry.add_theme_color_override("icon_pressed_color", Color.WHITE)
	entry.add_theme_stylebox_override("normal", _style(Color("1c2d3a"), 7, 6))
	entry.add_theme_stylebox_override("hover", _style(Color("2b4352"), 7, 6))
	entry.add_theme_stylebox_override("pressed", _style(Color("254e4e"), 7, 6))
	entry.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), 7, 6))
	entry.pressed.connect(toggle_panel.bind(key))
	_entries.add_child(entry)
	buttons[key] = entry
	_layout()
	return body

func toggle_panel(key: String) -> void:
	if not panels.has(key):
		return
	if active_key == key:
		close_panels()
		return
	close_panels()
	active_key = key
	panels[key].show()
	buttons[key].set_pressed_no_signal(true)
	panel_opened.emit(key)

func close_panels() -> void:
	for key in panels:
		panels[key].hide()
		buttons[key].set_pressed_no_signal(false)
	active_key = ""

func get_hit_regions() -> Array[Control]:
	var regions: Array[Control] = [_rail]
	for panel in panels.values():
		regions.append(panel)
	return regions

func _layout() -> void:
	if not is_instance_valid(_rail):
		return
	var rail_x := maxf(size.x - 86.0, 0.0)
	_rail.position = Vector2(rail_x, 150)
	_rail.size = Vector2(74, _entries.get_combined_minimum_size().y + 12)
	for panel in panels.values():
		panel.position = Vector2(maxf(rail_x - 346.0, 0.0), 150)
		panel.size = Vector2(336, maxf(size.y - 392.0, 300.0))

func _icon(key: String) -> Texture2D:
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="32" height="32" viewBox="0 0 32 32"><g fill="none" stroke="#a8d9d0" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">' + str(ICON_PATHS.get(key, "")) + '</g></svg>'
	var image := Image.new()
	image.load_svg_from_string(svg)
	return ImageTexture.create_from_image(image)

func _style(color: Color, radius: int, padding: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style
