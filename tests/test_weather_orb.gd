extends SceneTree
## Standalone presentation tests: only supplied weather and simulation time.
const WeatherOrb = preload("res://scripts/weather_orb.gd")
var checks := 0
var failures: Array[String] = []

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("WEATHER_ORB: " + description)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var orb = WeatherOrb.new()
	root.add_child(orb)
	await process_frame
	check(orb.custom_minimum_size == Vector2(76, 76), "compact 76 px footprint")
	check(orb.mouse_filter == Control.MOUSE_FILTER_STOP, "orb intercepts input within face")
	check(orb._has_point(Vector2(38, 38)), "center is interactive")
	check(not orb._has_point(Vector2.ZERO) and not orb._has_point(Vector2(75, 75)), "transparent corners pass input")
	check(not orb._has_point(Vector2(-20, 54)), "decorative mount never intercepts map input")
	check(not orb.is_processing(), "no independent frame or wall-clock animation")
	check(orb.get_display_state().icon == "unknown", "missing fields do not fabricate weather")
	for field in ["风速", "面上等效辐照 POA", "气温", "云量", "降水强度", "太阳高度"]:
		check(orb.tooltip_text.contains(field + "：未提供（未知）"), "missing field disclosed: " + field)
	var weather := {"wind_speed_mps": 7.25, "irradiance_wm2": 620.0, "air_temp_c": 18.4}
	var original := weather.duplicate(true)
	orb.set_weather(weather, 3661.0, "示例全局时序 · 第 2 行")
	var snapshot: Dictionary = orb.get_display_state()
	var tooltip: String = orb.tooltip_text
	check(snapshot.icon == "resource" and is_equal_approx(snapshot.solar_intensity, 0.62), "legacy irradiance uses resource icon, not a sky claim")
	check(snapshot.wind_strokes == 2, "wind stroke count follows supplied wind")
	check(snapshot.is_day == null and snapshot.day_basis == "unknown", "irradiance cannot establish day or night")
	for expected in ["全局背景天气", "7.25 m/s", "620.0 W/m²", "18.4 °C", "+01:01:01", "3661.0 s", "示例全局时序 · 第 2 行"]:
		check(tooltip.contains(expected), "hover includes exact context: " + expected)
	check(tooltip.contains("合成地图") and tooltip.contains("不代表真实地理位置"), "synthetic non-geographic scope explicit")
	check(tooltip.contains("设备专属数据可能不同"), "device overrides distinguished")
	check(snapshot.cloud_cover is String and snapshot.rainfall is String, "legacy input keeps cloud and precipitation unknown")
	check(weather == original, "caller values unchanged")
	orb.set_weather(weather, 3661.0, "示例全局时序 · 第 2 行")
	check(orb.get_display_state() == snapshot and orb.tooltip_text == tooltip, "same sample and time are deterministic")
	await create_timer(0.03).timeout
	await process_frame
	check(orb.get_display_state() == snapshot, "paused simulation freezes across wall-clock time")
	orb.set_weather(weather, 3662.0, "示例全局时序 · 第 2 行")
	check(orb.get_display_state().animation_phase != snapshot.animation_phase, "animation advances with simulation time")
	check(orb.position == Vector2.ZERO and orb.get_display_state().orb_center == Vector2(38, 38), "whole orb position never animates")
	orb.set_weather(weather, 3661.0, "示例全局时序 · 第 2 行")
	check(orb.get_display_state() == snapshot, "rewind reproduces exact resource display")
	var detached: Dictionary = orb.get_display_state()
	detached.values.air_temp_c = 99.0
	detached.icon_weights.resource = 0.0
	check(orb.get_display_state().values.air_temp_c == 18.4 and orb.get_display_state().icon_weights.resource == 1.0, "snapshots deeply detached")
	weather.air_temp_c = 99.0
	check(orb.get_display_state().values.air_temp_c == 18.4, "later caller edits cannot mutate live display")
	for irradiance in [0.0, 30.0, 119.0, 120.0, 1500.0]:
		orb.set_weather({"irradiance_wm2": irradiance, "wind_speed_mps": 0.0, "air_temp_c": -8.5}, 0.0, "手动参数")
		check(orb.get_display_state().icon == "resource", "irradiance alone remains neutral: %.1f" % irradiance)
		check(orb.get_display_state().is_day == null, "no irradiance threshold infers night")
		check(orb.get_display_state().wind_strokes == 0, "measured calm has no wind strokes")
	check(orb.tooltip_text.contains("-8.5 °C"), "valid negative temperature preserved")
	check(orb.tooltip_text.contains("1500.0 W/m²") and orb.get_display_state().solar_intensity == 1.0, "drawing clamp preserves measurement")
	var cases := [
		[{"cloud_cover": 0.0, "solar_altitude_deg": 40.0}, "clear_day"],
		[{"cloud_cover": 0.0, "solar_altitude_deg": -12.0, "irradiance_wm2": 900.0}, "clear_night"],
		[{"cloud_cover": 0.1, "solar_altitude_deg": 0.0}, "clear_night"],
		[{"cloud_cover": 0.5, "solar_altitude_deg": 15.0}, "partly_cloudy_day"],
		[{"cloud_cover": 0.5, "solar_altitude_deg": -15.0}, "partly_cloudy_night"],
		[{"cloud_cover": 1.0, "solar_altitude_deg": 20.0}, "cloudy_day"],
		[{"cloud_cover": 1.0, "solar_altitude_deg": -20.0}, "cloudy_night"],
		[{"cloud_cover": 0.0}, "clear"],
		[{"cloud_cover": 0.4}, "partly_cloudy"],
		[{"cloud_cover": 0.8}, "cloudy"],
		[{"precipitation_mm_h": 0.1, "solar_altitude_deg": 10.0}, "rain_day"],
		[{"precipitation_mm_h": 4.0, "solar_altitude_deg": -10.0}, "rain_night"],
		[{"precipitation_mm_h": 12.0}, "rain"],
		[{"precipitation_mm_h": 0.0, "irradiance_wm2": 500.0}, "resource"],
		[{"weather_state": "rain", "irradiance_wm2": 800.0}, "resource"],
		[{"weather_state": "clear", "air_temp_c": 12.0}, "resource"],
		[{"cloud_cover": 0.0, "solar_altitude_deg": -3.0, "is_day": true}, "clear_night"],
		[{"cloud_cover": 0.0, "is_day": true}, "clear_day"],
		[{"cloud_cover": 0.0, "is_day": false}, "clear_night"]
	]
	for index in range(cases.size()):
		var sample: Dictionary = cases[index][0]
		orb.set_weather(sample, 100.0 + float(index) * 3.0, "状态测试")
		check(orb.get_display_state().icon == cases[index][1], "explicit evidence selects " + cases[index][1])
		orb.set_weather(sample, 102.0 + float(index) * 3.0, "状态测试")
		check(orb.get_display_state().icon_weights == {cases[index][1]: 1.0}, "transition settles to " + cases[index][1])
		await process_frame # Exercise all custom draw branches, including moon/rain.
	orb.set_weather({"cloud_cover": 0.7, "precipitation_mm_h": 3.5, "source": "教学气候模型", "weather_state": "教学阵雨", "solar_altitude_deg": 25.0}, 300.0, "背景数据")
	check(orb.tooltip_text.contains("70%（显式数据）") and orb.tooltip_text.contains("3.50 mm/h"), "explicit cloud and precipitation disclosed")
	check(orb.tooltip_text.contains("背景数据 · 教学气候模型") and orb.tooltip_text.contains("源状态标记：教学阵雨"), "both source channels and teaching label remain in hover")
	check(orb.get_display_state().day_basis == "solar_altitude_deg", "solar altitude basis explicit")
	orb.set_weather({"wind_speed_mps": -2.0, "irradiance_wm2": NAN, "air_temp_c": INF, "cloud_cover": 1.1, "precipitation_mm_h": -0.1, "solar_altitude_deg": 91.0}, NAN, "")
	check(orb.get_display_state().values.is_empty() and orb.get_display_state().icon == "unknown", "invalid values remain unknown")
	check(orb.get_display_state().time_s == null and orb.tooltip_text.contains("相对模拟时间：未提供（未知）"), "invalid simulation time disclosed")
	orb.set_weather({"wind_speed_mps": "7.0", "irradiance_wm2": null, "air_temp_c": false, "cloud_cover": "0.5", "precipitation_mm_h": true, "is_day": 1}, -60.0, "   ")
	check(orb.get_display_state().values.is_empty() and orb.get_display_state().is_day == null, "no silent numeric or day/night coercion")
	check(orb.tooltip_text.contains("−00:01:00") and orb.tooltip_text.contains("来源：未提供"), "negative relative time and absent source explicit")
	var custom: Object = orb._make_custom_tooltip(orb.tooltip_text)
	check(custom is PanelContainer and custom.get_child(0).get_child_count() == 2, "source/details are hover-only")
	custom.free()
	orb._set_hovered(true)
	check(orb.get_display_state().icon == "unknown", "hover never changes weather")
	var geometry: Dictionary = orb.get_mount_geometry()
	check(geometry.left == Vector2(-27, 54) and geometry.right == Vector2(103, 54) and geometry.bottom == Vector2(38, 79.5), "mount geometry matches header integration")
	var curve: PackedVector2Array = orb._mount_outline()
	check(curve[0] == geometry.left and curve[-1] == geometry.right, "groove joins both horizontal panel shoulders")
	check(absf(curve[1].y - curve[0].y) < 0.2 and absf(curve[-2].y - curve[-1].y) < 0.2, "groove endpoint tangents stay horizontal")
	orb.size = Vector2(100, 76)
	check(orb._has_point(Vector2(50, 38)) and not orb._has_point(Vector2(2, 38)), "resizing centers face and hit test")
	await _test_transitions()
	var source := FileAccess.get_file_as_string("res://scripts/weather_orb.gd")
	check(not source.contains("draw_string(") and not source.contains('var caption'), "no label text drawn above, inside or below orb")
	check(not source.contains("Time.get_") and not source.contains("randf(") and not source.contains("func _process("), "all motion is deterministic simulation-time motion")
	orb.free()
	print("WEATHER_ORB_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _test_transitions() -> void:
	var first = WeatherOrb.new()
	var replay = WeatherOrb.new()
	root.add_child(first)
	root.add_child(replay)
	var clear := {"cloud_cover": 0.0, "solar_altitude_deg": 30.0, "wind_speed_mps": 4.0}
	var cloud := {"cloud_cover": 0.9, "solar_altitude_deg": 30.0, "wind_speed_mps": 4.0}
	for orb in [first, replay]:
		orb.set_weather(clear, 0.0, "教学")
		orb.set_weather(cloud, 10.0, "教学")
	check(first.get_display_state().icon_weights == {"clear_day": 1.0, "cloudy_day": 0.0}, "state change begins at previous visual without a jump")
	first.set_weather(cloud, 10.4, "教学")
	replay.set_weather(cloud, 10.4, "教学")
	var midpoint: Dictionary = first.get_display_state()
	check(is_equal_approx(midpoint.icon_weights.clear_day, 0.5) and is_equal_approx(midpoint.icon_weights.cloudy_day, 0.5), "smooth cross-fade midpoint")
	check(midpoint == replay.get_display_state(), "independent replay gives exact transition state")
	first.set_weather(cloud, 10.4, "教学")
	await create_timer(0.03).timeout
	await process_frame
	check(first.get_display_state() == midpoint, "paused transition stays frozen")
	first.set_weather(cloud, 11.0, "教学")
	check(first.get_display_state().icon_weights == {"cloudy_day": 1.0}, "transition completes on simulation clock")
	first.set_weather(cloud, 10.4, "教学")
	check(first.get_display_state() == midpoint, "scrubbing recorded transition reconstructs exact midpoint")
	for time_s in [10.45, 10.5, 10.6, 11.0, 12.0]:
		first.set_weather(cloud, time_s, "教学")
	check(first._transitions.size() == 2, "frame updates do not grow transition history")
	check(first.position == Vector2.ZERO and replay.position == Vector2.ZERO, "cross-fades never move the orb")
	first.reset_transition();first.set_weather(clear,12.0,"更换教学情景")
	check(first.get_display_state().icon_weights=={"clear_day":1.0},"paused scene edit immediately replaces previous weather icon")
	first.free()
	replay.free()
