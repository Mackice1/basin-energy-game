extends Window
## Staged import UI. The only external mutation hook is applied(series), emitted
## exactly once after a successful preview and an explicit Apply click.

signal applied(series: Dictionary)
signal cancelled

const Parser = preload("res://scripts/series_import.gd")
const FIELDS := ["power", "wind_ms", "irradiance_wm2", "temp_c", "cloud_cover", "precipitation_mm_h", "dni_wm2"]
const FIELD_NAMES := ["直接功率", "风速", "固定面等效POA（非DNI）", "环境温度", "云量（仅全局）", "降水强度（仅全局）", "直接法向DNI（仅全局，非POA）"]
const INK := Color("edf3f6")
const MUTED := Color("a5b7c4")
const BORDER := Color("344b59")
const FIELD_COLOR := Color("14212b")
const ACCENT := Color("69d1bd")
const ERROR := Color("ff9790")
const TIME_UNITS := ["s", "min", "h", "iso_utc"]
const DELIMITERS := [",", ";", "\t"]

var _device_options: Array = []
var _raw_text := ""
var _source_name := ""
var _pending_series: Dictionary = {}
var _built := false
var _updating := false
var _source_label: Label
var _field: OptionButton
var _target: OptionButton
var _delimiter: OptionButton
var _time_column: OptionButton
var _value_column: OptionButton
var _time_unit: OptionButton
var _value_unit: OptionButton
var _range_hint: Label
var _preview: RichTextLabel
var _apply: Button
var _preview_button: Button
var _file: FileDialog

func _init() -> void:
	visible = false
	title = "CSV 数据导入"
	size = Vector2i(860, 680)
	min_size = Vector2i(660, 560)
	transient = true
	exclusive = true

func _ready() -> void:
	_build_ui()

## Device dictionaries: {id, name, kind, rated_kw}. Power uses rated_kw as its
## upper bound. Wind/irradiance/temperature may be global or device-bound;
## cloud cover and precipitation always use global weather (empty ID).
func setup(device_options: Array) -> void:
	_device_options = device_options.duplicate(true)
	if is_inside_tree():
		_build_ui()
		_fill_targets()
		_invalidate()

func open() -> void:
	_build_ui()
	_pending_series = {}
	_apply.disabled = true
	_preview_state(MUTED)
	_preview.text = "等待选择文件\n\n1. 选择 CSV 文件\n2. 确认字段、绑定设备、时间列及单位\n3. 点击“检查并预览”，确认后应用\n\n应用前不会改动场景；取消会丢弃本次导入。"
	popup_centered_clamped(Vector2i(860, 680), 0.92)

## Also usable by an in-game clipboard adapter or a test. Stages only; never emits
## applied or writes a file. The scene remains the sole owner of assignment/save.
func stage_import(text: String, mapping: Dictionary, config: Dictionary = {}) -> Dictionary:
	_build_ui()
	_pending_series = {}
	_apply.disabled = true
	var result: Dictionary = Parser.parse(text, mapping, config)
	if not result.ok:
		_preview_state(ERROR)
		_preview.text = "导入未通过检查，场景未改动。\n请根据以下原因修正文件或映射：\n\n" + "\n".join(PackedStringArray(result.errors))
		return result
	_pending_series = result.series.duplicate(true)
	_apply.disabled = false
	_show_preview(_pending_series)
	return result

func cancel_import() -> void:
	_pending_series = {}
	if _built:
		_apply.disabled = true
		_file.hide()
	hide()
	cancelled.emit()

func apply_import() -> void:
	if _pending_series.is_empty():
		return
	var committed := _pending_series.duplicate(true)
	_pending_series = {}
	_apply.disabled = true
	hide()
	applied.emit(committed)

func _build_ui() -> void:
	if _built:
		return
	_built = true
	theme = _make_theme()
	close_requested.connect(cancel_import)
	var background := Panel.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_theme_stylebox_override("panel", _style(Color("0c151e"), BORDER, 0, 0))
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	background.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	var heading := Label.new()
	heading.text = "导入 CSV 数据"
	heading.add_theme_font_size_override("font_size", 24)
	column.add_child(heading)
	var intro := Label.new()
	intro.text = "01  选择文件    →    02  映射字段    →    03  检查预览    →    04  应用"
	intro.add_theme_color_override("font_color", ACCENT)
	intro.add_theme_font_size_override("font_size", 14)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(intro)
	# Keep the action row reachable when the window is made smaller.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 10)
	scroll.add_child(body)
	var file_row := HBoxContainer.new()
	file_row.add_theme_constant_override("separation", 12)
	body.add_child(file_row)
	var choose := Button.new()
	choose.text = "选择 CSV 文件…"
	choose.custom_minimum_size.y = 38
	choose.pressed.connect(func(): _file.popup_centered_clamped(Vector2i(820, 560), 0.9))
	file_row.add_child(choose)
	_source_label = Label.new()
	_source_label.text = "尚未选择文件"
	_source_label.add_theme_color_override("font_color", MUTED)
	_source_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_source_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	file_row.add_child(_source_label)
	var mapping_panel := PanelContainer.new()
	mapping_panel.add_theme_stylebox_override("panel", _style(Color("14212b"), BORDER, 9, 12))
	body.add_child(mapping_panel)
	var mapping_body := VBoxContainer.new()
	mapping_body.add_theme_constant_override("separation", 10)
	mapping_panel.add_child(mapping_body)
	var mapping_title := Label.new()
	mapping_title.text = "字段与单位"
	mapping_title.add_theme_color_override("font_color", ACCENT)
	mapping_title.add_theme_font_size_override("font_size", 16)
	mapping_body.add_child(mapping_title)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	mapping_body.add_child(grid)
	_field = _add_choice(grid, "导入字段", FIELD_NAMES)
	_target = _add_choice(grid, "绑定对象", [])
	_time_column = _add_choice(grid, "时间列", ["请先选择文件"])
	_time_unit = _add_choice(grid, "时间单位", ["秒（s）", "分钟（min）", "小时（h）", "ISO 8601 UTC"])
	_value_column = _add_choice(grid, "数值列", ["请先选择文件"])
	_value_unit = _add_choice(grid, "数值单位", ["kW", "MW"])
	_delimiter = _add_choice(grid, "分隔符", ["逗号 ,", "分号 ;", "制表符 Tab"])
	var blank := Label.new()
	grid.add_child(blank)
	grid.add_child(Label.new())
	_range_hint = Label.new()
	_range_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_range_hint.add_theme_font_size_override("font_size", 13)
	_range_hint.add_theme_color_override("font_color", MUTED)
	mapping_body.add_child(_range_hint)
	var rules := Label.new()
	rules.text = "辐照映射声明为固定30°集热面POA（方位由用户数据负责），不是GHI/DNI/DHI，不重复转置。未知列名映射视为用户声明。光热仅使用全局POA与环境温度。\n每次导入一个数值列。优先级：直接功率 > 导入气象 > 内置模型。\nDNI、云量、降水强度仅支持全局显式数据；不从辐照度推断云雨。\n每个值保持到下一时间点；超出首末时间点则无数据并暂停，缺失或无效值会被拒绝。\n时间按模拟时间计；ISO UTC 首个时间点对应 0 s，并保留原始起点。"
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.add_theme_font_size_override("font_size", 13)
	rules.add_theme_color_override("font_color", MUTED)
	body.add_child(rules)
	var preview_heading := Label.new()
	preview_heading.text = "检查与预览"
	preview_heading.add_theme_color_override("font_color", ACCENT)
	preview_heading.add_theme_font_size_override("font_size", 16)
	body.add_child(preview_heading)
	_preview = RichTextLabel.new()
	_preview.bbcode_enabled = false
	_preview.scroll_active = true
	_preview.selection_enabled = true
	_preview.custom_minimum_size = Vector2(0, 166)
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.add_theme_stylebox_override("normal", _style(FIELD_COLOR, BORDER, 9, 12))
	_preview.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), ACCENT, 9, 12, 2))
	_preview.add_theme_color_override("default_color", INK)
	_preview.add_theme_color_override("selection_color", Color("315c66"))
	_preview.add_theme_font_size_override("normal_font_size", 14)
	_preview.add_theme_constant_override("line_separation", 4)
	body.add_child(_preview)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	column.add_child(footer)
	_preview_button = Button.new()
	_preview_button.text = "检查并预览"
	_preview_button.custom_minimum_size.y = 38
	_preview_button.disabled = true
	_preview_button.pressed.connect(_preview_current)
	footer.add_child(_preview_button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var cancel := Button.new()
	cancel.text = "取消"
	cancel.custom_minimum_size = Vector2(80, 38)
	cancel.pressed.connect(cancel_import)
	footer.add_child(cancel)
	_apply = Button.new()
	_apply.text = "应用导入"
	_apply.custom_minimum_size = Vector2(108, 38)
	for state in ["normal", "hover", "pressed"]:
		_apply.add_theme_stylebox_override(state, _style(Color("224a4c") if state == "normal" else Color("2e6260"), ACCENT, 8, 10))
	_apply.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), ACCENT, 8, 10, 2))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_apply.add_theme_color_override(state, INK)
	_apply.disabled = true
	_apply.pressed.connect(apply_import)
	footer.add_child(_apply)
	_file = FileDialog.new()
	_file.title = "选择 UTF-8 编码的 CSV 文件"
	_file.theme = theme
	_file.access = FileDialog.ACCESS_FILESYSTEM
	_file.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file.ok_button_text = "打开"
	_file.cancel_button_text = "取消"
	_file.filters = PackedStringArray(["*.csv ; CSV 数据文件", "*.tsv ; 制表符数据文件", "*.txt ; 文本文件"])
	_file.file_selected.connect(_load_file)
	add_child(_file)
	_field.item_selected.connect(_on_field_selected)
	_target.item_selected.connect(func(_index: int): _invalidate(); _update_range_hint())
	_time_unit.item_selected.connect(func(_index: int): _invalidate())
	_value_unit.item_selected.connect(func(_index: int): _invalidate())
	_time_column.item_selected.connect(func(_index: int): _invalidate())
	_value_column.item_selected.connect(func(_index: int): _invalidate())
	_delimiter.item_selected.connect(func(_index: int): _load_headers())
	_fill_targets()
	_update_range_hint()

func _make_theme() -> Theme:
	var result := Theme.new()
	result.default_font = load("res://assets/InterfaceCJK.ttc")
	result.default_font_size = 15
	for type in ["Label", "Button", "OptionButton", "LineEdit", "Tree", "ItemList", "PopupMenu"]:
		result.set_color("font_color", type, INK)
		result.set_color("font_disabled_color", type, Color("788e9d"))
	for type in ["Button", "OptionButton"]:
		for state in ["font_hover_color", "font_pressed_color", "font_focus_color", "icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			result.set_color(state, type, INK)
		result.set_stylebox("normal", type, _style(FIELD_COLOR, BORDER, 7, 9))
		result.set_stylebox("hover", type, _style(Color("263e4d"), Color("69d1bd"), 7, 9))
		result.set_stylebox("pressed", type, _style(Color("224a4c"), Color("69d1bd"), 7, 9))
		result.set_stylebox("focus", type, _style(Color(0, 0, 0, 0), Color("69d1bd"), 7, 9, 2))
		result.set_stylebox("disabled", type, _style(Color("101c26"), Color("293d4a"), 7, 9))
	result.set_constant("modulate_arrow", "OptionButton", 1)
	result.set_color("folder_icon_color", "FileDialog", INK)
	result.set_color("file_icon_color", "FileDialog", MUTED)
	result.set_stylebox("panel", "PopupMenu", _style(FIELD_COLOR, BORDER, 8, 8))
	result.set_stylebox("hover", "PopupMenu", _style(Color("263e4d"), Color("263e4d"), 5, 6))
	result.set_color("font_hover_color", "PopupMenu", INK)
	result.set_constant("v_separation", "PopupMenu", 10)
	result.set_color("font_separator_color", "PopupMenu", MUTED)
	result.set_stylebox("panel", "FileDialog", _style(Color("0c151e"), BORDER, 9, 12))
	result.set_stylebox("panel", "AcceptDialog", _style(Color("0c151e"), BORDER, 9, 12))
	for type in ["Tree", "ItemList"]:
		result.set_stylebox("panel", type, _style(FIELD_COLOR, BORDER, 7, 7))
		result.set_stylebox("selected", type, _style(Color("315c66"), Color("467f80"), 4, 4))
		result.set_stylebox("selected_focus", type, _style(Color("315c66"), Color("69d1bd"), 4, 4))
		result.set_color("font_selected_color", type, INK)
	result.set_stylebox("normal", "LineEdit", _style(FIELD_COLOR, BORDER, 7, 8))
	result.set_stylebox("read_only", "LineEdit", _style(Color("101c26"), BORDER, 7, 8))
	result.set_stylebox("focus", "LineEdit", _style(Color(0, 0, 0, 0), Color("69d1bd"), 7, 8, 2))
	result.set_color("caret_color", "LineEdit", INK)
	result.set_color("font_placeholder_color", "LineEdit", MUTED)
	result.set_color("font_uneditable_color", "LineEdit", MUTED)
	result.set_color("selection_color", "LineEdit", Color("315c66"))
	for type in ["VScrollBar", "HScrollBar"]:
		result.set_stylebox("scroll", type, _style(Color("14212b"), Color("14212b"), 5, 4))
		for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
			result.set_stylebox(state, type, _style(Color("486575"), Color("486575"), 5, 4))
	return result

func _style(fill: Color, border: Color, radius: int, padding: int, border_width: int = 1) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = border
	result.set_border_width_all(border_width)
	result.set_corner_radius_all(radius)
	result.content_margin_left = padding
	result.content_margin_right = padding
	result.content_margin_top = padding
	result.content_margin_bottom = padding
	return result

func _add_choice(grid: GridContainer, label_text: String, choices: Array) -> OptionButton:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.custom_minimum_size = Vector2(170, 36)
	option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	for choice in choices:
		option.add_item(str(choice))
	grid.add_child(option)
	return option

func _fill_targets() -> void:
	_updating = true
	_target.clear()
	var is_power: bool = FIELDS[_field.selected] == "power"
	var global_only: bool = FIELDS[_field.selected] in Parser.GLOBAL_ONLY_FIELDS
	if not is_power:
		_target.add_item("全局气象")
		_target.set_item_metadata(0, {"id": "", "name": "Global weather"})
	for device in _device_options:
		if global_only:
			break
		if not device is Dictionary or str(device.get("id", "")).is_empty():
			continue
		if device.get("kind","")in ["solar_thermal","parabolic_trough","high_temp_store","oil_water_exchanger","steam_generator","steam_turbine","steam_condenser","feedwater_pump"]:continue
		if is_power and not _supports_power(device):
			continue
		var label := "%s [%s]" % [str(device.get("name", device.id)), str(device.id)]
		_target.add_item(label)
		_target.set_item_metadata(_target.item_count - 1, device.duplicate(true))
	if _target.item_count == 0:
		_target.add_item("请先放置发电设备")
		_target.set_item_metadata(0, {})
		_target.disabled = true
	else:
		_target.disabled = global_only
	_target.tooltip_text = "DNI、云量、降水强度仅支持全局，不可绑定设备。" if global_only else ""
	_updating = false
	_update_range_hint()

func _supports_power(device: Dictionary) -> bool:
	if device.get("kind","")in ["solar_thermal","parabolic_trough","high_temp_store","oil_water_exchanger","steam_generator","steam_turbine","steam_condenser","feedwater_pump"]:return false
	# Parents may provide only generators. If a known infrastructure kind is sent,
	# do not offer it as an energy source; rated_kw > 0 explicitly enables one.
	if float(device.get("rated_kw", 0.0)) > 0.0:
		return true
	return not str(device.get("kind", "")) in ["substation", "line", "cable", "auxiliary", "boiler", "steam_turbine", "pipe", "storage"]

func _on_field_selected(_index: int) -> void:
	_invalidate()
	_value_unit.clear()
	for unit in Parser.FIELD_UNITS[FIELDS[_field.selected]]:
		_value_unit.add_item(unit)
	_fill_targets()

func _load_file(path: String) -> void:
	_invalidate()
	_raw_text = ""
	_source_name = ""
	_source_label.text = "尚未选择文件"
	_preview_button.disabled = true
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_preview_state(ERROR)
		_preview.text = "无法读取文件（错误 %s），场景未改动。" % FileAccess.get_open_error()
		return
	if file.get_length() > Parser.MAX_BYTES:
		_preview_state(ERROR)
		_preview.text = "CSV 超过 8 MiB 大小上限，场景未改动。"
		file.close()
		return
	_raw_text = file.get_as_text()
	file.close()
	_source_name = path.get_file() # Do not persist a machine-specific absolute path.
	_source_label.text = _source_name
	_source_label.tooltip_text = _source_name
	if path.get_extension().to_lower() == "tsv":
		_delimiter.select(2)
	_load_headers()

func _load_headers() -> void:
	_invalidate()
	_time_column.clear()
	_value_column.clear()
	_preview_button.disabled = true
	if _raw_text.is_empty():
		_preview_state(ERROR)
		_preview.text = "请选择非空 CSV 文件，场景未改动。"
		return
	var result: Dictionary = Parser.inspect_csv(_raw_text, DELIMITERS[_delimiter.selected])
	if not result.ok:
		_preview_state(ERROR)
		_preview.text = "CSV 结构检查未通过，请修正文件后重试：\n\n" + "\n".join(PackedStringArray(result.errors))
		return
	for header in result.headers:
		_time_column.add_item(str(header))
		_value_column.add_item(str(header))
	if _value_column.item_count > 1:
		_value_column.select(1)
	_preview_button.disabled = false
	_preview.text = "%s · 共 %d 行数据\n请确认字段、绑定对象、列及单位，再点击“检查并预览”。\n系统不会根据数值猜测列或单位。" % [_source_name, result.records.size()]

func _preview_current() -> void:
	var mapping := {
		"time_column": _time_column.selected, "value_column": _value_column.selected,
		"time_unit": TIME_UNITS[_time_unit.selected],
		"value_unit": _value_unit.get_item_text(_value_unit.selected),
		"field": FIELDS[_field.selected],
		"target_device": str(_selected_device().get("id", "")),
		"delimiter": DELIMITERS[_delimiter.selected],
	}
	var config := {"source_name": _source_name}
	if mapping.field == "power" and float(_selected_device().get("rated_kw", 0.0)) > 0.0:
		config.max_power_kw = float(_selected_device().rated_kw)
	stage_import(_raw_text, mapping, config)

func _selected_device() -> Dictionary:
	if _target.selected < 0:
		return {}
	var metadata: Variant = _target.get_item_metadata(_target.selected)
	return metadata if metadata is Dictionary else {}

func _update_range_hint() -> void:
	if _range_hint == null:
		return
	var field: String = FIELDS[_field.selected]
	var maximum: float = Parser.BOUNDS[field][1]
	if field == "power" and float(_selected_device().get("rated_kw", 0.0)) > 0.0:
		maximum = minf(maximum, float(_selected_device().rated_kw))
	_range_hint.text = "换算后允许范围：%.3f 至 %.3f %s%s" % [Parser.BOUNDS[field][0], maximum, Parser.FIELD_UNITS[field][0], "（受设备额定值约束）" if field == "power" and _selected_device().has("rated_kw") else ""]
	if field in Parser.GLOBAL_ONLY_FIELDS:
		_range_hint.text += " · 仅全局显式数据，不可绑定设备"

func _show_preview(series: Dictionary) -> void:
	_preview_state(ACCENT)
	var target := str(series.target_device)
	if target.is_empty():
		target = "全局气象"
	var lines: Array[String] = [
		"预览通过 · %s → %s" % [FIELD_NAMES[FIELDS.find(series.field)], target],
		"%d 个样本 · 时间 %.3f–%.3f s · 数值 %.3f–%.3f %s" % [series.count, series.start_s, series.end_s, series.min_value, series.max_value, series.unit],
		"来源：%s · SHA-256 %s…" % [series.source.name, str(series.source.sha256).substr(0, 12)],
	]
	if not str(series.time_origin_utc).is_empty():
		lines.append("UTC 起点：%s，对应模拟时间 0 s" % series.time_origin_utc)
	lines.append("样本预览（已换算为标准单位）：")
	for i in mini(6, series.samples.size()):
		lines.append("  时间 %.3f s     数值 %.3f %s" % [series.samples[i].t, series.samples[i].value, series.unit])
	if series.samples.size() > 6:
		lines.append("  … 另有 %d 个样本" % (series.samples.size() - 6))
	lines.append("应用后替换同一绑定对象、同一字段的原导入；当前尚未改动场景。")
	_preview.text = "\n".join(PackedStringArray(lines))

func _invalidate() -> void:
	if _updating:
		return
	_pending_series = {}
	if _apply != null:
		_apply.disabled = true
	if _preview != null:
		_preview_state(MUTED)
		_preview.text = "映射已更新，请重新检查并预览后再应用。"

func _preview_state(color: Color) -> void:
	_preview.add_theme_stylebox_override("normal", _style(FIELD_COLOR, color if color != MUTED else BORDER, 9, 12))
	_preview.add_theme_color_override("default_color", ERROR if color == ERROR else INK)

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and visible:
		cancel_import()
		set_input_as_handled()
