extends VBoxContainer
## Explicit geography/calendar configuration. No external weather lookup.
signal apply_requested(config: Dictionary)

const Climate = preload("res://scripts/climate_model.gd")
const SCENARIOS := ["clear", "partly_cloudy", "overcast", "windy"]
const INK := Color("edf3f6")
const MUTED := Color("a5b7c4")
const ACCENT := Color("69d1bd")
const ERROR := Color("ff9790")

var latitude := SpinBox.new()
var longitude := SpinBox.new()
var utc_offset := SpinBox.new()
var start_local := LineEdit.new()
var scenario := OptionButton.new()
var feedback := Label.new()
var live := Label.new()

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var intro := Label.new()
	intro.text = "位置用于太阳位置计算，不会下载当地天气。场址地形仍是合成地图。"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", MUTED)
	intro.add_theme_font_size_override("font_size", 13)
	add_child(intro)
	_row("纬度 °（北正）", latitude)
	latitude.min_value = -90
	latitude.max_value = 90
	latitude.step = 0.01
	_row("经度 °（东正）", longitude)
	longitude.min_value = -180
	longitude.max_value = 180
	longitude.step = 0.01
	_row("UTC 偏移 h", utc_offset)
	utc_offset.min_value = -12
	utc_offset.max_value = 14
	utc_offset.step = 0.25
	var date_title := Label.new()
	date_title.text = "起始本地日期时间"
	date_title.add_theme_color_override("font_color", INK)
	date_title.add_theme_font_size_override("font_size", 14)
	add_child(date_title)
	start_local.placeholder_text = "2026-06-21T12:00:00"
	start_local.custom_minimum_size.y = 36
	start_local.tooltip_text = "格式：年-月-日T时:分:秒。使用上方固定 UTC 偏移，不采用夏令时。"
	add_child(start_local)
	var date_hint := Label.new()
	date_hint.text = "固定 UTC 偏移 · 不采用夏令时"
	date_hint.add_theme_color_override("font_color", MUTED)
	date_hint.add_theme_font_size_override("font_size", 12)
	add_child(date_hint)
	for caption in ["教学 · 晴空", "教学 · 多云", "教学 · 阴云", "教学 · 大风"]:
		scenario.add_item(caption)
	scenario.custom_minimum_size.y = 36
	scenario.tooltip_text = "教学示例气象，不是实测或天气预报；已绑定的 CSV 字段保持优先。"
	add_child(scenario)
	var apply := Button.new()
	apply.text = "应用位置 / 时间 / 教学情景…"
	apply.custom_minimum_size.y = 38
	apply.add_theme_color_override("font_color", ACCENT)
	add_child(apply)
	apply.pressed.connect(_submit)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.add_theme_font_size_override("font_size", 12)
	add_child(feedback)
	live.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	live.add_theme_font_size_override("font_size", 13)
	live.add_theme_color_override("font_color", INK)
	var live_style := StyleBoxFlat.new()
	live_style.bg_color = Color("14212b")
	live_style.border_color = Color("344b59")
	live_style.set_border_width_all(1)
	live_style.set_corner_radius_all(6)
	live_style.content_margin_left = 10
	live_style.content_margin_right = 10
	live_style.content_margin_top = 8
	live_style.content_margin_bottom = 8
	live.add_theme_stylebox_override("normal", live_style)
	live.hide()
	add_child(live)
	set_config(Climate.defaults())

func _row(caption: String, control: Control) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var title := Label.new()
	title.text = caption
	title.add_theme_color_override("font_color", INK)
	title.add_theme_font_size_override("font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	control.custom_minimum_size = Vector2(134, 36)
	row.add_child(control)

func set_config(config: Dictionary) -> void:
	latitude.value = config.latitude_deg
	longitude.value = config.longitude_deg
	utc_offset.value = config.utc_offset_hours
	start_local.text = config.start_local
	scenario.select(SCENARIOS.find(config.scenario))
	feedback.text = "示例气象随日历和模拟时间生成；CSV 已绑定字段仍优先。"
	feedback.add_theme_color_override("font_color", MUTED)

func _submit() -> void:
	var candidate := {"latitude_deg": latitude.value, "longitude_deg": longitude.value, "utc_offset_hours": utc_offset.value, "start_local": start_local.text.strip_edges(), "scenario": SCENARIOS[scenario.selected]}
	var error := Climate.validate(candidate)
	if error != "":
		feedback.text = "未应用：" + error
		feedback.add_theme_color_override("font_color", ERROR)
		return
	feedback.text = "设置检查通过，请在确认窗口中决定是否应用。"
	feedback.add_theme_color_override("font_color", ACCENT)
	apply_requested.emit(candidate)

func set_snapshot(snapshot: Dictionary) -> void:
	live.show()
	if not snapshot.get("valid", false):
		live.text = "当前气象不可用：" + str(snapshot.get("error", "未知"))
		live.add_theme_color_override("font_color", ERROR)
		return
	live.add_theme_color_override("font_color", INK)
	live.text = "当前气象 · %s\n%s\nUTC %s\n太阳高度 %.1f° · 方位 %.1f°\n%s" % ["日间" if snapshot.get("is_day", false) else "夜间", snapshot.get("local_datetime", ""), snapshot.get("utc_datetime", ""), snapshot.get("solar_altitude_deg", 0.0), snapshot.get("solar_azimuth_deg", 0.0), snapshot.get("source", "")]
