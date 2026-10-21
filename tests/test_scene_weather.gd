extends SceneTree
## Deterministic headless component checks; GUI/performance remains a separate run.
const SceneWeather = preload("res://scripts/scene_weather.gd")
var checks := 0
var failures: Array[String] = []

class TerrainStub:
	extends Node3D
	func height_at(x: float, z: float) -> float:
		return 2.0 + x * 0.01 + z * 0.005

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("SCENE_WEATHER: " + description)

func _initialize() -> void:
	call_deferred("_run")

func _fixture() -> Dictionary:
	var host := TerrainStub.new()
	root.add_child(host)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("c7cfcd")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("d4dfdf")
	environment.ambient_light_energy = 0.38
	world.environment = environment
	host.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-43, -33, 0)
	sun.light_color = Color("fff2d9")
	sun.light_energy = 0.82
	sun.shadow_enabled = true
	host.add_child(sun)
	var component = SceneWeather.new()
	host.add_child(component)
	component.setup(host)
	return {"host": host, "world": world, "environment": environment, "sun": sun, "weather": component,
		"sun_transform": sun.transform, "sun_energy": sun.light_energy, "sun_color": sun.light_color}

func _restored(fixture: Dictionary, message: String) -> void:
	check(fixture.world.environment == fixture.environment, message + ": original Environment object")
	check(fixture.environment.background_color == Color("c7cfcd") and fixture.environment.ambient_light_color == Color("d4dfdf") and is_equal_approx(fixture.environment.ambient_light_energy, 0.38), message + ": original environment fields")
	check(fixture.sun.transform == fixture.sun_transform and fixture.sun.light_color == fixture.sun_color and fixture.sun.light_energy == fixture.sun_energy and fixture.sun.shadow_enabled, message + ": exact original light")

func _run() -> void:
	var f := _fixture()
	var weather = f.weather
	check(not weather.is_processing() and not weather.is_physics_processing(), "no independent animation callbacks")
	check(f.host.get_node("SceneWeatherEffects").get_child_count() == 6, "exactly six reusable mesh strokes")
	_restored(f, "setup without sample")
	check(not f.host.get_node("SceneWeatherEffects").visible, "setup does not enable effects")
	var noon := {"valid": true, "is_day": true, "solar_altitude_deg": 65.0, "solar_azimuth_deg": 180.0,
		"wind_speed_mps": 10.0, "irradiance_wm2": 830.0, "air_temp_c": 22.0, "cloud_cover": 0.1,
		"precipitation_mm_h": 0.0, "source": "deterministic test", "field_sources": {"cloud_cover": "test"}}
	var original := noon.duplicate(true)
	weather.set_weather(noon, 100.5, true)
	var state: Dictionary = weather.get_display_state()
	check(state.active and state.valid and state.lighting_applied, "valid enabled snapshot applies lighting")
	check(state.source_snapshot == noon, "exact input snapshot available for GUI comparison")
	check(state.values.solar_altitude_deg == 65.0 and state.is_day and state.day_basis == "solar_altitude_deg", "solar altitude drives day classification")
	check(f.world.environment != f.environment and f.environment.background_color == Color("c7cfcd"), "lighting uses private duplicate and never modifies original resource")
	check(state.sun_energy > 0.6 and not state.shadow_enabled, "daytime direct illumination without shadow maps")
	check((state.sun_rotation_degrees as Vector3).is_equal_approx(Vector3(-65, 0, 0)), "south solar bearing gives expected light direction")
	check(state.wind_stroke_count == 6 and state.wind_stroke_limit == 6, "high wind obeys six-stroke budget")
	check(state.wind_direction_basis == "illustrative_positive_x_not_measured", "wind heading disclosed as schematic")
	check(state.rainfall == 0.0 and not state.rain_effect, "no rain effects invented")
	for stroke in f.host.get_node("SceneWeatherEffects").get_children():
		check(stroke is MeshInstance3D and stroke.mesh is BoxMesh, "wind uses basic meshes")
		check(stroke.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and stroke.material_override.albedo_color.a <= 0.270001, "strokes are low-alpha and cast no shadows")
		check(stroke.position.y > f.host.height_at(stroke.position.x, stroke.position.z), "strokes follow terrain height")
		check(absf(stroke.position.z) >= 54.0, "strokes stay in outer map lanes")
	check(noon == original, "component leaves source snapshot unchanged")
	weather.set_weather(noon, 100.5, true)
	check(weather.get_display_state() == state, "same snapshot/time reproduces all display values")
	await create_timer(0.03).timeout
	await process_frame
	check(weather.get_display_state() == state, "pause freezes state across wall-clock frames")
	for index in range(6):
		check(f.host.get_node("SceneWeatherEffects").get_child(index).position == state.wind_positions[index], "pause freezes actual stroke transform")
	weather.set_weather(noon, 101.5, true)
	check(weather.get_display_state().wind_positions != state.wind_positions, "only simulation time advances strokes")
	weather.set_weather(noon, 100.5, true)
	check(weather.get_display_state() == state, "rewind reconstructs exact scene state")
	var replay := _fixture()
	replay.weather.set_weather(noon, 100.5, true)
	check(replay.weather.get_display_state() == state, "independent component replay has identical state")
	replay.host.free()
	var copy: Dictionary = weather.get_display_state()
	copy.source_snapshot.field_sources.cloud_cover = "mutated"
	copy.values.wind_speed_mps = 999.0
	copy.wind_positions[0] = Vector3.ZERO
	check(weather.get_display_state() == state, "returned state deeply detached")
	noon.field_sources.cloud_cover = "caller changed later"
	check(weather.get_display_state() == state, "later caller edits cannot mutate source snapshot")
	noon = original.duplicate(true)
	weather.setup(f.host)
	check(weather.get_display_state() == state and f.host.get_node("SceneWeatherEffects").get_child_count() == 6, "repeated setup does not recapture active light or add meshes")
	var overcast := noon.duplicate(true)
	overcast.cloud_cover = 1.0
	weather.set_weather(overcast, 100.5, true)
	check(weather.get_display_state().sun_energy < state.sun_energy * 0.5, "only explicit cloud increases overcast soft dimming")
	var night := noon.duplicate(true)
	night.solar_altitude_deg = -30.0
	night.is_day = true
	night.irradiance_wm2 = 1500.0
	weather.set_weather(night, 100.5, true)
	var night_state: Dictionary = weather.get_display_state()
	check(not night_state.is_day and night_state.sun_energy == 0.0, "altitude overrides contradictory daylight and irradiance")
	check(night_state.background_color != state.background_color and night_state.ambient_energy >= 0.27, "night has cool readable ambient fill")
	check(night_state.night_fill_basis == "artistic_readability_not_irradiance", "night fill explicitly visual only")
	for azimuth in [0.0, 90.0, 180.0, 270.0]:
		var cardinal := noon.duplicate(true)
		cardinal.solar_altitude_deg = 30.0
		cardinal.solar_azimuth_deg = azimuth
		weather.set_weather(cardinal, 0.0, true)
		var expected_to_sun := Vector3(sin(deg_to_rad(azimuth)) * cos(deg_to_rad(30)), sin(deg_to_rad(30)), -cos(deg_to_rad(azimuth)) * cos(deg_to_rad(30)))
		check(f.sun.basis.z.is_equal_approx(expected_to_sun), "solar cardinal direction, north -Z: %.0f" % azimuth)
	for irradiance in [0.0, 30.0, 1500.0]:
		weather.set_weather({"valid": true, "irradiance_wm2": irradiance, "air_temp_c": -8.0}, 10.0, true)
		check(weather.get_display_state().is_day == null and not weather.get_display_state().lighting_applied, "irradiance never fabricates day/night")
		check(weather.get_display_state().cloud_cover == "not_modeled" and weather.get_display_state().rainfall == "not_modeled", "unknown cloud/rain remain unknown")
		_restored(f, "unknown sky")
	for is_day in [true, false]:
		weather.set_weather({"valid": true, "is_day": is_day}, 10.0, true)
		check(weather.get_display_state().is_day == is_day and weather.get_display_state().day_basis == "explicit_is_day", "explicit boolean is_day fallback")
		check(f.sun.transform == f.sun_transform, "is_day alone does not invent sun direction")
	for wind_speed in [0.0, 1.0, 5.0, 40.0]:
		weather.set_weather({"wind_speed_mps": wind_speed}, 10.0, true)
		check(weather.get_display_state().wind_stroke_count == {0.0: 0, 1.0: 2, 5.0: 4, 40.0: 6}[wind_speed], "wind quantity uses fixed cap")
		if wind_speed == 0.0:
			var calm: Dictionary = weather.get_display_state()
			weather.set_weather({"wind_speed_mps": 0.0}, 500.0, true)
			check(not f.host.get_node("SceneWeatherEffects").visible and weather.get_display_state().wind_positions == calm.wind_positions, "zero wind is hidden and motionless")
	weather.set_weather({"valid": false, "solar_altitude_deg": 65.0, "wind_speed_mps": 12.0}, 10.0, true)
	check(not weather.get_display_state().active and weather.get_display_state().wind_stroke_count == 0, "invalid snapshot disables effects")
	_restored(f, "invalid snapshot")
	weather.set_weather({"solar_altitude_deg": 91.0, "solar_azimuth_deg": -1.0, "wind_speed_mps": -1.0, "irradiance_wm2": NAN, "air_temp_c": INF, "cloud_cover": 1.1, "precipitation_mm_h": -1.0, "is_day": 1}, NAN, true)
	check(weather.get_display_state().values.is_empty() and weather.get_display_state().is_day == null and weather.get_display_state().time_s == null, "invalid numbers and boolean coercions rejected")
	_restored(f, "invalid measurements")
	weather.set_weather({"wind_speed_mps": "9.0", "cloud_cover": false, "precipitation_mm_h": true}, 0.0, true)
	check(weather.get_display_state().values.is_empty(), "no string/bool numeric coercion")
	weather.set_weather(noon, NAN, true)
	check(weather.get_display_state().wind_stroke_count == 0, "unknown time cannot animate wind")
	weather.set_weather(noon, 1.0e300, true)
	for position in weather.get_display_state().wind_positions:
		check(position.is_finite(), "very large finite time keeps transforms finite")
	weather.set_weather(noon, 100.5, false)
	check(not weather.get_display_state().active and not f.host.get_node("SceneWeatherEffects").visible, "disabled hides all added effects")
	_restored(f, "disabled")
	weather.set_weather(noon, 100.5, true)
	check(weather.get_display_state() == state, "re-enabling reproduces same appearance")
	weather.free()
	await process_frame
	_restored(f, "component removed")
	check(not f.host.has_node("SceneWeatherEffects"), "component removal cleans up extra geometry")
	f.host.free()
	await _test_rebinding()
	var source := FileAccess.get_file_as_string("res://scripts/scene_weather.gd")
	for prohibited in ["func _process(", "func _physics_process(", "Time.get_", "randf(", "randi(", "ShaderMaterial.new(", "GPUParticles3D.new(", "CPUParticles3D.new("]:
		check(not source.contains(prohibited), "no wall-clock/random/heavy effects: " + prohibited)
	print("SCENE_WEATHER_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _test_rebinding() -> void:
	var first := _fixture()
	var second := _fixture()
	second.weather.free()
	await process_frame
	first.weather.set_weather({"solar_altitude_deg": -25.0, "wind_speed_mps": 5.0}, -15.0, true)
	first.weather.setup(second.host)
	_restored(first, "rebind restores previous host")
	check(not first.host.has_node("SceneWeatherEffects") and second.host.has_node("SceneWeatherEffects"), "rebind moves geometry without duplicates")
	check(first.weather.get_display_state().time_s == -15.0 and first.weather.get_display_state().active, "rebind reapplies current deterministic sample")
	first.weather.setup(null)
	_restored(second, "null setup releases host")
	check(not first.weather.get_display_state().active, "no host is safe")
	var empty := Node3D.new()
	root.add_child(empty)
	first.weather.setup(empty)
	check(first.weather.get_display_state().ambient_energy == null and first.weather.get_display_state().sun_energy == null, "host without light/environment is safe")
	check(empty.get_child_count() == 1, "missing lighting does not create competing light or environment")
	first.host.free()
	second.host.free()
	empty.free()
