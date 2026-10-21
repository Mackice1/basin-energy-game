extends VBoxContainer
## Integer slider and validated integer entry. Pause belongs to the controller.
## Programmatic set_speed() never emits speed_changed. Invalid values are
## explicitly rejected; neither input nor controller values silently clamp.

signal speed_changed(value: float)

const MIN_SPEED := 1.0
const MAX_SPEED := 60.0
const INK := Color("edf3f6")
const MUTED := Color("a5b7c4")
const BORDER := Color("344b59")
const ERROR := Color("ff9790")
const INPUT_HELP := "输入 1–60 的整数倍，按回车或离开输入框应用；小数和越界值不会生效。"

var _speed := 1.0
var _built := false
var _syncing := false
var _committed_text := "1"
var _slider: HSlider
var _input: LineEdit
var _range_note: Label
var _error: Label

func _ready() -> void:
	_build_ui()

## Safe before _ready, or in response to speed_changed. Identical controller
## refreshes do not erase text the user is currently typing or an error message.
func set_speed(value: float) -> void:
	_build_ui()
	if not _valid_speed(value):
		_reject_input()
		return
	if value == _speed:
		return
	_speed = value
	_sync_controls()
	_clear_error()

func get_speed() -> float:
	return _speed

func _build_ui() -> void:
	if _built:
		return
	_built = true
	name = "SpeedControl"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 3)
	var title := _label("模拟速度", 15, INK)
	title.custom_minimum_size.y = 24
	add_child(title)
	var row := HBoxContainer.new()
	row.name = "SpeedRow"
	row.add_theme_constant_override("separation", 7)
	add_child(row)
	_slider = HSlider.new()
	_slider.name = "SpeedSlider"
	_slider.min_value = MIN_SPEED
	_slider.max_value = MAX_SPEED
	_slider.step = 1.0
	_slider.value = _speed
	_slider.custom_minimum_size = Vector2(104, 34)
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slider.scrollable = false
	_slider.tooltip_text = "1–60 倍，线性滑条；拖动或方向键每次调整 1 倍，也可在右侧输入整数。"
	for state in ["slider", "grabber_area", "grabber_area_highlight"]:
		var track := StyleBoxFlat.new()
		track.bg_color = BORDER if state == "slider" else Color("69d1bd")
		track.set_corner_radius_all(3)
		track.content_margin_top = 3
		track.content_margin_bottom = 3
		_slider.add_theme_stylebox_override(state, track)
	row.add_child(_slider)
	var multiplier := _label("×", 16, MUTED)
	multiplier.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(multiplier)
	_input = LineEdit.new()
	_input.name = "SpeedInput"
	_input.custom_minimum_size = Vector2(80, 34)
	_input.expand_to_text_length = false
	_input.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_input.select_all_on_focus = true
	_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	_input.add_theme_font_size_override("font_size", 16)
	_input.add_theme_color_override("font_color", INK)
	_input.add_theme_color_override("caret_color", INK)
	_input.add_theme_color_override("selection_color", Color("315c66"))
	_input.add_theme_stylebox_override("normal", _input_style(BORDER))
	_input.add_theme_stylebox_override("focus", _input_style(Color("69d1bd"), true))
	_input.tooltip_text = INPUT_HELP
	row.add_child(_input)
	_range_note = _label("1–60 倍 · 拖动每次 1 倍，右侧输入整数", 12, MUTED)
	_range_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_range_note.tooltip_text = INPUT_HELP
	add_child(_range_note)
	_error = _label("", 12, ERROR)
	_error.name = "SpeedError"
	_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_error.hide()
	add_child(_error)
	_slider.value_changed.connect(_on_slider_changed)
	_input.text_submitted.connect(_commit_text)
	_input.focus_exited.connect(func(): _commit_text(_input.text))
	_input.text_changed.connect(func(_text: String): _clear_error())
	_sync_controls()

func _on_slider_changed(value: float) -> void:
	if _syncing:
		return
	_accept_speed(value)

func _commit_text(text: String) -> void:
	if _syncing:
		return
	var candidate := text.strip_edges()
	# No duplicate emission on Enter followed by focus exit; a rejected input's
	# error also remains visible after the restored value loses focus.
	if candidate == _committed_text:
		_input.text = _committed_text
		return
	if not candidate.is_valid_float():
		_reject_input()
		return
	var value := candidate.to_float()
	if not _valid_speed(value):
		_reject_input()
		return
	_accept_speed(value)

func _accept_speed(value: float) -> void:
	if not _valid_speed(value):
		_reject_input()
		return
	var changed := value != _speed
	_speed = value
	_sync_controls()
	_clear_error()
	if changed:
		speed_changed.emit(_speed)

func _sync_controls() -> void:
	_syncing = true
	# Silent Range update prevents controller synchronization from looping.
	_slider.set_value_no_signal(_speed)
	_committed_text = _format_speed(_speed)
	_input.text = _committed_text
	_syncing = false

func _reject_input() -> void:
	_sync_controls()
	_error.text = "请输入 1–60 范围内的整数；已恢复原值。"
	_error.show()
	_input.tooltip_text = _error.text + "\n" + INPUT_HELP
	_input.add_theme_stylebox_override("normal", _input_style(ERROR))

func _clear_error() -> void:
	_error.hide()
	_error.text = ""
	_input.tooltip_text = INPUT_HELP
	_input.add_theme_stylebox_override("normal", _input_style(BORDER))

func _valid_speed(value: float) -> bool:
	return is_finite(value) and value >= MIN_SPEED and value <= MAX_SPEED and value == floorf(value)

func _format_speed(value: float) -> String:
	return str(int(value))

func _label(text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result

func _input_style(border: Color, focus: bool = false) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = Color(0, 0, 0, 0) if focus else Color("14212b")
	result.border_color = border
	result.set_border_width_all(2 if focus else 1)
	result.set_corner_radius_all(6)
	result.content_margin_left = 7
	result.content_margin_right = 7
	result.content_margin_top = 5
	result.content_margin_bottom = 5
	return result
