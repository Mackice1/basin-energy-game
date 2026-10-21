extends Control
## An original, simulation-clock-only weather instrument. The orb never moves.
## Cloud, rain and day/night are shown only when explicitly supplied. The legacy
## three resource fields remain supported without claiming a sky condition.

const ORB_SIZE := 76.0
const TITLE := "全局背景天气"
const FIELDS := ["wind_speed_mps", "irradiance_wm2", "air_temp_c", "cloud_cover", "precipitation_mm_h", "solar_altitude_deg"]
const TRANSITION_SECONDS := 0.8
const MAX_TRANSITIONS := 256
const CENTER := Vector2(38, 38)
const FACE_RADIUS := 32.5

## The parent breaks its panel's bottom border across this mount, matching these
## colors. In local coordinates the horizontal seam is y=54 by default,
## shoulders x=-27/103, low point y=79.5. No mount area intercepts map input.
var mount_enabled := true
var mount_seam_y := 54.0
var mount_fill := Color(0.88, 0.92, 0.87, 0.86)
var mount_border := Color(0.98, 1.0, 0.95, 0.48)

var _values: Dictionary = {}
var _time_s := 0.0
var _time_valid := true
var _source := "未提供"
var _state_label := ""
var _calendar := ""
var _hovered := false
var _display: Dictionary = {}
var _transitions: Array[Dictionary] = []
var _has_sample := false
var _layer_alpha := 1.0

func _init() -> void:
	name = "WeatherOrb"
	custom_minimum_size = Vector2(ORB_SIZE, ORB_SIZE)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_HELP
	focus_mode = Control.FOCUS_NONE
	set_process(false)
	set_weather({}, 0.0, "")
	_has_sample = false
	_transitions.clear()

func _ready() -> void:
	mouse_entered.connect(_set_hovered.bind(true))
	mouse_exited.connect(_set_hovered.bind(false))
	resized.connect(queue_redraw)

## source_text is retained for existing callers. A nonempty weather.source is
## also disclosed. weather_state is provenance only, never a replacement for
## missing cloud/rain measurements. solar_altitude_deg has priority over is_day.
func set_weather(weather: Dictionary, time_s: float, source_text: String = "") -> void:
	_values = {}
	for field in FIELDS:
		var value: Variant = weather.get(field)
		if not _valid_number(value):
			continue
		var number := float(value)
		if field == "cloud_cover" and (number < 0.0 or number > 1.0):
			continue
		if field == "solar_altitude_deg" and (number < -90.0 or number > 90.0):
			continue
		if field not in ["air_temp_c", "solar_altitude_deg"] and number < 0.0:
			continue
		_values[field] = number
	_time_valid = is_finite(time_s)
	_time_s = time_s if _time_valid else 0.0
	var supplied_source := str(weather.get("source", "")).strip_edges() if weather.get("source") is String else ""
	_source = source_text.strip_edges()
	if not supplied_source.is_empty() and not _source.contains(supplied_source):
		_source = supplied_source if _source.is_empty() else _source + " · " + supplied_source
	if _source.is_empty():
		_source = "未提供"
	_state_label = str(weather.get("weather_state", "")).strip_edges() if weather.get("weather_state") is String else ""
	_calendar=str(weather.get("local_datetime",""))
	if not _calendar.is_empty():_calendar+=" · UTC%+.2f h"%float(weather.get("utc_offset_hours",0.0))
	var day: Variant = null
	var day_basis := "unknown"
	if _values.has("solar_altitude_deg"):
		day = _values.solar_altitude_deg > 0.0
		day_basis = "solar_altitude_deg"
	elif weather.get("is_day") is bool:
		day = weather.is_day
		day_basis = "explicit_is_day"
	var icon := _classify(day)
	var weights := _transition_weights(icon)
	var irradiance: float = _values.get("irradiance_wm2", 0.0)
	var wind: float = _values.get("wind_speed_mps", 0.0)
	var stroke_count := 0 if wind <= 0.0 else (1 if wind < 4.0 else (2 if wind < 9.0 else 3))
	_display = {
		"icon": icon,
		"icon_weights": weights,
		"solar_intensity": clampf(irradiance / 1000.0, 0.0, 1.0),
		"wind_strokes": stroke_count,
		"animation_phase": fposmod(_time_s / 9.0, 1.0),
		"cloud_phase": fposmod(_time_s / 11.0, 1.0),
		"rotation_phase": fposmod(_time_s / 45.0, 1.0),
		"rain_phase": fposmod(_time_s / 1.7, 1.0),
		"star_phase": fposmod(_time_s / 5.0, 1.0),
		"values": _values.duplicate(),
		"time_s": _time_s if _time_valid else null,
		"source": _source,
		"weather_state": _state_label,
		"cloud_cover": _values.get("cloud_cover", "not_modeled"),
		"rainfall": _values.get("precipitation_mm_h", "not_modeled"),
		"is_day": day,
		"day_basis": day_basis,
		"orb_center": CENTER,
		"transition_seconds": TRANSITION_SECONDS
	}
	_has_sample = true
	tooltip_text = _tooltip()
	queue_redraw()

func _classify(day: Variant) -> String:
	var suffix := "" if day == null else ("_day" if day else "_night")
	if _values.get("precipitation_mm_h", 0.0) > 0.0:
		return "rain" + suffix
	if not _values.has("cloud_cover"):
		return "resource" if not _values.is_empty() else "unknown"
	var cloud: float = _values.cloud_cover
	return ("clear" if cloud < 0.2 else ("partly_cloudy" if cloud < 0.75 else "cloudy")) + suffix

## State changes cross-fade on simulation time, not process delta. Keep a small
## event history so scrubbing/replaying a recorded transition yields the same
## image. Only state changes are recorded; ordinary 60 Hz samples add no events.
func _transition_weights(target: String) -> Dictionary:
	if not _has_sample or _transitions.is_empty():
		_transitions = [{"time": _time_s, "from": {target: 1.0}, "target": target}]
		return {target: 1.0}
	var index := -1
	for i in range(_transitions.size()):
		if float(_transitions[i].time) <= _time_s:
			index = i
		else:
			break
	if index < 0:
		# A seek before the retained history has no known preceding weather.
		_transitions.push_front({"time": _time_s, "from": {target: 1.0}, "target": target})
		return {target: 1.0}
	var event := _transitions[index]
	if event.target != target:
		var previous := _weights_at(event, _time_s)
		_transitions.resize(index + 1)
		event = {"time": _time_s, "from": previous, "target": target}
		_transitions.append(event)
		if _transitions.size() > MAX_TRANSITIONS:
			_transitions.pop_front()
	return _weights_at(event, _time_s)

func _weights_at(event: Dictionary, time_s: float) -> Dictionary:
	var amount := clampf((time_s - float(event.time)) / TRANSITION_SECONDS, 0.0, 1.0)
	amount = amount * amount * (3.0 - 2.0 * amount)
	var result: Dictionary = {}
	for key in event.from:
		var weight := float(event.from[key]) * (1.0 - amount)
		if weight > 0.00001:
			result[key] = weight
	result[event.target] = float(result.get(event.target, 0.0)) + amount
	return result

## Explicit scene edits/load/seek must immediately show the new source, even while paused.
func reset_transition() -> void:
	_has_sample=false
	_transitions.clear()

## A copied snapshot makes deterministic rendering straightforward to verify.
func get_display_state() -> Dictionary:
	return _display.duplicate(true)

func get_mount_geometry() -> Dictionary:
	var scale_factor := minf(size.x, size.y) / ORB_SIZE
	var offset := (size - Vector2.ONE * ORB_SIZE * scale_factor) * 0.5
	return {"left": offset + Vector2(-27, mount_seam_y) * scale_factor,
		"right": offset + Vector2(103, mount_seam_y) * scale_factor,
		"bottom": offset + Vector2(38, 79.5) * scale_factor,
		"center": offset + CENTER * scale_factor,
		"fill": mount_fill, "border": mount_border}

## Transparent corners and the decorative shoulders pass map input through.
func _has_point(point: Vector2) -> bool:
	return point.distance_to(size * 0.5) <= minf(size.x, size.y) * 0.5 - 1.0

func _valid_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _set_hovered(value: bool) -> void:
	_hovered = value
	queue_redraw()

func _measurement(field: String, precision: int, unit: String) -> String:
	if not _values.has(field):
		return "未提供（未知）"
	return ("%." + str(precision) + "f %s") % [_values[field], unit]

func _relative_time() -> String:
	if not _time_valid:
		return "未提供（未知）"
	var seconds := int(absf(_time_s))
	return "%s%02d:%02d:%02d（%.1f s）" % [
		"−" if _time_s < 0.0 else "+", seconds / 3600,
		(seconds % 3600) / 60, seconds % 60, _time_s]

func _tooltip() -> String:
	var details: Array[String] = [TITLE,
		"风速：" + _measurement("wind_speed_mps", 2, "m/s"),
		"面上等效辐照 POA：" + _measurement("irradiance_wm2", 1, "W/m²"),
		"气温：" + _measurement("air_temp_c", 1, "°C"),
		"云量：" + ("%.0f%%（显式数据）" % (_values.cloud_cover * 100.0) if _values.has("cloud_cover") else "未提供（未知）"),
		"降水强度：" + _measurement("precipitation_mm_h", 2, "mm/h"),
		"太阳高度：" + _measurement("solar_altitude_deg", 1, "°"),
		"日夜依据：" + ("太阳高度" if _display.day_basis == "solar_altitude_deg" else ("显式 is_day 字段" if _display.day_basis == "explicit_is_day" else "未提供（未知）")),
		"相对模拟时间：" + _relative_time(),
		"来源：" + _source]
	if not _calendar.is_empty():details.append("本地模拟日历："+_calendar)
	if not _state_label.is_empty():
		details.append("源状态标记：" + _state_label)
	details.append_array(["", "合成地图；不代表真实地理位置的天气。", "这是全局背景值；设备专属数据可能不同。",
		"缺云雨不推断晴、多云或降雨；低辐照不推断夜间。"])
	if not _values.has("cloud_cover"):
		details.append("当前显示能源资源图标，未声明天空状况。")
	return "\n".join(details)

func _make_custom_tooltip(for_text: String) -> Object:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("f6f5e9")
	style.border_color = Color("94a18a")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 13
	style.shadow_color = Color(0.03, 0.08, 0.05, 0.22)
	style.shadow_size = 6
	panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(column)
	var heading := Label.new()
	heading.text = TITLE
	heading.add_theme_font_override("font", get_theme_default_font())
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", Color("254e3b"))
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)
	var detail := Label.new()
	detail.text = for_text.trim_prefix(TITLE + "\n")
	detail.add_theme_font_override("font", get_theme_default_font())
	detail.add_theme_font_size_override("font_size", 13)
	detail.add_theme_color_override("font_color", Color("435b4b"))
	detail.custom_minimum_size.x = 360
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(detail)
	return panel

func _mount_outline() -> PackedVector2Array:
	var points := PackedVector2Array()
	var left := Vector2(-27, mount_seam_y)
	var right := Vector2(103, mount_seam_y)
	var first := CENTER + Vector2(cos(2.48), sin(2.48)) * 41.5
	var last := CENTER + Vector2(cos(PI - 2.48), sin(PI - 2.48)) * 41.5
	var incoming := Vector2(sin(2.48), -cos(2.48))
	var outgoing := Vector2(sin(PI - 2.48), -cos(PI - 2.48))
	for i in range(17):
		points.append(left.bezier_interpolate(left + Vector2(18, 0), first - incoming * 10, first, float(i) / 16.0))
	for i in range(1, 49):
		var angle := lerpf(2.48, PI - 2.48, float(i) / 48.0)
		points.append(CENTER + Vector2(cos(angle), sin(angle)) * 41.5)
	for i in range(1, 17):
		points.append(last.bezier_interpolate(last + outgoing * 10, right - Vector2(18, 0), right, float(i) / 16.0))
	return points

func _draw_mount() -> void:
	var edge := _mount_outline()
	# Wide, low-alpha strokes form one soft shared shadow under the curved edge.
	for layer in range(7, 0, -1):
		var shadow := PackedVector2Array()
		for point in edge:
			shadow.append(point + Vector2(0, 1.5))
		draw_polyline(shadow, Color(0.04, 0.13, 0.10, 0.012), float(layer) * 1.8, true)
	var fill := edge.duplicate()
	fill.append(Vector2(103, mount_seam_y))
	fill.append(Vector2(-27, mount_seam_y))
	draw_colored_polygon(fill, mount_fill)
	draw_polyline(edge, Color("8c9f85"), 2.3, true)
	draw_polyline(edge, mount_border, 1.1, true)

func _draw() -> void:
	var scale_factor := minf(size.x, size.y) / ORB_SIZE
	draw_set_transform((size - Vector2.ONE * ORB_SIZE * scale_factor) * 0.5, 0.0, Vector2.ONE * scale_factor)
	if mount_enabled:
		_draw_mount()
	# Recessed glass has a quiet mineral rim; the shared mount owns the shadow.
	draw_circle(CENTER, 37.0, Color("91a58b"), true, -1.0, true)
	draw_circle(CENTER, 35.7, Color("e5deaf"), true, -1.0, true)
	draw_circle(CENTER, 34.3, Color("617a60"), true, -1.0, true)
	var glass := Color.BLACK
	glass.a = 1.0
	var mixed := Vector3.ZERO
	for state in _display.get("icon_weights", {}):
		var palette := _palette(state)
		mixed += Vector3(palette.r, palette.g, palette.b) * float(_display.icon_weights[state])
	glass = Color(mixed.x, mixed.y, mixed.z, 1.0)
	draw_circle(CENTER, FACE_RADIUS, glass, true, -1.0, true)
	for layer in range(16):
		var fraction := float(layer) / 15.0
		draw_circle(CENTER + Vector2(-3.0, -5.5) * fraction, lerpf(31.5, 5.0, fraction), glass.lightened(fraction * 0.16), true, -1.0, true)
	for state in _display.get("icon_weights", {}):
		_layer_alpha = float(_display.icon_weights[state])
		if _layer_alpha > 0.001:
			_draw_icon(state)
	_layer_alpha = 1.0
	_draw_wind(CENTER + Vector2(0, 19))
	draw_arc(CENTER, 35.1, -2.92, -0.4, 48, Color(1.0, 0.98, 0.80, 0.78), 1.1, true)
	draw_arc(CENTER, 33.2, 0.1, 2.65, 42, Color(0.05, 0.16, 0.13, 0.7), 1.1, true)
	draw_arc(CENTER + Vector2(-1, -1), 28.8, -2.7, -1.45, 24, Color(0.92, 1.0, 0.9, 0.13), 1.7, true)
	if _hovered:
		draw_arc(CENTER, 36.2, 0.0, TAU, 96, Color(1.0, 0.92, 0.64, 0.85), 1.2, true)
	draw_set_transform(Vector2.ZERO)

func _palette(state: String) -> Color:
	if state.ends_with("_night"):
		return Color("263c56")
	if state.begins_with("rain"):
		return Color("3c6269")
	if state.begins_with("cloudy"):
		return Color("54736c")
	if state.begins_with("clear") or state.begins_with("partly"):
		return Color("346965")
	return Color("244d40")

func _ink(hex: String, alpha: float = 1.0) -> Color:
	var color := Color(hex)
	color.a *= _layer_alpha * alpha
	return color

func _draw_icon(state: String) -> void:
	var center := CENTER + Vector2(0, -3)
	if state == "unknown":
		_draw_unknown(center)
		return
	if state == "resource":
		_draw_resource(center)
		return
	var night := state.ends_with("_night")
	var day := state.ends_with("_day")
	if state.begins_with("clear"):
		if day:
			_draw_sun(center, 1.0)
		elif night:
			_draw_moon(center)
		else:
			_draw_clear_unknown(center)
	elif state.begins_with("partly"):
		if day:
			_draw_sun(center + Vector2(-7, -6), 0.72)
		elif night:
			_draw_moon(center + Vector2(-7, -7), 0.75)
		_draw_cloud(center + Vector2(4, 7), 0.9, false)
	elif state.begins_with("cloudy"):
		if night:
			_draw_stars(center)
		_draw_cloud(center + Vector2(-5, -7), 0.76, true)
		_draw_cloud(center + Vector2(2, 4), 1.07, false)
	else:
		if night:
			_draw_stars(center)
		if _values.has("cloud_cover"):
			_draw_cloud(center + Vector2(0, -6), 1.05, true)
		_draw_rain(center + Vector2(0, 1))

func _draw_sun(center: Vector2, scale_value: float) -> void:
	var phase: float = _display.animation_phase * TAU
	var pulse := 0.55 * sin(phase)
	for layer in range(4):
		draw_circle(center, (16.0 - layer * 1.7 + pulse) * scale_value, _ink("ffcf73", 0.025))
	for ray in range(10):
		var angle: float = float(ray) * TAU / 10.0 + _display.rotation_phase * TAU
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(center + direction * 12.0 * scale_value, center + direction * (15.0 + pulse) * scale_value, _ink("f7d78d"), 1.7, true)
	draw_circle(center, 9.1 * scale_value, _ink("d49a53"), true, -1.0, true)
	draw_circle(center + Vector2(-0.4, -0.7), 8.1 * scale_value, _ink("f6cb76"), true, -1.0, true)
	draw_circle(center + Vector2(-2, -2) * scale_value, 5.8 * scale_value, _ink("ffe3a0"), true, -1.0, true)

func _draw_moon(center: Vector2, scale_value: float = 1.0) -> void:
	_draw_stars(center)
	var crescent := PackedVector2Array()
	for i in range(33):
		var angle := lerpf(-PI * 0.6, PI * 0.6, float(i) / 32.0)
		crescent.append(center + Vector2(-cos(angle) * 11.5, sin(angle) * 11.5) * scale_value)
	var top := Vector2(-cos(-PI * 0.6) * 11.5, sin(-PI * 0.6) * 11.5)
	var bottom := Vector2(top.x, -top.y)
	for i in range(1, 32):
		var amount := float(i) / 32.0
		var point := bottom.bezier_interpolate(Vector2(-10, 7), Vector2(-10, -7), top, amount)
		crescent.append(center + point * scale_value)
	draw_colored_polygon(crescent, _ink("dce8cf"))
	draw_arc(center, 14 * scale_value, PI * 0.65, PI * 1.35, 24, _ink("afcbd6", 0.19 + 0.08 * sin(_display.star_phase * TAU)), 1.1, true)

func _draw_stars(center: Vector2) -> void:
	var stars := [Vector2(15, -10), Vector2(19, 2), Vector2(-15, -16)]
	for i in range(stars.size()):
		var brightness := 0.45 + 0.4 * sin(_display.star_phase * TAU + float(i) * 2.1)
		var point: Vector2 = center + stars[i]
		point = CENTER + (point - CENTER).limit_length(26.5)
		draw_line(point + Vector2(-1.6, 0), point + Vector2(1.6, 0), _ink("e2e9c9", brightness), 1.0, true)
		draw_line(point + Vector2(0, -1.6), point + Vector2(0, 1.6), _ink("e2e9c9", brightness), 1.0, true)

func _draw_cloud(center: Vector2, scale_value: float, rear: bool) -> void:
	var drift := sin(_display.cloud_phase * TAU + (1.8 if rear else 0.0)) * (2.0 if rear else 2.7)
	var origin := center + Vector2(drift, sin(_display.cloud_phase * TAU * 2.0) * 0.55)
	var shade := _ink("a7c2bd" if rear else "d7e4ce")
	var light := _ink("c0d1c2" if rear else "edf0d7")
	draw_circle(origin + Vector2(-9, 0) * scale_value, 6.0 * scale_value, shade, true, -1.0, true)
	draw_circle(origin + Vector2(-2, -4) * scale_value, 8.0 * scale_value, shade, true, -1.0, true)
	draw_circle(origin + Vector2(7, -1) * scale_value, 6.5 * scale_value, shade, true, -1.0, true)
	draw_style_box(_cloud_base(shade, scale_value), Rect2(origin + Vector2(-10, -1) * scale_value, Vector2(23, 8) * scale_value))
	draw_arc(origin + Vector2(-2, -4) * scale_value, 7.1 * scale_value, -2.8, -0.55, 20, light, 1.1, true)

func _cloud_base(color: Color, scale_value: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(4.0 * scale_value))
	return style

func _draw_rain(center: Vector2) -> void:
	# Drops follow fixed lanes, wrap deterministically and remain inside glass.
	var rate: float = _values.get("precipitation_mm_h", 0.0)
	var count := 4 if rate < 2.0 else (6 if rate < 10.0 else 8)
	for drop in range(count):
		var phase := fposmod(float(_display.rain_phase) + float(drop) * 0.173, 1.0)
		var x := -14.0 + float(drop) * 28.0 / maxf(float(count - 1), 1.0)
		var y := -2.0 + phase * 19.0
		var opacity := sin(phase * PI) * 0.95
		draw_line(center + Vector2(x + 2.0 - phase * 4.0, y), center + Vector2(x + 0.2 - phase * 4.0, y + 4.4), _ink("a6e0e1", opacity), 1.7, true)
	if not _values.has("cloud_cover"):
		# Measured rain does not invent an unmeasured cloud amount.
		draw_arc(center + Vector2(0, -7), 8, PI * 1.05, PI * 1.95, 24, _ink("c9ded5", 0.65), 1.3, true)

func _draw_clear_unknown(center: Vector2) -> void:
	# Cloud-free was supplied, but no sun/moon without a day/night basis.
	draw_arc(center, 12, -0.2 + _display.rotation_phase * TAU, 4.8 + _display.rotation_phase * TAU, 48, _ink("d7e4bb"), 1.8, true)
	draw_arc(center, 6, 1.2 - _display.rotation_phase * TAU, 4.1 - _display.rotation_phase * TAU, 24, _ink("b4d0b5", 0.8), 1.3, true)

func _draw_resource(center: Vector2) -> void:
	if _values.has("irradiance_wm2"):
		# A photovoltaic grid means irradiance, never sunny weather or daylight.
		var panel := PackedVector2Array([center + Vector2(-13, -8), center + Vector2(10, -8), center + Vector2(14, 9), center + Vector2(-16, 9)])
		draw_colored_polygon(panel, _ink("608b82", 0.55))
		panel.append(panel[0])
		draw_polyline(panel, _ink("e1dba4"), 1.4, true)
		for column in range(1, 4):
			var fraction := float(column) / 4.0
			draw_line(center + Vector2(lerpf(-13, 10, fraction), -8), center + Vector2(lerpf(-16, 14, fraction), 9), _ink("a8c7ad", 0.85), 1.0, true)
		draw_line(center + Vector2(-14.5, 0.5), center + Vector2(12, 0.5), _ink("a8c7ad", 0.85), 1.0, true)
		var scan := sin(_display.animation_phase * TAU) * 6.8
		draw_line(center + Vector2(-11.0, scan), center + Vector2(9, scan), _ink("f3e3a2", 0.32 + _display.solar_intensity * 0.32), 1.5, true)
		draw_line(center + Vector2(0, 10), center + Vector2(0, 15), _ink("c7d2ae"), 1.4, true)
		draw_line(center + Vector2(-6, 15), center + Vector2(6, 15), _ink("c7d2ae"), 1.4, true)
	elif _values.has("wind_speed_mps"):
		_draw_wind(center + Vector2(0, -2), true)
	elif _values.has("air_temp_c"):
		draw_line(center + Vector2(0, -12), center + Vector2(0, 7), _ink("d8ddb5"), 4.0, true)
		draw_circle(center + Vector2(0, 9), 5.0, _ink("e0bd7b"), true, -1.0, true)
		var pulse := sin(_display.animation_phase * TAU) * 3.0
		draw_line(center + Vector2(0, 6), center + Vector2(0, -5 + pulse), _ink("e0bd7b"), 2.0, true)
	else:
		_draw_unknown(center)

func _draw_unknown(center: Vector2) -> void:
	var phase: float = _display.animation_phase * TAU
	for segment in range(8):
		var angle := float(segment) * TAU / 8.0
		var alpha := 0.32 + 0.35 * (0.5 + 0.5 * sin(phase - angle))
		draw_arc(center, 12, angle, angle + 0.43, 8, _ink("c0d6b5", alpha), 1.7, true)
	for dot in range(3):
		draw_circle(center + Vector2((dot - 1) * 5, 0), 1.3, _ink("dce3c6", 0.5 + 0.3 * sin(phase + dot)), true, -1.0, true)

func _draw_wind(center: Vector2, primary: bool = false) -> void:
	var count := int(_display.get("wind_strokes", 0))
	if primary and count == 0:
		# A measured calm resource still has an animated instrument, not a gust.
		_draw_unknown(center)
		return
	var phase: float = _display.animation_phase * TAU
	for stroke in range(count):
		var drift := sin(phase + float(stroke) * 0.8) * 3.0
		var y := float(stroke) * 4.0 - 3.0
		var left := -15.0 + float(stroke % 2) * 4.0 + drift
		var right := 10.0 - float(stroke) * 2.0 + drift
		var color := _ink("c5ddbb" if stroke == 0 else "94bdad", 0.7 + 0.2 * sin(phase + stroke))
		draw_line(center + Vector2(left, y), center + Vector2(right, y), color, 1.45, true)
		if stroke == 0:
			draw_arc(center + Vector2(right, y - 2.3), 2.3, -PI * 0.85, PI * 0.5, 18, color, 1.45, true)
