extends Node
## Visual-only teaching weather: no equipment, energy, save or input mutations.
## setup() captures the map's existing light/environment, including their exact
## resource and transform. Disabling or invalid input restores that baseline.
## North is -Z, east is +X. Night fill is deliberately readable artistic light,
## never irradiance. Wind strokes travel along a fixed illustrative +X heading;
## the snapshot supplies speed, not a measured wind direction.

const MAX_WIND_STROKES := 6
const WIND_SPAN := 166.0
const NUMBER_FIELDS := ["solar_altitude_deg", "solar_azimuth_deg", "wind_speed_mps", "irradiance_wm2", "air_temp_c", "cloud_cover", "precipitation_mm_h"]
const NIGHT_BACKGROUND := Color("263748")
const NIGHT_AMBIENT := Color("a5bbd0")

var _host: Node3D
var _environment_node: WorldEnvironment
var _original_environment: Environment
var _weather_environment: Environment
var _sun: DirectionalLight3D
var _baseline: Dictionary = {}
var _effects_root: Node3D
var _wind_strokes: Array[MeshInstance3D] = []
var _wind_material: StandardMaterial3D
var _source_snapshot: Dictionary = {}
var _values: Dictionary = {}
var _enabled := false
var _valid := true
var _time_s := 0.0
var _time_valid := true
var _day: Variant = null
var _day_basis := "unknown"
var _display: Dictionary = {}

func _init() -> void:
	name = "SceneWeather"
	set_process(false)
	set_physics_process(false)

func setup(host: Node3D) -> void:
	if is_instance_valid(_host) and _host == host and is_instance_valid(_effects_root):
		_apply_weather()
		return
	_release_host()
	if not is_instance_valid(host):
		_apply_weather()
		return
	_host = host
	_find_lighting(host)
	if is_instance_valid(_environment_node):
		_original_environment = _environment_node.environment
		if _original_environment != null:
			_weather_environment = _original_environment.duplicate() as Environment
	if is_instance_valid(_sun):
		_baseline = {"sun_transform": _sun.transform, "sun_rotation_degrees": _sun.rotation_degrees, "sun_color": _sun.light_color,
			"sun_energy": _sun.light_energy, "sun_shadow": _sun.shadow_enabled}
	_effects_root = Node3D.new()
	_effects_root.name = "SceneWeatherEffects"
	_effects_root.set_meta("visual_only", true)
	_effects_root.set_meta("wind_direction_basis", "illustrative_positive_x_not_measured")
	_host.add_child(_effects_root)
	_build_wind_strokes()
	_apply_weather()

func set_weather(snapshot: Dictionary, time_s: float, enabled: bool) -> void:
	# A paused UI may resend its snapshot every frame. Do not touch rendering
	# resources or transforms at all when the supplied presentation is unchanged.
	var same_time := (_time_valid and is_finite(time_s) and _time_s == time_s) or (not _time_valid and not is_finite(time_s))
	if not _display.is_empty() and snapshot == _source_snapshot and enabled == _enabled and same_time:
		return
	_source_snapshot = snapshot.duplicate(true)
	_values = {}
	_enabled = enabled
	_valid = not snapshot.has("valid") or (snapshot.valid is bool and snapshot.valid)
	_time_valid = is_finite(time_s)
	_time_s = time_s if _time_valid else 0.0
	_day = null
	_day_basis = "unknown"
	if _valid:
		for field in NUMBER_FIELDS:
			var value: Variant = snapshot.get(field)
			if not _valid_number(value):
				continue
			var number := float(value)
			if field == "solar_altitude_deg" and (number < -90.0 or number > 90.0):
				continue
			if field == "solar_azimuth_deg" and (number < 0.0 or number > 360.0):
				continue
			if field == "cloud_cover" and (number < 0.0 or number > 1.0):
				continue
			if field not in ["air_temp_c", "solar_altitude_deg"] and number < 0.0:
				continue
			_values[field] = number
		if _values.has("solar_altitude_deg"):
			_day = float(_values.solar_altitude_deg) > 0.0
			_day_basis = "solar_altitude_deg"
		elif snapshot.get("is_day") is bool:
			_day = snapshot.is_day
			_day_basis = "explicit_is_day"
	_apply_weather()

func get_display_state() -> Dictionary:
	return _display.duplicate(true)

func _valid_number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _find_lighting(parent: Node) -> void:
	for child in parent.get_children():
		if child == self:
			continue
		if child is WorldEnvironment and _environment_node == null:
			_environment_node = child
		elif child is DirectionalLight3D and _sun == null:
			_sun = child
		_find_lighting(child)

func _build_wind_strokes() -> void:
	_wind_material = StandardMaterial3D.new()
	_wind_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_wind_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_wind_material.albedo_color = Color(0.77, 0.90, 0.91, 0.27)
	_wind_material.roughness = 1.0
	var stroke_mesh := BoxMesh.new()
	stroke_mesh.size = Vector3(3.0, 0.075, 0.075)
	for index in range(MAX_WIND_STROKES):
		var stroke := MeshInstance3D.new()
		stroke.name = "WindStroke%d" % (index + 1)
		stroke.mesh = stroke_mesh
		stroke.material_override = _wind_material
		stroke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		stroke.visible = false
		_effects_root.add_child(stroke)
		_wind_strokes.append(stroke)

func _apply_weather() -> void:
	var active := _enabled and _valid and is_instance_valid(_host)
	var daylight: Variant = null
	var cloud: float = _values.get("cloud_cover", 0.0)
	var lighting_applied := false
	if active:
		if _values.has("solar_altitude_deg"):
			daylight = smoothstep(-10.0, 16.0, float(_values.solar_altitude_deg))
		elif _day != null:
			daylight = 1.0 if _day else 0.0
		lighting_applied = daylight != null or _values.has("cloud_cover")
		if lighting_applied:
			_apply_lighting(daylight, cloud)
		else:
			_restore_lighting()
		if is_instance_valid(_sun) and _values.has("solar_altitude_deg"):
			var orientation: Vector3 = _baseline.sun_rotation_degrees
			orientation.x = -float(_values.solar_altitude_deg)
			if _values.has("solar_azimuth_deg") and _source_snapshot.get("solar_azimuth_defined", true) != false:
				orientation.y = 180.0 - float(_values.solar_azimuth_deg)
				orientation.z = 0.0
			_sun.rotation_degrees = orientation
		elif is_instance_valid(_sun) and not _baseline.is_empty():
			_sun.transform = _baseline.sun_transform
	else:
		_restore_lighting()
	var wind: float = _values.get("wind_speed_mps", 0.0)
	var stroke_count := 0
	if active and _time_valid and wind > 0.0:
		stroke_count = 2 if wind < 4.0 else (4 if wind < 9.0 else MAX_WIND_STROKES)
	var positions: Array[Vector3] = []
	var wind_phase := 0.0
	if _time_valid and wind > 0.0:
		# Modulo before multiplication also keeps very large timestamps finite.
		var visual_speed := clampf(wind * 0.35, 0.0, 6.0)
		wind_phase = fposmod(_time_s, WIND_SPAN / visual_speed) * visual_speed
	if is_instance_valid(_effects_root):
		_effects_root.visible = active and stroke_count > 0
		for index in range(_wind_strokes.size()):
			var stroke := _wind_strokes[index]
			stroke.visible = index < stroke_count
			# Thin, low-alpha strokes stay near the outer map lanes. They are not
			# an opaque full-screen overlay and never intercept input or picking.
			var x := -WIND_SPAN * 0.5 + fposmod(wind_phase + float(index) * 29.0, WIND_SPAN)
			var z := -58.0 if index % 2 == 0 else 59.0
			z += float(index / 2) * (2.0 if index % 2 == 0 else -2.0)
			var ground := _ground_height(x, z)
			stroke.position = Vector3(x, ground + 3.5 + float(index % 2), z)
			stroke.scale.x = 1.0 + clampf(wind / 20.0, 0.0, 1.0)
			positions.append(stroke.position)
	_display = {
		"enabled": _enabled, "valid": _valid, "active": active,
		"lighting_applied": active and lighting_applied,
		"time_s": _time_s if _time_valid else null,
		"source_snapshot": _source_snapshot.duplicate(true), "values": _values.duplicate(true),
		"is_day": _day, "day_basis": _day_basis, "daylight_factor": daylight,
		"cloud_cover": _values.get("cloud_cover", "not_modeled"),
		"rainfall": _values.get("precipitation_mm_h", "not_modeled"),
		"rain_effect": false, "cloud_geometry_count": 0,
		"wind_stroke_count": stroke_count, "wind_stroke_limit": MAX_WIND_STROKES,
		"wind_phase": wind_phase, "wind_positions": positions,
		"wind_direction_basis": "illustrative_positive_x_not_measured",
		"north_axis": Vector3.FORWARD, "night_fill_basis": "artistic_readability_not_irradiance",
		"background_color": _environment_node.environment.background_color if is_instance_valid(_environment_node) and _environment_node.environment != null else null,
		"ambient_color": _environment_node.environment.ambient_light_color if is_instance_valid(_environment_node) and _environment_node.environment != null else null,
		"ambient_energy": _environment_node.environment.ambient_light_energy if is_instance_valid(_environment_node) and _environment_node.environment != null else null,
		"sun_color": _sun.light_color if is_instance_valid(_sun) else null,
		"sun_energy": _sun.light_energy if is_instance_valid(_sun) else null,
		"sun_rotation_degrees": _sun.rotation_degrees if is_instance_valid(_sun) else null,
		"shadow_enabled": _sun.shadow_enabled if is_instance_valid(_sun) else null,
		"visual_only": true
	}

func _apply_lighting(daylight: Variant, cloud: float) -> void:
	if _weather_environment != null and is_instance_valid(_environment_node):
		_weather_environment.background_mode = Environment.BG_COLOR
		_weather_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		var background := _original_environment.background_color
		var ambient := _original_environment.ambient_light_color
		var ambient_energy := _original_environment.ambient_light_energy
		if daylight != null:
			var day_amount := float(daylight)
			var day_background := background
			if _values.has("solar_altitude_deg"):
				var horizon_warmth := 1.0 - smoothstep(0.0, 18.0, absf(float(_values.solar_altitude_deg)))
				day_background = background.lerp(Color("d6bd9f"), 0.25 * horizon_warmth)
			background = NIGHT_BACKGROUND.lerp(day_background, day_amount)
			ambient = NIGHT_AMBIENT.lerp(ambient, day_amount)
			# A lower bound keeps the editable map readable at night. This fill
			# deliberately has no relationship to the irradiance/power model.
			ambient_energy = lerpf(maxf(0.30, ambient_energy * 0.80), ambient_energy, day_amount)
		_weather_environment.background_color = background.lerp(Color("83939d"), cloud * 0.30)
		_weather_environment.ambient_light_color = ambient.lerp(Color("b9c7d0"), cloud * 0.28)
		_weather_environment.ambient_light_energy = ambient_energy * (1.0 - cloud * 0.08)
		_environment_node.environment = _weather_environment
	if is_instance_valid(_sun):
		var direct_factor := 1.0
		var sunlight := _baseline.sun_color as Color
		if _values.has("solar_altitude_deg"):
			var altitude := float(_values.solar_altitude_deg)
			direct_factor = pow(maxf(0.0, sin(deg_to_rad(altitude))), 0.45)
			sunlight = Color("ffca90").lerp(_baseline.sun_color, smoothstep(0.0, 28.0, altitude))
		elif _day != null:
			direct_factor = 1.0 if _day else 0.0
		_sun.light_color = sunlight.lerp(Color("d9e3ea"), cloud * 0.45)
		_sun.light_energy = float(_baseline.sun_energy) * direct_factor * (1.0 - 0.64 * cloud)
		_sun.shadow_enabled = false

func _ground_height(x: float, z: float) -> float:
	if is_instance_valid(_host) and _host.has_method("height_at"):
		var height: Variant = _host.call("height_at", x, z)
		if _valid_number(height):
			return float(height)
	return 0.0

func _restore_lighting() -> void:
	if is_instance_valid(_environment_node):
		_environment_node.environment = _original_environment
	if is_instance_valid(_sun) and not _baseline.is_empty():
		_sun.transform = _baseline.sun_transform
		_sun.light_color = _baseline.sun_color
		_sun.light_energy = _baseline.sun_energy
		_sun.shadow_enabled = _baseline.sun_shadow

func _release_host() -> void:
	_restore_lighting()
	if is_instance_valid(_effects_root):
		_effects_root.free()
	_effects_root = null
	_wind_strokes.clear()
	_host = null
	_environment_node = null
	_original_environment = null
	_weather_environment = null
	_sun = null
	_baseline.clear()

func _exit_tree() -> void:
	_restore_lighting()
	if is_instance_valid(_effects_root):
		_effects_root.queue_free()
