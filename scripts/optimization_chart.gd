extends Control
## Read-only step plot for an isolated optimization result. Missing values are
## omitted rather than replaced with zero. Values are never interpolated.

signal step_selected(index: int)

const INK := Color("edf3f6")
const MUTED := Color("a5b7c4")
const GRID := Color("344b59")
const PAPER := Color("14212b")
const ACCENT := Color("69d1bd")

var _steps: Array = []
var _series: Array = []
var _title := ""
var _unit := "MW"
var _fixed_max := -1.0
var _selected := -1
var _empty_text := "尚无求解结果"
var _plot := Rect2()
var _start_s := 0.0
var _end_s := 1.0
var _legend_hits: Array = []
var _hidden: Dictionary = {}
var _preferred_height := 220.0

func _init() -> void:
	custom_minimum_size = Vector2(300, 220)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	tooltip_text = "点击曲线选择时段；左右方向键切换。点击图例可隐藏或显示该曲线。"

func _ready() -> void:
	_preferred_height = custom_minimum_size.y
	resized.connect(_refresh_layout)
	_refresh_layout()

## Series entries: {key, label, color, multiplier?}; dotted keys read a nested
## carrier ledger (for example thermal.served_mwth), without merging units.
## A fixed_max of 100 is
## appropriate for SOC percent. Input data is copied and never mutated.
func configure(title_text: String, unit: String, series: Array, fixed_max: float = -1.0) -> void:
	_title = title_text
	_unit = unit
	_series = series.duplicate(true)
	_fixed_max = fixed_max
	_hidden.clear()
	_refresh_layout()

func set_steps(steps: Array) -> void:
	_steps = steps.duplicate(true)
	_selected = 0 if not _steps.is_empty() else -1
	if not _steps.is_empty():
		_start_s = float(_steps[0].get("time_s", 0.0))
		var last: Dictionary = _steps[-1]
		_end_s = float(last.get("time_s", _start_s)) + float(last.get("dt_h", 0.0)) * 3600.0
		_end_s = maxf(_end_s, _start_s + 0.001)
	_refresh_layout()

func clear(message: String = "尚无求解结果") -> void:
	_steps.clear()
	_selected = -1
	_empty_text = message
	_refresh_layout()

func set_selected(index: int) -> void:
	_selected = clampi(index, 0, _steps.size() - 1) if not _steps.is_empty() else -1
	queue_redraw()

func _draw() -> void:
	if size.x < 100.0 or size.y < 100.0:
		return
	var font: Font = get_theme_default_font()
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	draw_string(font, Vector2(14, 24), _title + " · " + _unit, HORIZONTAL_ALIGNMENT_LEFT, size.x - 28, 15, INK)
	_legend_hits = _layout_legend(maxf(size.x, 300.0))
	for hit in _legend_hits:
		var rect: Rect2 = hit.rect
		var hidden: bool = _hidden.get(hit.key, false)
		var color: Color = MUTED if hidden else hit.color
		draw_style_box(_legend_style(hidden), rect)
		draw_line(rect.position + Vector2(7, 12), rect.position + Vector2(23, 12), color, 2.5, true)
		draw_string(font, rect.position + Vector2(29, 17), hit.caption, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 35, 13, MUTED if hidden else INK)
		if hidden:
			draw_line(rect.position + Vector2(7, 7), rect.position + Vector2(23, 17), MUTED, 1.0, true)
	var legend_bottom := 34.0 if _legend_hits.is_empty() else float(_legend_hits[-1].rect.end.y)
	_plot = Rect2(62, legend_bottom + 16, maxf(size.x - 84.0, 20.0), maxf(size.y - legend_bottom - 60.0, 80.0))
	if _steps.is_empty():
		draw_string(font, Vector2(_plot.position.x + 10, _plot.get_center().y), _empty_text, HORIZONTAL_ALIGNMENT_CENTER, _plot.size.x - 20, 14, MUTED)
		return
	var peak := _maximum()
	for tick in range(5):
		var ratio := float(tick) / 4.0
		var y := _plot.end.y - ratio * _plot.size.y
		draw_line(Vector2(_plot.position.x, y), Vector2(_plot.end.x, y), GRID, 1)
		draw_string(font, Vector2(7, y + 4), _number(peak * ratio), HORIZONTAL_ALIGNMENT_RIGHT, 43, 11, MUTED)
	for tick in range(5):
		var ratio := float(tick) / 4.0
		var x := _plot.position.x + ratio * _plot.size.x
		draw_line(Vector2(x, _plot.position.y), Vector2(x, _plot.end.y), Color(GRID, 0.55), 1)
		var hour := (_end_s - _start_s) * ratio / 3600.0
		draw_string(font, Vector2(x - 21, _plot.end.y + 17), _number(hour), HORIZONTAL_ALIGNMENT_CENTER, 42, 11, MUTED)
	draw_string(font, Vector2(_plot.position.x, size.y - 6), "相对预测起点 / h", HORIZONTAL_ALIGNMENT_RIGHT, _plot.size.x, 11, MUTED)
	if _selected >= 0 and _selected < _steps.size():
		var selected_step: Dictionary = _steps[_selected]
		var left := _x(float(selected_step.get("time_s", _start_s)))
		var right := _x(float(selected_step.get("time_s", _start_s)) + float(selected_step.get("dt_h", 0.0)) * 3600.0)
		draw_rect(Rect2(left, _plot.position.y, maxf(right - left, 2.0), _plot.size.y), Color(ACCENT, 0.10))
		draw_line(Vector2(left, _plot.position.y), Vector2(left, _plot.end.y), ACCENT, 1.5)
	for serie in _series:
		var key := str(serie.get("key", ""))
		if _hidden.get(key, false):
			continue
		var color: Color = serie.get("color", INK)
		var multiplier := float(serie.get("multiplier", 1.0))
		var previous := Vector2.ZERO
		var previous_end_s := -INF
		for step in _steps:
			var raw_value: Variant = _series_value(step, key)
			if not _valid_number(raw_value):
				previous_end_s = -INF
				continue
			var value := float(raw_value) * multiplier
			var time_s := float(step.get("time_s", _start_s))
			var end_s := time_s + float(step.get("dt_h", 0.0)) * 3600.0
			var y := _plot.end.y - clampf(value / peak, 0.0, 1.0) * _plot.size.y
			var point := Vector2(_x(time_s), y)
			var end := Vector2(_x(end_s), y)
			if is_finite(previous_end_s) and absf(previous_end_s - time_s) < 0.001:
				draw_line(previous, point, Color(color, 0.55), 1.0, true)
			draw_line(point, end, color, 2.0, true)
			previous = end
			previous_end_s = end_s
	if has_focus():
		draw_rect(Rect2(Vector2(2, 2), size - Vector2(4, 4)), ACCENT, false, 1.5)

## Only omit wholly absent fields, never valid zeroes. The series catalog and
## missing-value semantics remain unchanged; hidden legends stay available.
func _layout_legend(width: float) -> Array:
	var hits: Array = []
	if _steps.is_empty():
		return hits
	var font: Font = get_theme_default_font()
	var cursor := Vector2(14, 36)
	for serie in _series:
		var key := str(serie.get("key", ""))
		var has_data := false
		for step in _steps:
			if _valid_number(_series_value(step, key)):
				has_data = true
				break
		if not has_data:
			continue
		var caption := str(serie.get("label", key))
		var entry_width := minf(font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x + 40.0, width - 28.0)
		if cursor.x + entry_width > width - 14.0 and cursor.x > 14.0:
			cursor.x = 14.0
			cursor.y += 30.0
		hits.append({"rect": Rect2(cursor, Vector2(entry_width, 24)), "key": key, "caption": caption, "color": serie.get("color", INK)})
		cursor.x += entry_width + 6.0
	return hits

func _refresh_layout() -> void:
	if not is_inside_tree():
		_preferred_height = custom_minimum_size.y
	var hits := _layout_legend(maxf(size.x, 300.0))
	var bottom := 34.0 if hits.is_empty() else float(hits[-1].rect.end.y)
	# Reserve a real plotting area even when multi-carrier legends wrap.
	custom_minimum_size.y = maxf(_preferred_height, bottom + 156.0)
	queue_redraw()

func _legend_style(hidden: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("101c26") if hidden else Color("1c2d3a")
	style.border_color = GRID
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	return style

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		grab_focus()
		for hit in _legend_hits:
			if hit.rect.has_point(event.position):
				_hidden[hit.key] = not _hidden.get(hit.key, false)
				queue_redraw()
				accept_event()
				return
		if _plot.has_point(event.position) and not _steps.is_empty():
			var target_s := _start_s + clampf((event.position.x - _plot.position.x) / _plot.size.x, 0.0, 1.0) * (_end_s - _start_s)
			var nearest := 0
			for index in range(_steps.size()):
				if float(_steps[index].get("time_s", _start_s)) <= target_s:
					nearest = index
			_choose(nearest)
			accept_event()
	elif event is InputEventKey and event.pressed and not _steps.is_empty():
		if event.keycode == KEY_LEFT or event.keycode == KEY_RIGHT:
			_choose(clampi(_selected + (-1 if event.keycode == KEY_LEFT else 1), 0, _steps.size() - 1))
			accept_event()

func _choose(index: int) -> void:
	set_selected(index)
	step_selected.emit(_selected)

func _x(time_s: float) -> float:
	return _plot.position.x + (time_s - _start_s) / (_end_s - _start_s) * _plot.size.x

func _maximum() -> float:
	if _fixed_max > 0.0:
		return _fixed_max
	var peak := 0.0
	for step in _steps:
		for serie in _series:
			var key := str(serie.get("key", ""))
			var value: Variant = _series_value(step, key)
			if not _hidden.get(key, false) and _valid_number(value):
				peak = maxf(peak, float(value) * float(serie.get("multiplier", 1.0)))
	return maxf(peak * 1.1, 1.0)

func _series_value(step: Dictionary, key: String) -> Variant:
	var value: Variant = step
	for part in key.split("."):
		if not value is Dictionary or not value.has(part):
			return null
		value = value[part]
	return value

func _number(value: float) -> String:
	if absf(value) >= 100.0:
		return "%.0f" % value
	return "%.1f" % value

func _valid_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.border_color = GRID
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	return style
