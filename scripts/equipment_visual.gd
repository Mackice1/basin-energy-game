extends RefCounted
## Procedural/imported display assets only; no simulation capacity or links.
## API: create(kind, profile, prefer_blender_assets=false) -> EquipmentNode;
## footprint(kind) -> world radius. Imported wind/PV assets support the reference
## geometry only; custom dimensions use the original procedural geometry.
## EquipmentNode: set_highlight, set_preview(valid), clear_preview,
## set_operating(radians_per_second), port_local, port_global()/get_port_position().
## Named ports: named_port_locals, has_named_port(id), get_named_port_position(id).
## Thermal SOC is a separate text gauge; fixed temperature zones never interpolate.
## Wind uses 0.1 world units/m. Reference metric PV uses complete physical
## module layouts; only legacy illustrative PV uses a compressed field icon.
## Source module dimensions and display scale remain available in metadata.

const WORLD_UNITS_PER_METER := 0.1
const Spatial = preload("res://scripts/spatial_dimensions.gd")
const IVORY := Color("e8e8d8")
const BLUE := Color("176095")
const METAL := Color("667e82")
const CONCRETE := Color("9eaaa3")
const GREEN := Color("51c793")
const RANKINE_KINDS := ["salt_steam_generator", "steam_generator", "steam_turbine", "steam_condenser", "feedwater_pump"]
const PREVIEW_SITE_KINDS := ["tower_station_preview", "tower_station"]
const TOWER_DEVICE_KINDS := ["solar_tower_receiver", "molten_salt_store"]
const CHEMICAL_KINDS := ["nitrogen_supply_boundary", "co2_supply_boundary", "ammonia_synthesis_station", "methanol_synthesis_station"]
const H2_PHASE_STORAGE_KINDS := ["hydrogen_liquid_store", "hydrogen_metal_hydride_store"]
const MATERIAL_KINDS := ["water_supply_boundary", "electrolyzer_station", "hydrogen_gas_store", "fuel_cell_station"]
const NEW_STORAGE_KINDS := ["co2_liquid_cycle_store", "battery_sodium", "battery_flow", "caes_aboveground", "liquid_air_store", "hydrogen_storage_system", "solid_thermal_store"]
const HIGH_TEMP_KINDS := ["parabolic_trough", "high_temp_store", "oil_water_exchanger"]
static var _solar_glass: StandardMaterial3D
static var _blender_scenes: Dictionary = {}
const BLENDER_ASSETS := {
	"wind": "res://assets/models/wind_turbine.glb",
	"pv": "res://assets/models/solar_array.glb",
	"electric_boiler": "res://assets/models/electric_boiler.glb",
	"fuel_boiler": "res://assets/models/fuel_boiler.glb",
	"solar_thermal": "res://assets/models/solar_thermal.glb",
	"thermal_store": "res://assets/models/thermal_store.glb",
	"heat_exchanger": "res://assets/models/heat_exchanger.glb",
}

# The marker names carry the same semantics in legacy and metric geometry.
# Their metric coordinates are authored in the GLB and checked against its
# manifest; legacy saved scenes keep their original procedural coordinates.
const THERMAL_ASSET_PORTS := {
	"solar_thermal": {"ac_in": ["input", ""], "heat_out": ["output", "hw_primary_90_60"]},
	"electric_boiler": {"ac_in": ["input", ""], "heat_out": ["output", "hw_primary_90_60"]},
	"fuel_boiler": {"ac_in": ["input", ""], "heat_out": ["output", "hw_primary_90_60"]},
	"thermal_store": {"heat_in": ["input", "hw_primary_90_60"], "heat_out": ["output", "hw_primary_90_60"]},
	"heat_exchanger": {"hot_in": ["input", "hw_primary_90_60"], "warm_out": ["output", "hw_secondary_70_40"]},
}
const THERMAL_MANIFEST := "res://assets/models/thermal_asset_manifest.json"
const FUEL_BOILER_MANIFEST := "res://assets/models/fuel_boiler_manifest.json"
static var _thermal_manifest: Dictionary = {}
static var _fuel_boiler_manifest: Dictionary = {}

static func thermal_asset_definition(kind: String) -> Dictionary:
	if kind == "salt_steam_generator":
		return JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/tower_asset_manifest.json")).get("assets",{}).get(kind,{})
	if kind in PREVIEW_SITE_KINDS or kind in RANKINE_KINDS:
		var preview_path := "res://assets/models/rankine_asset_manifest.json"
		var preview_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(preview_path)) if FileAccess.file_exists(preview_path) else {}
		return preview_parsed.get("assets", {}).get(kind, {}) if preview_parsed is Dictionary else {}
	if kind in HIGH_TEMP_KINDS:
		var high_path := "res://assets/models/high_temp_asset_manifest.json"
		var high_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(high_path)) if FileAccess.file_exists(high_path) else {}
		return high_parsed.get("assets", {}).get(kind, {}) if high_parsed is Dictionary else {}
	if kind == "solar_thermal":
		var solar_path := "res://assets/models/solar_thermal_manifest.json"
		var solar_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(solar_path)) if FileAccess.file_exists(solar_path) else {}
		return solar_parsed.get("assets", {}).get(kind, {}) if solar_parsed is Dictionary else {}
	if kind == "fuel_boiler":
		if _fuel_boiler_manifest.is_empty() and FileAccess.file_exists(FUEL_BOILER_MANIFEST):
			var fuel_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FUEL_BOILER_MANIFEST))
			if fuel_parsed is Dictionary:
				_fuel_boiler_manifest = fuel_parsed
		return _fuel_boiler_manifest.get("assets", {}).get(kind, {})
	if _thermal_manifest.is_empty() and FileAccess.file_exists(THERMAL_MANIFEST):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(THERMAL_MANIFEST))
		if parsed is Dictionary:
			_thermal_manifest = parsed
	return _thermal_manifest.get("assets", {}).get(kind, {})

static func _vector3(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2])) if values.size() == 3 else Vector3.ZERO

class EquipmentNode:
	extends Node3D
	var device_kind := ""
	var rotor: Node3D
	var rotor_speed_rad_s := 0.0
	var solar_tracking_pivots: Array[Node3D] = []

	## Azimuth clockwise from north, east +X and north -Z. Below horizon stows upward.
	func set_solar_tracking(altitude_deg: float, azimuth_deg: float) -> void:
		if not is_finite(altitude_deg) or not is_finite(azimuth_deg):
			return
		var altitude := deg_to_rad(altitude_deg)
		var east := cos(altitude) * sin(deg_to_rad(azimuth_deg))
		var angle := -atan2(east, sin(altitude)) if altitude_deg > 0.0 else 0.0
		for pivot in solar_tracking_pivots:
			pivot.rotation.z = angle
		set_meta("tracking_angle_deg", rad_to_deg(angle))

	func set_tower_tracking(altitude_deg: float, azimuth_deg: float) -> void:
		if device_kind != "tower_station" or not is_finite(altitude_deg) or not is_finite(azimuth_deg): return
		var alt := deg_to_rad(altitude_deg)
		var az := deg_to_rad(azimuth_deg)
		var sun := Vector3(cos(alt)*sin(az),sin(alt),-cos(alt)*cos(az))
		var authored_units: float = 10.0 if get_meta("visual_backend", "") == "blender_glb" else 1.0
		for face in find_children("MirrorSurface*", "MeshInstance3D", true, false):
			var center: Vector3 = face.position
			var normal := Vector3.UP if altitude_deg <= 0 else (sun + (Vector3(0,2.4*authored_units,0)-center).normalized()).normalized()
			face.quaternion = Quaternion(Vector3.UP,normal)
			var backing: Node3D = face.get_parent().find_child("MirrorBacking*",false,false)
			if backing != null:
				backing.quaternion = face.quaternion
				backing.position = center-normal*.006*authored_units

	var port_local := Vector3.ZERO
	var port: Node3D
	var named_port_locals: Dictionary = {}
	var named_ports: Dictionary = {}
	# Physical return nozzles are visual anchors, never extra simulation ports.
	var physical_return_locals: Dictionary = {}
	var thermal_soc_label: Label3D
	var selected := false
	var hovered := false
	var compatible_target := false
	var connection_source := false
	var annotation_labels: Array[Label3D] = []
	var hint_materials: Dictionary = {}
	var _details_requested := false
	var _ports_requested := false
	var preview_enabled := false
	var preview_valid := true
	var selection_ring: MeshInstance3D
	var surfaces: Array[MeshInstance3D] = []
	var base_materials: Array[Material] = []
	var preview_good: StandardMaterial3D
	var preview_bad: StandardMaterial3D

	func _process(delta: float) -> void:
		if is_instance_valid(rotor) and not preview_enabled:
			rotor.rotation.z = fposmod(rotor.rotation.z + rotor_speed_rad_s * delta, TAU)

	func set_operating(speed_rad_s: float) -> void:
		rotor_speed_rad_s = clampf(speed_rad_s, -20.0, 20.0) if is_finite(speed_rad_s) else 0.0

	func set_highlight(enabled: bool) -> void:
		selected = enabled
		_update_interaction_hint()
		fit_annotation_labels()

	## Selection stays authoritative; hover and connection hints never mutate it.
	func set_interaction_hint(is_hovered: bool, compatible: bool, source: bool) -> void:
		hovered = is_hovered
		compatible_target = compatible
		connection_source = source
		_update_interaction_hint()

	func set_hovered(enabled: bool) -> void:
		set_interaction_hint(enabled, compatible_target, connection_source)

	func _update_interaction_hint() -> void:
		if not is_instance_valid(selection_ring):
			return
		selection_ring.visible = not preview_enabled and (selected or hovered or compatible_target or connection_source)
		if preview_enabled or hint_materials.is_empty():
			return
		var hint := "selected" if selected or not (hovered or compatible_target or connection_source) else "source" if connection_source else "compatible" if compatible_target else "hover"
		selection_ring.material_override = hint_materials[hint]

	## Only intrinsic annotations are cached. Caller-owned device titles are
	## controlled by their view, and duplicate fallback-module labels stay hidden.
	func set_annotation_visibility(show_details: bool, show_ports: bool = false) -> void:
		_details_requested = show_details
		_ports_requested = show_ports
		_update_annotation_visibility()

	func _update_annotation_visibility() -> void:
		if _details_requested or _ports_requested:
			fit_annotation_labels()
		for label in annotation_labels:
			if is_instance_valid(label):
				label.visible = not preview_enabled and (_ports_requested if label.name == "PortLabel" else _details_requested)

	func fit_annotation_labels() -> void:
		if not is_inside_tree():
			return
		var view_camera := get_viewport().get_camera_3d()
		for label in annotation_labels:
			_fit_screen_label(label, view_camera, 18.0 if label.name == "PortLabel" else 20.0)

	static func _fit_screen_label(label: Label3D, view_camera: Camera3D, height_px: float = 20.0) -> void:
		if not is_instance_valid(label) or not is_instance_valid(view_camera) or not view_camera.is_inside_tree():
			return
		var viewport_height := maxf(1.0, view_camera.get_viewport().get_visible_rect().size.y)
		var projection_factor := 1.0
		if view_camera.projection != Camera3D.PROJECTION_ORTHOGONAL:
			projection_factor = absf(view_camera.get_camera_projection().y.y)
		if not is_finite(projection_factor) or projection_factor <= 0.0:
			return
		var pixel_scale := 2.0 * clampf(height_px, 12.0, 28.0) / (maxi(1, label.font_size) * viewport_height * projection_factor)
		label.fixed_size = true
		label.set_disable_scale(true)
		if not is_equal_approx(label.pixel_size, pixel_scale):
			label.pixel_size = pixel_scale

	func set_preview(valid: bool) -> void:
		preview_enabled = true
		preview_valid = valid
		for surface in surfaces:
			surface.material_override = preview_good if valid else preview_bad
		if is_instance_valid(selection_ring):
			selection_ring.visible = false
		_update_annotation_visibility()

	func clear_preview() -> void:
		preview_enabled = false
		for i in surfaces.size():
			surfaces[i].material_override = base_materials[i]
		set_highlight(selected)
		_update_annotation_visibility()

	func set_preview_disabled() -> void:
		clear_preview()

	func port_global() -> Vector3:
		return to_global(port_local) if is_inside_tree() else transform * port_local

	func get_port_position() -> Vector3:
		return port_global()

	func has_named_port(port_id: String) -> bool:
		return named_port_locals.has(port_id)

	## Unknown names preserve the legacy endpoint; connection validation belongs
	## to Catalog. Call has_named_port() before selecting a new thermal endpoint.
	func get_named_port_position(port_id: String) -> Vector3:
		var local: Vector3 = named_port_locals.get(port_id, port_local)
		return to_global(local) if is_inside_tree() else transform * local

	func set_thermal_soc(soc: float) -> void:
		if is_instance_valid(thermal_soc_label):
			thermal_soc_label.text = "库存 SOC %.1f%%" % (100.0 * clampf(soc, 0.0, 1.0)) if is_finite(soc) else "库存 SOC —"

static func _canonical(kind: String) -> String:
	match kind.to_lower():
		"wind", "wind_turbine", "turbine": return "wind"
		"pv", "solar", "pv_array", "solar_pv": return "pv"
		"station", "substation", "transformer": return "station"
		"load", "consumer", "industrial_load": return "load"
		"battery", "storage", "battery_storage": return "battery"
	return kind.to_lower()

static func footprint(kind: String, params: Dictionary = {}) -> float:
	if _canonical(kind) in CHEMICAL_KINDS or _canonical(kind) in H2_PHASE_STORAGE_KINDS or _canonical(kind) == "collector_substation" or _canonical(kind) in MATERIAL_KINDS or _canonical(kind) in NEW_STORAGE_KINDS or _canonical(kind) in RANKINE_KINDS or _canonical(kind) in PREVIEW_SITE_KINDS or _canonical(kind) in HIGH_TEMP_KINDS or _canonical(kind) == "solar_thermal" or (_canonical(kind)=="thermal_store" and str(params.get("visual_site_geometry_profile","reference_size_v1"))=="reference_size_v1") or str(params.get("visual_dimension_profile", "legacy_illustrative")) == "metric_v1":
		return float(Spatial.profile(_canonical(kind), params, false, str(params.get("visual_geometry_profile","flow_process_v2")), str(params.get("visual_site_geometry_profile","reference_size_v1"))).clearance_radius_world)
	match _canonical(kind):
		"wind": return 7.0
		"pv": return 5.0
		"station": return 4.0
		"load": return 5.5
		"battery": return 4.0
		"electric_boiler", "fuel_boiler", "heat_exchanger", "heat_demand": return 4.0
		"thermal_store": return 5.0
	return 2.0

static func create(kind: String, params: Dictionary = {}, prefer_blender_assets: bool = false) -> Node3D:
	var item := EquipmentNode.new()
	item.device_kind = _canonical(kind)
	item.name = item.device_kind.capitalize() + "Visual"
	item.set_meta("visual_only", true)
	item.set_meta("capacity_added", 0.0)
	item.set_meta("visual_backend", "procedural")
	item.set_meta("footprint_radius", footprint(kind,params))
	item.preview_good = _material(Color(0.15, 0.95, 0.58, 0.54), 0.25, true)
	item.preview_bad = _material(Color(1.0, 0.19, 0.15, 0.58), 0.25, true)
	var palette := {
		"ivory": _material(IVORY), "blue": _material(BLUE, 0.18),
		"metal": _material(METAL, 0.5), "concrete": _material(CONCRETE),
		"dark": _material(Color("283f48")), "green": _material(GREEN, 0.2),
		"gold": _material(Color("f4d476"), 0.1, true),
		"gravel": _material(Color("777f73")),
		"porcelain": _material(Color("a99b80"), 0.12),
		"solar": _solar_material(),
		"heat_primary": _material(Color("c87038"), 0.18),
		"heat_secondary": _material(Color("dda548"), 0.18),
		"heat_return": _material(Color("4c829a"), 0.18),
	}
	var profile: Dictionary = params.get(item.device_kind, params)
	if params.has("visual_dimension_profile") and not profile.has("visual_dimension_profile"):
		profile = profile.duplicate(true)
		profile.visual_dimension_profile = params.visual_dimension_profile
	if item.device_kind in CHEMICAL_KINDS or item.device_kind in H2_PHASE_STORAGE_KINDS or item.device_kind == "collector_substation" or item.device_kind in MATERIAL_KINDS or item.device_kind in NEW_STORAGE_KINDS or item.device_kind in TOWER_DEVICE_KINDS or item.device_kind in RANKINE_KINDS or item.device_kind in PREVIEW_SITE_KINDS or item.device_kind in HIGH_TEMP_KINDS or item.device_kind == "solar_thermal":
		profile = profile.duplicate(true)
		profile.visual_dimension_profile = "metric_v1"
	var site_geometry_profile: String = str(params.get("visual_site_geometry_profile", profile.get("visual_site_geometry_profile", "reference_size_v1")))
	profile = profile.duplicate(true)
	profile.visual_site_geometry_profile = site_geometry_profile
	if item.device_kind == "thermal_store" and site_geometry_profile == "reference_size_v1":
		profile = profile.duplicate(true)
		profile.visual_dimension_profile = "metric_v1"
	var metric := str(profile.get("visual_dimension_profile", "legacy_illustrative")) == "metric_v1"
	var dimensions: Dictionary = Spatial.profile(item.device_kind, profile, true, str(params.get("visual_geometry_profile",profile.get("visual_geometry_profile","flow_process_v2"))), site_geometry_profile) if metric else {}
	item.set_meta("site_geometry_profile",site_geometry_profile)
	item.set_meta("reference_site_geometry",dimensions.get("reference_site_geometry",{}))
	# Failed metric profiles contain only the zero-sized base contract. Do not
	# enter any builder, import a default asset, add terminals, or read optional
	# kind-specific dimensions (for example wind foundation_dimensions_m).
	item.set_meta("visual_valid", not metric or bool(dimensions.get("valid", false)))
	if metric and not bool(dimensions.get("valid", false)):
		_apply_metric_metadata(item, dimensions)
		item.set_meta("visual_backend", "invalid_metric")
		item.set_meta("visual_errors", dimensions.get("errors", []).duplicate(true))
		item.set_meta("asset_fallback", "invalid metric dimensions")
		item.preview_valid = false
		return item
	var imported := false
	if item.device_kind in CHEMICAL_KINDS:
		_build_chemical_facility(item, dimensions, palette)
		imported = true
	elif item.device_kind in H2_PHASE_STORAGE_KINDS:
		_build_hydrogen_phase_facility(item, dimensions, palette)
		imported = true
	elif item.device_kind == "collector_substation":
		_build_collector_substation(item, dimensions, palette)
		imported = true
	elif item.device_kind in MATERIAL_KINDS:
		_build_material_facility(item, dimensions, palette)
		imported = true
	elif item.device_kind == "co2_liquid_cycle_store":
		_build_co2_facility(item, dimensions, palette)
		imported = true
	elif item.device_kind in NEW_STORAGE_KINDS:
		_build_storage_facility(item, dimensions, palette)
		imported = true
	elif item.device_kind in TOWER_DEVICE_KINDS:
		_build_tower_device(item, dimensions, palette)
		imported = true
	elif item.device_kind in RANKINE_KINDS:
		_build_rankine(item, dimensions, palette, prefer_blender_assets)
		imported = true
	elif item.device_kind in PREVIEW_SITE_KINDS:
		_build_tower_station_preview(item, dimensions, palette, prefer_blender_assets, bool(profile.get("preview_interior", false)))
		imported = true
	elif item.device_kind in HIGH_TEMP_KINDS:
		_build_high_temp(item, dimensions, palette, prefer_blender_assets)
		imported = true
	elif metric and item.device_kind == "thermal_store" and site_geometry_profile == "reference_size_v1":
		_build_reference_water_store(item, dimensions, palette)
		imported = true
	elif metric and item.device_kind in ["pv", "battery", "station"]:
		_build_metric_electrical(item, dimensions, palette)
		imported = true
	else:
		imported = prefer_blender_assets and _try_build_blender(item, profile)
	if metric and not imported and THERMAL_ASSET_PORTS.has(item.device_kind):
		_build_metric_thermal_fallback(item, profile, dimensions)
		imported = true
	if not imported:
		match item.device_kind:
			"wind": _build_wind(item, profile, palette)
			"pv": _build_pv(item, profile, palette)
			"station": _build_station(item, profile, palette)
			"load": _build_load(item, profile, palette)
			"battery": _build_battery(item, profile, palette)
			"electric_boiler": _build_electric_boiler(item, profile, palette)
			"fuel_boiler": _build_fuel_boiler(item, profile, palette)
			"thermal_store": _build_thermal_store(item, profile, palette)
			"heat_exchanger": _build_heat_exchanger(item, profile, palette)
			"heat_demand": _build_heat_demand(item, profile, palette)
			_:
				push_warning("Unknown equipment visual: " + kind)
				_box(item, item, "Placeholder", Vector3(1, 1, 1), Vector3(0, 0.5, 0), palette.ivory)
	if metric and item.device_kind == "wind":
		_normalize_metric_wind_site(item, dimensions, palette)
	if metric and item.device_kind in ["load", "heat_demand"]:
		_rescale_procedural_unit(item, Vector3(0.30, 0.35, 0.30))
	if metric:
		_apply_metric_metadata(item, dimensions)
	if item.named_port_locals.is_empty() and not item.device_kind in PREVIEW_SITE_KINDS:
		_add_terminal(item, palette, metric)
		_register_legacy_port_names(item)
	var ring := TorusMesh.new()
	var site_radius: float = item.get_meta("footprint_radius", footprint(kind))
	var ring_width := clampf(site_radius * 0.015, 0.008, 0.09) if metric else 0.09
	ring.inner_radius = maxf(0.001, site_radius - ring_width)
	ring.outer_radius = site_radius + ring_width
	ring.rings = 64
	ring.ring_segments = 6
	item.selection_ring = _mesh(item, item, "SelectionRing", ring, Vector3(0, 0.012 if metric else 0.14, 0), palette.gold)
	item.selection_ring.visible = false
	item.hint_materials = interaction_hint_materials(palette.gold)
	for label in item.find_children("*", "Label3D", true, false):
		if not label.get_meta("annotation_suppressed", false):
			item.annotation_labels.append(label)
	item.set_annotation_visibility(false)
	return item

## One compact vocabulary across equipment and whole-site facades. These are
## display materials only: authored meshes, footprint and dispatch stay intact.
static func interaction_hint_materials(selected_material: Material) -> Dictionary:
	var result := {"selected": selected_material}
	for entry in [["source", Color("ffc06a")], ["compatible", Color("64e2d1")], ["hover", Color("dcece8")]]:
		var material := _material(entry[1], 0.0, true)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		result[entry[0]] = material
	return result

## Fixed-size billboards are depth-scaled by Godot, but orthogonal and
## perspective shaders use different normalizations. Fit their nominal font
## height to the viewport so zoom/projection changes cannot make giant labels.
static func fit_screen_label(label: Label3D, view_camera: Camera3D, height_px: float = 20.0) -> void:
	EquipmentNode._fit_screen_label(label, view_camera, height_px)

## The Blender meshes are self-contained reference assets. A dimension change
## is never silently ignored: non-reference geometry takes the procedural path.
static func _try_build_blender(item: EquipmentNode, profile: Dictionary) -> bool:
	if not BLENDER_ASSETS.has(item.device_kind):
		return false
	if THERMAL_ASSET_PORTS.has(item.device_kind) and str(profile.get("visual_dimension_profile", "legacy_illustrative")) != "metric_v1":
		return false
	if item.device_kind == "wind":
		if not is_equal_approx(_number(profile, ["hub_height_m"], 90.0), 90.0) or not is_equal_approx(_number(profile, ["rotor_diameter_m", "nominal_rotor_diameter_m"], 126.0), 126.0):
			item.set_meta("asset_fallback", "custom wind geometry")
			return false
	elif item.device_kind == "pv":
		if not is_equal_approx(_number(profile, ["module_area_m2", "panel_area_m2", "array_area_m2"], 16000.0), 16000.0) or not is_equal_approx(_number(profile, ["tilt_deg", "panel_tilt_deg"], 25.0), 25.0):
			item.set_meta("asset_fallback", "custom PV geometry")
			return false
	var path: String = BLENDER_ASSETS[item.device_kind]
	if not _blender_scenes.has(path):
		if not ResourceLoader.exists(path, "PackedScene"):
			item.set_meta("asset_fallback", "reference asset unavailable or not imported")
			return false
		var packed := load(path) as PackedScene
		if packed == null:
			item.set_meta("asset_fallback", "reference asset could not load")
			return false
		_blender_scenes[path] = packed
	var asset := (_blender_scenes[path] as PackedScene).instantiate() as Node3D
	if asset == null:
		return false
	if THERMAL_ASSET_PORTS.has(item.device_kind):
		return _bind_blender_thermal(item, asset, path, profile)
	var imported_port := asset.find_child("ElectricityPort", true, false) as Node3D
	var imported_rotor := asset.find_child("Rotor", true, false) as Node3D
	if imported_port == null or (item.device_kind == "wind" and imported_rotor == null):
		asset.free()
		item.set_meta("asset_fallback", "reference asset lacks required port or rotor")
		return false
	asset.name = "BlenderAsset"
	item.add_child(asset)
	item.port_local = _position_relative_to(imported_port, item)
	# Reuse the authored position but create the same selectable terminal marker
	# as procedural equipment, leaving one authoritative port on EquipmentNode.
	imported_port.free()
	_register_asset_meshes(item, asset)
	item.set_meta("visual_backend", "blender_glb")
	item.set_meta("asset_source", path)
	if item.device_kind == "wind":
		item.rotor = imported_rotor
		item.set_meta("hub_height_m", 90.0)
		item.set_meta("rotor_diameter_m", 126.0)
		item.set_meta("display_hub_height", 9.0)
		item.set_meta("world_units_per_meter", WORLD_UNITS_PER_METER)
		item.set_operating(0.75)
	else:
		item.set_meta("module_area_m2", 16000.0)
		item.set_meta("module_surface_area_world", 1.55 * 1.7 * 12.0)
		item.set_meta("world_units_per_meter", sqrt(1.55 * 1.7 * 12.0 / 16000.0))
		item.set_meta("field_representation", true)
		item.set_meta("tilt_deg", 25.0)
	return true

## Thermal meshes are fixed-size teaching models. Power, inventory and other
## operating parameters do not scale geometry, recolour tanks, or move ports.
static func _bind_blender_thermal(item: EquipmentNode, asset: Node3D, path: String, profile: Dictionary) -> bool:
	var definitions: Dictionary = THERMAL_ASSET_PORTS[item.device_kind]
	var anchors: Dictionary = {}
	var authored := thermal_asset_definition(item.device_kind)
	for port_id in definitions:
		var anchor := asset.find_child("Port_" + port_id, true, false) as Node3D
		var expected: Array = authored.get("ports", {}).get(port_id, [])
		if anchor == null or (not expected.is_empty() and not _position_relative_to(anchor, asset).is_equal_approx(_vector3(expected))):
			asset.free()
			item.set_meta("asset_fallback", "thermal asset lacks the agreed named-port coordinates")
			return false
		anchors[port_id] = anchor
	var soc_anchor := asset.find_child("ThermalSOCAnchor", true, false) as Node3D
	if item.device_kind == "thermal_store" and soc_anchor == null:
		asset.free()
		item.set_meta("asset_fallback", "thermal store asset lacks its separate SOC anchor")
		return false
	var dimensions: Dictionary = Spatial.profile(item.device_kind, profile, true, str(profile.get("visual_geometry_profile","flow_process_v2")), str(item.get_meta("site_geometry_profile","")))
	var modules: Array = dimensions.module_origins_world
	var group := Node3D.new()
	group.name = "BlenderAsset"
	item.add_child(group)
	for index in modules.size():
		var module := asset if index == 0 else (_blender_scenes[path] as PackedScene).instantiate() as Node3D
		module.name = "Module%03d" % (index + 1)
		module.position = modules[index]
		group.add_child(module)
		_register_asset_meshes(item, module)
		if item.device_kind == "solar_thermal":
			module.set_meta("absorber_utilization", dimensions.last_module_utilization if index == modules.size() - 1 else 1.0)
	item.set_meta("visual_backend", "blender_glb")
	item.set_meta("asset_source", path)
	for port_id in definitions:
		var contract: Array = definitions[port_id]
		_register_named_terminal(item, anchors[port_id], port_id, _position_relative_to(anchors[port_id], item), contract[0], contract[1])
		_add_thermal_port_label(anchors[port_id], contract[0], contract[1], true)
		var return_anchor := asset.find_child("Return_" + port_id, true, false) as Node3D
		if return_anchor != null:
			item.physical_return_locals[port_id] = _position_relative_to(return_anchor, item)
	var caption := ""
	match item.device_kind:
		"electric_boiler":
			_thermal_metadata(item, "electric_hot_water_skid")
			item.set_meta("fixed_temperature_profile", "90/60°C")
			caption = "电热水 · 90/60°C"
		"fuel_boiler":
			_fuel_boiler_metadata(item)
			caption = "燃气热水 · 90/60°C"
		"thermal_store":
			_thermal_metadata(item, "fixed_grade_two_zone_heat_store")
			item.set_meta("fixed_temperature_profile", "90/60°C")
			item.set_meta("storage_approximation", "理想分层/双区等效库存；固定供水品质；非完全混合水箱")
			item.set_meta("soc_changes_temperature", false)
			item.thermal_soc_label = _thermal_label(soc_anchor, "ThermalSOC", "库存 SOC —", Vector3.ZERO, 33)
			item.thermal_soc_label.no_depth_test = true
			item.thermal_soc_label.pixel_size = 0.00055
			caption = "90/60°C · 固定双区"
		"heat_exchanger":
			_thermal_metadata(item, "isolated_plate_heat_exchanger")
			item.set_meta("fixed_temperature_profile", "90/60→70/40°C")
			caption = "隔离换热 · 90/60→70/40°C"
	if item.device_kind == "solar_thermal":
		_solar_thermal_metadata(item, dimensions)
		caption = "真空管集热 · 固定30° · 90/60°C"
	var caption_position := _vector3(authored.get("profile_anchor", [0, 0.8, 0]))
	var label := _thermal_label(item, "ProfileLabel", caption, caption_position, 34)
	label.pixel_size = 0.0006
	return true

static func _position_relative_to(node: Node3D, ancestor: Node3D) -> Vector3:
	var transform := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != null and cursor != ancestor:
		if cursor is Node3D:
			transform = cursor.transform * transform
		cursor = cursor.get_parent()
	return transform.origin

static func _register_asset_meshes(item: EquipmentNode, node: Node) -> void:
	if node is MeshInstance3D:
		item.surfaces.append(node)
		# GLB materials live on individual mesh surfaces; null is a meaningful
		# original override and must be restored after preview/highlight.
		item.base_materials.append(node.material_override)
	for child in node.get_children():
		_register_asset_meshes(item, child)

## Only the fixed ground works change in metric mode. Imported wind statics
## are batched by material; never scale the whole asset, tower, rotor or port.
static func _normalize_metric_wind_site(item: EquipmentNode, dimensions: Dictionary, palette: Dictionary) -> void:
	for instance in item.surfaces:
		var label := str(instance.name)
		if label in ["Foundation", "Service apron", "ServiceApron"]:
			var span: float = 1.8 if label == "Foundation" else 3.2
			var relative := _relative_transform(instance, item)
			var bounds: AABB = relative * instance.mesh.get_aabb()
			var correction := _wind_ground_correction(bounds, span)
			var parent_relative := _relative_transform(instance.get_parent(), item)
			instance.transform = parent_relative.affine_inverse() * correction * relative
		elif label == "Structure" and instance.mesh is ArrayMesh:
			# Original GLB joins the apron and footing into dedicated materials.
			# Rebuild a private mesh so legacy instances and cached imports stay intact.
			var fitted := ArrayMesh.new()
			var relative := _relative_transform(instance, item)
			for slot in instance.mesh.get_surface_count():
				var arrays: Array = instance.mesh.surface_get_arrays(slot)
				var material := instance.mesh.surface_get_material(slot)
				var material_name: String = material.resource_name if material != null else ""
				if material_name in ["Warm concrete", "Fine aggregate"]:
					var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					var bounds := AABB(relative * vertices[0], Vector3.ZERO)
					for vertex in vertices:
						bounds = bounds.expand(relative * vertex)
					var span: float = 1.8 if material_name == "Warm concrete" else 3.2
					var correction := relative.affine_inverse() * _wind_ground_correction(bounds, span) * relative
					var normal_basis := correction.basis.inverse().transposed()
					for index in vertices.size():
						vertices[index] = correction * vertices[index]
					arrays[Mesh.ARRAY_VERTEX] = vertices
					if arrays[Mesh.ARRAY_NORMAL] != null:
						var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
						for index in normals.size():
							normals[index] = (normal_basis * normals[index]).normalized()
						arrays[Mesh.ARRAY_NORMAL] = normals
					if arrays[Mesh.ARRAY_TANGENT] != null:
						var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
						for index in range(0, tangents.size(), 4):
							var tangent := (correction.basis * Vector3(tangents[index], tangents[index + 1], tangents[index + 2])).normalized()
							tangents[index] = tangent.x; tangents[index + 1] = tangent.y; tangents[index + 2] = tangent.z
						arrays[Mesh.ARRAY_TANGENT] = tangents
				fitted.add_surface_from_arrays(instance.mesh.surface_get_primitive_type(slot), arrays)
				fitted.surface_set_material(slot, material)
			instance.mesh = fitted
	# Explicit square slab makes the stated 18x18 m foundation projection real;
	# the circular tower footing remains within it and retains its original height.
	_box(item, item, "MetricFoundationBase", Vector3(1.8, 0.08, 1.8), Vector3(0, 0.04, 0), palette.concrete)
	item.set_meta("foundation_dimensions_m", dimensions.foundation_dimensions_m)
	item.set_meta("foundation_area_m2", dimensions.body_area_m2)
	item.set_meta("maintenance_margin_m", dimensions.maintenance_margin_m)
	item.set_meta("groundworks_profile", "metric_18m_square_foundation_32m_square_apron")

static func _wind_ground_correction(bounds: AABB, span: float) -> Transform3D:
	var factor := Vector3(span / bounds.size.x, 1.0, span / bounds.size.z)
	var center := bounds.get_center()
	return Transform3D(Basis.from_scale(factor), Vector3(-center.x * factor.x, 0.0, -center.z * factor.z))

static func _apply_metric_metadata(item: EquipmentNode, dimensions: Dictionary) -> void:
	item.set_meta("visual_dimension_profile", "metric_v1")
	item.set_meta("world_units_per_meter", WORLD_UNITS_PER_METER)
	item.set_meta("footprint_radius", float(dimensions.clearance_radius_world))
	for key in ["module_count", "unit_dimensions_m", "body_dimensions_m", "body_area_m2", "land_dimensions_m", "land_area_m2", "source_note"]:
		item.set_meta(key, dimensions[key])
	for key in ["site_geometry_profile","reference_site_geometry","actual_net_volume_m3","actual_solid_volume_m3","required_net_volume_m3","reference_volume_check_pass","pressure_vessel_certified"]:
		if dimensions.has(key): item.set_meta(key, dimensions[key])
	for key in ["reference_hardware","reference_container_dimensions_m","reference_capacity_per_module","reference_power_per_module","reference_hardware_energy_mwh","reference_hardware_power_mw","reference_hardware_energy_mwh_ac","reference_hardware_power_mw_ac","reference_capacity_basis","reference_process_units_per_module","reference_process_unit_count"]:
		if dimensions.has(key): item.set_meta(key, dimensions[key])
	item.set_meta("modules_share_simulation_limits", true)

## These physical modules are display instances of one aggregate device. Their
## number never adds dispatch nodes, storage inventory, power, or connections.
static func _build_metric_electrical(item: EquipmentNode, dimensions: Dictionary, p: Dictionary) -> void:
	item.set_meta("visual_backend", "metric_batched")
	if not dimensions.valid:
		item.set_meta("asset_fallback", "invalid metric dimensions")
		return
	if item.device_kind == "pv":
		_build_metric_pv(item, dimensions, p)
		return
	var unit: Vector3 = dimensions.unit_dimensions_m
	var total_count: int = int(dimensions.module_count)
	# Historical saves may contain tens of thousands of full battery containers.
	# Keep their complete analytical site/capacity, but render a bounded sample.
	# New reference lithium sites have at most four boxes, so all remain visible.
	var display_count: int = mini(total_count,16) if item.device_kind == "station" else mini(total_count,48)
	item.set_meta("display_module_count",display_count)
	item.set_meta("representative_lod",display_count<total_count)
	if item.device_kind == "station":
		item.set_meta("visual_revision","photo_referenced_compact_mv_phase2")
		item.set_meta("has_pv_inverters",false)
	for display_index in display_count:
		var index: int = display_index if display_count==total_count else int(round(float(display_index)*(total_count-1)/maxi(1,display_count-1)))
		var module := Node3D.new()
		module.name = "PhysicalModule%03d" % (index + 1)
		module.position = Spatial.module_origin_m(dimensions,index) * WORLD_UNITS_PER_METER
		item.add_child(module)
		if item.device_kind == "battery":
			_metric_box(item, module, "ContainerBase", Vector3(unit.x, 0.12, unit.z), Vector3(0, 0.06, 0), p.dark)
			_metric_box(item, module, "BatteryContainer", Vector3(unit.x, unit.y - 0.24, unit.z), Vector3(0, unit.y * 0.5, 0), p.ivory)
			_metric_box(item, module, "ContainerRoof", Vector3(unit.x, 0.12, unit.z), Vector3(0, unit.y - 0.06, 0), p.ivory)
			for door in 4:
				var x: float = -unit.x * 0.5 + 0.78 + float(door) * 1.45
				_metric_box(item, module, "ServiceDoor", Vector3(1.32, 2.30, 0.035), Vector3(x, 1.43, -unit.z * 0.5 + 0.018), p.metal)
				_metric_box(item, module, "DoorPanel", Vector3(1.20, 2.18, 0.012), Vector3(x, 1.43, -unit.z * 0.5 + 0.007), p.ivory)
				_metric_box(item, module, "DoorHandle", Vector3(0.045, 0.30, 0.025), Vector3(x + 0.43, 1.42, -unit.z * 0.5 + 0.013), p.dark)
			for slot in 6:
				_metric_box(item, module, "Ventilation", Vector3(0.025, 0.10, 1.55), Vector3(unit.x * 0.5 - 0.013, 0.65 + slot * 0.20, 0), p.dark)
			for rib in 10:
				_metric_box(item, module, "ContainerCornerSeam", Vector3(.035, unit.y - .35, .024), Vector3(-unit.x*.5 + .20 + rib*(unit.x-.40)/9.0, unit.y*.5, unit.z*.5-.012), p.metal)
			_metric_box(item, module, "HVACServiceFrame", Vector3(.035, 1.70, 1.90), Vector3(unit.x*.5-.018, 1.55, 0), p.metal)
			_metric_box(item, module, "HVACIntake", Vector3(.045, .68, 1.55), Vector3(unit.x*.5-.023, 2.01, 0), p.dark)
			_metric_box(item, module, "StaticBatteryBadge", Vector3(0.85, 0.45, 0.025), Vector3(-2.15, 1.85, -unit.z * 0.5 + 0.013), p.green)
		else:
			# Same original compact MV assembly as the detailed representative.
			# Full metric envelope/ports remain exactly the established contract.
			var assembly := preload("res://scripts/station_detail_sample.gd").new()
			assembly.name = "CompactMVTransformerSwitchgear"
			assembly.scale = Vector3.ONE * WORLD_UNITS_PER_METER
			module.add_child(assembly)
			_register_asset_meshes(item, assembly)

	item.port_local = Vector3(-float(dimensions.body_dimensions_m.x) * 0.5, 0.65, -float(dimensions.body_dimensions_m.z) * 0.5 - 0.4) * WORLD_UNITS_PER_METER
	item.set_meta("representation", "metric_container_battery" if item.device_kind == "battery" else "metric_mv_platform_group")
	item.set_meta("geometry_assumption", str(dimensions.source_note))
	if item.device_kind == "battery":
		item.set_meta("soc_emblem_is_static", true)
	_combine_static_meshes(item, "MetricModuleGeometry")

static func _metric_box(item: EquipmentNode, parent: Node3D, label: String, size_m: Vector3, position_m: Vector3, material: Material) -> void:
	_box(item, parent, label, size_m * WORLD_UNITS_PER_METER, position_m * WORLD_UNITS_PER_METER, material)

static func _build_metric_pv(item: EquipmentNode, dimensions: Dictionary, p: Dictionary) -> void:
	var count: int = dimensions.panel_count
	var module := BoxMesh.new()
	module.size = dimensions.unit_dimensions_m * WORLD_UNITS_PER_METER
	var cells := PlaneMesh.new()
	cells.size = Vector2(dimensions.panel_width_m - 0.025, dimensions.panel_length_m - 0.025) * WORLD_UNITS_PER_METER
	var frames := SurfaceTool.new()
	frames.begin(Mesh.PRIMITIVE_TRIANGLES)
	var glass := SurfaceTool.new()
	glass.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(dimensions.tilt_deg))
	# Full physical panel count is rendered for normal installations. Extremely
	# large rejected/preview fields retain their exact envelope with a documented
	# coarse row representation rather than allocating millions of triangles.
	var detailed := count <= 32768
	if detailed:
		for index in count:
			var center: Vector3 = Spatial.panel_origin_m(dimensions, index) * WORLD_UNITS_PER_METER
			frames.append_from(module, 0, Transform3D(tilt, center))
			glass.append_from(cells, 0, Transform3D(tilt, center + tilt * Vector3(0, module.size.y * 0.51, 0)))
	else:
		var rows: int = dimensions.rows
		var columns: int = dimensions.columns
		for row in mini(rows, 4096):
			var start: Vector3 = Spatial.panel_origin_m(dimensions, row * columns) * WORLD_UNITS_PER_METER
			var row_count := mini(columns, count - row * columns)
			var length: float = ((row_count - 1) * dimensions.column_pitch_m + dimensions.panel_width_m) * WORLD_UNITS_PER_METER
			var strip := BoxMesh.new()
			strip.size = Vector3(length, module.size.y, module.size.z)
			var row_cells := PlaneMesh.new()
			row_cells.size = Vector2(length - 0.0025, cells.size.y)
			var center := start + Vector3((row_count - 1) * dimensions.column_pitch_m * WORLD_UNITS_PER_METER * 0.5, 0, 0)
			frames.append_from(strip, 0, Transform3D(tilt, center))
			glass.append_from(row_cells, 0, Transform3D(tilt, center + tilt * Vector3(0, module.size.y * 0.51, 0)))
	frames.set_material(p.metal)
	glass.set_material(p.solar)
	var batch := ArrayMesh.new()
	frames.commit(batch)
	glass.commit(batch)
	var mesh := MeshInstance3D.new()
	mesh.name = "PhysicalPVModules"
	mesh.mesh = batch
	item.add_child(mesh)
	_register_asset_meshes(item, mesh)
	# Sparse actual rack legs, not a node per panel. They are batched together
	# with the field and inverter below to keep the software-renderer draw count low.
	var leg := BoxMesh.new()
	var support := SurfaceTool.new()
	support.begin(Mesh.PRIMITIVE_TRIANGLES)
	var support_stride := maxi(3, int(ceil(float(count) / 4000.0)))
	for index in range(0, mini(count, 32768), support_stride):
		var center: Vector3 = Spatial.panel_origin_m(dimensions, index) * WORLD_UNITS_PER_METER
		var half_span: float = dimensions.panel_length_m * WORLD_UNITS_PER_METER * .32
		for side in [-1.0,1.0]:
			var top: Vector3 = center + tilt * Vector3(0,-.004,side*half_span)
			leg.size = Vector3(.008,top.y,.008)
			support.append_from(leg,0,Transform3D(Basis.IDENTITY,Vector3(top.x,top.y*.5,top.z)))
		leg.size = Vector3(.009,.012,dimensions.panel_length_m*WORLD_UNITS_PER_METER*.92)
		support.append_from(leg,0,Transform3D(tilt,center+tilt*Vector3(0,-.012,0)))
	support.set_material(p.metal)
	var rack := MeshInstance3D.new()
	rack.name = "PhysicalPVRacks"
	rack.mesh = support.commit()
	item.add_child(rack)
	_register_asset_meshes(item, rack)
	var body: Vector3 = dimensions.body_dimensions_m
	_metric_box(item, item, "FieldInverter", Vector3(1.2, 1.7, 0.6), Vector3(-body.x * 0.5 + 0.6, 0.85, body.z * 0.5 + 1.0), p.ivory)
	_metric_box(item, item, "FieldInverterDisplay", Vector3(0.55, 0.28, 0.02), Vector3(-body.x * 0.5 + 0.6, 1.3, body.z * 0.5 + 1.31), p.dark)
	item.port_local = Vector3(-body.x * 0.5 + 0.6, 0.85, body.z * 0.5 + 1.45) * WORLD_UNITS_PER_METER
	item.set_meta("module_area_m2", dimensions.module_area_m2)
	item.set_meta("module_surface_area_world", dimensions.module_area_m2 * WORLD_UNITS_PER_METER * WORLD_UNITS_PER_METER)
	item.set_meta("panel_count", count)
	item.set_meta("rendered_panel_count", count if detailed else 0)
	item.set_meta("field_representation", false)
	item.set_meta("visual_lod", "individual_metric_panels" if detailed else "metric_row_bands")
	item.set_meta("tilt_deg", dimensions.tilt_deg)
	item.set_meta("geometry_assumption", str(dimensions.source_note))
	_combine_static_meshes(item, "MetricPVField")

static func _relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var relative := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != null and cursor != ancestor:
		if cursor is Node3D:
			relative = cursor.transform * relative
		cursor = cursor.get_parent()
	return relative

static func _combine_static_meshes(item: EquipmentNode, label: String) -> void:
	var groups: Dictionary = {}
	for instance in item.surfaces:
		for slot in instance.mesh.get_surface_count():
			var material := instance.get_active_material(slot)
			if not groups.has(material):
				var builder := SurfaceTool.new()
				builder.begin(Mesh.PRIMITIVE_TRIANGLES)
				builder.set_material(material)
				groups[material] = builder
			groups[material].append_from(instance.mesh, slot, _relative_transform(instance, item))
	var combined := ArrayMesh.new()
	for builder: SurfaceTool in groups.values():
		builder.commit(combined)
	for instance in item.surfaces:
		instance.get_parent().remove_child(instance)
		instance.free()
	item.surfaces.clear()
	item.base_materials.clear()
	var mesh := MeshInstance3D.new()
	mesh.name = label
	mesh.mesh = combined
	item.add_child(mesh)
	_register_asset_meshes(item, mesh)

static func _rescale_procedural_unit(item: EquipmentNode, target: Vector3) -> void:
	var bounds := AABB()
	var found := false
	for mesh in item.surfaces:
		if mesh == item.selection_ring:
			continue
		var box: AABB = _relative_transform(mesh, item) * mesh.mesh.get_aabb()
		bounds = bounds.merge(box) if found else box
		found = true
	if not found or bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or bounds.size.z <= 0.0:
		return
	var factor := target / bounds.size
	for child in item.get_children():
		if child is Node3D:
			child.position *= factor
			child.scale *= factor
	item.port_local *= factor
	for port_id in item.named_port_locals:
		item.named_port_locals[port_id] *= factor

static func _build_metric_thermal_fallback(item: EquipmentNode, profile: Dictionary, dimensions: Dictionary) -> void:
	if item.device_kind == "solar_thermal":
		_build_metric_solar_thermal(item, dimensions)
		return
	var legacy_profile := profile.duplicate(true)
	legacy_profile.erase("visual_dimension_profile")
	for index in dimensions.module_origins_world.size():
		var module: EquipmentNode = create(item.device_kind, legacy_profile, false)
		module.surfaces.erase(module.selection_ring)
		module.base_materials.remove_at(module.base_materials.size() - 1)
		module.selection_ring.free()
		module.selection_ring = null
		if item.device_kind == "fuel_boiler":
			# Fuel fallback is also directly authored in metres. Convert once;
			# never fit/rescale a burner or flue to a requested capacity/footprint.
			module.scale = Vector3.ONE * WORLD_UNITS_PER_METER
		else:
			_rescale_procedural_unit(module, dimensions.unit_dimensions_m * WORLD_UNITS_PER_METER)
		module.name = "FallbackModule%03d" % (index + 1)
		module.position = dimensions.module_origins_world[index]
		item.add_child(module)
		item.surfaces.append_array(module.surfaces)
		item.base_materials.append_array(module.base_materials)
		if index == 0:
			for key in ["representation", "geometry_assumption", "thermal_boundary", "temperature_is_dynamic", "fixed_temperature_profile", "storage_approximation", "soc_changes_temperature", "fuel_type", "fuel_energy_basis"]:
				if module.has_meta(key):
					item.set_meta(key, module.get_meta(key))
			item.port = module.port
			item.port_local = _position_relative_to(module.port, item)
			item.named_ports = module.named_ports
			for port_id in module.named_ports:
				item.named_port_locals[port_id] = _position_relative_to(module.named_ports[port_id], item)
			item.thermal_soc_label = module.thermal_soc_label
		else:
			for label in module.find_children("*", "Label3D", true, false):
				label.set_meta("annotation_suppressed", true)
				label.visible = false
	item.set_meta("visual_backend", "metric_procedural_fallback")

static func _number(profile: Dictionary, names: Array, fallback: float) -> float:
	for key in names:
		if profile.has(key) and (profile[key] is int or profile[key] is float):
			var value := float(profile[key])
			if is_finite(value): return value
	for group in ["source_values", "design_assumptions", "parameters", "geometry"]:
		if profile.get(group) is Dictionary:
			var nested: Dictionary = profile[group]
			for key in names:
				if nested.has(key) and (nested[key] is int or nested[key] is float):
					var value := float(nested[key])
					if is_finite(value): return value
	return fallback

static func _material(color: Color, metallic := 0.0, glow := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.72
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow:
		material.emission_enabled = true
		material.emission = Color(color.r, color.g, color.b)
		material.emission_energy_multiplier = 0.45
	return material

static func _solar_material() -> StandardMaterial3D:
	# A shared cell texture adds fine busbars without hundreds of tiny meshes.
	if _solar_glass != null:
		return _solar_glass
	var image := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var cell_x := x % 32
			var cell_y := y % 32
			var shade := 0.015 * float((x / 32 + y / 32) % 3)
			var color := Color(0.035 + shade, 0.12 + shade, 0.23 + shade)
			if cell_x < 2 or cell_y < 2:
				color = Color("7893a2")
			elif cell_x == 10 or cell_x == 22:
				color = Color("526b80")
			image.set_pixel(x, y, color)
	image.generate_mipmaps()
	var material := _material(Color.WHITE, 0.48)
	material.albedo_texture = ImageTexture.create_from_image(image)
	material.roughness = 0.24
	material.clearcoat_enabled = true
	material.clearcoat = 0.65
	material.clearcoat_roughness = 0.18
	_solar_glass = material
	return material

static func _mesh(item: EquipmentNode, parent: Node3D, label: String, mesh: Mesh, position: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	parent.add_child(instance)
	item.surfaces.append(instance)
	item.base_materials.append(material)
	return instance

static func _box(item: EquipmentNode, parent: Node3D, label: String, size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(item, parent, label, mesh, position, material)

static func _cylinder(item: EquipmentNode, parent: Node3D, label: String, bottom: float, top: float, height: float, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 1
	return _mesh(item, parent, label, mesh, position, material)

static func _build_wind(item: EquipmentNode, profile: Dictionary, p: Dictionary) -> void:
	var requested_height := maxf(10.0, _number(profile, ["hub_height_m"], 90.0))
	var diameter := maxf(2.0, _number(profile, ["rotor_diameter_m", "nominal_rotor_diameter_m"], 126.0))
	var radius := diameter * WORLD_UNITS_PER_METER * 0.5
	# Invalid profiles must not bury blades; the source value stays inspectable.
	var hub_height := maxf(requested_height * WORLD_UNITS_PER_METER, radius + 0.6)
	item.set_meta("hub_height_m", requested_height)
	item.set_meta("rotor_diameter_m", diameter)
	item.set_meta("display_hub_height", hub_height)
	item.set_meta("world_units_per_meter", WORLD_UNITS_PER_METER)
	item.set_meta("footprint_radius", maxf(footprint("wind"), radius + 0.7))
	_box(item, item, "ServiceApron", Vector3(3.5, 0.06, 2.7), Vector3(0.35, 0.03, -0.15), p.gravel)
	_cylinder(item, item, "Foundation", 0.95, 0.95, 0.24, Vector3(0, 0.12, 0), p.concrete)
	_cylinder(item, item, "AnchorFlange", 0.53, 0.53, 0.09, Vector3(0, 0.285, 0), p.metal)
	var tower_height := hub_height - 0.3
	_cylinder(item, item, "Tower", 0.40, 0.22, tower_height, Vector3(0, 0.24 + tower_height / 2.0, 0), p.ivory)
	_box(item, item, "ServiceDoor", Vector3(0.26, 0.58, 0.06), Vector3(0, 0.55, -0.405), p.blue)
	_box(item, item, "DoorStep", Vector3(0.46, 0.12, 0.35), Vector3(0, 0.30, -0.55), p.metal)
	_box(item, item, "DoorHandle", Vector3(0.025, 0.10, 0.03), Vector3(0.085, 0.57, -0.45), p.ivory)
	_box(item, item, "Nacelle", Vector3(0.95, 0.6, 1.7), Vector3(0, hub_height, 0.20), p.ivory)
	_box(item, item, "NacelleStripe", Vector3(0.96, 0.14, 0.7), Vector3(0, hub_height, 0.70), p.blue)
	_box(item, item, "NacelleVent", Vector3(0.65, 0.27, 0.025), Vector3(0, hub_height, 1.065), p.dark)
	_cylinder(item, item, "AnemometerMast", 0.025, 0.025, 0.34, Vector3(0, hub_height + 0.46, 0.65), p.metal)
	_box(item, item, "WindVane", Vector3(0.33, 0.055, 0.08), Vector3(0, hub_height + 0.64, 0.65), p.metal)
	item.rotor = Node3D.new()
	item.rotor.name = "Rotor"
	item.rotor.position = Vector3(0, hub_height, -0.85)
	item.add_child(item.rotor)
	var hub := _cylinder(item, item.rotor, "Hub", 0.33, 0.17, 0.50, Vector3(0, 0, -0.1), p.ivory)
	hub.rotation.x = PI * 0.5
	for index in 3:
		var blade := _mesh(item, item.rotor, "Blade%d" % (index + 1), _blade_mesh(radius), Vector3.ZERO, p.ivory)
		blade.rotation.z = float(index) * TAU / 3.0
		blade.set_meta("rotor_blade", true)
		var tip := _box(item, blade, "Tip", Vector3(0.105, radius * 0.08, 0.105), Vector3(-0.075, radius * 0.94, 0), p.blue)
		tip.rotation.z = -0.035
	_box(item, item, "Converter", Vector3(0.70, 1.0, 0.60), Vector3(1.15, 0.5, 0), p.green)
	_box(item, item, "ConverterVent", Vector3(0.46, 0.24, 0.025), Vector3(1.15, 0.25, -0.315), p.dark)
	_box(item, item, "TowerCableDuct", Vector3(.87,.08,.18), Vector3(.66,.10,0), p.metal)
	_box(item, item, "ConverterTermination", Vector3(.15,.14,.14), Vector3(1.15,.65,-.31), p.metal)
	for bolt in 12:
		var angle := float(bolt)*TAU/12.0
		_cylinder(item,item,"TowerAnchorBolt",.018,.018,.065,Vector3(.47*cos(angle),.36,.47*sin(angle)),p.metal)
	item.port_local = Vector3(1.15, 0.65, -0.37)
	item.set_operating(0.75)

static func _blade_mesh(radius: float) -> ArrayMesh:
	# Closed, tapered airfoil silhouette, extending out of the hub along +Y.
	var outline := PackedVector2Array([
		Vector2(-0.13, 0.24), Vector2(-0.28, radius * 0.18),
		Vector2(-0.20, radius * 0.60), Vector2(-0.11, radius),
		Vector2(-0.025, radius), Vector2(0.14, radius * 0.55),
		Vector2(0.31, radius * 0.18), Vector2(0.13, 0.24),
	])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var depth := 0.06
	for side in [-1.0, 1.0]:
		for i in range(1, outline.size() - 1):
			var ids: Array = [0, i, i + 1] if side > 0 else [0, i + 1, i]
			for index in ids:
				st.add_vertex(Vector3(outline[index].x, outline[index].y, side * depth))
	for i in outline.size():
		var j := (i + 1) % outline.size()
		var a := Vector3(outline[i].x, outline[i].y, -depth)
		var b := Vector3(outline[j].x, outline[j].y, -depth)
		var c := Vector3(outline[j].x, outline[j].y, depth)
		var d := Vector3(outline[i].x, outline[i].y, depth)
		for point in [a, b, c, a, c, d]: st.add_vertex(point)
	st.generate_normals()
	st.index()
	return st.commit()

static func _build_pv(item: EquipmentNode, profile: Dictionary, p: Dictionary) -> void:
	var area := maxf(1.0, _number(profile, ["module_area_m2", "panel_area_m2", "array_area_m2"], 16000.0))
	var tilt := deg_to_rad(clampf(_number(profile, ["tilt_deg", "panel_tilt_deg"], 25.0), 0.0, 75.0))
	var side := clampf(sqrt(area / 12.0) * 0.045, 0.55, 1.65)
	item.set_meta("module_area_m2", area)
	item.set_meta("module_surface_area_world", side * side * 12.0)
	item.set_meta("world_units_per_meter", sqrt(side * side * 12.0 / area))
	item.set_meta("field_representation", true)
	item.set_meta("tilt_deg", rad_to_deg(tilt))
	_box(item, item, "FieldGravel", Vector3(7.0, 0.045, 6.2), Vector3(0, 0.0225, 0), p.gravel)
	for row in 3:
		for col in 4:
			var x := (float(col) - 1.5) * (side + 0.24)
			var z := (float(row) - 1.0) * (side + 0.52)
			var center_y := 0.48 + sin(tilt) * side * 0.5
			var frame := Node3D.new()
			frame.name = "Panel_%d_%d" % [row, col]
			frame.position = Vector3(x, center_y, z)
			frame.rotation.x = tilt
			item.add_child(frame)
			_box(item, frame, "Frame", Vector3(side + 0.06, 0.08, side + 0.06), Vector3.ZERO, p.metal)
			var glass := _box(item, frame, "Cells", Vector3(side, 0.016, side), Vector3(0, 0.049, 0), p.solar)
			glass.set_meta("pv_panel", true)
			for grid in range(1, 4):
				var offset := (float(grid) / 4.0 - 0.5) * side
				_box(item, frame, "CellRow%d" % grid, Vector3(side, 0.004, 0.009), Vector3(0, 0.060, offset), p.metal)
				_box(item, frame, "CellCol%d" % grid, Vector3(0.009, 0.004, side), Vector3(offset, 0.060, 0), p.metal)
			for end in [-1.0, 1.0]:
				var local_z: float = end * side * 0.34
				var leg_height: float = center_y - sin(tilt) * local_z - 0.06
				_cylinder(item, item, "Support_%d_%d_%d" % [row, col, int(end)], 0.055, 0.055, leg_height, Vector3(x, leg_height / 2.0, z + cos(tilt) * local_z), p.metal)
	_box(item, item, "Inverter", Vector3(0.70, 0.75, 0.45), Vector3(3.75, 0.375, 0), p.ivory)
	_box(item, item, "InverterPlinth", Vector3(0.95, 0.09, 0.70), Vector3(3.75, 0.045, 0), p.concrete)
	_box(item, item, "InverterVent", Vector3(0.43, 0.17, 0.025), Vector3(3.75, 0.18, -0.235), p.dark)
	_box(item, item, "InverterStatus", Vector3(0.3, 0.10, 0.02), Vector3(3.75, 0.58, -0.235), p.green)
	item.port_local = Vector3(3.75, 0.38, -0.30)

static func _build_station(item: EquipmentNode, _profile: Dictionary, p: Dictionary) -> void:
	_box(item, item, "Foundation", Vector3(5.8, 0.16, 4.7), Vector3(0, 0.08, 0), p.concrete)
	_box(item, item, "GravelBed", Vector3(5.25, 0.035, 3.9), Vector3(0, 0.1775, 0), p.gravel)
	_box(item, item, "TransformerPlinth", Vector3(2.75, 0.16, 2.05), Vector3(-0.55, 0.25, 0), p.dark)
	_box(item, item, "Transformer", Vector3(2.4, 1.6, 1.65), Vector3(-0.55, 1.03, 0), p.green)
	_box(item, item, "TransformerCap", Vector3(2.6, 0.18, 1.8), Vector3(-0.55, 1.88, 0), p.ivory)
	var conservator := _cylinder(item, item, "OilConservator", 0.23, 0.23, 1.85, Vector3(-0.55, 2.26, 0.62), p.green)
	conservator.rotation.z = PI * 0.5
	for x in [-1.15, 0.05]:
		_box(item, item, "TankBracket", Vector3(0.09, 0.30, 0.12), Vector3(x, 2.04, 0.62), p.metal)
	_box(item, item, "Nameplate", Vector3(0.43, 0.21, 0.025), Vector3(-0.55, 1.51, -0.838), p.ivory)
	for index in 8:
		var x := -1.55 + index * 0.285
		_box(item, item, "CoolingFin%d" % index, Vector3(0.10, 1.2, 0.28), Vector3(x, 1.02, -0.90), p.metal)
		_box(item, item, "RearCoolingFin%d" % index, Vector3(0.10, 1.2, 0.28), Vector3(x, 1.02, 0.90), p.metal)
	for index in 3:
		var x := -1.30 + index * 0.72
		_cylinder(item, item, "Bushing%d" % index, 0.10, 0.07, 0.72, Vector3(x, 2.25, 0), p.ivory)
		for disc in 4:
			_cylinder(item, item, "Insulator%d_%d" % [index, disc], 0.16, 0.12, 0.055, Vector3(x, 2.03 + disc * 0.13, 0), p.porcelain)
		_cylinder(item, item, "BushingTerminal%d" % index, 0.055, 0.055, 0.15, Vector3(x, 2.66, 0), p.metal)
	_box(item, item, "SwitchCabinet", Vector3(0.95, 1.5, 1.1), Vector3(1.65, 0.91, 0.1), p.ivory)
	_box(item, item, "CabinetDoor", Vector3(0.76, 1.20, 0.025), Vector3(1.65, 0.93, -0.463), p.metal)
	_box(item, item, "StatusLamp", Vector3(0.20, 0.08, 0.028), Vector3(1.65, 1.30, -0.486), p.green)
	_box(item, item, "CabinetHandle", Vector3(0.035, 0.23, 0.055), Vector3(1.92, 0.96, -0.50), p.dark)
	# Open front gate makes the single electrical terminal accessible.
	for side in [-1.0, 1.0]:
		for index in 5:
			var z := -2.15 + index * 1.075
			_cylinder(item, item, "FenceSide_%d_%d" % [int(side), index], 0.035, 0.035, 0.90, Vector3(side * 2.75, 0.61, z), p.metal)
		for height in [0.52, 0.95]:
			_box(item, item, "FenceRailSide", Vector3(0.045, 0.04, 4.3), Vector3(side * 2.75, height, 0), p.metal)
	for index in 6:
		_cylinder(item, item, "FenceBack%d" % index, 0.035, 0.035, 0.90, Vector3(-2.75 + index * 1.1, 0.61, 2.15), p.metal)
	for height in [0.52, 0.95]:
		_box(item, item, "FenceRailBack", Vector3(5.5, 0.04, 0.045), Vector3(0, height, 2.15), p.metal)
		for side in [-1.0, 1.0]:
			_box(item, item, "GateRail", Vector3(1.65, 0.04, 0.045), Vector3(side * 1.925, height, -2.15), p.metal)
	item.port_local = Vector3(0, 0.45, -2.45)

## A compact connection marker for existing electrical demand, not a factory.
## It adds no demand or capacity. The legacy footprint and cable endpoint stay
## unchanged so loading an existing scene cannot move connected cable ends.
static func _build_load(item: EquipmentNode, _profile: Dictionary, p: Dictionary) -> void:
	item.set_meta("representation", "demand_connection_marker")
	item.set_meta("geometry_assumption", "Fixed-size demand connection marker, not a factory or demand-scaled building; no new demand added")
	item.set_meta("is_factory", false)
	item.set_meta("demand_added", 0.0)
	_cylinder(item, item, "DemandBasePlate", 1.60, 1.60, 0.20, Vector3(0, 0.10, 0), p.concrete)
	_cylinder(item, item, "DemandBaseInset", 1.43, 1.43, 0.045, Vector3(0, 0.2225, 0), p.dark)
	var ring := TorusMesh.new()
	ring.inner_radius = 1.43
	ring.outer_radius = 1.57
	ring.rings = 32
	ring.ring_segments = 6
	_mesh(item, item, "DemandBaseRing", ring, Vector3(0, 0.25, 0), p.green)
	_cylinder(item, item, "DemandPoleFoot", 0.32, 0.32, 0.12, Vector3(0, 0.305, 0.16), p.metal)
	_cylinder(item, item, "DemandPole", 0.12, 0.10, 2.45, Vector3(0, 1.59, 0.16), p.ivory)
	_cylinder(item, item, "DemandPoleCap", 0.17, 0.17, 0.08, Vector3(0, 2.855, 0.16), p.metal)
	# A freestanding downward arrow denotes power entering the demand node.
	_box(item, item, "DemandArrowStem", Vector3(0.22, 0.78, 0.20), Vector3(0, 2.43, -0.10), p.green)
	_cylinder(item, item, "DemandArrowHead", 0.0, 0.48, 0.56, Vector3(0, 1.79, -0.10), p.green)
	_box(item, item, "DemandMeterPanel", Vector3(0.80, 0.62, 0.24), Vector3(0, 1.15, -0.03), p.metal)
	_box(item, item, "DemandMeterDisplay", Vector3(0.56, 0.22, 0.03), Vector3(0, 1.22, -0.165), p.dark)
	for index in 3:
		_box(item, item, "DemandMeterTick%d" % index, Vector3(0.09, 0.08, 0.035), Vector3(-0.16 + index * 0.16, 1.22, -0.185), p.ivory)
	_box(item, item, "DemandMeterLabel", Vector3(0.40, 0.05, 0.035), Vector3(0, 0.99, -0.165), p.ivory)
	# A low conduit reaches the original exposed terminal without a building.
	_box(item, item, "DemandTerminalConduit", Vector3(0.12, 0.07, 1.30), Vector3(0.95, 0.15, -1.48), p.metal)
	_box(item, item, "DemandTerminalFoot", Vector3(0.58, 0.12, 0.58), Vector3(0.95, 0.06, -2.06), p.concrete)
	_box(item, item, "DemandTerminalBollard", Vector3(0.38, 0.55, 0.38), Vector3(0.95, 0.395, -2.06), p.metal)
	item.port_local = Vector3(0.95, 0.52, -2.39)

static func _sawtooth_mesh(width: float, height: float, depth: float) -> ArrayMesh:
	var a := Vector3(-width * 0.5, 0.0, -depth * 0.5)
	var b := Vector3(-width * 0.5, height, -depth * 0.5)
	var c := Vector3(width * 0.5, 0.0, -depth * 0.5)
	var d := a + Vector3(0.0, 0.0, depth)
	var e := b + Vector3(0.0, 0.0, depth)
	var f := c + Vector3(0.0, 0.0, depth)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	# Clockwise front faces follow Godot's mesh winding convention.
	for vertex in [a, c, b, d, e, f, a, b, e, a, e, d, b, c, f, b, f, e, a, d, f, a, f, c]:
		surface.add_vertex(vertex)
	surface.generate_normals()
	surface.index()
	return surface.commit()

## Containerized battery with independent cabinet geometry. The three bars are
## an equipment emblem, not a live SOC gauge; energy state belongs to the model.
static func _build_battery(item: EquipmentNode, _profile: Dictionary, p: Dictionary) -> void:
	item.set_meta("representation", "container_battery")
	item.set_meta("geometry_assumption", "Stylized battery container; fixed display footprint, not capacity-scaled")
	item.set_meta("soc_emblem_is_static", true)
	_box(item, item, "BatteryFoundation", Vector3(6.6, 0.16, 4.0), Vector3(0, 0.08, 0), p.concrete)
	_box(item, item, "ContainerBase", Vector3(5.85, 0.23, 2.95), Vector3(-0.1, 0.275, 0.15), p.dark)
	_box(item, item, "BatteryContainer", Vector3(5.6, 2.25, 2.7), Vector3(-0.1, 1.495, 0.15), p.ivory)
	_box(item, item, "ContainerRoof", Vector3(5.85, 0.14, 2.94), Vector3(-0.1, 2.68, 0.15), p.ivory)
	for side in [-1.0, 1.0]:
		for index in 13:
			var x := -2.73 + float(index) * 0.44
			_box(item, item, "ContainerRib_%d_%d" % [int(side), index], Vector3(0.045, 1.98, 0.055), Vector3(x, 1.48, 0.15 + side * 1.37), p.metal)
	# Service doors occupy the front; each has an independent locking bar.
	for index in 2:
		var x := 0.8 + float(index) * 1.10
		_box(item, item, "ServiceDoor%d" % index, Vector3(0.98, 1.90, 0.06), Vector3(x, 1.43, -1.255), p.green)
		_box(item, item, "DoorLock%d" % index, Vector3(0.035, 1.55, 0.055), Vector3(x + 0.28, 1.43, -1.315), p.dark)
		_box(item, item, "DoorHandle%d" % index, Vector3(0.22, 0.045, 0.07), Vector3(x + 0.20, 1.36, -1.35), p.ivory)
	_box(item, item, "BatteryEmblem", Vector3(1.65, 1.08, 0.08), Vector3(-1.55, 1.60, -1.27), p.dark)
	_box(item, item, "BatteryEmblemCap", Vector3(0.15, 0.40, 0.08), Vector3(-0.65, 1.60, -1.27), p.dark)
	for index in 3:
		_box(item, item, "BatteryEmblemCell%d" % index, Vector3(0.32, 0.69, 0.035), Vector3(-2.02 + index * 0.48, 1.60, -1.325), p.green)
	_box(item, item, "CoolingUnit", Vector3(0.32, 1.30, 1.65), Vector3(2.85, 1.43, 0.32), p.metal)
	for index in 8:
		_box(item, item, "CoolingLouver%d" % index, Vector3(0.035, 0.045, 1.34), Vector3(3.025, 0.94 + index * 0.14, 0.32), p.dark)
	_box(item, item, "BatteryController", Vector3(0.50, 0.43, 0.08), Vector3(-1.55, 0.71, -1.28), p.metal)
	_box(item, item, "ControllerDisplay", Vector3(0.31, 0.15, 0.025), Vector3(-1.55, 0.75, -1.335), p.blue)
	item.port_local = Vector3(-2.55, 0.57, -1.56)

## The legacy five device meshes and electrical marker stay unchanged. Named
## aliases only let new callers address their existing AC terminal explicitly.
static func _register_legacy_port_names(item: EquipmentNode) -> void:
	var ids: Array = []
	match item.device_kind:
		"wind", "pv": ids = ["out"]
		"station": ids = ["in", "out"]
		"load": ids = ["in"]
		"battery": ids = ["ac"]
	for port_id in ids:
		item.named_port_locals[port_id] = item.port_local
		item.named_ports[port_id] = item.port

static func _thermal_metadata(item: EquipmentNode, representation: String) -> void:
	item.set_meta("representation", representation)
	item.set_meta("geometry_assumption", "原创教学示意；固定显示尺寸，不按额定功率缩放")
	item.set_meta("thermal_boundary", "已充水、固定工作点；循环辅机包含在设备等效效率内；热连接代表一组供回水服务")
	item.set_meta("temperature_is_dynamic", false)

static func _thermal_label(parent: Node3D, label: String, text: String, position: Vector3, size: int = 38) -> Label3D:
	var marker := Label3D.new()
	marker.name = label
	marker.text = text
	marker.font = load("res://assets/InterfaceCJK.ttc")
	marker.font_size = size
	# Keep requested text compact at both the base-map and close interior camera.
	# Ancestor scaling in the procedural fallback must not resize screen text.
	marker.pixel_size = 0.0006
	marker.fixed_size = true
	marker.set_disable_scale(true)
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.modulate = Color("fcf8e9")
	marker.outline_modulate = Color("243f47")
	marker.outline_size = 8
	marker.position = position
	parent.add_child(marker)
	return marker

static func _named_terminal(item: EquipmentNode, p: Dictionary, port_id: String, local: Vector3, direction: String, grade: String = "") -> void:
	var terminal := Node3D.new()
	terminal.name = "Port_" + port_id
	terminal.position = local
	item.add_child(terminal)
	_register_named_terminal(item, terminal, port_id, local, direction, grade)
	var electric := grade.is_empty()
	var primary := grade == "hw_primary_90_60"
	var tint: Material = p.blue if electric else (p.heat_primary if primary else p.heat_secondary)
	_box(item, terminal, "TerminalPad", Vector3(0.68, 0.13, 0.56), Vector3(0, -0.33, 0), p.dark)
	if electric:
		_box(item, terminal, "ACSquare", Vector3(0.40, 0.40, 0.28), Vector3.ZERO, tint)
		_box(item, terminal, "ACSocket", Vector3(0.20, 0.11, 0.04), Vector3(0, 0, -0.16), p.ivory)
	else:
		# One hexagonal flange for the primary grade; a second nested ring for
		# the secondary grade, so colour is never the only distinguishing cue.
		var ring := TorusMesh.new()
		ring.inner_radius = 0.17
		ring.outer_radius = 0.30
		ring.rings = 6
		ring.ring_segments = 6
		var flange := _mesh(item, terminal, "PrimaryHexFlange" if primary else "SecondaryOuterFlange", ring, Vector3.ZERO, tint)
		flange.rotation.x = PI * 0.5
		if not primary:
			var inner := TorusMesh.new()
			inner.inner_radius = 0.07
			inner.outer_radius = 0.12
			inner.rings = 12
			inner.ring_segments = 6
			var inset := _mesh(item, terminal, "SecondaryInnerFlange", inner, Vector3(0, 0, -0.04), p.ivory)
			inset.rotation.x = PI * 0.5
	var arrow := _cylinder(item, terminal, "DirectionArrow", 0.13, 0.0, 0.22, Vector3(0, -0.17, -0.43), tint)
	arrow.rotation.x = -PI * 0.5 if direction == "output" else PI * 0.5
	_add_thermal_port_label(terminal, direction, grade)

static func _register_named_terminal(item: EquipmentNode, terminal: Node3D, port_id: String, local: Vector3, direction: String, grade: String = "") -> void:
	var electric := grade.is_empty()
	terminal.set_meta("port_id", port_id)
	terminal.set_meta("direction", direction)
	terminal.set_meta("carrier", "electricity_ac" if electric else "heat_water")
	terminal.set_meta("unit", "MW" if electric else "MWth")
	terminal.set_meta("port_type", "electricity" if electric else "heat_water")
	if electric:
		terminal.set_meta("voltage_level", "AC_BUS")
	else:
		terminal.set_meta("grade_id", grade)
	item.named_port_locals[port_id] = local
	item.named_ports[port_id] = terminal
	if item.port == null:
		item.port = terminal
		item.port_local = local

static func _add_thermal_port_label(terminal: Node3D, direction: String, grade: String, metric: bool = false) -> void:
	var caption := ("电AC" if grade.is_empty() else ("热90" if grade == "hw_primary_90_60" else "热70")) + (" 出" if direction == "output" else " 入")
	var label := _thermal_label(terminal, "PortLabel", caption, Vector3(0, 0.07, -0.02) if metric else Vector3(0, 0.57, -0.18), 32)
	if metric:
		label.pixel_size = 0.00055

## Electric resistance hot-water skid: horizontal insulated vessel, switchboard
## and zigzag heating emblem. There is deliberately no stack or steam turbine.
static func _build_electric_boiler(item: EquipmentNode, _profile: Dictionary, p: Dictionary) -> void:
	_thermal_metadata(item, "electric_hot_water_skid")
	item.set_meta("fixed_temperature_profile", "90/60°C")
	_box(item, item, "BoilerSkid", Vector3(5.5, 0.18, 3.4), Vector3(0, 0.09, 0), p.concrete)
	for x in [-1.0, 1.0]:
		_box(item, item, "VesselSaddle", Vector3(0.25, 0.75, 1.4), Vector3(x, 0.55, 0.22), p.metal)
	var vessel := _cylinder(item, item, "InsulatedHotWaterVessel", 0.85, 0.85, 3.2, Vector3(0, 1.55, 0.25), p.ivory)
	vessel.rotation.z = PI * 0.5
	for x in [-1.30, 1.30]:
		var band := _cylinder(item, item, "VesselBand", 0.875, 0.875, 0.10, Vector3(x, 1.55, 0.25), p.metal)
		band.rotation.z = PI * 0.5
	_box(item, item, "ElectricControlCabinet", Vector3(0.85, 1.75, 0.75), Vector3(-2.03, 1.07, 0.20), p.blue)
	_box(item, item, "ControlDisplay", Vector3(0.47, 0.30, 0.03), Vector3(-2.03, 1.49, -0.19), p.dark)
	_box(item, item, "HeaterEmblemBack", Vector3(1.30, 0.72, 0.08), Vector3(0.05, 1.57, -0.62), p.dark)
	for index in 5:
		var stroke := _box(item, item, "ResistanceStroke%d" % index, Vector3(0.10, 0.45, 0.045), Vector3(-0.43 + index * 0.24, 1.57, -0.68), p.heat_primary)
		stroke.rotation.z = 0.48 if index % 2 == 0 else -0.48
	_box(item, item, "HotServiceManifold", Vector3(0.22, 1.15, 0.22), Vector3(2.20, 0.78, 0.20), p.heat_primary)
	_box(item, item, "HotServiceOutlet", Vector3(0.22, 0.22, 1.80), Vector3(2.20, 0.65, -0.70), p.heat_primary)
	_thermal_label(item, "ProfileLabel", "电热水 · 90/60°C", Vector3(0, 2.75, 0.1), 34)
	_named_terminal(item, p, "ac_in", Vector3(-2.10, 0.65, -1.85), "input")
	_named_terminal(item, p, "heat_out", Vector3(2.20, 0.65, -1.85), "output", "hw_primary_90_60")

## One gas-fired hot-water unit, directly authored in metres. The distinct
## burner, gas train and vertical flue never imply steam or electricity output.
static func _fuel_boiler_metadata(item: EquipmentNode) -> void:
	_thermal_metadata(item, "natural_gas_hot_water_skid")
	item.set_meta("fixed_temperature_profile", "90/60°C")
	item.set_meta("fuel_type", "natural_gas")
	item.set_meta("fuel_energy_basis", "LHV")
	item.set_meta("thermal_boundary", "已充水、固定90/60°C热水工作点；燃料与辅助用电分别计量；循环辅机Paux=auxiliary_electric_ratio×燃料LHV输入；不产蒸汽")
	item.set_meta("geometry_assumption", "米制原创燃气热水底撬；厂家外形量级参考，非厂家CAD；扩容增加等尺寸模块，绝不缩小设备塞入场地")

static func _build_fuel_boiler(item: EquipmentNode, _profile: Dictionary, p: Dictionary) -> void:
	_fuel_boiler_metadata(item)
	_box(item, item, "FuelBoilerSkid", Vector3(5.0, 0.15, 3.0), Vector3(0, 0.075, 0), p.concrete)
	_box(item, item, "InsulatedHotWaterShell", Vector3(3.48, 1.73, 1.51), Vector3(0.05, 1.165, 0.10), p.ivory)
	for x in [-1.15, 1.15]:
		_box(item, item, "BoilerBearingRail", Vector3(0.25, 0.20, 1.40), Vector3(x, 0.25, 0.10), p.metal)
	var door := _cylinder(item, item, "CombustionAccessDoor", 0.64, 0.64, 0.10, Vector3(-1.74, 1.18, 0.10), p.dark)
	door.rotation.z = PI * 0.5
	_box(item, item, "ForcedDraftBurner", Vector3(0.60, 0.73, 0.69), Vector3(-2.12, 1.13, -0.05), p.blue)
	var fan := _cylinder(item, item, "BurnerFanInlet", 0.28, 0.28, 0.04, Vector3(-2.44, 1.13, -0.05), p.dark)
	fan.rotation.z = PI * 0.5
	_box(item, item, "NaturalGasTrain", Vector3(1.60, 0.13, 0.13), Vector3(-1.43, 0.62, -0.94), p.heat_secondary)
	_box(item, item, "BurnerGasFeed", Vector3(0.13, 0.13, 0.71), Vector3(-2.16, 0.62, -0.60), p.heat_secondary)
	for x in [-1.82, -1.27]:
		_box(item, item, "GasSafetyValve", Vector3(0.22, 0.38, 0.22), Vector3(x, 0.75, -0.94), p.metal)
	var flue_connector := _cylinder(item, item, "CombustionFlueConnector", 0.20, 0.20, 0.37, Vector3(1.935, 1.12, 0.58), p.metal)
	flue_connector.rotation.z = PI * 0.5
	_cylinder(item, item, "FlueStack", 0.20, 0.20, 3.32, Vector3(2.10, 2.66, 0.58), p.metal)
	_cylinder(item, item, "FlueRainCap", 0.29, 0.05, 0.10, Vector3(2.10, 4.45, 0.58), p.metal)
	_box(item, item, "HotWaterSupplyRiser", Vector3(0.19, 1.73, 0.19), Vector3(1.84, 1.43, 0.10), p.heat_primary)
	_box(item, item, "HotWaterSupplyPipe", Vector3(0.19, 0.19, 1.49), Vector3(1.84, 0.63, -0.60), p.heat_primary)
	_box(item, item, "WaterReturnRiser", Vector3(0.15, 1.84, 0.15), Vector3(1.54, 1.34, 0.10), p.heat_return)
	_box(item, item, "WaterReturnPipe", Vector3(0.15, 0.15, 1.40), Vector3(1.54, 0.43, -0.57), p.heat_return)
	_box(item, item, "AuxiliaryControlCabinet", Vector3(0.63, 1.30, 0.48), Vector3(0.61, 0.90, -1.02), p.blue)
	_box(item, item, "AuxiliaryControlDisplay", Vector3(0.37, 0.19, 0.025), Vector3(0.61, 1.12, -1.273), p.dark)
	_thermal_label(item, "ProfileLabel", "燃气热水 · 90/60°C", Vector3(0, 2.62, -0.25), 34)
	_named_terminal(item, p, "ac_in", Vector3(-0.15, 0.56, -1.34), "input")
	_named_terminal(item, p, "heat_out", Vector3(1.84, 0.63, -1.34), "output", "hw_primary_90_60")
	for terminal in item.named_ports.values():
		# Small fittings remain entirely within the 5×3 m skid, not a third inlet.
		terminal.scale = Vector3.ONE * 0.25

## Twin fixed-zone silhouettes show the stratified/two-zone approximation only.
## Runtime energy is confined to the separate SOC plaque, never a tank colour,
## a moving thermocline, a liquid level, or an interpolated actual temperature.
static func _build_thermal_store(item: EquipmentNode, _profile: Dictionary, p: Dictionary) -> void:
	_thermal_metadata(item, "fixed_grade_two_zone_heat_store")
	item.set_meta("fixed_temperature_profile", "90/60°C")
	item.set_meta("storage_approximation", "理想分层/双区等效库存；固定供水品质；非完全混合水箱")
	item.set_meta("soc_changes_temperature", false)
	_box(item, item, "ThermalStoreFoundation", Vector3(5.8, 0.18, 4.2), Vector3(0, 0.09, 0), p.concrete)
	for index in 2:
		var x: float = -1.28 + index * 2.56
		_cylinder(item, item, "TankFoot%d" % index, 1.09, 1.09, 0.22, Vector3(x, 0.29, 0.15), p.dark)
		_cylinder(item, item, "FixedReturnZone%d" % index, 1.0, 1.0, 1.40, Vector3(x, 1.10, 0.15), p.heat_return)
		_cylinder(item, item, "FixedZoneDivider%d" % index, 1.04, 1.04, 0.12, Vector3(x, 1.86, 0.15), p.metal)
		_cylinder(item, item, "FixedSupplyZone%d" % index, 1.0, 1.0, 1.40, Vector3(x, 2.62, 0.15), p.heat_primary)
		_cylinder(item, item, "TankInsulatedCap%d" % index, 1.05, 0.92, 0.22, Vector3(x, 3.43, 0.15), p.ivory)
		for z in [-0.50, 0.80]:
			_box(item, item, "TankInsulationStrap", Vector3(0.10, 2.92, 0.08), Vector3(x - 0.75, 1.86, z), p.ivory)
	_box(item, item, "SOCMeterPlate", Vector3(2.8, 0.63, 0.12), Vector3(0, 1.55, -1.26), p.dark)
	item.thermal_soc_label = _thermal_label(item, "ThermalSOC", "库存 SOC —", Vector3(0, 1.55, -1.35), 33)
	# This camera-facing inventory annotation must not intersect its fixed
	# physical plaque when viewed obliquely. It is a UI gauge, not tank geometry.
	item.thermal_soc_label.no_depth_test = true
	_thermal_label(item, "ProfileLabel", "90/60°C · 固定双区", Vector3(0, 3.98, 0), 34)
	for x in [-2.25, 2.25]:
		_box(item, item, "StoreServiceManifold", Vector3(0.20, 0.20, 1.10), Vector3(x, 0.65, -1.32), p.heat_primary)
	_named_terminal(item, p, "heat_in", Vector3(-2.25, 0.65, -2.04), "input", "hw_primary_90_60")
	_named_terminal(item, p, "heat_out", Vector3(2.25, 0.65, -2.04), "output", "hw_primary_90_60")

## Plate-and-frame exchanger, with separate hot and warm manifolds and a visible
## mechanical divider. Its geometry never implies direct primary/secondary mix.
static func _build_heat_exchanger(item: EquipmentNode, _profile: Dictionary, p: Dictionary) -> void:
	_thermal_metadata(item, "isolated_plate_heat_exchanger")
	item.set_meta("fixed_temperature_profile", "90/60→70/40°C")
	_box(item, item, "ExchangerSkid", Vector3(5.5, 0.18, 3.7), Vector3(0, 0.09, 0), p.concrete)
	for x in [-1.50, 1.50]:
		_box(item, item, "ExchangerFoot", Vector3(0.35, 0.30, 2.2), Vector3(x, 0.32, 0.20), p.dark)
		_box(item, item, "FrameEndPlate", Vector3(0.22, 2.35, 1.95), Vector3(x, 1.55, 0.20), p.metal)
	for index in 9:
		var x: float = -1.20 + index * 0.30
		_box(item, item, "HeatTransferPlate%d" % index, Vector3(0.12, 1.95, 1.65), Vector3(x, 1.55, 0.20), p.ivory)
		_box(item, item, "PlateFrontRidge%d" % index, Vector3(0.16, 1.62, 0.08), Vector3(x, 1.55, -0.66), p.metal)
	for height in [0.65, 2.48]:
		_box(item, item, "TieBar", Vector3(3.60, 0.10, 0.10), Vector3(0, height, -0.84), p.dark)
	for index in 2:
		var x: float = -2.15 if index == 0 else 2.15
		var tint: Material = p.heat_primary if index == 0 else p.heat_secondary
		_box(item, item, "IsolatedManifold%d" % index, Vector3(0.28, 1.55, 0.28), Vector3(x, 1.15, -0.45), tint)
		_box(item, item, "ServicePair%d" % index, Vector3(0.28, 0.28, 1.3), Vector3(x, 0.65, -1.20), tint)
	_thermal_label(item, "ProfileLabel", "隔离换热 · 90/60→70/40°C", Vector3(0, 3.15, 0), 32)
	_named_terminal(item, p, "hot_in", Vector3(-2.15, 0.65, -1.95), "input", "hw_primary_90_60")
	_named_terminal(item, p, "warm_out", Vector3(2.15, 0.65, -1.95), "output", "hw_secondary_70_40")

## Abstract thermal service request marker, not an additional factory. It has a
## hexagonal base and three heat-wave strokes, distinct from the electric load.
static func _build_heat_demand(item: EquipmentNode, _profile: Dictionary, p: Dictionary) -> void:
	_thermal_metadata(item, "thermal_demand_connection_marker")
	item.set_meta("is_factory", false)
	item.set_meta("demand_added", 0.0)
	item.set_meta("fixed_temperature_profile", "70/40°C")
	var base := _cylinder(item, item, "HeatDemandHexBase", 1.55, 1.55, 0.20, Vector3(0, 0.10, 0), p.concrete)
	(base.mesh as CylinderMesh).radial_segments = 6
	_cylinder(item, item, "HeatDemandInset", 1.20, 1.20, 0.07, Vector3(0, 0.235, 0), p.dark)
	for x in [-0.83, 0.83]:
		_box(item, item, "DemandSignPost", Vector3(0.11, 2.25, 0.12), Vector3(x, 1.40, 0.10), p.metal)
	_box(item, item, "HeatDemandSign", Vector3(2.0, 1.45, 0.18), Vector3(0, 2.12, 0.08), p.dark)
	for column in 3:
		for index in 3:
			var wave := _box(item, item, "HeatWave%d_%d" % [column, index], Vector3(0.10, 0.28, 0.06), Vector3(-0.50 + column * 0.50, 1.87 + index * 0.23, -0.04), p.heat_secondary)
			wave.rotation.z = 0.40 if index % 2 == 0 else -0.40
	_cylinder(item, item, "HeatRequestArrow", 0.0, 0.34, 0.46, Vector3(0, 1.12, 0.0), p.heat_secondary)
	_thermal_label(item, "ProfileLabel", "热需求 · 70/40°C", Vector3(0, 3.22, 0), 34)
	_box(item, item, "DemandServicePair", Vector3(0.22, 0.20, 0.90), Vector3(0, 0.42, -1.25), p.heat_secondary)
	_named_terminal(item, p, "heat_in", Vector3(0, 0.65, -1.90), "input", "hw_secondary_70_40")

static func _add_terminal(item: EquipmentNode, p: Dictionary, metric: bool = false) -> void:
	item.port = Node3D.new()
	item.port.name = "ElectricityPort"
	item.port.position = item.port_local
	item.port.set_meta("port_type", "electricity")
	item.add_child(item.port)
	var marker := SphereMesh.new()
	marker.radius = 0.025 if metric else 0.15
	marker.height = 0.05 if metric else 0.30
	marker.radial_segments = 12
	marker.rings = 6
	_mesh(item, item.port, "Terminal", marker, Vector3.ZERO, p.gold)

## The returned route lives in the coordinate system of a and b. Rebuild when
## endpoints change; display curves never add capacity or model edges.
static func create_line(a: Vector3, b: Vector3, physical: bool = true, highlight: bool = false) -> Node3D:
	var route := Node3D.new()
	route.name = "PhysicalCable" if physical else "TopologyLink"
	route.set_meta("visual_only", true)
	route.set_meta("capacity_added", 0.0)
	var color := Color("ffd578") if highlight else (Color("3e4f58") if physical else Color("64e2c2"))
	var material := _material(color, 0.2, not physical or highlight)
	var points := PackedVector3Array()
	var segments := 12 if physical else 1
	for index in range(segments + 1):
		var t := float(index) / float(segments)
		var point := a.lerp(b, t)
		# Small upward service loop; cannot sag below either endpoint's linear route.
		if physical: point.y += sin(PI * t) * minf(0.55, a.distance_to(b) * 0.025)
		points.append(point)
	for index in segments:
		var start := points[index]
		var finish := points[index + 1]
		var direction := finish - start
		if direction.length_squared() < 0.000001: continue
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 0.055 if physical else 0.045
		cylinder.bottom_radius = cylinder.top_radius
		cylinder.height = direction.length()
		cylinder.radial_segments = 6
		cylinder.rings = 1
		var segment := MeshInstance3D.new()
		segment.name = "Segment%d" % index
		segment.mesh = cylinder
		segment.material_override = material
		segment.position = (start + finish) * 0.5
		segment.quaternion = Quaternion(Vector3.UP, direction.normalized())
		route.add_child(segment)
	route.set_meta("route_points", points)
	return route

static func _solar_thermal_metadata(item: EquipmentNode, dimensions: Dictionary) -> void:
	_thermal_metadata(item, "fixed_tilt_evacuated_tube_collector")
	item.set_meta("fixed_temperature_profile", "90/60°C")
	item.set_meta("geometry_assumption", dimensions.source_note)
	item.set_meta("thermal_boundary", "已充水、固定90/60°C热水工作点；循环辅机用电单独计量；固定非聚光真空管，无追日运动，无蒸汽")
	for key in ["requested_absorber_area_m2", "installed_absorber_area_m2", "installed_aperture_area_m2", "installed_gross_area_m2", "last_module_utilization", "tube_count", "tilt_deg"]:
		item.set_meta(key, dimensions[key])
	if float(dimensions.last_module_utilization) < 0.999999:
		var last: Vector3 = Spatial.module_origin_m(dimensions, int(dimensions.module_count) - 1) * WORLD_UNITS_PER_METER
		_thermal_label(item, "PartialUtilizationLabel", "末组有效利用 %.1f%% · 完整尺寸" % (100.0 * float(dimensions.last_module_utilization)), last + Vector3(0, float(dimensions.unit_dimensions_m.y) * WORLD_UNITS_PER_METER + 0.05, 0), 30)

## Direct metric fallback: identical whole-module counts and full-size tubes.
## No capacity-to-size fit, hidden compression, or photovoltaic plate substitute.
static func _build_metric_solar_thermal(item: EquipmentNode, dimensions: Dictionary) -> void:
	var p := {"metal": _material(METAL, 0.5), "dark": _material(Color("283f48")), "blue": _material(BLUE, 0.3), "ivory": _material(IVORY), "heat_primary": _material(Color("c87038")), "heat_secondary": _material(Color("dda548"))}
	var angle := deg_to_rad(Spatial.SOLAR_TILT_DEG)
	var center_y: float = Spatial.SOLAR_BOTTOM_M + (float(dimensions.unit_dimensions_m.y) - Spatial.SOLAR_BOTTOM_M) * 0.5
	for index in dimensions.module_origins_world.size():
		var module := Node3D.new()
		module.name = "SolarThermalModule%03d" % (index + 1)
		module.position = dimensions.module_origins_world[index]
		module.set_meta("absorber_utilization", dimensions.last_module_utilization if index == int(dimensions.module_count) - 1 else 1.0)
		item.add_child(module)
		var collector := Node3D.new()
		collector.name = "FixedTilt24TubeCollector"
		collector.position.y = center_y * WORLD_UNITS_PER_METER
		collector.rotation.x = -angle
		module.add_child(collector)
		_metric_box(item, collector, "UpperManifold", Vector3(2.061, .15, .241), Vector3(0, 0, 1.0), p.ivory)
		_metric_box(item, collector, "LowerRail", Vector3(2.061, .075, .075), Vector3(0, -.027, -1.083), p.metal)
		for tube_index in 24:
			var x := -.958 + tube_index * (1.916 / 23.0)
			var tube := _cylinder(item, collector, "EvacuatedTube%02d" % (tube_index + 1), .0029, .0029, .19245, Vector3(x, 0, -.08275) * WORLD_UNITS_PER_METER, p.blue)
			tube.rotation.x = PI * .5
		for x in [-.84, .84]:
			_metric_box(item, collector, "RackLongitudinalMember", Vector3(.055, .04, 2.12), Vector3(x, -.055, 0), p.metal)
			for z in [-.8, .8]:
				var top_y: float = center_y + z * sin(angle) - .075 * cos(angle)
				var top_z: float = z * cos(angle) + .075 * sin(angle)
				_metric_box(item, module, "RackSupportLeg", Vector3(.055, top_y, .055), Vector3(x, top_y * .5, top_z), p.metal)
				_metric_box(item, module, "RackAnchorFoot", Vector3(.24, .06, .22), Vector3(x, .03, top_z), p.dark)
		_metric_box(item, module, "AuxiliaryController", Vector3(.30, .35, .20), Vector3(-.70, .30, -.45), p.ivory)
		_metric_box(item, module, "PairedSupply", Vector3(.056, .056, 1.4), Vector3(.90, .22, 0), p.heat_primary)
		_metric_box(item, module, "PairedReturn", Vector3(.046, .046, 1.4), Vector3(.78, .15, 0), p.blue)
	var origin: Vector3 = dimensions.module_origins_world[0] if not dimensions.module_origins_world.is_empty() else Vector3.ZERO
	_named_terminal(item, p, "ac_in", origin + Vector3(-.70, .18, -.75) * WORLD_UNITS_PER_METER, "input")
	_named_terminal(item, p, "heat_out", origin + Vector3(.90, .22, -.75) * WORLD_UNITS_PER_METER, "output", "hw_primary_90_60")
	for terminal in item.named_ports.values():
		terminal.scale = Vector3.ONE * .025
	_solar_thermal_metadata(item, dimensions)
	item.set_meta("visual_backend", "metric_procedural_fallback")


## V19 assets and fallback use the same physical dimensions; only the collector
## optical assembly rotates. Foundations, service ports and safety bounds stay fixed.
static func _build_high_temp(item: EquipmentNode, d: Dictionary, p: Dictionary, prefer_assets: bool) -> void:
	if not d.valid:
		item.set_meta("asset_fallback", "invalid high-temperature geometry")
		return
	var oil_grade := "oil_300_200"
	var path := "res://assets/models/" + item.device_kind + ".glb"
	var reference_store := is_equal_approx(float(d.get("tank_geometric_volume_m3_each", 0.0)), 0.2 * 3600000.0 / 238.0 / 809.0 / 0.8)
	var packed: PackedScene = load(path) as PackedScene if prefer_assets and ResourceLoader.exists(path) and (item.device_kind != "high_temp_store" or reference_store) else null
	for i in d.module_origins_world.size():
		var module := packed.instantiate() as Node3D if packed != null else Node3D.new()
		module.name = "HighTemperatureModule%03d" % i
		module.position = d.module_origins_world[i]
		item.add_child(module)
		if packed != null:
			_register_asset_meshes(item, module)
			if item.device_kind == "high_temp_store":
				var tank_d: float = d.tank_diameter_m
				for tank_index in 2:
					_thermal_label(module, "TankLabel", "热油300°C" if tank_index == 0 else "冷油200°C", Vector3((-.5 if tank_index == 0 else .5) * (tank_d + 2.0), tank_d + .6, 0) * .1, 28)
			var pivot := module.find_child("TrackingPivot", true, false) as Node3D
			if pivot != null: item.solar_tracking_pivots.append(pivot)
		else:
			match item.device_kind:
				"parabolic_trough": _high_temp_trough_module(item, module, p)
				"high_temp_store": _high_temp_store_module(item, module, d, p)
				"oil_water_exchanger": _high_temp_hx_module(item, module, p)
	var ports: Dictionary = {}
	var caption := ""
	match item.device_kind:
		"parabolic_trough":
			ports = {"ac_in": [Vector3(-1, .5, -6.3), "input", ""], "heat_out": [Vector3(1, .5, -6.3), "output", oil_grade]}
			caption = "槽式聚光 · 导热油300/200°C · 南北轴"
			for key in ["installed_aperture_area_m2", "requested_aperture_area_m2", "last_module_utilization", "sweep_radius_m", "focal_length_m", "axis_orientation"]: item.set_meta(key, d[key])
		"high_temp_store":
			var diameter: float = d.tank_diameter_m
			ports = {"heat_in": [Vector3(-diameter * .5, .35, -diameter * .5 - .3), "input", oil_grade], "heat_out": [Vector3(diameter * .5, .35, -diameter * .5 - .3), "output", oil_grade]}
			caption = "双罐导热油 · 热300°C / 冷200°C"
			item.thermal_soc_label = _thermal_label(item, "ThermalSOC", "库存 SOC —", Vector3(0, diameter + .8, 0) * WORLD_UNITS_PER_METER, 33)
			for key in ["tank_diameter_m", "tank_height_m", "tank_geometric_volume_m3_each", "hot_full_volume_m3_each", "oil_inventory_mass_kg", "freeboard_fraction"]: item.set_meta(key, d[key])
		"oil_water_exchanger":
			ports = {"hot_in": [Vector3(-1.25, .45, -.9), "input", oil_grade], "warm_out": [Vector3(1.25, .45, -.9), "output", "hw_primary_90_60"], "ac_in": [Vector3(0, .4, -.9), "input", ""]}
			caption = "油水隔离换热 · 300/200→90/60°C"
	for port_id in ports:
		var spec: Array = ports[port_id]
		_named_terminal(item, p, port_id, d.module_origins_world[0] + spec[0] * WORLD_UNITS_PER_METER, spec[1], spec[2])
		var terminal: Node3D = item.named_ports[port_id]
		terminal.scale = Vector3.ONE * .025
		if spec[2] == oil_grade:
			terminal.set_meta("carrier", "heat_oil")
			terminal.set_meta("port_type", "heat_oil")
			var label := terminal.find_child("PortLabel", true, false) as Label3D
			if label != null: label.text = "油300/200 " + ("出" if spec[1] == "output" else "入")
	_thermal_label(item, "ProfileLabel", caption, Vector3(0, float(d.unit_dimensions_m.y) + .3, 0) * WORLD_UNITS_PER_METER, 34)
	item.set_meta("visual_backend", "blender_glb" if packed != null else "metric_procedural_fallback")
	item.set_meta("asset_source", path if packed != null else "")
	item.set_meta("fixed_temperature_profile", "300/200°C oil; 90/60°C water" if item.device_kind == "oil_water_exchanger" else "300/200°C Therminol 66")
	item.set_meta("soc_changes_temperature", false)
	item.set_meta("thermal_boundary", "Fixed-grade sensible oil heat; no steam, molten salt, or mixing of oil and water")

static func _high_temp_trough_module(item: EquipmentNode, module: Node3D, p: Dictionary) -> void:
	for z in [-5.7, 5.7]:
		_metric_box(item, module, "ConcretePier", Vector3(1.4, .2, .8), Vector3(0, .1, z), p.concrete)
		_metric_box(item, module, "AxisSupport", Vector3(.25, 3.3, .25), Vector3(0, 1.85, z), p.metal)
	var pivot := Node3D.new()
	pivot.name = "TrackingPivot"
	pivot.position.y = .35
	module.add_child(pivot)
	item.solar_tracking_pivots.append(pivot)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mirror := _material(Color("d9e4e6"), .85)
	mirror.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(mirror)
	for j in 48:
		var x0: float = -2.885 + 5.77 * j / 48.0
		var x1: float = -2.885 + 5.77 * (j + 1) / 48.0
		var y0 := x0 * x0 / (4.0 * 1.71)
		var y1 := x1 * x1 / (4.0 * 1.71)
		for vertex in [Vector3(x0,y0,-6),Vector3(x1,y1,6),Vector3(x1,y1,-6),Vector3(x0,y0,-6),Vector3(x0,y0,6),Vector3(x1,y1,6)]: st.add_vertex(vertex * WORLD_UNITS_PER_METER)
	st.generate_normals()
	var reflector := MeshInstance3D.new()
	reflector.name = "ParabolicReflector"
	reflector.mesh = st.commit()
	pivot.add_child(reflector)
	_register_asset_meshes(item, reflector)
	var receiver := _cylinder(item, pivot, "ReceiverAtFocus", .0035, .0035, 1.2, Vector3(0,.171,0), p.dark)
	receiver.rotation.x = PI * .5
	for z in [-5.5,-2.75,0,2.75,5.5]:
		_metric_box(item, pivot, "ReceiverSupport", Vector3(.045, 1.71, .045), Vector3(0,.855,z), p.metal)
	_metric_box(item, pivot, "TorqueBeam", Vector3(.12,.12,12), Vector3(0,-.10,0), p.metal)
	_metric_box(item, module, "OilSupply", Vector3(.12,.12,12.7), Vector3(1,.5,0), p.heat_primary)
	_metric_box(item, module, "OilReturn", Vector3(.10,.10,12.7), Vector3(.7,.3,0), p.heat_return)

static func _high_temp_store_module(item: EquipmentNode, module: Node3D, d: Dictionary, p: Dictionary) -> void:
	var diameter: float = d.tank_diameter_m
	for i in 2:
		var x := (-.5 if i == 0 else .5) * (diameter + 2.0)
		var tint: Material = p.heat_primary if i == 0 else p.heat_return
		_cylinder(item, module, "HotOilTank" if i == 0 else "ColdOilTank", diameter * .05, diameter * .05, diameter * .1, Vector3(x, diameter * .5 + .2, 0) * .1, p.ivory)
		_cylinder(item, module, "TankColourBand", diameter * .0501, diameter * .0501, .025, Vector3(x, diameter * .7 + .2, 0) * .1, tint)
		_cylinder(item, module, "TankRoof", diameter * .05, diameter * .045, .025, Vector3(x, diameter + .325, 0) * .1, p.metal)
		_thermal_label(module, "TankLabel", "热油300°C" if i == 0 else "冷油200°C", Vector3(x, diameter + .6, 0) * .1, 28)
		_metric_box(item, module, "TankFoot", Vector3(diameter,.2,diameter), Vector3(x,.1,0), p.concrete)
		_metric_box(item, module, "OilServicePipe", Vector3(.10,.10,diameter*.5+.4), Vector3(x,.35,-diameter*.25-.2), tint)

static func _high_temp_hx_module(item: EquipmentNode, module: Node3D, p: Dictionary) -> void:
	_metric_box(item,module,"OilWaterSkid",Vector3(3,.15,2),Vector3(0,.075,0),p.concrete)
	var shell := _cylinder(item,module,"IsolatedShellAndTube",.04,.04,.19,Vector3(0,.095,.02),p.ivory)
	shell.rotation.z = PI*.5
	for x in [-1.0,1.0]:
		_metric_box(item,module,"Saddle",Vector3(.15,.6,.8),Vector3(x,.45,.2),p.metal)
	_metric_box(item,module,"OilManifold",Vector3(.15,1.1,.15),Vector3(-1.25,.8,-.4),p.heat_primary)
	_metric_box(item,module,"WaterManifold",Vector3(.15,1.1,.15),Vector3(1.25,.8,-.4),p.heat_secondary)
	_metric_box(item,module,"ACPumpCabinet",Vector3(.5,.65,.4),Vector3(0,.5,-.65),p.blue)


## Independent, uncommissioned site preview. Its real dimensions are unchanged
## between world and interior views; no terminal or electrical output is invented.
static func _build_tower_station_preview(item: EquipmentNode, d: Dictionary, p: Dictionary, prefer_assets: bool, interior_only: bool = false) -> void:
	var path := "res://assets/models/tower_station_preview.glb"
	var packed: PackedScene = load(path) as PackedScene if prefer_assets and ResourceLoader.exists(path) else null
	if packed != null:
		var asset := packed.instantiate() as Node3D
		asset.name = "TowerPreviewAsset"
		if interior_only:
			var exterior := asset.find_child("ExteriorSite", true, false)
			if exterior != null: exterior.free()
		item.add_child(asset)
		_register_asset_meshes(item, asset)
	else:
		_tower_preview_geometry(item, p, interior_only)
	item.set_meta("visual_backend", "blender_glb" if packed != null else "metric_procedural_fallback")
	item.set_meta("asset_source", path if packed != null else "")
	item.set_meta("kind", item.device_kind)
	item.set_meta("preview_only", item.device_kind == "tower_station_preview")
	item.set_meta("commissioned", item.device_kind == "tower_station")
	item.set_meta("energy_ports", [])
	item.set_meta("energy_output_mw", 0.0)
	item.set_meta("preview_interior", interior_only)
	item.set_meta("representation", "commissioned_teaching_salt_tower" if item.device_kind == "tower_station" else "uncommissioned_teaching_tower_preview")
	for key in ["interior_dimensions_m", "interior_area_m2", "tower_height_m", "heliostat_count", "mirror_dimensions_m", "mirror_aperture_area_m2"]: item.set_meta(key, d[key])
	_thermal_label(item, "ProfileLabel", ("塔式光热站 · 盐热回路" if item.device_kind == "tower_station" else "塔式光热站 · 未投运预览") + "\n25 m塔 / 100面定日镜 / 镜面1600 m²", Vector3(0, 2.8, 0), 34)
	item.set_process(false)

static func _metric_rod(item: EquipmentNode, parent: Node3D, label: String, a: Vector3, b: Vector3, radius_m: float, material: Material) -> MeshInstance3D:
	var shaft := _cylinder(item, parent, label, radius_m * .1, radius_m * .1, a.distance_to(b) * .1, (a + b) * .05, material)
	shaft.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	return shaft

static func _tower_preview_geometry(item: EquipmentNode, p: Dictionary, interior_only: bool) -> void:
	p = p.duplicate()
	p.gravel = _material(Color("504839"))
	p.metal = _material(Color("3f5961"), .45)
	if not interior_only:
		var exterior := Node3D.new()
		exterior.name = "ExteriorSite"
		item.add_child(exterior)
		_metric_box(item, exterior, "Site160m", Vector3(160,.07,160), Vector3(0,.035,0), _material(Color("594f45")))
		for z in [-79.8,79.8]:
			_metric_box(item, exterior, "ExteriorFence", Vector3(159.6,.055,.055), Vector3(0,1,z), p.metal)
			for x in range(-78,79,6): _metric_box(item, exterior, "ExteriorFencePost", Vector3(.10,1.4,.10), Vector3(x,.7,z), p.metal)
		for x in [-79.8,79.8]:
			_metric_box(item, exterior, "ExteriorFence", Vector3(.055,.055,159.6), Vector3(x,1,0), p.metal)
			for z in range(-78,79,6): _metric_box(item, exterior, "ExteriorFencePost", Vector3(.10,1.4,.10), Vector3(x,.7,z), p.metal)
	var working := Node3D.new()
	working.name = "WorkingPreview"
	item.add_child(working)
	_metric_box(item, working, "Usable120m", Vector3(120,.03,120), Vector3(0,.085,0), p.gravel)
	for z in [-59.8,59.8]: _metric_box(item, working, "NetBoundary", Vector3(119.6,.012,.10), Vector3(0,.106,z), p.heat_secondary)
	for x in [-59.8,59.8]: _metric_box(item, working, "NetBoundary", Vector3(.10,.012,119.6), Vector3(x,.106,0), p.heat_secondary)
	var mirror_material := _material(Color("5a8ea2"), .55)
	_metric_box(item, working, "RadialServiceRoad", Vector3(120,.012,4), Vector3(0,.108,0), p.concrete)
	var mirrors: Array = Spatial.tower_mirror_layout()
	for i in mirrors.size():
		var center: Vector3 = mirrors[i].center_m
		var x: float = center.x
		var z: float = center.z
		var heliostat := Node3D.new()
		heliostat.name = "Heliostat%02d" % (i + 1)
		heliostat.set_meta("aperture_area_m2", 16.0)
		working.add_child(heliostat)
		_metric_box(item, heliostat, "MirrorFooting", Vector3(1.2,.2,1.2), Vector3(x,.20,z), p.concrete)
		_metric_rod(item, heliostat, "AzimuthPedestal", Vector3(x,.3,z), Vector3(x,3,z), .10, p.metal)
		var normal: Vector3 = mirrors[i].normal
		var face := _box(item, heliostat, "MirrorSurface%02d" % (i + 1), Vector3(.4,.004,.4), Vector3(x,3,z) * .1, mirror_material)
		face.quaternion = Quaternion(Vector3.UP, normal)
		var backing := _box(item, heliostat, "MirrorBacking", Vector3(.4,.008,.4), (Vector3(x,3,z) - normal * .06) * .1, p.dark)
		backing.quaternion = face.quaternion
	var tower := Node3D.new()
	tower.name = "ReceiverTower25m"
	working.add_child(tower)
	preload("res://scripts/tower_visual.gd").build(tower)
	_register_asset_meshes(item, tower)
	_metric_box(item, working, "FutureServiceBuilding", Vector3(14,4.5,8), Vector3(48,2.35,48), p.ivory)
	_metric_box(item, working, "FutureServiceRoof", Vector3(14.2,.10,8.2), Vector3(48,4.65,48), p.metal)
	_metric_box(item, working, "UncommissionedPreviewPlaque", Vector3(8,1.2,.04), Vector3(48,2.4,43.96), p.heat_secondary)
	_metric_box(item, working, "FutureServiceDoor", Vector3(2.2,2.7,.05), Vector3(48,1.45,43.94), p.dark)


## These are separate process equipment models, not a generic heat-to-power box.
## Each aggregate owns one port set; copies never create extra simulation capacity.
static func rankine_port_definitions(kind: String) -> Dictionary:
	if kind == "salt_steam_generator":
		var ports: Dictionary = rankine_port_definitions("steam_generator").duplicate(true)
		ports.salt_in = ports.oil_in
		ports.erase("oil_in")
		ports.salt_in[2] = "salt_565_290"
		ports.salt_in[3] = "heat_salt"
		ports.salt_in[4] = "盐565/290 入"
		return ports
	match kind:
		"steam_generator": return {"oil_in":[Vector3(-1.75,.55,-1.10),"input","oil_300_200","heat_oil","油300/200 入"],"ac_in":[Vector3(-.75,.50,-1.10),"input","","electricity_ac","AC 入"],"feed_in":[Vector3(.50,.50,-1.10),"input","rankine_feedwater_v1","water_steam","给水 入"],"steam_out":[Vector3(1.75,2.65,-1.10),"output","rankine_live_v1","water_steam","主蒸汽 出"]}
		"steam_turbine": return {"steam_in":[Vector3(-1.75,1.6,-1.10),"input","rankine_live_v1","water_steam","主蒸汽 入"],"exhaust_out":[Vector3(-.6,.5,-1.10),"output","rankine_exhaust_v1","water_steam","乏汽 出"],"ac_out":[Vector3(1.75,.5,-1.10),"output","","electricity_ac","AC 出"]}
		"steam_condenser": return {"exhaust_in":[Vector3(-2.7,1.0,-1.8),"input","rankine_exhaust_v1","water_steam","乏汽 入"],"condensate_out":[Vector3(2.7,.4,-1.8),"output","rankine_condensate_v1","water_steam","凝结水 出"],"ac_in":[Vector3(0,.5,-1.8),"input","","electricity_ac","风机AC 入"]}
		"feedwater_pump": return {"condensate_in":[Vector3(-.8,.5,-.48),"input","rankine_condensate_v1","water_steam","凝结水 入"],"feed_out":[Vector3(.8,.85,-.48),"output","rankine_feedwater_v1","water_steam","给水 出"],"ac_in":[Vector3(0,1.25,-.48),"input","","electricity_ac","泵AC 入"]}
	return {}

static func _build_rankine(item: EquipmentNode, d: Dictionary, p: Dictionary, prefer_assets: bool) -> void:
	if not d.valid:
		item.set_meta("asset_fallback", "invalid Rankine geometry")
		return
	var path := "res://assets/models/" + item.device_kind + ".glb"
	var packed: PackedScene = load(path) as PackedScene if prefer_assets and ResourceLoader.exists(path) else null
	for index in d.module_origins_world.size():
		var module := packed.instantiate() as Node3D if packed != null else Node3D.new()
		module.name = "RankineModule%03d" % (index + 1)
		module.position = d.module_origins_world[index]
		item.add_child(module)
		if packed != null: _register_asset_meshes(item, module)
		else: _rankine_module_geometry(item, module, p)
	var definitions := rankine_port_definitions(item.device_kind)
	for port_id in definitions:
		var spec: Array = definitions[port_id]
		_named_terminal(item, p, port_id, d.module_origins_world[0] + spec[0] * WORLD_UNITS_PER_METER, spec[1], spec[2])
		var terminal: Node3D = item.named_ports[port_id]
		terminal.scale = Vector3.ONE * (.02 if item.device_kind == "feedwater_pump" else .025)
		terminal.set_meta("carrier", spec[3])
		terminal.set_meta("port_type", spec[3])
		terminal.set_meta("unit", "kg/s" if spec[3] == "water_steam" else "MWth" if spec[3] in ["heat_oil","heat_salt"] else "MW")
		var label := terminal.find_child("PortLabel", true, false) as Label3D
		if label != null: label.text = spec[4]
	var captions := {"salt_steam_generator":"盐水蒸汽发生器 · 565/290°C盐隔离", "steam_generator":"油加热蒸汽发生器 · 油/水隔离", "steam_turbine":"小型汽轮发电机 · 闭式朗肯循环", "steam_condenser":"干式空冷冷凝器 · 凝结回收", "feedwater_pump":"给水泵 · 凝结水升压回路"}
	_thermal_label(item, "ProfileLabel", captions[item.device_kind], Vector3(0, d.unit_dimensions_m.y + .3, 0) * .1, 34)
	item.set_meta("visual_backend", "blender_glb" if packed != null else "metric_procedural_fallback")
	item.set_meta("asset_source", path if packed != null else "")
	item.set_meta("representation", "closed_rankine_" + item.device_kind)
	item.set_meta("geometry_assumption", d.source_note)
	item.set_meta("thermal_boundary", "Closed fixed-state water/steam cycle; " + ("565/290C molten salt isolated" if item.device_kind == "salt_steam_generator" else "oil isolated") + "; condenser heat rejected to dry air, no hot-water coproduct")
	for key in ["reference_rating_per_module", "rating_parameter", "rating_unit", "requested_rating", "installed_reference_rating"]: item.set_meta(key, d[key])
	item.set_meta("water_cooling_required", false)

static func _rankine_module_geometry(item: EquipmentNode, module: Node3D, p: Dictionary) -> void:
	match item.device_kind:
		"steam_generator", "salt_steam_generator":
			_metric_box(item,module,"SteamGeneratorSkid",Vector3(4,.15,2.5),Vector3(0,.075,0),p.concrete)
			for x in [-1.05,1.05]: _metric_box(item,module,"PressureVesselSaddle",Vector3(.22,.70,1.05),Vector3(x,.5,.15),p.metal)
			_metric_rod(item,module,"OilWaterIsolatedShell",Vector3(-1.35,1.30,.15),Vector3(1.35,1.30,.15),.55,p.ivory)
			for x in [-1.38,1.38]: _metric_rod(item,module,"BoltedTubeSheet",Vector3(x-.05,1.30,.15),Vector3(x+.05,1.30,.15),.60,p.metal)
			_metric_rod(item,module,"SteamDome",Vector3(.5,1.65,.15),Vector3(.5,2.65,.15),.28,p.ivory)
			_metric_rod(item,module,"SafetyValveStem",Vector3(.5,2.65,.15),Vector3(.5,2.95,.15),.055,p.heat_primary)
			_metric_box(item,module,"SafetyValveHandwheel",Vector3(.3,.04,.08),Vector3(.5,2.98,.15),p.heat_secondary)
			_metric_box(item,module,"OilManifold",Vector3(.15,1.1,.15),Vector3(-1.75,1.1,-.3),p.heat_primary)
			_metric_box(item,module,"LiveSteamRiser",Vector3(.13,1.2,.13),Vector3(1.75,2.1,-.1),p.heat_secondary)
			_metric_box(item,module,"LiveSteamOutlet",Vector3(.13,.13,1.1),Vector3(1.75,2.65,-.6),p.heat_secondary)
			_metric_box(item,module,"AuxiliaryControlPanel",Vector3(.55,.90,.45),Vector3(-.75,.65,-.85),p.blue)
			_metric_box(item,module,"FeedwaterLine",Vector3(.09,.09,.9),Vector3(.5,.5,-.65),p.heat_return)
		"steam_turbine":
			_metric_box(item,module,"TurbineGeneratorSkid",Vector3(4,.15,2.5),Vector3(0,.075,0),p.concrete)
			for x in [-1.1,.65,1.4]: _metric_box(item,module,"BearingPedestal",Vector3(.25,.6,.65),Vector3(x,.45,.15),p.metal)
			_metric_rod(item,module,"SteamTurbineCasing",Vector3(-1.45,1.05,.15),Vector3(-.25,1.05,.15),.52,p.ivory)
			for x in [-1.43,-.30]: _metric_rod(item,module,"SplitCasingFlange",Vector3(x-.035,1.05,.15),Vector3(x+.035,1.05,.15),.55,p.metal)
			_metric_rod(item,module,"ShaftCoupling",Vector3(-.25,1.05,.15),Vector3(.35,1.05,.15),.16,p.dark)
			_metric_rod(item,module,"ACGenerator",Vector3(.35,1.05,.15),Vector3(1.55,1.05,.15),.48,p.blue)
			for x in [.45,.62,.79,.96,1.13,1.30]: _metric_rod(item,module,"GeneratorCoolingFin",Vector3(x,1.05,.15),Vector3(x+.035,1.05,.15),.51,p.metal)
			_metric_box(item,module,"LiveSteamInlet",Vector3(.13,.60,.13),Vector3(-1.75,1.85,-1.1),p.heat_secondary)
			_metric_box(item,module,"LiveSteamHeader",Vector3(.93,.13,.13),Vector3(-1.35,2.10,-.45),p.heat_secondary)
			_metric_box(item,module,"TurbineExhaust",Vector3(.3,.3,1.25),Vector3(-.6,.5,-.48),p.heat_return)
			_metric_box(item,module,"GeneratorTerminalBox",Vector3(.50,.90,.45),Vector3(1.65,.65,-.85),p.dark)
			_metric_box(item,module,"LubeOilSystem",Vector3(.6,.5,.45),Vector3(-1.25,.4,-.85),p.metal)
		"steam_condenser":
			_metric_box(item,module,"DryCondenserSkid",Vector3(6,.15,4),Vector3(0,.075,0),p.concrete)
			for x in [-2.45,2.45]:
				for z in [-1.4,1.4]: _metric_box(item,module,"DryCoolerSupport",Vector3(.18,2.9,.18),Vector3(x,1.6,z),p.metal)
			_metric_rod(item,module,"SurfaceCondenserShell",Vector3(-1.95,.85,0),Vector3(1.95,.85,0),.45,p.ivory)
			_metric_box(item,module,"DryRadiatorCore",Vector3(5.2,.45,3),Vector3(0,2.95,0),p.metal)
			for index in 33: _metric_box(item,module,"AirSideFin",Vector3(.025,.55,2.9),Vector3(-2.4+index*.15,2.95,0),p.ivory)
			_metric_box(item,module,"FanPlenum",Vector3(5.2,.20,3),Vector3(0,3.3,0),p.dark)
			for x in [-1.45,1.45]:
				_metric_rod(item,module,"DryFanHousing",Vector3(x,3.4,0),Vector3(x,4.1,0),.78,p.metal)
				_metric_rod(item,module,"DryFanInlet",Vector3(x,4.105,0),Vector3(x,4.115,0),.70,p.dark)
				_metric_rod(item,module,"FanHub",Vector3(x,4.12,0),Vector3(x,4.2,0),.13,p.ivory)
				for angle in [0.0,PI*.5,PI,PI*1.5]:
					var blade := _box(item,module,"VisibleDryFanBlade",Vector3(.059,.0025,.016),Vector3(x+.34*cos(angle),4.135,.34*sin(angle))*.1,p.ivory)
					blade.rotation.y = -angle
			_metric_box(item,module,"LowPressureSteamHeader",Vector3(.30,.30,2),Vector3(-2.7,1,-.8),p.heat_secondary)
			_metric_box(item,module,"CondensateHotwellOutlet",Vector3(.12,.12,2),Vector3(2.7,.4,-.8),p.heat_return)
			_metric_box(item,module,"DryFanACControl",Vector3(.8,1,.45),Vector3(0,.65,-1.55),p.blue)
		"feedwater_pump":
			_metric_box(item,module,"FeedPumpSkid",Vector3(2,.15,1.2),Vector3(0,.075,0),p.concrete)
			_metric_box(item,module,"PumpBearing",Vector3(.40,.3,.5),Vector3(-.35,.29,0),p.metal)
			_metric_box(item,module,"MotorBearing",Vector3(.65,.3,.5),Vector3(.4,.29,0),p.metal)
			_metric_rod(item,module,"PumpVolute",Vector3(-.55,.65,0),Vector3(-.15,.65,0),.28,p.ivory)
			_metric_rod(item,module,"PumpCoupling",Vector3(-.15,.65,0),Vector3(.15,.65,0),.10,p.dark)
			_metric_rod(item,module,"FeedPumpACMotor",Vector3(.15,.65,0),Vector3(.75,.65,0),.24,p.blue)
			for x in [.22,.35,.48,.61]: _metric_rod(item,module,"MotorCoolingFin",Vector3(x,.65,0),Vector3(x+.03,.65,0),.26,p.metal)
			_metric_box(item,module,"CondensateSuction",Vector3(.11,.11,.55),Vector3(-.8,.5,-.20),p.heat_return)
			_metric_box(item,module,"PressurizedFeedDischarge",Vector3(1.24,.09,.09),Vector3(.20,1.15,0),p.heat_secondary)
			_metric_box(item,module,"FeedOutlet",Vector3(.09,.35,.55),Vector3(.8,1,-.20),p.heat_secondary)
			_metric_box(item,module,"PumpACIsolator",Vector3(.35,.44,.24),Vector3(0,1.28,-.35),p.blue)

static func _build_tower_device(item: EquipmentNode, d: Dictionary, p: Dictionary) -> void:
	if not d.valid: return
	var definitions: Dictionary = {}
	if item.device_kind == "solar_tower_receiver":
		_metric_box(item,item,"TowerControlCabinet",Vector3(2,1.5,1.2),Vector3(0,.75,0),p.blue)
		definitions = {"ac_in":[Vector3(-.8,.6,-.6),"input","","electricity_ac","泵/追踪AC入"],"heat_out":[Vector3(.8,.6,-.6),"output","salt_565_290","heat_salt","盐565/290出"]}
		_thermal_label(item,"ProfileLabel","塔接收器 · 镜场1600m²",Vector3(0,.20,0),30)
	else:
		var diameter: float = d.tank_diameter_m
		for i in 2:
			var x: float = (-.5 if i == 0 else .5)*(diameter+2)
			var tint: Material = p.heat_primary if i == 0 else p.heat_return
			_cylinder(item,item,"HotSaltTank" if i == 0 else "ColdSaltTank",diameter*.05,diameter*.05,diameter*.1,Vector3(x,diameter*.5+.2,0)*.1,p.ivory)
			_cylinder(item,item,"SaltTankBand",diameter*.0501,diameter*.0501,.025,Vector3(x,diameter*.7+.2,0)*.1,tint)
			_cylinder(item,item,"SaltTankRoof",diameter*.05,diameter*.045,.025,Vector3(x,diameter+.325,0)*.1,p.metal)
			_metric_box(item,item,"TankFoot",Vector3(diameter,.2,diameter),Vector3(x,.1,0),p.concrete)
			for level in [.30,.53,.88]:
				_cylinder(item,item,"SaltJacketSeam",diameter*.05015,diameter*.05015,.004,Vector3(x,diameter*level+.2,0)*.1,p.metal)
			# Top-entry piping distinguishes high-temperature salt storage from the
			# 90/60 C parallel water buffers. Geometry is not a freeze-protection model.
			_metric_box(item,item,"SaltRoofManway",Vector3(.42,.12,.42),Vector3(x,diameter+.38,0),p.metal)
			_metric_box(item,item,"SaltPumpHead",Vector3(.34,.38,.34),Vector3(x,diameter+.55,-diameter*.22),p.blue)
			_metric_rod(item,item,"SaltPumpRiser",Vector3(x,.4,-diameter*.5-.20),Vector3(x,diameter+.55,-diameter*.5-.20),.06,p.metal)
			_metric_rod(item,item,"SaltRoofBranch",Vector3(x,diameter+.55,-diameter*.5-.20),Vector3(x,diameter+.55,-diameter*.22),.06,p.metal)
			for support_y in [.3,.7]:
				_metric_box(item,item,"SaltRiserBracket",Vector3(.20,.07,.36),Vector3(x,diameter*support_y,-diameter*.5-.08),p.metal)
			var service_x := -1.0 if i == 0 else 1.0
			_metric_rod(item,item,"SaltServiceHeader",Vector3(x,.4,-diameter*.5-.20),Vector3(service_x,.4,-diameter*.5-.20),.06,p.metal)
			_metric_rod(item,item,"SaltBoundaryNozzle",Vector3(service_x,.4,-diameter*.5-.20),Vector3(service_x,.4,-diameter*.5-.4),.06,tint)

			_thermal_label(item,"TankLabel","热盐565°C" if i == 0 else "冷盐290°C",Vector3(x,diameter+.6,0)*.1,28)
		definitions = {"heat_in":[Vector3(-1,.4,-diameter*.5-.4),"input","salt_565_290","heat_salt","充盐入"],"heat_out":[Vector3(1,.4,-diameter*.5-.4),"output","salt_565_290","heat_salt","放盐出"],"ac_in":[Vector3(0,.4,-diameter*.5-.4),"input","","electricity_ac","盐泵AC入"]}
		item.thermal_soc_label = _thermal_label(item,"StorageSOC","盐库存",Vector3(0,(diameter+1)*.1,0),28)
	for port_id in definitions:
		var spec: Array = definitions[port_id]
		_named_terminal(item,p,port_id,spec[0]*.1,spec[1],spec[2])
		var terminal: Node3D = item.named_ports[port_id]
		terminal.scale=Vector3.ONE*.025
		terminal.set_meta("carrier",spec[3]);terminal.set_meta("port_type",spec[3]);terminal.set_meta("unit","MWth" if spec[3]=="heat_salt" else "MW")
		var label:=terminal.find_child("PortLabel",true,false) as Label3D
		if label != null: label.text=spec[4]
	item.set_meta("visual_backend","metric_procedural_fallback")
	item.set_meta("geometry_assumption",d.source_note)


## Complete first-level facilities: distinct process stages and one authoritative
## inventory. These meshes never create extra physics devices or hidden ports.
static func _build_storage_facility(item: EquipmentNode, d: Dictionary, p: Dictionary) -> void:
	if not d.valid: return
	var stages := {
		"battery_sodium": "钠离子电池箱 → 双向PCS",
		"battery_flow": "正/负电解液罐 ↔ 泵组/电堆 ↔ 双向PCS",
		"caes_aboveground": "电驱压缩机 → 地上承压容器组 → 膨胀发电机",
		"liquid_air_store": "液化机/冷箱 → 绝热液罐 → 泵/膨胀发电机",
		"hydrogen_storage_system": "电解/压缩制氢 → 储氢容器组 → 燃料电池回发",
		"solid_thermal_store": "热输入 → 保温固体蓄热体/换热通道 → 热输出（不发电）"}
	item.set_meta("storage_stages", stages[item.device_kind])
	if item.device_kind=="battery_flow":
		item.set_meta("geometry_profile",d.get("geometry_profile","flow_process_v2"))
		item.set_meta("legacy_icon_geometry",d.get("legacy_icon_geometry",false))
		item.set_meta("geometry_is_capacity_proof",false)
	item.set_meta("representation", "complete_" + item.device_kind)
	item.set_meta("visual_backend", "metric_batched_storage")
	item.set_meta("geometry_assumption", d.source_note)
	item.set_meta("pressure_is_simulated", false)
	item.set_meta("temperature_is_dynamic", false)
	item.set_meta("capacity_added", 0.0)
	var tint := p.duplicate()
	tint.sodium = _material(Color("d4a34b"), 0.1)
	tint.flow = _material(Color("6f8fba"), 0.15)
	tint.hydrogen = _material(Color("6caab3"), 0.15)
	if item.device_kind == "caes_aboveground":
		# Local matte finishes preserve shape under the existing detail lighting.
		# Do not darken the shared palette used by other technologies.
		var finishes := {"ivory": "7b8584", "caes_receiver": "667f8a", "caes_cladding": "626966", "caes_roof": "4a5c64", "concrete": "353f40"}
		for finish in finishes:
			var material := _material(Color(finishes[finish]))
			material.roughness = 0.94
			material.metallic_specular = 0.15
			tint[finish] = material
	var unit: Vector3 = d.unit_dimensions_m
	var display_count := mini(int(d.module_count), 48)
	item.set_meta("display_module_count", display_count)
	item.set_meta("representative_lod", display_count < int(d.module_count))
	for display_index in display_count:
		var index := display_index if display_count == int(d.module_count) else int(round(float(display_index) * float(int(d.module_count) - 1) / float(maxi(display_count - 1, 1))))
		var module := Node3D.new()
		module.name = "StorageModule%03d" % (index + 1)
		module.position = Spatial.module_origin_m(d, index) * WORLD_UNITS_PER_METER
		item.add_child(module)
		_metric_box(item, module, "CompleteFacilityFoundation", Vector3(unit.x, .20, unit.z), Vector3(0, .10, 0), tint.concrete)
		match item.device_kind:
			"battery_sodium":
				if d.get("site_geometry_profile", "") == "reference_size_v1": _storage_sodium_reference(item,module,tint,d)
				else: _storage_sodium(item,module,tint)
			"battery_flow":
				if d.get("geometry_profile","flow_process_v2") == "flow_icon_v1": _storage_flow(item, module, tint)
				else: _storage_flow_process(item, module, tint)
			"caes_aboveground": _storage_caes(item, module, tint)
			"liquid_air_store": _storage_liquid_air(item, module, tint)
			"hydrogen_storage_system": _storage_hydrogen(item, module, tint)
			"solid_thermal_store": _storage_solid(item, module, tint)
	# Material-batched surfaces keep full-size installations cheap to render.
	_combine_static_meshes(item, "StorageFacilityGeometry")
	var front: float = -float(d.body_dimensions_m.z) * .5 - .35
	if item.device_kind == "solid_thermal_store":
		for port_id in ["heat_in", "heat_out"]:
			var x := -.8 if port_id == "heat_in" else .8
			_named_terminal(item, p, port_id, Vector3(x, .55, front) * .1, "input" if port_id == "heat_in" else "output", "hw_primary_90_60")
			item.named_ports[port_id].scale = Vector3.ONE * .1
		item.thermal_soc_label = _thermal_label(item, "StorageSOC", "固体热库存", Vector3(0, unit.y + .5, 0) * .1, 28)
	else:
		_named_terminal(item, p, "ac", Vector3(-float(d.body_dimensions_m.x) * .5 + .5, .65, front) * .1, "bidirectional")
		item.named_ports.ac.scale = Vector3.ONE * .1
		var port_label: Label3D = item.named_ports.ac.find_child("PortLabel", true, false)
		if port_label != null: port_label.text = "AC 充 ↔ 放"
	item.set_process(false)

static func _storage_stage(parent: Node3D, label: String, origin_m: Vector3 = Vector3.ZERO) -> Node3D:
	var stage := Node3D.new()
	stage.name = label
	stage.position = origin_m * .1
	parent.add_child(stage)
	return stage

static func _storage_cabinet(item: EquipmentNode, parent: Node3D, label: String, size: Vector3, at: Vector3, tint: Material, p: Dictionary) -> void:
	_metric_box(item, parent, label, size, at + Vector3(0, size.y * .5 + .2, 0), tint)
	_metric_box(item, parent, label + "Roof", Vector3(size.x + .08, .12, size.z + .08), at + Vector3(0, size.y + .24, 0), p.metal)
	for door in 3:
		var x: float = at.x + (door - 1) * size.x * .30
		_metric_box(item, parent, label + "Door", Vector3(size.x * .27, size.y * .75, .04), Vector3(x, size.y * .52 + .2, at.z - size.z * .5 - .02), p.ivory)
		_metric_box(item, parent, label + "Handle", Vector3(.045, .25, .04), Vector3(x + size.x * .10, size.y * .5 + .2, at.z - size.z * .5 - .06), p.dark)
		_metric_box(item, parent, label + "Vent", Vector3(size.x * .18, .14, .045), Vector3(x, size.y * .8 + .2, at.z - size.z * .5 - .05), p.dark)

static func _storage_vertical_tank(item: EquipmentNode, parent: Node3D, label: String, at: Vector3, radius: float, height: float, tint: Material, p: Dictionary) -> void:
	_cylinder(item, parent, label, radius * .1, radius * .1, height * .1, (at + Vector3(0, height * .5 + .25, 0)) * .1, tint)
	_cylinder(item, parent, label + "DishedRoof", radius * .1, radius * .075, .03, (at + Vector3(0, height + .40, 0)) * .1, p.ivory)
	for level in [.22, .55, .84]:
		_cylinder(item, parent, label + "JacketBand", (radius + .015) * .1, (radius + .015) * .1, .008, (at + Vector3(0, height * level + .25, 0)) * .1, p.metal)
	_metric_box(item, parent, label + "Manway", Vector3(.4, .12, .4), at + Vector3(0, height + .59, 0), p.metal)
	_metric_rod(item, parent, label + "ServicePipe", at + Vector3(radius + .12, .45, 0), at + Vector3(radius + .12, height + .35, 0), .075, p.metal)

static func _storage_pressure_bank(item: EquipmentNode, parent: Node3D, label: String, origin: Vector3, rows: int, length: float, radius: float, p: Dictionary) -> void:
	var bank := _storage_stage(parent, label, origin)
	for row in rows:
		var z: float = (row - (rows - 1) * .5) * (radius * 2.0 + .55)
		var body := CapsuleMesh.new()
		body.radius = radius * .1
		body.height = length * .1
		body.radial_segments = 16
		body.rings = 4
		var vessel := _mesh(item, bank, "AbovegroundPressureVessel", body, Vector3(0, radius + .65, z) * .1, p.ivory)
		vessel.rotation.z = PI * .5
		for x in [-length * .30, length * .30]:
			_metric_box(item, bank, "VesselSaddle", Vector3(.35, .80, radius * 1.8), Vector3(x, .6, z), p.metal)
		_metric_rod(item, bank, "VesselNeck", Vector3(length * .5, radius + .65, z), Vector3(length * .5 + .3, radius + .65, z), .08, p.metal)
	_metric_rod(item, bank, "BankManifold", Vector3(length * .5 + .3, radius + .65, -(rows - 1) * (radius + .275)), Vector3(length * .5 + .3, radius + .65, (rows - 1) * (radius + .275)), .12, p.blue)

static func _storage_turbomachine(item: EquipmentNode, parent: Node3D, label: String, at: Vector3, p: Dictionary) -> void:
	var stage := _storage_stage(parent, label, at)
	_metric_box(item, stage, "MachineSkid", Vector3(4.3, .25, 2.4), Vector3(0, .325, 0), p.dark)
	_metric_rod(item, stage, "ElectricMachine", Vector3(-1.8, 1.15, 0), Vector3(-.5, 1.15, 0), .62, p.blue)
	_metric_rod(item, stage, "ShaftCoupling", Vector3(-.5, 1.15, 0), Vector3(.1, 1.15, 0), .20, p.metal)
	_metric_rod(item, stage, "TurbomachineCasing", Vector3(.1, 1.15, 0), Vector3(1.5, 1.15, 0), .80, p.ivory)
	_metric_rod(item, stage, "ServiceInlet", Vector3(1.15, 1.15, -.65), Vector3(1.15, 1.15, -1.1), .22, p.metal)
	for x in [-1.65, -1.4, -1.15, -.9, -.65]:
		_metric_rod(item, stage, "MotorCoolingFin", Vector3(x, 1.15, 0), Vector3(x + .05, 1.15, 0), .67, p.metal)

## Three complete source-sized cabinets; the larger unit foundation includes
## teaching auxiliary space, never a uniformly enlarged battery enclosure.
static func _storage_sodium_reference(item: EquipmentNode, module: Node3D, p: Dictionary, d: Dictionary) -> void:
	item.set_meta("storage_reference_revision", "sodium_fixed_capacity_20261021")
	item.set_meta("storage_reference_ids", ["ZTTEK_QUANTUM_N2_5_DATASHEET", "DATANG_QIANJIANG_20240701"])
	item.set_meta("geometry_is_capacity_proof", false)
	var stage := _storage_stage(module,"SodiumSourceSizedContainerAndAuxiliary")
	var size: Vector3 = d.reference_container_dimensions_m
	var center := Vector3(-0.45,0.30 + size.y * 0.5,0.0)
	var anchor := _storage_stage(stage,"SourceSizedSodiumCabinet",center)
	anchor.set_meta("outer_dimensions_m",size)
	anchor.set_meta("nominal_energy_mwh",d.reference_capacity_per_module)
	# Exact outer box, including its flush roof: 7.120 x 2.896 x 2.800 m.
	_metric_box(item,anchor,"SourceSizedBatteryEnclosure",size,Vector3.ZERO,p.ivory)
	for x in [-size.x*.5+.10,size.x*.5-.10]:
		for z in [-size.z*.5+.10,size.z*.5-.10]:
			_metric_box(item,stage,"CabinFoundationPier",Vector3(.30,.28,.30),Vector3(center.x+x,.16,z),p.concrete)
	for door in 6:
		var x: float = center.x-size.x*.5+.60+float(door)*(size.x-1.2)/5.0
		_metric_box(item,stage,"CabinetServicePanel",Vector3(.98,size.y-.28,.025),Vector3(x,center.y,-size.z*.5-.013),p.ivory)
		_metric_box(item,stage,"CabinetServiceHandle",Vector3(.045,.24,.045),Vector3(x+.35,1.60,-size.z*.5-.04),p.metal)
	_metric_box(item,stage,"SodiumTechnologyStripe",Vector3(size.x-.25,.14,.025),Vector3(center.x,3.00,-size.z*.5-.027),p.sodium)
	# Visible thermal-management end grille, not an extra simulation load/port.
	for row in 10:
		_metric_box(item,stage,"EndCoolingLouver",Vector3(.035,.10,2.30),Vector3(center.x+size.x*.5+.02,.72+row*.20,0),p.dark)
	_metric_box(item,stage,"AuxiliarySwitchgear",Vector3(.70,2.0,1.90),Vector3(3.85,1.20,0),p.blue)
	_metric_box(item,stage,"CabinetToAuxiliaryCableTrench",Vector3(.70,.08,.36),Vector3(3.42,.24,0),p.dark)

static func _storage_sodium(item: EquipmentNode, module: Node3D, p: Dictionary) -> void:
	# Datang/HiNa Qianjiang operating-site photos: raised battery cabins,
	# repeated service panels, cooling units and separate power conversion.
	# Original teaching envelope/rating, not a measured Qianjiang container.
	item.set_meta("storage_reference_revision", "primary_photos_20261021")
	item.set_meta("storage_reference_ids", ["DATANG_QIANJIANG_20240701", "HINA_QIANJIANG_20241129"])
	item.set_meta("geometry_is_capacity_proof", false)
	var stage := _storage_stage(module, "SodiumIonContainerAndPCS")
	_storage_cabinet(item, stage, "SodiumIonCabinet", Vector3(5.7, 2.4, 2.5), Vector3(-.10, 0, .10), p.ivory, p)
	_metric_box(item, stage, "SodiumTechnologyStripe", Vector3(5.5, .16, .05), Vector3(-.1, 2.62, -1.18), p.sodium)
	for x in [-2.7, 2.5]:
		for z in [-1.08, 1.25]:
			_metric_box(item, stage, "CabinFoundationPier", Vector3(.35, .22, .35), Vector3(x, .21, z), p.concrete)
		_metric_box(item, stage, "CabinCornerFrame", Vector3(.075, 2.5, .07), Vector3(x, 1.5, -1.18), p.metal)
	for x in [-1.8, 0.0, 1.8]:
		_metric_box(item, stage, "FrontServiceCoolingModule", Vector3(.62, .82, .24), Vector3(x, 1.8, -1.33), p.metal)
		for row in 5:
			_metric_box(item, stage, "CoolingModuleLouver", Vector3(.50, .035, .025), Vector3(x, 1.55+row*.12, -1.46), p.dark)
		_metric_box(item, stage, "CableEntryGland", Vector3(.16, .16, .16), Vector3(x, .34, -1.35), p.dark)
	_metric_box(item, stage, "BidirectionalPCS", Vector3(.55, 1.8, 1.8), Vector3(2.95, 1.10, .10), p.blue)
	for rib in 6:
		_metric_box(item, stage, "PCSIntakeLouver", Vector3(.035, .08, 1.4), Vector3(3.235, .7 + rib * .20, .10), p.dark)

static func _storage_flow(item: EquipmentNode, module: Node3D, p: Dictionary) -> void:
	var tanks := _storage_stage(module, "PositiveAndNegativeElectrolyteTanks")
	_storage_vertical_tank(item, tanks, "PositiveElectrolyteTank", Vector3(-3.5, 0, 1.8), 1.9, 4.4, p.flow, p)
	_storage_vertical_tank(item, tanks, "NegativeElectrolyteTank", Vector3(3.5, 0, 1.8), 1.9, 4.4, p.hydrogen, p)
	var stacks := _storage_stage(module, "FlowCellStackAndCirculationPumps")
	_metric_box(item, stacks, "StackSkid", Vector3(6, .2, 2), Vector3(0, .3, -2.5), p.dark)
	for layer in 16:
		_metric_box(item, stacks, "ElectrodeStackPlate", Vector3(.13, 1.45, 1.5), Vector3(-1.25 + layer * .16, 1.15, -2.5), p.metal if layer % 2 == 0 else p.dark)
	for x in [-3.5, 3.5]:
		_metric_rod(item, stacks, "ElectrolyteLoopPipe", Vector3(x, .7, 1.8), Vector3(x, .7, -2.5), .12, p.flow if x < 0 else p.hydrogen)
		_metric_rod(item, stacks, "CirculationPump", Vector3(x - .3, .7, -2.5), Vector3(x + .3, .7, -2.5), .28, p.blue)
	_storage_cabinet(item, module, "FlowBidirectionalPCS", Vector3(1.7, 2.1, 1.8), Vector3(5.2, 0, -2.3), p.blue, p)


static func _storage_flow_process(item: EquipmentNode, module: Node3D, p: Dictionary) -> void:
	# Photo-backed two-story arrangement. Exact component box dimensions are
	# references, not a manufacturer-certified reproduction or electrolyte
	# volume proof. New reference metadata distinguishes AC nameplate from
	# internal inventory; the old 10MWh replication threshold is legacy only.
	item.set_meta("storage_reference_revision", "primary_photos_20261021")
	item.set_meta("storage_reference_ids", ["SUMITOMO_HOKKAIDO_2022", "SUMITOMO_RFB_CATALOG_202510"])
	item.set_meta("flow_process_units_per_module",6)
	var plant:=_storage_stage(module,"FlowTwoStoryProcessArray")
	for n in 6:
		var x:float=-12.85+n*5.14
		var unit:=_storage_stage(plant,"FlowProcessUnit%02d" % (n+1),Vector3(x,0,0))
		for sign_index in 2:
			var tx:float=-1.232+sign_index*2.464
			var liquid:Material=p.flow if sign_index==0 else p.hydrogen
			_metric_box(item,unit,"PositiveTankContainer" if sign_index==0 else "NegativeTankContainer",Vector3(2.438,2.896,12.192),Vector3(tx,1.548,0),p.ivory)
			_metric_box(item,unit,"ElectrolyteCircuitStripe",Vector3(2.1,.12,.03),Vector3(tx,2.6,-6.115),liquid)
			for z in [-5.7,0.0,5.7]:
				_metric_box(item,unit,"RaisedFoundationPier",Vector3(2.3,.18,.38),Vector3(tx,.11,z),p.concrete)
			for rib in 18:
				_metric_box(item,unit,"TankContainerRib",Vector3(.035,2.65,.05),Vector3(tx+(1.23 if sign_index==1 else -1.23),1.55,-5.9+rib*.69),p.metal)
		_metric_box(item,unit,"ElevatedCellStackContainer",Vector3(2.28,2.45,5.92),Vector3(0,4.221,-2.55),p.ivory)
		_metric_box(item,unit,"CellStackContainerRoof",Vector3(2.35,.03,5.99),Vector3(0,5.46,-2.55),p.metal)
		for z in [-4.5,-2.5,-.5]:
			_metric_box(item,unit,"StackServiceDoor",Vector3(.025,1.8,1.45),Vector3(1.155,4.13,z),p.metal)
			_metric_box(item,unit,"UpperCoolingLouver",Vector3(.08,.3,1.15),Vector3(1.18,5.04,z),p.dark)
		_metric_box(item,unit,"UpperServiceWalkway",Vector3(1.0,.08,6.1),Vector3(1.72,3.04,-2.55),p.metal)
		for z in [-5.5,-2.55,.4]:
			_metric_rod(item,unit,"WalkwayGuardPost",Vector3(2.18,3.08,z),Vector3(2.18,4.1,z),.025,p.metal)
		_metric_rod(item,unit,"WalkwayGuardRail",Vector3(2.18,4.1,-5.5),Vector3(2.18,4.1,.4),.025,p.metal)
		for tx in [-1.232,1.232]:
			_metric_rod(item,unit,"SeparateElectrolyteRiser",Vector3(tx,1.0,5.7),Vector3(tx,3.65,5.7),.075,p.flow if tx<0 else p.hydrogen)
			_metric_rod(item,unit,"SeparateElectrolyteReturn",Vector3(tx,3.65,5.7),Vector3(tx,3.65,.65),.075,p.flow if tx<0 else p.hydrogen)
			_metric_rod(item,unit,"ElectrolytePumpSkid",Vector3(tx-.27,3.28,4.8),Vector3(tx+.27,3.28,4.8),.17,p.blue)
	var power:=_storage_stage(module,"FlowDedicatedPCSAndControl")
	for z in [-4.5,0,4.5]:
		_storage_cabinet(item,power,"PowerConversionCabinet",Vector3(2.3,2.5,2.3),Vector3(-17.35,0,z),p.blue,p)
	_metric_box(item,power,"GroundCableTrench",Vector3(33,.06,.42),Vector3(-.5,.23,-6.75),p.dark)
	_metric_box(item,power,"ControlSwitchgear",Vector3(2.4,2.2,1.2),Vector3(16.7,1.3,-5.8),p.metal)

static func _storage_caes(item: EquipmentNode, module: Node3D, p: Dictionary) -> void:
	# Photo-derived layout, not a miniature of a 100/300 MW cavern project.
	# Reference mapping and inspected image URLs: docs/storage_1003/CAES_VISUAL_REFERENCES.md.
	# Keep the existing 24 x 18 x 6 m teaching envelope and sole aggregate AC port.
	item.set_meta("caes_visual_revision", "photo_referenced_surface_plant_v2")
	item.set_meta("caes_reference_ids", ["CEEC_JINTAN_PHOTO", "IET_ZHANGJIAKOU_HALL", "IET_ZHANGJIAKOU_EXTERIOR", "PRESSVESS_RECEIVER_3_5"])
	item.set_meta("caes_storage_location", "aboveground_pressure_vessels_only")
	item.set_meta("caes_geometry_is_capacity_proof", false)
	item.set_meta("caes_thermal_vessels_are_air_storage", false)
	item.set_meta("caes_hall_cutaway", true)
	item.set_meta("storage_stages", "压缩/膨胀机房 ↔ 换热蓄热区 ↔ 地上储气容器列（无地下储气）")
	_storage_caes_machine_hall(item, module, p)
	_storage_caes_heat_recovery(item, module, p)
	if module.name == "StorageModule001":
		_thermal_label(module, "CAESMachineHallLabel", "压缩 / 膨胀机房", Vector3(-5.8, 5.9, -4.8)*.1, 24)
		_thermal_label(module, "CAESHeatRecoveryLabel", "换热 · 蓄热（非储气）", Vector3(6, 4.0, -5.5)*.1, 24)
		_thermal_label(module, "CAESAbovegroundAirLabel", "地上储气容器", Vector3(0, 3.1, 4.1)*.1, 24)
	var bank := _storage_stage(module, "AbovegroundAirVesselBank", Vector3(0, 0, 4.1))
	bank.set_meta("role", "air_inventory_display_only")
	bank.set_meta("vessel_count", 4)
	bank.set_meta("reference_id", "PRESSVESS_RECEIVER_3_5")
	for row in 4:
		var z: float = (row - 1.5) * 2.2
		_storage_caes_receiver(item, bank, Vector3(0, 1.6, z), 15.0, .9, p)
		_metric_rod(item, bank, "AirBranch", Vector3(7.5, 1.6, z), Vector3(9.4, 1.6, z), .10, p.blue)
		_metric_box(item, bank, "BranchIsolationValve", Vector3(.28, .32, .30), Vector3(8.5, 1.6, z), p.metal)
		_metric_rod(item, bank, "ValveStem", Vector3(8.5, 1.6, z), Vector3(8.5, 2.0, z), .035, p.metal)
		_metric_rod(item, bank, "ValveHandwheel", Vector3(8.5, 2.0, z-.17), Vector3(8.5, 2.0, z+.17), .035, p.dark)
	_metric_rod(item, module, "AirBankManifold", Vector3(9.4, 1.6, .8), Vector3(9.4, 1.6, 7.4), .15, p.blue)
	var gallery := _storage_stage(module, "ElevatedProcessPipeGallery")
	gallery.set_meta("reference_id", "CEEC_JINTAN_PHOTO")
	for x in [-9.8, -5.0, 0.0, 4.8, 9.4]:
		for z in [-.30, .30]:
			_metric_box(item, gallery, "PipeRackColumn", Vector3(.12, 3.1, .12), Vector3(x, 1.75, z), p.metal)
		_metric_box(item, gallery, "PipeRackCrossbeam", Vector3(.18, .16, 1.1), Vector3(x, 3.3, 0), p.metal)
	for z in [-.26, .26]:
		_metric_rod(item, gallery, "InsulatedAirHeader", Vector3(-9.8, 3.5, z), Vector3(9.4, 3.5, z), .12, p.ivory)
	_metric_rod(item, gallery, "StorageManifoldDrop", Vector3(9.4, 3.5, .26), Vector3(9.4, 1.6, .8), .12, p.ivory)
	for x in [-8.3, -3.3, 3.8, 7.6]:
		_metric_rod(item, gallery, "ProcessBranchDrop", Vector3(x, 3.5, -.26), Vector3(x, 3.5, -2), .12, p.ivory)
		_metric_rod(item, gallery, "ProcessBranchRiser", Vector3(x, 3.5, -2), Vector3(x, 1.6, -2), .12, p.ivory)

static func _storage_caes_machine_hall(item: EquipmentNode, module: Node3D, p: Dictionary) -> void:
	var hall := _storage_stage(module, "CompressorExpanderMachineHall", Vector3(-5.8, 0, -4.8))
	hall.set_meta("reference_id", "IET_ZHANGJIAKOU_HALL")
	hall.set_meta("front_wall_cutaway_for_teaching", true)
	_metric_box(item, hall, "MachineHallPlinth", Vector3(10.8, .3, 7.2), Vector3(0, .35, 0), p.dark)
	_metric_box(item, hall, "RearCladding", Vector3(10.8, 4.8, .12), Vector3(0, 2.9, 3.5), p.caes_cladding)
	for x in [-5.3, 5.3]:
		_metric_box(item, hall, "SideCladding", Vector3(.12, 4.8, 7.0), Vector3(x, 2.9, 0), p.caes_cladding)
		for z in [-3.4, 0.0, 3.4]:
			_metric_box(item, hall, "SteelHallColumn", Vector3(.20, 4.8, .20), Vector3(x, 2.9, z), p.metal)
		_metric_box(item, hall, "CladdingBaseBand", Vector3(.14, .65, 7.0), Vector3(x, .85, 0), p.blue)
	# Three open front bays expose actual equipment, instead of a misleading opaque box.
	for x in [-5.3, 0.0, 5.3]:
		_metric_box(item, hall, "OpenServiceBayColumn", Vector3(.18, 4.8, .18), Vector3(x, 2.9, -3.5), p.metal)
	_metric_box(item, hall, "OpenServiceBayLintel", Vector3(10.8, .45, .22), Vector3(0, 5.1, -3.5), p.blue)
	_metric_box(item, hall, "MachineHallRoof", Vector3(11.0, .18, 7.3), Vector3(0, 5.4, 0), p.caes_roof)
	for x in [-4.8, -2.4, 0.0, 2.4, 4.8]:
		_metric_box(item, hall, "RoofStandingSeam", Vector3(.035, .055, 7.2), Vector3(x, 5.52, 0), p.metal)
	for x in [-3.6, 0.0, 3.6]:
		_metric_box(item, hall, "RoofVentilator", Vector3(.8, .25, 1.1), Vector3(x, 5.6, .8), p.metal)
	_metric_box(item, hall, "OverheadMaintenanceCraneBeam", Vector3(9.8, .28, .30), Vector3(0, 4.35, -.7), p.flow)
	_metric_box(item, hall, "MaintenanceHoist", Vector3(.55, .35, .55), Vector3(-1.7, 4.0, -.7), p.dark)
	_storage_turbomachine(item, hall, "ElectricDrivenAirCompressor", Vector3(-2.6, .3, -.7), p)
	_storage_turbomachine(item, hall, "AirExpanderGenerator", Vector3(2.5, .3, -.7), p)
	for x in [-2.6, 2.5]:
		_metric_rod(item, hall, "MachineInsulatedVerticalPipe", Vector3(x+1.15, 1.45, -1.8), Vector3(x+1.15, 3.3, -1.8), .19, p.ivory)
		_metric_rod(item, hall, "MachineInsulatedOverheadPipe", Vector3(x+1.15, 3.3, -1.8), Vector3(x+1.15, 3.3, 2.9), .19, p.ivory)

static func _storage_caes_heat_recovery(item: EquipmentNode, module: Node3D, p: Dictionary) -> void:
	var heat := _storage_stage(module, "ThermalRecoveryAndStorageArea", Vector3(6, 0, -4.9))
	heat.set_meta("role", "internal_compression_heat_recovery_not_air_inventory")
	heat.set_meta("reference_id", "IET_ZHANGJIAKOU_EXTERIOR")
	# Small original teaching equivalents of the clearly separate thermal vessels;
	# not copies of the project size, heat inventory or pressure specification.
	for x in [-2.1, 2.1]:
		var tank := _storage_stage(heat, "InsulatedThermalBuffer", Vector3(x, 0, -1.1))
		tank.set_meta("contents_role", "thermal_buffer_not_compressed_air")
		var shell := SphereMesh.new()
		shell.radius = .135; shell.height = .27
		shell.radial_segments = 20; shell.rings = 10
		_mesh(item, tank, "InsulatedThermalSphere", shell, Vector3(0, 2.1, 0)*.1, p.metal)
		for sx in [-.8, .8]:
			for sz in [-.8, .8]:
				_metric_box(item, tank, "ThermalTankLeg", Vector3(.12, 1.8, .12), Vector3(sx, 1.1, sz), p.metal)
		_metric_box(item, tank, "ThermalTankTopPlatform", Vector3(.8, .08, .8), Vector3(0, 3.5, 0), p.metal)
		_metric_rod(item, tank, "ThermalReturnPipe", Vector3(0, .75, 0), Vector3(0, .75, 2.3), .10, p.heat_return)
		_metric_rod(item, tank, "ThermalChargePipe", Vector3(1.1, 1.7, 0), Vector3(1.1, 1.7, 2.3), .10, p.heat_primary)
	var exchangers := _storage_stage(heat, "InsulatedHeatExchangerTrain", Vector3(0, 0, 1.8))
	for z in [-.45, .45]:
		_metric_rod(item, exchangers, "InsulatedExchangerShell", Vector3(-2.8, 1.1, z), Vector3(2.8, 1.1, z), .30, p.ivory)
		for x in [-2.6, 2.6]:
			_metric_rod(item, exchangers, "ExchangerEndFlange", Vector3(x-.05, 1.1, z), Vector3(x+.05, 1.1, z), .37, p.metal)
		for x in [-1.9, 1.9]:
			_metric_box(item, exchangers, "ExchangerSupport", Vector3(.25, .65, .5), Vector3(x, .53, z), p.metal)
	_metric_box(item, heat, "ThermalAreaIdentification", Vector3(7.2, .28, .12), Vector3(0, .55, 3.4), p.heat_primary)

static func _storage_caes_receiver(item: EquipmentNode, parent: Node3D, center: Vector3, length: float, radius: float, p: Dictionary) -> void:
	# Pressvess workshop photographs: cylindrical shell, shallow dished ends,
	# two saddles, bolted side manway and flanged nozzle. No capacity inferred.
	var vessel := _storage_stage(parent, "AirReceiver", center)
	vessel.set_meta("shell_form", "cylinder_with_shallow_dished_heads")
	var half_shell := length*.5-radius*.45
	_metric_rod(item, vessel, "AirReceiverShell", Vector3(-half_shell, 0, 0), Vector3(half_shell, 0, 0), radius, p.caes_receiver)
	for side in [-1.0, 1.0]:
		var head := SphereMesh.new()
		head.radius = radius*.1; head.height = radius*.2
		head.radial_segments = 16; head.rings = 8
		var cap := _mesh(item, vessel, "ShallowDishedEnd", head, Vector3(side*half_shell, 0, 0)*.1, p.caes_receiver)
		cap.scale.x = .45
		_metric_box(item, vessel, "AirReceiverSaddle", Vector3(.38, .72, radius*1.65), Vector3(side*length*.29, -radius-.12, 0), p.metal)
		_metric_box(item, vessel, "SaddleFootplate", Vector3(.62, .10, radius*2.0), Vector3(side*length*.29, -radius-.40, 0), p.metal)
		_metric_rod(item, vessel, "ReceiverLiftingLug", Vector3(side*length*.32, radius, -.10), Vector3(side*length*.32, radius+.15, .10), .07, p.metal)
	_metric_rod(item, vessel, "InspectionManway", Vector3(-3.1, 0, -radius), Vector3(-3.1, 0, -radius-.15), .30, p.metal)
	for bolt in 8:
		var angle := TAU * float(bolt)/8.0
		_metric_box(item, vessel, "ManwayBolt", Vector3(.07, .07, .055), Vector3(-3.1+cos(angle)*.235, sin(angle)*.235, -radius-.18), p.dark)
	_metric_rod(item, vessel, "AirOutletFlange", Vector3(length*.5-.05, 0, 0), Vector3(length*.5+.08, 0, 0), .23, p.metal)

static func _storage_liquid_air(item: EquipmentNode, module: Node3D, p: Dictionary) -> void:
	# Highview's CEC 2017 slides 23/24 are actual Slough/Pilsworth photos.
	# Slough tank reads Liquid Nitrogen: component form only, not a claim
	# that this game's liquid-air inventory is pure nitrogen or that a photo
	# proves our original 20x16m / 10MWh teaching module.
	item.set_meta("storage_reference_revision", "primary_photos_20261021")
	item.set_meta("storage_reference_ids", ["HIGHVIEW_CEC2017_SLIDE23", "HIGHVIEW_CEC2017_SLIDE24"])
	item.set_meta("geometry_is_capacity_proof", false)
	item.set_meta("unmetered_external_waste_heat", false)
	var tanks := _storage_stage(module, "InsulatedCryogenicLiquidAirTanks")
	for x in [-4.7, .5]:
		_storage_vertical_tank(item, tanks, "VacuumInsulatedLiquidAirTank", Vector3(x, 0, 3), 2.0, 9.6, p.ivory, p)
		for z in [2.65, 3.35]:
			_metric_rod(item, tanks, "TankServiceLadderRail", Vector3(x + 2.12, .6, z), Vector3(x + 2.12, 9.7, z), .035, p.metal)
		for rung in 29:
			_metric_rod(item, tanks, "TankServiceLadderRung", Vector3(x+2.12,.7+rung*.31,2.65), Vector3(x+2.12,.7+rung*.31,3.35), .027, p.metal)
		_metric_box(item, tanks, "TankValveServicePlatform", Vector3(2.2,.12,1.1), Vector3(x,2.7,.4),p.metal)
		for px in [x-.95,x+.95]:
			_metric_rod(item,tanks,"PlatformSteelLeg",Vector3(px,.25,.4),Vector3(px,2.7,.4),.055,p.metal)
			_metric_rod(item,tanks,"PlatformGuardPost",Vector3(px,2.7,-.1),Vector3(px,3.7,-.1),.028,p.metal)
		_metric_rod(item,tanks,"PlatformGuardRail",Vector3(x-.95,3.7,-.1),Vector3(x+.95,3.7,-.1),.028,p.metal)
	var cold := _storage_stage(module, "LiquefierAndColdBox")
	_storage_cabinet(item, cold, "InsulatedColdBox", Vector3(3.1, 6.2, 3.1), Vector3(6.4, 0, 2.6), p.flow, p)
	_storage_turbomachine(item, cold, "LiquefactionCompressor", Vector3(-5, 0, -4.7), p)
	_storage_turbomachine(item, module, "LiquidAirPumpExpanderGenerator", Vector3(4.5, 0, -4.7), p)
	var recovery := _storage_stage(module, "InternalHeatAndColdRecovery")
	for x in [-1.0,.55]:
		_storage_vertical_tank(item,recovery,"InternalRegeneratorVessel",Vector3(x,0,-4.6),.55,3.3,p.metal,p)
		_metric_rod(item,recovery,"RecoveryBranch",Vector3(x,2.2,-4.6),Vector3(x,2.2,-2.9),.13,p.metal)
	_metric_rod(item, module, "InsulatedTransferHeader", Vector3(-5, 1.1, -2.9), Vector3(6.4, 1.1, -2.9), .22, p.ivory)
	_metric_rod(item,recovery,"RecoveryReturnHeader",Vector3(-5,2.2,-2.9),Vector3(6.4,2.2,-2.9),.16,p.metal)
	for x in [-4.7, .5, 6.4]:
		_metric_rod(item, module, "CryogenicTransferBranch", Vector3(x, 1.1, -2.9), Vector3(x, 1.1, .8), .16, p.ivory)
		for z in [-2.9,-.5]:
			_metric_rod(item,module,"PipeRackSupport",Vector3(x,.2,z),Vector3(x,1.1,z),.045,p.metal)
	for x in [-5,4.5]:
		_metric_rod(item,module,"MachineProcessConnection",Vector3(x,1.1,-2.9),Vector3(x,1.1,-4.0),.16,p.ivory)

static func _storage_hydrogen(item: EquipmentNode, module: Node3D, p: Dictionary) -> void:
	var electrolyzer := _storage_stage(module, "ElectrolyzerAndCompressionStage")
	_storage_cabinet(item, electrolyzer, "ElectrolyzerEnclosure", Vector3(5.0, 3.0, 4.0), Vector3(-8, 0, 1.5), p.hydrogen, p)
	_storage_turbomachine(item, electrolyzer, "HydrogenCompressor", Vector3(-8, 0, -4.2), p)
	var g: Dictionary = item.get_meta("reference_site_geometry",{})
	_storage_pressure_bank(item, module, "HydrogenStorageVesselBank", Vector3(0, 0, 2), int(g.get("vessel_count",5)), float(g.get("outer_total_length_m",5.5)), float(g.get("outer_radius_m",.65)), p)
	var fuelcell := _storage_stage(module, "FuelCellAndInverterStage")
	_storage_cabinet(item, fuelcell, "FuelCellEnclosure", Vector3(4.5, 2.7, 4), Vector3(8, 0, 1.5), p.blue, p)
	_storage_cabinet(item, fuelcell, "FuelCellACInverter", Vector3(3, 2.0, 2), Vector3(8, 0, -4.1), p.metal, p)
	for x in [-3.7, 3.7]:
		_metric_rod(item, module, "InternalHydrogenPipe", Vector3(x, .8, -3.5), Vector3(x, .8, 2), .08, p.hydrogen)
	_metric_rod(item, module, "InternalHydrogenHeader", Vector3(-8, .8, -3.5), Vector3(8, .8, -3.5), .08, p.hydrogen)

static func _storage_solid(item: EquipmentNode, module: Node3D, p: Dictionary) -> void:
	if not (item.get_meta("reference_site_geometry",{}) as Dictionary).is_empty():
		_storage_solid_reference(item,module,p)
		return
	# EnergyNest manufacturing photographs support the framed, manifolded
	# solid-element cassette form. Their thermal-oil/high-temperature product
	# is NOT the performance basis of this fixed 90/60 water teaching store.
	item.set_meta("storage_reference_revision", "primary_photos_20261021")
	item.set_meta("storage_reference_ids", ["ENERGYNEST_CASSETTE_2018", "ENERGYNEST_HANDOVER_2020"])
	item.set_meta("geometry_is_capacity_proof", false)
	item.set_meta("source_product_temperature_is_adopted", false)
	var core := _storage_stage(module, "InsulatedSolidStorageBlock")
	_metric_box(item, core, "SolidThermalBlock", Vector3(6.8, 3.8, 4.4), Vector3(0, 2.3, .2), p.heat_primary)
	_metric_box(item, core, "InsulatedOuterJacket", Vector3(7.0, 4.05, 3.9), Vector3(0, 2.375, .65), p.ivory)
	_metric_box(item, core, "InsulatedRoof", Vector3(7.2, .20, 4.9), Vector3(0, 4.65, .2), p.metal)
	var frame:=_storage_stage(module,"SolidElementCassetteFrame")
	for x in [-3.55,0.0,3.55]:
		for z in [-2.28,2.58]:
			_metric_box(item,frame,"CassettePier",Vector3(.42,.25,.42),Vector3(x,.3,z),p.concrete)
			_metric_box(item,frame,"CassetteSteelPost",Vector3(.13,4.3,.13),Vector3(x,2.4,z),p.metal)
	for y in [.42,4.48]:
		for z in [-2.28,2.58]:
			_metric_box(item,frame,"CassetteLongitudinalBeam",Vector3(7.2,.14,.14),Vector3(0,y,z),p.metal)
	for x in [-3.55,3.55]:
		_metric_rod(item,frame,"CassetteDiagonalBrace",Vector3(x,.5,-2.28),Vector3(x,4.4,2.58),.06,p.metal)
	for x in [-2.7, -1.35, 0.0, 1.35, 2.7]:
		_metric_box(item, core, "JacketPanelSeam", Vector3(.04, 3.9, .06), Vector3(x, 2.4, -1.33), p.metal)
		for y in [1.45,2.2,2.95,3.7]:
			_metric_rod(item,core,"SolidElementEndCap",Vector3(x,y,-2.18),Vector3(x,y,-2.32),.25,p.dark)
			_metric_rod(item,core,"EmbeddedChannelInspectionCap",Vector3(x,y,-2.32),Vector3(x,y,-2.44),.065,p.metal)
		_metric_rod(item, core, "HeatExchangeChannelEnd", Vector3(x, 1.3, -2.2), Vector3(x, 1.3, -2.7), .12, p.heat_primary)
		_metric_rod(item,core,"ClosedReturnBranch",Vector3(x,.65,-2.7),Vector3(x,.65,-2.2),.10,p.heat_return)
	_metric_rod(item, core, "HotWaterInletHeader", Vector3(-3, 1.3, -2.7), Vector3(3, 1.3, -2.7), .16, p.heat_primary)
	_metric_rod(item, core, "ReturnWaterHeader", Vector3(-3, .65, -2.7), Vector3(3, .65, -2.7), .14, p.heat_return)

static func _build_material_facility(item: EquipmentNode, d: Dictionary, palette: Dictionary) -> void:
	if not d.valid: return
	item.set_meta("representation", "material_process_" + item.device_kind)
	item.set_meta("visual_backend", "metric_batched_material")
	item.set_meta("geometry_assumption", d.source_note)
	item.set_meta("geometry_is_capacity_proof", false)
	item.set_meta("pressure_is_simulated", false)
	item.set_meta("temperature_is_dynamic", false)
	item.set_meta("material_phase", d.material_phase)
	item.set_meta("reference_audit", "docs/phase2/MATERIAL_2A_VISUAL_REFERENCES.md")
	var p := palette.duplicate()
	for finish in {"ivory":"82918e", "concrete":"444d48", "metal":"677e83", "hydrogen":"37676a", "water":"537e9b", "composite":"273b40"}:
		var colors := {"ivory":"82918e", "concrete":"444d48", "metal":"677e83", "hydrogen":"37676a", "water":"537e9b", "composite":"273b40"}
		p[finish] = _material(Color(colors[finish]))
		p[finish].roughness = .93
		p[finish].metallic_specular = .15
	var unit: Vector3 = d.unit_dimensions_m
	var display_count := mini(int(d.module_count), 32)
	item.set_meta("display_module_count", display_count)
	item.set_meta("representative_lod", display_count < int(d.module_count))
	for display_index in display_count:
		var index := display_index if display_count == int(d.module_count) else int(round(float(display_index) * (int(d.module_count)-1) / maxi(display_count-1,1)))
		var module := _storage_stage(item, "MaterialModule%03d" % (index+1), Spatial.module_origin_m(d,index))
		_metric_box(item, module, "MaterialFacilityFoundation", Vector3(unit.x,.2,unit.z), Vector3(0,.1,0), p.concrete)
		match item.device_kind:
			"water_supply_boundary": _material_water(item,module,p)
			"electrolyzer_station": _material_electrolyzer(item,module,p)
			"hydrogen_gas_store": _material_gas_store(item,module,p)
			"fuel_cell_station": _material_fuel_cell(item,module,p)
	_combine_static_meshes(item, "MaterialFacilityGeometry")
	# Catalog is the only port contract. Grade, phase, direction and kg/s are
	# copied verbatim, never inferred from an energy-storage visual analogue.
	var specs: Array = preload("res://scripts/device_catalog.gd").ports(item.device_kind)
	var front: float = -d.body_dimensions_m.z * .5 - .45
	for index in specs.size():
		var spec: Dictionary = specs[index]
		var local := Vector3((index-(specs.size()-1)*.5)*1.4,.65,front)*.1
		if spec.carrier == "electricity_ac":
			_named_terminal(item,p,spec.id,local,spec.direction)
			item.named_ports[spec.id].scale = Vector3.ONE*.1
		else:
			_material_terminal(item,p,spec,local)
	item.set_process(false)

static func _material_terminal(item: EquipmentNode, p: Dictionary, spec: Dictionary, local: Vector3) -> void:
	var terminal := Node3D.new()
	terminal.name = "Port_" + str(spec.id)
	terminal.position = local
	item.add_child(terminal)
	terminal.set_meta("port_id",spec.id)
	terminal.set_meta("port_type","material")
	for key in ["direction","carrier","unit","species_id","phase_id","grade_id"]:
		terminal.set_meta(key,spec[key])
	item.named_ports[spec.id] = terminal
	item.named_port_locals[spec.id] = local
	if item.port == null: item.port = terminal; item.port_local = local
	var water: bool = spec.species_id == "H2O"
	var tint: Material = p.water if water else p.hydrogen
	_metric_box(item,terminal,"MaterialSocketBase",Vector3(.60,.12,.48),Vector3(0,-.28,0),p.dark)
	_metric_rod(item,terminal,"WaterRoundCoupling" if water else "GasCoupling",Vector3(0,0,-.17),Vector3(0,0,.1),.18,tint)
	_metric_rod(item,terminal,"CouplingFace",Vector3(0,0,-.21),Vector3(0,0,-.18),.23,p.metal)
	if not water:
		_metric_box(item,terminal,"GasValveStem",Vector3(.04,.22,.04),Vector3(0,.22,0),p.metal)
		_metric_box(item,terminal,"GasValveHandle",Vector3(.32,.04,.07),Vector3(0,.34,0),tint)
	var direction := "入" if spec.direction == "input" else "出"
	var species_label: String = {"H2O":"水 H₂O","H2":"气氢 H₂","N2":"氮气 N₂","CO2":"气态碳源 CO₂"}.get(str(spec.species_id),str(spec.species_id))
	_thermal_label(terminal,"PortLabel",species_label+" "+direction+" · kg/s",Vector3(0,.07,0),24)

static func _material_water(item: EquipmentNode, module: Node3D, p: Dictionary) -> void:
	var tank := _storage_stage(module,"FiniteSectionalWaterReservoir",Vector3(-.8,0,.5))
	tank.set_meta("reference_id","BALMORAL_GRP_PHOTO")
	tank.set_meta("gross_volume_m3",12.0)
	_metric_box(item,tank,"GRPReservoirShell",Vector3(3,2,2),Vector3(0,1.3,0),p.ivory)
	for x in [-1.5,-.5,.5,1.5]:
		for z in [-1.02,1.02]: _metric_box(item,tank,"PanelVerticalFlange",Vector3(.045,2,.055),Vector3(x,1.3,z),p.metal)
	for y in [.3,1.3,2.3]:
		for z in [-1.02,1.02]: _metric_box(item,tank,"PanelHorizontalFlange",Vector3(3,.045,.055),Vector3(0,y,z),p.metal)
	for x in [-1.52,1.52]:
		_metric_box(item,tank,"EndPanelDivider",Vector3(.055,2,.045),Vector3(x,1.3,0),p.metal)
	_metric_box(item,tank,"ReservoirRoof",Vector3(3.08,.1,2.08),Vector3(0,2.35,0),p.metal)
	_metric_box(item,tank,"InspectionHatch",Vector3(.65,.12,.65),Vector3(.65,2.46,0),p.dark)
	for y in range(7): _metric_rod(item,tank,"AccessLadderRung",Vector3(-1.9,.45+y*.3,-.3),Vector3(-1.9,.45+y*.3,.3),.022,p.metal)
	for z in [-.3,.3]: _metric_rod(item,tank,"AccessLadderRail",Vector3(-1.9,.3,z),Vector3(-1.9,2.7,z),.025,p.metal)
	var pump := _storage_stage(module,"WaterMeterAndPumpSkid",Vector3(1.7,0,-1.3))
	pump.set_meta("reference_id","GRUNDFOS_ROTTAL_PHOTO")
	for x in [-.35,.35]:
		_metric_rod(item,pump,"VerticalMultistagePump",Vector3(x,.35,0),Vector3(x,1.15,0),.13,p.metal)
		_metric_rod(item,pump,"PumpTopMotor",Vector3(x,1.15,0),Vector3(x,1.55,0),.20,p.dark)
	_metric_rod(item,pump,"WaterHeader",Vector3(-1.0,.45,0),Vector3(.8,.45,0),.065,p.water)
	_metric_box(item,pump,"OutletFlowMeter",Vector3(.22,.22,.22),Vector3(.65,.58,0),p.blue)
	_metric_rod(item,module,"ReservoirOutlet",Vector3(.7,.5,.5),Vector3(.7,.5,-1.3),.065,p.water)

static func _material_electrolyzer(item: EquipmentNode, module: Node3D, p: Dictionary) -> void:
	var process := _storage_stage(module,"PEMElectrolyzerEnclosure",Vector3(0,0,1.8))
	process.set_meta("reference_id","NEL_MC_ENCLOSURE_AND_DENHAM_FIELD")
	_material_container(item,process,p,Vector3(12.2,3,2.5),p.hydrogen)
	var power := _storage_stage(module,"RectifierPowerSupplyEnclosure",Vector3(-3,0,-2.1))
	_material_container(item,power,p,Vector3(6.1,2.6,2.5),p.blue)
	var cooler := _storage_stage(module,"ElectrolyzerThermalControl",Vector3(3.7,0,-2.1))
	_metric_box(item,cooler,"DryCoolerFrame",Vector3(4.1,1.6,2.1),Vector3(0,1.05,0),p.metal)
	for x in [-1.25,0,1.25]:
		_cylinder(item,cooler,"CoolingFanRing",.050,.050,.012,Vector3(x,1.91,0)*.1,p.dark)
		_metric_box(item,cooler,"FanBlade",Vector3(.78,.045,.10),Vector3(x,1.99,0),p.ivory)
	_metric_rod(item,module,"InternalDCBusTrunk",Vector3(-3,.4,-.85),Vector3(-3,.4,.5),.10,p.dark)
	for x in [5.7,6.2]:
		_metric_rod(item,module,"ProcessVentMast",Vector3(x,.3,1.8),Vector3(x,3.8,1.8),.045,p.metal)
		_metric_rod(item,module,"VentElbow",Vector3(x,3.8,1.8),Vector3(x+.2,3.8,1.8),.045,p.metal)

static func _material_container(item: EquipmentNode, stage: Node3D, p: Dictionary, size: Vector3, stripe: Material) -> void:
	_metric_box(item,stage,"ContainerShell",size,Vector3(0,size.y*.5+.2,0),p.ivory)
	_metric_box(item,stage,"ContainerRoof",Vector3(size.x+.06,.08,size.z+.06),Vector3(0,size.y+.24,0),p.metal)
	for i in 16:
		for z in [-1.0,1.0]:
			_metric_box(item,stage,"Corrugation",Vector3(.045,size.y-.15,.035),Vector3(-size.x*.5+.15+i*(size.x-.3)/15,size.y*.5+.2,z*(size.z*.5+.018)),p.metal)
	for x in [-size.x*.5,size.x*.5]:
		for z in [-size.z*.25,size.z*.25]:
			_metric_box(item,stage,"ContainerEndDoor",Vector3(.04,size.y-.3,size.z*.46),Vector3(x,size.y*.5+.2,z),p.ivory)
			_metric_box(item,stage,"ContainerLockingBar",Vector3(.07,size.y-.6,.035),Vector3(x,size.y*.5+.2,z),p.dark)
	_metric_box(item,stage,"TechnologyBand",Vector3(size.x-.1,.25,.05),Vector3(0,.85,-size.z*.5-.04),stripe)

static func _material_gas_store(item: EquipmentNode, module: Node3D, p: Dictionary) -> void:
	var sized: bool = not (item.get_meta("reference_site_geometry",{}) as Dictionary).is_empty()
	var g: Dictionary = item.get_meta("reference_site_geometry",{})
	var pitch: float = 1.05 if sized else .72
	var rack_half: float = 9.55 if sized else 6.8
	var rack_top: float = 3.85 if sized else 3.45
	var rack := _storage_stage(module,"VerticalCompositeHydrogenCylinderRack",Vector3(0,0,1.8))
	rack.set_meta("reference_id","HEXAGON_VERTICAL_CYLINDER_PHOTO")
	rack.set_meta("gas_only",true)
	rack.set_meta("vessel_count",54)
	# 45-ft-class framing, original teaching arrangement. No sphere and no LH2.
	for i in 18:
		for j in 3:
			var center := Vector3((i-8.5)*pitch,1.92 if sized else 1.72,(j-1)*pitch)
			var mesh := CapsuleMesh.new()
			mesh.radius=float(g.get("outer_radius_m",.32))*.1; mesh.height=float(g.get("outer_total_length_m",2.78))*.1; mesh.radial_segments=12; mesh.rings=3
			_mesh(item,rack,"VerticalGasCylinder",mesh,center*.1,p.composite)
			_metric_rod(item,rack,"CylinderValveNeck",center+Vector3(0,1.565 if sized else 1.39,0),center+Vector3(0,1.76 if sized else 1.58,0),.035,p.metal)
	for y in [.25,rack_top]:
		for z in [-1.65 if sized else -1.18,1.65 if sized else 1.18]: _metric_box(item,rack,"RackLongitudinalRail",Vector3(rack_half*2+.1,.12,.12),Vector3(0,y,z),p.metal)
	for col in 5:
		var x: float = -rack_half+col*rack_half*.5
		for z in [-1.65 if sized else -1.18,1.65 if sized else 1.18]: _metric_box(item,rack,"RackUpright",Vector3(.12,rack_top-.13,.12),Vector3(x,(rack_top+.25)*.5,z),p.metal)
		_metric_box(item,rack,"RackCrossMember",Vector3(.12,.12,3.42 if sized else 2.48),Vector3(x,rack_top,0),p.metal)
		if col<4:
			for z in [-1.67 if sized else -1.2,1.67 if sized else 1.2]:
				_metric_rod(item,rack,"RackDiagonalBrace",Vector3(x,.3,z),Vector3(x+rack_half*.5,rack_top-.05,z),.035,p.metal)
				_metric_rod(item,rack,"RackDiagonalBrace",Vector3(x,rack_top-.05,z),Vector3(x+rack_half*.5,.3,z),.035,p.metal)
	_metric_rod(item,rack,"CylinderManifold",Vector3(-rack_half+.4,rack_top-.1,0),Vector3(rack_half-.2,rack_top-.1,0),.06,p.hydrogen)
	var compressor := _storage_stage(module,"HydrogenCompressorAndValveSkid",Vector3(-3.9,0,-2.2))
	_metric_box(item,compressor,"CompressorBase",Vector3(4.5,.20,2.1),Vector3(0,.3,0),p.dark)
	_metric_rod(item,compressor,"CompressorMotor",Vector3(-1.7,.85,0),Vector3(-.6,.85,0),.38,p.blue)
	_metric_box(item,compressor,"CompressionHeadEnclosure",Vector3(1.7,1.05,1.25),Vector3(.5,.85,0),p.metal)
	for x in [.15,.75]: _metric_rod(item,compressor,"CompressionHead",Vector3(x,.7,-.8),Vector3(x,.7,.8),.18,p.hydrogen)
	_storage_cabinet(item,module,"GasElectricalControl",Vector3(1.4,1.8,1.0),Vector3(3.9,0,-2.2),p.blue,p)
	var valves := _storage_stage(module,"GasDeliveryRegulationAndMetering",Vector3(.4,0,-2.2))
	for x in [-.7,.7]:
		_metric_rod(item,valves,"RegulatedGasBranch",Vector3(x,.65,-.7),Vector3(x,.65,.7),.06,p.hydrogen)
		_metric_rod(item,valves,"IsolationValveStem",Vector3(x,.65,0),Vector3(x,1.05,0),.03,p.metal)
		_metric_box(item,valves,"ValveHandwheel",Vector3(.35,.05,.12),Vector3(x,1.08,0),p.hydrogen)

static func _material_fuel_cell(item: EquipmentNode, module: Node3D, p: Dictionary) -> void:
	var bank := _storage_stage(module,"FuelCellCabinetBank")
	bank.set_meta("reference_id","BALLARD_FCWAVE_CABINET")
	bank.set_meta("cabinet_count",6)
	for i in 6:
		var at := Vector3(-4.0+i*1.55,0,.45)
		var cabinet := _storage_stage(bank,"PEMFuelCellCabinet%02d"%i,at)
		_metric_box(item,cabinet,"FuelCellCabinetShell",Vector3(1.215,2.195,.738),Vector3(0,1.2975,0),p.ivory)
		for x in [-.30,.30]:
			_metric_box(item,cabinet,"CabinetDoor",Vector3(.58,1.84,.035),Vector3(x,1.44,-.386),p.metal)
			for row in 5: _metric_box(item,cabinet,"FrontVentLouver",Vector3(.42,.045,.045),Vector3(x,2.03+row*.065,-.42),p.dark)
		for x in [-.4,0,.4]: _metric_rod(item,cabinet,"FrontServiceCoupling",Vector3(x,.4,-.36),Vector3(x,.4,-.56),.05,p.hydrogen)
	_metric_rod(item,module,"FuelCellHydrogenSupplyHeader",Vector3(-4.6,.40,-.25),Vector3(4.8,.40,-.25),.05,p.hydrogen)
	var cooler := _storage_stage(module,"FuelCellDryCoolingBank",Vector3(-1.5,0,2.15))
	_metric_box(item,cooler,"CoolingBankBody",Vector3(6.3,1.3,1.25),Vector3(0,1.0,0),p.metal)
	for x in [-2.3,-.8,.8,2.3]:
		_cylinder(item,cooler,"CoolingFan",.042,.042,.012,Vector3(x,1.72,0)*.1,p.dark)
		_metric_box(item,cooler,"CoolingFanBlade",Vector3(.67,.03,.09),Vector3(x,1.8,0),p.ivory)
	var inverter := _storage_stage(module,"FuelCellInverterAndACSwitchgear",Vector3(3.9,0,-1.85))
	_storage_cabinet(item,inverter,"InverterCabinet",Vector3(2.4,2.2,1.2),Vector3.ZERO,p.blue,p)

## Murei photograph-derived complete CO2 station. The 5/141/97 counts are
## published; dimensions are a declared original teaching general arrangement.
static func _build_co2_facility(item: EquipmentNode, d: Dictionary, palette: Dictionary) -> void:
	if not d.valid: return
	var p := palette.duplicate()
	for key in {"membrane":"9baead", "liquid":"588392", "thermal":"a48f70", "concrete":"555d55", "hall":"6e8387"}:
		var colors := {"membrane":"9baead", "liquid":"588392", "thermal":"a48f70", "concrete":"555d55", "hall":"6e8387"}
		p[key]=_material(Color(colors[key]));p[key].roughness=.95;p[key].metallic_specular=.1
	item.set_meta("representation","complete_closed_co2_gas_liquid_cycle")
	item.set_meta("visual_backend","metric_batched_co2_site")
	item.set_meta("geometry_assumption",d.source_note)
	item.set_meta("geometry_is_capacity_proof",false)
	item.set_meta("pressure_is_simulated",false)
	item.set_meta("working_fluid_mass_calibrated",false)
	item.set_meta("soc_is_gas_volume",false)
	item.set_meta("closed_working_fluid","CO2")
	item.set_meta("temperature_is_dynamic",false)
	item.set_meta("storage_stages","封闭大气仓 ↔ 压缩/液化与内部蓄热 ↔ 储液阵列 ↔ 气化/回热/膨胀发电")
	item.set_meta("gas_holder_count",5)
	item.set_meta("liquid_storage_unit_count",141)
	item.set_meta("thermal_storage_unit_count",97)
	item.set_meta("display_module_count",1)
	item.set_meta("representative_lod",false)
	_metric_box(item,item,"CO2CompleteSiteFoundation",Vector3(748,.4,748),Vector3(0,.2,0),p.concrete)
	# Five long membrane-like halls; never high-pressure spheres or CAES bottles.
	var holders := _storage_stage(item,"CO2LowPressureGasHolderDistrict")
	holders.set_meta("count",5)
	var positions := [Vector3(-195,0,-275),Vector3(-195,0,-160),Vector3(-195,0,-45),Vector3(195,0,-275),Vector3(195,0,-160)]
	var shell := _co2_gas_holder_mesh()
	for index in 5:
		var holder := _storage_stage(holders,"CO2GasHolder%02d"%(index+1),positions[index])
		holder.set_meta("dimensions_status","original_300x90x44m_teaching_assumption_not_measured")
		_mesh(item,holder,"ArchedFlexibleGasEnvelope",shell,Vector3.ZERO,p.membrane)
		_metric_box(item,holder,"GasHolderPerimeterBase",Vector3(304,.7,94),Vector3(0,.75,0),p.blue)
		_metric_rod(item,holder,"GasHolderProcessConnection",Vector3(0,3,45),Vector3(0,3,50),1.1,p.liquid)
	var liquids := _storage_stage(item,"CO2LiquidStorageDistrict",Vector3(-230,0,200))
	liquids.set_meta("unit_count",141)
	liquids.set_meta("vessel_form_is_teaching_assumption",true)
	# Exact unit counts in low-poly grouped arrangements; form not vendor CAD.
	for index in 141:
		var at := Vector3((index%12-5.5)*16,4.2,(int(index/12)-5.5)*20)
		var tank := CapsuleMesh.new();tank.radius=.26;tank.height=1.4;tank.radial_segments=12;tank.rings=3
		var mesh := _mesh(item,liquids,"LiquidCO2Unit",tank,at*.1,p.liquid)
		mesh.rotation.x=PI*.5
		for z in [-4.1,4.1]: _metric_box(item,liquids,"LiquidUnitSaddle",Vector3(4.3,1.7,.6),Vector3(at.x,1.25,at.z+z),p.metal)
	var heat := _storage_stage(item,"CO2InternalThermalStorageDistrict",Vector3(225,0,190))
	heat.set_meta("unit_count",97)
	heat.set_meta("thermal_medium_unspecified",true)
	for index in 97:
		var at := Vector3((index%10-4.5)*19,0,(int(index/10)-4.5)*21)
		# Insulated generic process unit, not a claim of molten-salt technology.
		_metric_box(item,heat,"InsulatedThermalUnit",Vector3(9,10,13),at+Vector3(0,5.4,0),p.thermal)
		_metric_box(item,heat,"ThermalUnitRoof",Vector3(9.4,.4,13.4),at+Vector3(0,10.6,0),p.metal)
	var core := _storage_stage(item,"CO2CompressionExpansionProcessCore",Vector3(0,0,140))
	core.set_meta("original_layout_not_measured",true)
	for z in [-70,45]:
		_metric_box(item,core,"MachineHall",Vector3(78,25,82),Vector3(0,12.9,z),p.hall)
		_metric_box(item,core,"MachineHallRoof",Vector3(82,1,86),Vector3(0,26,z),p.metal)
		for x in [-24,0,24]: _metric_box(item,core,"MachineHallServiceBay",Vector3(17,13,.5),Vector3(x,7,z-41.2),p.dark)
	var exchange := _storage_stage(item,"CO2HeatExchangeAndLiquefactionTrain",Vector3(190,0,-30))
	for row in 4:
		_metric_rod(item,exchange,"ProcessHeatExchanger",Vector3(-50,7,(row-1.5)*17),Vector3(50,7,(row-1.5)*17),3.8,p.metal)
		for x in [-35,35]: _metric_box(item,exchange,"ExchangerPedestal",Vector3(2,4.2,6),Vector3(x,2.5,(row-1.5)*17),p.dark)
	var gallery := _storage_stage(item,"CO2ClosedLoopPipeGallery")
	for x in [-31,31]:
		_metric_rod(item,gallery,"ClosedCO2Header",Vector3(x,8,-320),Vector3(x,8,320),.8,p.liquid)
		for z in range(-300,321,40): _metric_box(item,gallery,"PipeGallerySupport",Vector3(1.2,7.6,1.2),Vector3(x,4.2,z),p.metal)
	for z in [-275,-160,-45,200]:
		_metric_rod(item,gallery,"CO2DistrictBranch",Vector3(-195,8,z),Vector3(195,8,z),.65,p.liquid)
	# Simple internal lanes, not additional road capacity or buildable cells.
	for x in [-355,0,355]: _metric_box(item,item,"CO2InternalServiceLane",Vector3(8,.07,725),Vector3(x,.44,0),p.gravel)
	for z in [-350,345]: _metric_box(item,item,"CO2InternalServiceLane",Vector3(718,.07,8),Vector3(0,.44,z),p.gravel)
	_combine_static_meshes(item,"CO2CompleteSiteGeometry")
	_named_terminal(item,p,"ac",Vector3(0,.65,375)*.1,"bidirectional")
	item.named_ports.ac.scale=Vector3.ONE*.1
	var port_label: Label3D = item.named_ports.ac.find_child("PortLabel",true,false)
	if port_label!=null: port_label.text="总站 AC 充 ↔ 放"
	_thermal_label(holders,"CO2GasHolderLabel","封闭CO₂气仓 · 5座（SOC不是气仓液位）",Vector3(0,5.4,-27),26)
	_thermal_label(liquids,"CO2LiquidLabel","储液区 · 141示意单元",Vector3(0,2.4,0),26)
	_thermal_label(heat,"CO2HeatLabel","内部蓄热 · 97示意单元（无外售热）",Vector3(0,2.4,0),26)
	item.set_process(false)

static func _co2_gas_holder_mesh() -> ArrayMesh:
	# Long arch with rounded shallow end transitions. Fixed world scale once.
	var st := SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var xs := [-150.0,-148.0,-143.0,-135.0,-125.0,125.0,135.0,143.0,148.0,150.0]
	var scales := [.035,.28,.55,.82,1.0,1.0,.82,.55,.28,.035]
	for row in xs.size()-1:
		for segment in 16:
			var points: Array[Vector3] = []
			for q in [[row,segment],[row+1,segment],[row,segment+1],[row+1,segment+1]]:
				var a: float = float(q[1])*PI/16
				var f: float = scales[q[0]]
				points.append(Vector3(xs[q[0]],1.2+42.8*sin(a)*f,45*cos(a)*f)*.1)
			for i in [0,2,1,1,2,3]: st.add_vertex(points[i])
	st.generate_normals();st.index()
	return st.commit()

## Independent base collector, not a scaled-up compact MV cabinet. Real field
## photos establish the AIS district vocabulary; the layout is explicitly original.
static func _build_collector_substation(item: EquipmentNode, d: Dictionary, palette: Dictionary) -> void:
	if not d.valid: return
	var p := palette.duplicate()
	for key in {"tank":"5c7770", "steel":"7b8b90", "porcelain":"6d6055", "gravel":"777969", "building":"87948e", "road":"505a57", "concrete":"737e78"}:
		var colors := {"tank":"5c7770", "steel":"7b8b90", "porcelain":"6d6055", "gravel":"777969", "building":"87948e", "road":"505a57", "concrete":"737e78"}
		p[key]=_material(Color(colors[key]));p[key].roughness=.86;p[key].metallic_specular=.18
	item.set_meta("representation","complete_collector_ais_substation")
	item.set_meta("visual_backend","metric_batched_collector")
	item.set_meta("geometry_assumption",d.source_note)
	item.set_meta("geometry_is_capacity_proof",false)
	item.set_meta("numeric_voltage_is_simulated",false)
	item.set_meta("has_pv_inverters",false)
	item.set_meta("electrical_topology_is_simulated",false)
	item.set_meta("display_module_count",1)
	item.set_meta("representative_lod",false)
	item.set_meta("transformer_display_count",2)
	item.set_meta("reference_ids",["CORDAL_AIS_FIELD","KIRBY_TRANSFORMER_CT_VT_FIELD","DONEGAL_1120289_AREA"])
	_metric_box(item,item,"CollectorGravelYard",Vector3(96,.20,98),Vector3(0,.10,0),p.gravel)
	var roads := _storage_stage(item,"CollectorAccessAndServiceRoads")
	for x in [-40,40]:_metric_box(item,roads,"PerimeterServiceRoad",Vector3(5,.07,80),Vector3(x,.235,.5),p.road)
	for z in [-42,43]:_metric_box(item,roads,"PerimeterServiceRoad",Vector3(85,.07,5),Vector3(0,.235,z),p.road)
	_metric_box(item,roads,"ControlBuildingAccess",Vector3(5,.07,22.5),Vector3(0,.235,29.25),p.road)
	for x in [-25,25]:
		var transformer := _storage_stage(item,"CollectorPowerTransformer"+str(int(x)),Vector3(x,0,19))
		transformer.set_meta("reference_id","KIRBY_TRANSFORMER_CT_VT_FIELD")
		_collector_transformer(item,transformer,p)
	var ais := _storage_stage(item,"CollectorAISBusbarAndBayYard")
	ais.set_meta("appearance_only_not_circuit_diagram",true)
	for bay in 4:
		var x:float=-30+bay*20
		var bay_node := _storage_stage(ais,"AISBay%02d"%bay,Vector3(x,0,-6))
		_metric_box(item,bay_node,"AISBayConcreteFoundations",Vector3(10,.25,18),Vector3(0,.325,0),p.concrete)
		for phase in 3:
			var px:float=(phase-1)*3
			_collector_insulator(item,bay_node,"InstrumentTransformer",Vector3(px,0,-5),4.6,p)
			_cylinder(item,bay_node,"InstrumentHead",.060,.060,.11,Vector3(px,4.95,-5)*.1,p.steel)
			_collector_insulator(item,bay_node,"CircuitBreakerPole",Vector3(px,0,1),3.8,p)
			_metric_box(item,bay_node,"BreakerDriveBase",Vector3(.9,.65,.7),Vector3(px,.75,1),p.steel)
			_collector_insulator(item,bay_node,"DisconnectorSupport",Vector3(px,0,6),3.4,p)
			_metric_rod(item,bay_node,"DisconnectorBlade",Vector3(px,3.6,4.9),Vector3(px,3.6,7.1),.065,p.steel)
			_metric_rod(item,bay_node,"BayPhaseLead",Vector3(px,4.9,-5),Vector3(px,4.2,1),.035,p.steel)
			_metric_rod(item,bay_node,"BayPhaseLead",Vector3(px,4.2,1),Vector3(px,3.6,6),.035,p.steel)
		_metric_box(item,bay_node,"BayMarshallingCabinet",Vector3(1.1,1.4,.65),Vector3(4.2,1.0,6),p.building)
		_metric_box(item,bay_node,"MarshallingDoor",Vector3(.95,1.15,.035),Vector3(4.2,1.0,5.66),p.steel)
	# Distinct overhead buses and portal supports, absent from compact station.
	var bus := _storage_stage(item,"CollectorOverheadBusbarStructures")
	for z in [-33,-26,-19]:
		_metric_rod(item,bus,"ThreePhaseBusbar",Vector3(-35,7.3,z),Vector3(35,7.3,z),.065,p.steel)
		for x in [-35,-15,15,35]:
			_metric_box(item,bus,"BusSupportFooting",Vector3(1.8,.35,1.8),Vector3(x,.375,z),p.concrete)
			_metric_box(item,bus,"BusSupportSteelPost",Vector3(.16,5,.16),Vector3(x,2.95,z),p.steel)
			_collector_insulator(item,bus,"BusPostInsulator",Vector3(x,4.75,z),2.1,p)
	for x in [-35,35]:
		for z in [-36,-14]:
			_metric_box(item,bus,"PortalSteelLeg",Vector3(.22,10.5,.22),Vector3(x,5.6,z),p.steel)
			_metric_rod(item,bus,"PortalDiagonalBrace",Vector3(x-.9,.3,z),Vector3(x,5.5,z),.07,p.steel)
		_metric_box(item,bus,"PortalCrossbeam",Vector3(.35,.35,23),Vector3(x,10.9,-25),p.steel)
	# Two actual-looking small control buildings, not another transformer.
	var control := _storage_stage(item,"CollectorControlAndProtectionBuildings")
	for side in [-1,1]:
		var x:float=side*12
		_metric_box(item,control,"ControlBuildingPlinth",Vector3(12.5,.35,8.5),Vector3(x,.375,36),p.concrete)
		_metric_box(item,control,"ControlBuildingWalls",Vector3(12,4.4,8),Vector3(x,2.65,36),p.building)
		var roof := _metric_roof_mesh(12.6,9.0,1.5)
		_mesh(item,control,"PitchedControlBuildingRoof",roof,Vector3(x,4.85,36)*.1,p.dark)
		_metric_box(item,control,"ControlRoomDoor",Vector3(1.2,2.4,.07),Vector3(x-3,1.65,31.96),p.steel)
		for wx in [0.0,3.0]: _metric_box(item,control,"ControlRoomWindow",Vector3(1.8,1.0,.06),Vector3(x+wx,2.8,31.96),p.blue)
		for i in 5:_metric_box(item,control,"ControlRoomVent",Vector3(1.5,.08,.06),Vector3(x-3,3.55+i*.15,31.96),p.dark)
	var fence := _storage_stage(item,"CollectorPerimeterPalisadeAndEntryGate")
	for x in range(-47,48):
		for z in [-48.0,48.0]:
			if z>0 and abs(x)<7:continue
			_metric_box(item,fence,"PalisadePicket",Vector3(.045,2.6,.045),Vector3(x,1.5,z),p.steel)
	for z in range(-47,48):
		for x in [-47.0,47.0]:_metric_box(item,fence,"PalisadePicket",Vector3(.045,2.6,.045),Vector3(x,1.5,z),p.steel)
	for y in [.7,2.35]:
		for x in [-47.0,47.0]:_metric_rod(item,fence,"FenceLongRail",Vector3(x,y,-48),Vector3(x,y,48),.045,p.steel)
		_metric_rod(item,fence,"FenceRearRail",Vector3(-47,y,-48),Vector3(47,y,-48),.045,p.steel)
		for side in [-1,1]:_metric_rod(item,fence,"FenceEntryRail",Vector3(side*7,y,48),Vector3(side*47,y,48),.045,p.steel)
	for x in [-7.0,7.0]:_metric_box(item,fence,"EntryGatePost",Vector3(.2,2.9,.2),Vector3(x,1.65,48),p.steel)
	var lightning := _storage_stage(item,"CollectorLightningProtectionMasts")
	for at in [Vector3(-43,0,-39),Vector3(43,0,39)]:
		_metric_box(item,lightning,"LightningMastFoundation",Vector3(1.8,.4,1.8),at+Vector3(0,.4,0),p.concrete)
		_metric_rod(item,lightning,"LightningMast",at+Vector3(0,.4,0),at+Vector3(0,15.4,0),.10,p.steel)
	# Three spatially separated phases connect the transformer bushings to the
	# outer AIS bays. No floating transformer islands or fictitious voltage ports.
	var jumpers := _storage_stage(item,"CollectorTransformerThreePhaseJumpers")
	for side in [-1,1]:
		var tx:float=side*25
		var bx:float=side*30
		for dx in [-4,4]:
			_metric_box(item,jumpers,"JumperPortalFoot",Vector3(1,.3,1),Vector3(bx+dx,.35,8),p.concrete)
			_metric_box(item,jumpers,"JumperPortalLeg",Vector3(.16,4.8,.16),Vector3(bx+dx,2.6,8),p.steel)
		_metric_box(item,jumpers,"JumperPortalBeam",Vector3(8.5,.2,.2),Vector3(bx,4.9,8),p.steel)
		for phase in 3:
			var dx:float=phase-1
			_collector_insulator(item,jumpers,"JumperSupportInsulator",Vector3(bx+dx*3,4.6,8),1.5,p)
			_metric_rod(item,jumpers,"TransformerPhaseJumper",Vector3(tx+dx*2,7,14),Vector3(bx+dx*3,6.5,8),.04,p.steel)
			_metric_rod(item,jumpers,"TransformerPhaseJumper",Vector3(bx+dx*3,6.5,8),Vector3(bx+dx*3,3.6,0),.04,p.steel)
	# Bus take-offs use different heights and x positions: no phase conductor
	# intersects another bus. This is appearance, not a solved wiring topology.
	var bus_links := _storage_stage(item,"CollectorThreePhaseBusTakeoffs")
	for bay in 4:
		for phase in 3:
			var x:float=-30+bay*20+(phase-1)*3
			var z:float=-33+phase*7
			var height:float=9.0-phase*.7
			_metric_rod(item,bus_links,"BusTakeoffRiser",Vector3(x,7.3,z),Vector3(x,height,z),.035,p.steel)
			_metric_rod(item,bus_links,"BusPhaseLead",Vector3(x,height,z),Vector3(x,height,-12),.035,p.steel)
			_metric_rod(item,bus_links,"InstrumentTerminalDrop",Vector3(x,height,-12),Vector3(x,4.95,-11),.035,p.steel)
	var trenches := _storage_stage(item,"CollectorControlCableTrenches")
	for side in [-1,1]:
		_metric_box(item,trenches,"CoveredControlTrench",Vector3(.45,.10,11),Vector3(side*25,.25,24.5),p.concrete)
		_metric_box(item,trenches,"CoveredControlTrench",Vector3(13,.10,.45),Vector3(side*18.5,.25,30),p.concrete)
		_metric_box(item,trenches,"ControlBuildingCableEntry",Vector3(.45,.10,1.5),Vector3(side*12,.25,30.75),p.concrete)
	_combine_static_meshes(item,"CollectorSubstationGeometry")
	for spec in [["in","input",-14.0],["out","output",14.0]]:
		_named_terminal(item,p,spec[0],Vector3(spec[2],.65,50)*.1,spec[1])
		item.named_ports[spec[0]].scale=Vector3.ONE*.1
		var label:Label3D=item.named_ports[spec[0]].find_child("PortLabel",true,false)
		if label!=null:label.text="汇集 AC 入" if spec[0]=="in" else "送出 AC 出"
	_thermal_label(ais,"CollectorModelBoundaryLabel","AIS站级外观 · 未模拟数值电压/保护",Vector3(0,1.65,0),26)
	item.set_process(false)

static func _collector_insulator(item: EquipmentNode,parent:Node3D,label:String,at:Vector3,height:float,p:Dictionary)->void:
	var support:float=height*.48
	_metric_box(item,parent,label+"Foot",Vector3(.7,.2,.7),at+Vector3(0,.3,0),p.concrete)
	_metric_box(item,parent,label+"SteelStand",Vector3(.16,support,.16),at+Vector3(0,support*.5+.4,0),p.steel)
	_metric_rod(item,parent,label+"Stem",at+Vector3(0,support+.4,0),at+Vector3(0,height+.4,0),.085,p.porcelain)
	for ring in 10:
		var y:float=support+.5+ring*(height-support-.2)/9
		_cylinder(item,parent,label+"InsulatorShed",.018,.025,.006,(at+Vector3(0,y,0))*.1,p.porcelain)

static func _collector_transformer(item:EquipmentNode,parent:Node3D,p:Dictionary)->void:
	# Original large power-transformer proportions from the inspected Kirby photos,
	# not enlarged compact-MV cabinet geometry or a copy of its 2MW module.
	_metric_box(item,parent,"TransformerContainmentSlab",Vector3(13,.35,11),Vector3(0,.375,0),p.concrete)
	_metric_box(item,parent,"ContainmentRecess",Vector3(11.8,.06,9.8),Vector3(0,.58,0),p.dark)
	for z in [-5.2,5.2]:_metric_box(item,parent,"ContainmentKerb",Vector3(12.7,.6,.25),Vector3(0,.65,z),p.concrete)
	for x in [-6.25,6.25]:_metric_box(item,parent,"ContainmentKerb",Vector3(.25,.6,10.5),Vector3(x,.65,0),p.concrete)
	_metric_box(item,parent,"MainPowerTransformerTank",Vector3(6.2,3.7,3.7),Vector3(0,2.55,0),p.tank)
	_metric_box(item,parent,"TankTopFlange",Vector3(6.4,.18,3.9),Vector3(0,4.48,0),p.steel)
	for side in [-1,1]:
		for fin in 24:
			_metric_box(item,parent,"PowerTransformerRadiatorFin",Vector3(.10,3.35,1.5),Vector3(-2.9+fin*.25,2.5,side*2.55),p.tank)
		for y in [1.1,4.0]:_metric_rod(item,parent,"RadiatorOilHeader",Vector3(-3,y,side*2.55),Vector3(3,y,side*2.55),.13,p.steel)
	_metric_rod(item,parent,"ConservatorTank",Vector3(-3.1,5.45,1),Vector3(3.1,5.45,1),.65,p.tank)
	for x in [-2.2,2.2]:_metric_box(item,parent,"ConservatorSupport",Vector3(.18,.9,.18),Vector3(x,4.95,1),p.steel)
	for phase in 3:
		var x:float=(phase-1)*2.0
		_collector_insulator(item,parent,"TransformerPhaseBushing",Vector3(x,4.1,-.8),2.5,p)
		_metric_rod(item,parent,"BushingTerminalConductor",Vector3(x,7,-.8),Vector3(x,7,-5),.045,p.steel)
	_metric_box(item,parent,"TransformerAuxiliaryCabinet",Vector3(1.2,1.4,.6),Vector3(3.9,1.4,-2.5),p.building)

static func _metric_roof_mesh(width:float,depth:float,rise:float)->ArrayMesh:
	var a:=Vector3(-width*.5,0,-depth*.5)*.1
	var b:=Vector3(width*.5,0,-depth*.5)*.1
	var c:=Vector3(0,rise,-depth*.5)*.1
	var d:=a+Vector3(0,0,depth*.1)
	var e:=b+Vector3(0,0,depth*.1)
	var f:=c+Vector3(0,0,depth*.1)
	var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [a,c,b,d,e,f,a,d,f,a,f,c,c,f,e,c,e,b]:st.add_vertex(v)
	st.generate_normals();st.index();return st.commit()

## Internal phase/binding-state stores. External ports remain ordinary gas H2;
## distinct original machinery is not a re-skinned compressed cylinder bank.
static func _build_hydrogen_phase_facility(item: EquipmentNode, d: Dictionary, palette: Dictionary) -> void:
	if not d.valid: return
	var p := palette.duplicate()
	var colors := {"ivory":"869d9e","metal":"718a8c","concrete":"535d56","hydrogen":"356b73","water":"4e8194","thermal":"b18550","jacket":"8da6a6","hall":"637b81"}
	for key in colors:
		p[key]=_material(Color(colors[key]));p[key].roughness=.90;p[key].metallic_specular=.15
	item.set_meta("representation","complete_"+item.device_kind)
	item.set_meta("visual_backend","metric_batched_hydrogen_phase_site")
	item.set_meta("geometry_assumption",d.source_note)
	item.set_meta("geometry_is_capacity_proof",false)
	item.set_meta("pressure_is_simulated",false)
	item.set_meta("temperature_is_dynamic",false)
	item.set_meta("internal_inventory_phase",d.material_phase)
	item.set_meta("external_hydrogen_phase","gas")
	item.set_meta("soc_is_liquid_level",false)
	item.set_meta("display_module_count",1)
	item.set_meta("representative_lod",false)
	item.set_meta("reference_audit","docs/phase2/PROCESS_FACILITY_VISUAL_PLAN.md")
	var u:Vector3=d.body_dimensions_m
	_metric_box(item,item,"PhaseStorageSiteFoundation",Vector3(u.x,.2,u.z),Vector3(0,.1,0),p.concrete)
	if item.device_kind=="hydrogen_liquid_store": _phase_liquid_hydrogen(item,p)
	else:
		_phase_lani5_hydrogen(item,p)
		var label:Label3D=item.find_child("LaNi5MaterialLabel",true,false)
		if label!=null:label.text="LaNi₅结合态储氢 · %.1fkg干宿主 / %.2fkg可用氢" % [d.dry_host_mass_kg,d.derived_hydrogen_capacity_kg]
	_combine_static_meshes(item,"HydrogenPhaseFacilityGeometry")
	# Catalog remains the single port source; internal phase changes never
	# create liquid or heat-network connections.
	var specs:Array=preload("res://scripts/device_catalog.gd").ports(item.device_kind)
	for i in specs.size():
		var spec:Dictionary=specs[i]
		var local:=Vector3((i-1)*2.0,.65,-u.z*.5-.45)*.1
		if spec.carrier=="electricity_ac":
			_named_terminal(item,p,spec.id,local,spec.direction);item.named_ports[spec.id].scale=Vector3.ONE*.1
		else:_material_terminal(item,p,spec,local)
	item.set_process(false)

static func _phase_liquid_hydrogen(item:EquipmentNode,p:Dictionary)->void:
	var tank:=_storage_stage(item,"LH2VacuumInsulatedStorage",Vector3(-12,0,-3))
	tank.set_meta("reference_id","AIR_LIQUIDE_LH2_FIELD")
	tank.set_meta("outer_geometry_not_inner_capacity",true)
	var sphere:=SphereMesh.new();sphere.radius=.21;sphere.height=.42;sphere.radial_segments=24;sphere.rings=12
	_mesh(item,tank,"VacuumJacketedLH2Sphere",sphere,Vector3(0,.28,0),p.jacket)
	for x in [-1.3,1.3]:
		for z in [-1.3,1.3]:
			_metric_box(item,tank,"InsulatedTankSupportFoot",Vector3(.8,.3,.8),Vector3(x,.35,z),p.metal)
			_metric_box(item,tank,"TankSupportLeg",Vector3(.16,1.6,.16),Vector3(x,1.15,z),p.metal)
	_metric_box(item,tank,"TankTopServicePlatform",Vector3(1.5,.12,1.5),Vector3(0,4.95,0),p.metal)
	_phase_rail(item,tank,Vector3(-.75,5.9,-.75),Vector3(.75,5.9,-.75),p)
	_phase_rail(item,tank,Vector3(-.75,5.9,.75),Vector3(.75,5.9,.75),p)
	for z in [-.75,.75]:_phase_rail(item,tank,Vector3(-.75,5.9,z),Vector3(-.75,4.95,z),p)
	for y in 15:_metric_rod(item,tank,"TankAccessLadderRung",Vector3(2.35,.5+y*.31,-.27),Vector3(2.35,.5+y*.31,.27),.025,p.metal)
	for z in [-.27,.27]:_metric_rod(item,tank,"TankAccessLadderRail",Vector3(2.35,.25,z),Vector3(2.35,5.35,z),.035,p.metal)
	var cold:=_storage_stage(item,"LH2LiquefierColdBox",Vector3(-.5,0,4))
	cold.set_meta("reference_id","AIR_LIQUIDE_LH2_FIELD")
	_metric_box(item,cold,"InsulatedColdBox",Vector3(4,12,4),Vector3(0,6.25,0),p.ivory)
	for x in [-2.25,2.25]:
		for z in [-2.25,2.25]:_metric_box(item,cold,"ColdBoxFramePost",Vector3(.13,12.3,.13),Vector3(x,6.35,z),p.metal)
	for y in [4.0,8.0,12.4]:
		_metric_box(item,cold,"ColdBoxPlatform",Vector3(5.4,.14,5.4),Vector3(0,y,0),p.metal)
		for z in [-2.65,2.65]:
			_phase_rail(item,cold,Vector3(-2.65,y+1.0,z),Vector3(2.65,y+1.0,z),p)
			for x in [-2.65,0,2.65]:_phase_rail(item,cold,Vector3(x,y,z),Vector3(x,y+1.0,z),p)
		_metric_rod(item,cold,"ColdBoxFrameBrace",Vector3(-2.25,y-3.5,-2.25),Vector3(2.25,y,-2.25),.045,p.metal)
	for y in 40:_metric_rod(item,cold,"ColdBoxLadderRung",Vector3(-3.0,.45+y*.31,-.25),Vector3(-3.0,.45+y*.31,.25),.025,p.thermal)
	for z in [-.25,.25]:_metric_rod(item,cold,"ColdBoxLadderRail",Vector3(-3,.3,z),Vector3(-3,13,z),.035,p.thermal)
	for x in [-1.0,1.0]:_metric_rod(item,cold,"ColdCycleExternalPipe",Vector3(x,.5,-2.5),Vector3(x,11.5,-2.5),.095,p.metal)
	var hall:=_storage_stage(item,"LH2CompressionAndRefrigerationHall",Vector3(10,0,2))
	_metric_box(item,hall,"CompressorHallWalls",Vector3(14,6,10),Vector3(0,3.25,0),p.hall)
	_metric_box(item,hall,"CompressorHallRoof",Vector3(14.4,.25,10.4),Vector3(0,6.4,0),p.metal)
	for x in [-4,4]:_metric_box(item,hall,"CompressorHallServiceDoor",Vector3(3.3,4.1,.07),Vector3(x,2.3,-5.04),p.dark)
	for x in [-4.8,-1.8,1.8,4.8]:_metric_box(item,hall,"CompressorHallVent",Vector3(2,.55,.07),Vector3(x,5.3,-5.04),p.metal)
	var skid:=_storage_stage(item,"LH2LiquefactionCompressorSkids",Vector3(9,0,-6.6))
	for z in [-1.35,1.35]:_storage_turbomachine(item,skid,"LiquefierCompressor",Vector3(0,0,z),p)
	var vapor:=_storage_stage(item,"LH2FiniteAmbientVaporizer",Vector3(-5.6,0,-9))
	vapor.set_meta("heat_source","ambient_finite_rated_vaporizer")
	for x in [-1.5,1.5]:
		_metric_box(item,vapor,"AmbientVaporizerFrame",Vector3(2.2,.25,2.4),Vector3(x,.4,0),p.metal)
		for row in 4:
			for col in 4:
				var at:=Vector3(x+(col-1.5)*.45,.55,(row-1.5)*.50)
				_metric_rod(item,vapor,"AmbientVaporizerTube",at,at+Vector3(0,3.5,0),.055,p.metal)
				_metric_box(item,vapor,"AmbientVaporizerFin",Vector3(.32,3.5,.025),at+Vector3(0,1.75,0),p.ivory)
				_metric_box(item,vapor,"AmbientVaporizerCrossFin",Vector3(.025,3.5,.32),at+Vector3(0,1.75,0),p.ivory)
	var gallery:=_storage_stage(item,"LH2InsulatedTransferAndWarmGasHeaders")
	for line in [[Vector3(-12,1,-3),Vector3(-12,1,4)],[Vector3(-12,1,4),Vector3(-.5,1,4)],[Vector3(-12,1,-3),Vector3(-12,1,-9)],[Vector3(-12,1,-9),Vector3(-5.6,1,-9)]]:
		_metric_rod(item,gallery,"VacuumInsulatedTransferPipe",line[0],line[1],.13,p.jacket)
	_metric_rod(item,gallery,"WarmGasOutputHeader",Vector3(-5.6,.65,-9),Vector3(-5.6,.65,-12.8),.065,p.hydrogen)
	_metric_rod(item,gallery,"GasIntakeHeader",Vector3(9,.65,-12.8),Vector3(9,.65,-6.6),.065,p.hydrogen)
	_metric_rod(item,gallery,"ColdBoxMachineHallConnection",Vector3(-.5,1.8,4),Vector3(9,1.8,4),.11,p.metal)
	var vent:=_storage_stage(item,"LH2BoiloffVentMast",Vector3(-16,0,6))
	_metric_rod(item,vent,"VentStack",Vector3(0,.25,0),Vector3(0,14,0),.075,p.metal)
	_metric_rod(item,vent,"VentStackOutlet",Vector3(0,14,0),Vector3(.6,14,0),.075,p.metal)
	for x in [-.65,.65]:_metric_rod(item,vent,"VentMastBrace",Vector3(x,.25,0),Vector3(0,5,0),.04,p.metal)
	_metric_rod(item,gallery,"BoiloffVentLine",Vector3(-12,4.8,-3),Vector3(-16,4.8,-3),.05,p.metal)
	_metric_rod(item,gallery,"BoiloffVentLine",Vector3(-16,4.8,-3),Vector3(-16,4.8,6),.05,p.metal)
	_phase_dry_cooler(item,item,p,Vector3(10,0,10.6),6)
	_storage_cabinet(item,item,"LH2ControlAndPowerCabinet",Vector3(2.5,2.5,1.4),Vector3(16.2,0,-10),p.blue,p)
	_thermal_label(tank,"LH2PhaseLabel","液氢内库存 · 真空绝热罐（不显示液位/压力）",Vector3(0,.68,0),24)
	_thermal_label(vapor,"LH2VaporizerLabel","有限环境气化器 · 出口仍为气氢",Vector3(0,.55,0),24)

static func _phase_lani5_hydrogen(item:EquipmentNode,p:Dictionary)->void:
	item.set_meta("dry_host_mass_kg",10000.0)
	item.set_meta("derived_hydrogen_capacity_kg",120.0)
	item.set_meta("material_identity","LaNi5_teaching_system_not_GKN_composition")
	var enclosure:=_storage_stage(item,"LaNi5WeatherEnclosedBedModule",Vector3(-5,0,2))
	enclosure.set_meta("reference_id","NREL_GKN_CONTAINER_FORM_ONLY")
	_material_container(item,enclosure,p,Vector3(6.1,3,3.4),p.hydrogen)
	var bed:=_storage_stage(item,"LaNi5JacketedTubularBedRack",Vector3(4.9,0,2))
	bed.set_meta("reference_id","DLR_LANI5_TUBE_AND_HEAT_TRANSFER_EXPERIMENT")
	bed.set_meta("representative_internal_tubes_not_vendor_product",true)
	_metric_box(item,bed,"MaterialBedRackBase",Vector3(6.6,.3,4.4),Vector3(0,.4,0),p.metal)
	for x in [-2.9,2.9]:
		for z in [-2,2]:_metric_box(item,bed,"BedRackUpright",Vector3(.12,3.7,.12),Vector3(x,2.25,z),p.metal)
	_metric_box(item,bed,"WeatherCanopyRoof",Vector3(6.8,.14,4.6),Vector3(0,4.22,0),p.ivory)
	for row in 3:
		for layer in 3:
			var y:float=1.05+layer*.9
			var z:float=(row-1)*1.1
			_metric_rod(item,bed,"HydrideReactionTubeThermalJacket",Vector3(-2.0,y,z),Vector3(2.0,y,z),.23,p.metal)
			_metric_rod(item,bed,"TubeEndFlange",Vector3(1.98,y,z),Vector3(2.10,y,z),.29,p.ivory)
			_metric_rod(item,bed,"HydrogenTubeBranch",Vector3(-2.35,y,z),Vector3(-2.0,y,z),.04,p.hydrogen)
			_metric_rod(item,bed,"ThermalJacketSupplyBranch",Vector3(2.12,y,z),Vector3(2.5,y,z),.055,p.thermal)
			_metric_rod(item,bed,"ThermalJacketReturnBranch",Vector3(2.12,y+.17,z),Vector3(2.75,y+.17,z),.055,p.water)
	for z in [-1.1,0,1.1]:
		_metric_rod(item,bed,"BedGasManifold",Vector3(-2.35,.6,z),Vector3(-2.35,3.2,z),.07,p.hydrogen)
		_metric_rod(item,bed,"HotFluidManifold",Vector3(2.5,.6,z),Vector3(2.5,3.2,z),.075,p.thermal)
		_metric_rod(item,bed,"ReturnFluidManifold",Vector3(2.75,.6,z),Vector3(2.75,3.4,z),.075,p.water)
	var heat:=_storage_stage(item,"LaNi5ElectricHeatingAndCirculation",Vector3(-5.5,0,-4.3))
	heat.set_meta("desorption_heat_source","metered_electric_heater")
	_storage_cabinet(item,heat,"FinitePowerElectricHeater",Vector3(2.8,2.4,1.3),Vector3(-1,0,0),p.thermal,p)
	_storage_vertical_tank(item,heat,"ClosedThermalFluidBuffer",Vector3(1.8,0,0),.55,1.6,p.metal,p)
	_metric_rod(item,heat,"ThermalCirculationPump",Vector3(.5,.65,-.9),Vector3(1.2,.65,-.9),.23,p.blue)
	var cool:=_storage_stage(item,"LaNi5AbsorptionHeatRejection",Vector3(4.5,0,-4.3))
	_phase_dry_cooler(item,cool,p,Vector3.ZERO,6)
	var loop:=_storage_stage(item,"LaNi5ClosedThermalManagementLoop")
	for spec in [[-.85,p.thermal],[-1.1,p.water]]:
		_metric_rod(item,loop,"BedThermalHeader",Vector3(-5.5,.7,spec[0]),Vector3(7.65,.7,spec[0]),.075,spec[1])
		for x in [-5.5,4.5,7.65]:_metric_rod(item,loop,"ThermalMachineBranch",Vector3(x,.7,spec[0]),Vector3(x,.7,-4.3),.075,spec[1])
	_metric_rod(item,loop,"BedThermalReturn",Vector3(7.65,.7,-1.1),Vector3(7.65,.7,3.1),.075,p.water)
	_metric_rod(item,loop,"BedThermalSupply",Vector3(7.4,.7,-.85),Vector3(7.4,.7,3.1),.075,p.thermal)
	_storage_cabinet(item,item,"HydrideControlAndPowerPanel",Vector3(1.2,2.0,1.0),Vector3(-8.8,0,-1.5),p.blue,p)
	_thermal_label(bed,"LaNi5MaterialLabel","LaNi₅结合态储氢 · 10t干宿主 / 120kg可用氢",Vector3(0,.55,0),24)
	_thermal_label(heat,"LaNi5HeatLabel","吸氢排热 / 电热放氢 · 不接外部免费热",Vector3(0,.38,0),24)

static func _phase_rail(item:EquipmentNode,parent:Node3D,a:Vector3,b:Vector3,p:Dictionary)->void:
	_metric_rod(item,parent,"ServiceGuardrail",a,b,.035,p.thermal)

static func _phase_dry_cooler(item:EquipmentNode,parent:Node3D,p:Dictionary,at:Vector3,width:float)->void:
	var cooler:=_storage_stage(parent,"FiniteHeatRejectionDryCooler",at)
	_metric_box(item,cooler,"DryCoolerFrame",Vector3(width,1.5,2),Vector3(0,1.05,0),p.metal)
	for x in [-width*.32,0,width*.32]:
		_cylinder(item,cooler,"CoolerFanRing",.055,.055,.012,Vector3(x,1.85,0)*.1,p.dark)
		_metric_box(item,cooler,"FanBlade",Vector3(.88,.04,.12),Vector3(x,1.94,0),p.ivory)
	for side in [-1,1]:
		for i in 8:_metric_box(item,cooler,"CoolerFinRow",Vector3(width-.2,.045,.055),Vector3(0,.5+i*.16,side*1.025),p.ivory)

## Separate finite-material boundary and synthesis sites. Actual material ports
## come only from Catalog; these internal machines never supply free reagents.
static func _build_chemical_facility(item:EquipmentNode,d:Dictionary,palette:Dictionary)->void:
	if not d.valid:return
	var p:=palette.duplicate()
	var colors:Dictionary={"ivory":"91a4a3","metal":"71898d","concrete":"515e58","gas":"60866d","co2":"6d8e98","hall":"586e79","thermal":"ba9860","hydrogen":"6097a1"}
	for key in colors:
		p[key]=_material(Color(colors[key]));p[key].roughness=.92;p[key].metallic_specular=.12
	item.set_meta("representation","complete_"+item.device_kind)
	item.set_meta("visual_backend","metric_batched_chemical_site")
	item.set_meta("geometry_assumption",d.source_note)
	for key in ["geometry_is_capacity_proof","pressure_is_simulated","temperature_is_dynamic","soc_is_gas_volume","has_free_material_source"]:item.set_meta(key,false)
	item.set_meta("display_module_count",1);item.set_meta("representative_lod",false)
	item.set_meta("reference_audit","docs/phase2/PROCESS_FACILITY_VISUAL_PLAN.md")
	var u:Vector3=d.body_dimensions_m
	_metric_box(item,item,"ChemicalSiteFoundation",Vector3(u.x,.2,u.z),Vector3(0,.1,0),p.concrete)
	match item.device_kind:
		"nitrogen_supply_boundary":_chemical_nitrogen_source(item,p)
		"co2_supply_boundary":_chemical_co2_source(item,p)
		"ammonia_synthesis_station":_chemical_synthesis_plant(item,p,false)
		"methanol_synthesis_station":_chemical_synthesis_plant(item,p,true)
	_combine_static_meshes(item,"ChemicalFacilityGeometry")
	var specs:Array=preload("res://scripts/device_catalog.gd").ports(item.device_kind)
	for i in specs.size():
		var spec:Dictionary=specs[i]
		var local:=Vector3((i-(specs.size()-1)*.5)*3.0,.65,-u.z*.5-.45)*.1
		if spec.carrier=="electricity_ac":
			_named_terminal(item,p,spec.id,local,spec.direction);item.named_ports[spec.id].scale=Vector3.ONE*.1
		else:_material_terminal(item,p,spec,local)
	item.set_process(false)

static func _chemical_nitrogen_source(item:EquipmentNode,p:Dictionary)->void:
	var groups:=_storage_stage(item,"FinitePreparedNitrogenBottleBundles")
	groups.set_meta("reference_id","MORRIS_N2_PHOTO_AND_BOC_CYLINDERS")
	groups.set_meta("is_air_separation_plant",false)
	# Eight prepared-gas bundles; no claim of vendor-certified pressure or kg.
	for n in 8:
		var at:=Vector3(-5.7+(n%4)*3.8,0,-2.0+int(n/4)*4.1)
		var bundle:=_storage_stage(groups,"NitrogenBundle%02d"%n,at)
		_metric_box(item,bundle,"BottleBundleSkid",Vector3(1.7,.16,1.3),Vector3(0,.28,0),p.metal)
		for row in 3:
			for col in 5:
				var x:float=-.60+col*.30;var z:float=-.30+row*.30
				var mesh:=CapsuleMesh.new();mesh.radius=.012;mesh.height=.155;mesh.radial_segments=10;mesh.rings=3
				_mesh(item,bundle,"PreparedNitrogenSteelCylinder",mesh,Vector3(x,1.15,z)*.1,p.gas)
				_metric_rod(item,bundle,"CylinderValveGuard",Vector3(x,1.90,z),Vector3(x,2.12,z),.045,p.metal)
		for x in [-.82,.82]:
			for z in [-.62,.62]:_metric_box(item,bundle,"BottleBundleUpright",Vector3(.07,2.05,.07),Vector3(x,1.37,z),p.metal)
		_metric_rod(item,bundle,"BundleValveManifold",Vector3(-.7,2.18,0),Vector3(.7,2.18,0),.045,p.metal)
		_metric_rod(item,groups,"BundleDeliveryBranch",at+Vector3(0,.55,0),Vector3(at.x,.55,4.7),.045,p.gas)
	var meter:=_storage_stage(item,"NitrogenRegulationAndMetering",Vector3(0,0,4.7))
	_metric_rod(item,meter,"CommonFiniteGasHeader",Vector3(-6,.55,0),Vector3(6,.55,0),.075,p.gas)
	for x in [-1,1]:
		_metric_box(item,meter,"PressureReductionBody",Vector3(.5,.5,.4),Vector3(x,.8,0),p.metal)
		_metric_rod(item,meter,"ValveHandwheelStem",Vector3(x,.9,0),Vector3(x,1.3,0),.035,p.metal)
	_storage_cabinet(item,meter,"GasMeterCabinet",Vector3(1.4,1.6,.9),Vector3(2.7,0,0),p.blue,p)
	for x in [-7.8,7.8]:
		for z in [-5.5,5.7]:_metric_rod(item,item,"SupplyBayBollard",Vector3(x,.2,z),Vector3(x,1.3,z),.09,p.thermal)

static func _chemical_co2_source(item:EquipmentNode,p:Dictionary)->void:
	var holder:=_storage_stage(item,"FiniteCO2FlexibleGasBuffer")
	holder.set_meta("reference_id","PRESENCO_REAL_FLEXIBLE_GAS_BAGS")
	holder.set_meta("geometry_volume_status","original_outer_ellipsoid_748m3_not_certified_working_volume")
	# 1000kg CO2 at 25C and 1 atm is ~556m3. 17x8.4x10m outer
	# ellipsoid is ~748m3: order-of-magnitude allowance, not a pressure model.
	var mesh:=SphereMesh.new();mesh.radius=1;mesh.height=2;mesh.radial_segments=32;mesh.rings=16
	var bag:=_mesh(item,holder,"FabricGasBufferNotLiquidTank",mesh,Vector3(0,.44,0),p.co2)
	bag.scale=Vector3(.85,.42,.50)
	for x in [-8.8,-4.4,0,4.4,8.8]:
		for z in [-5.8,5.8]:
			_metric_box(item,holder,"SuspensionSteelPost",Vector3(.12,9.0,.12),Vector3(x,4.7,z),p.metal)
			var q:float=sqrt(maxf(0,1-pow(x*.85/8.5,2)))
			_metric_rod(item,holder,"FabricSuspensionTether",Vector3(x,8.5,z),Vector3(x*.85,4.4+4.2*q*.70710678,signf(z)*5*q*.70710678),.018,p.dark)
		_metric_box(item,holder,"SuspensionCrossRail",Vector3(.12,.12,11.7),Vector3(x,9.15,0),p.metal)
	for z in [-5.8,5.8]:_metric_box(item,holder,"SuspensionLongRail",Vector3(17.8,.12,.12),Vector3(0,9.15,z),p.metal)
	# Seam arcs follow the fabric surface, not rigid pressure-vessel hoops.
	for x in [-6,-3,0,3,6]:
		var q:float=sqrt(maxf(0,1-pow(x/8.5,2)))
		for step in 20:
			var a:float=PI*step/20.0;var b:float=PI*(step+1)/20.0
			_metric_rod(item,holder,"FabricWeldSeam",Vector3(x,4.4+4.21*q*sin(a),5.01*q*cos(a)),Vector3(x,4.4+4.21*q*sin(b),5.01*q*cos(b)),.014,p.metal)
	var outlet:=_storage_stage(item,"CO2GasOutletMeterAndIsolation",Vector3(0,0,-6.2))
	for x in [-1,1]:
		_metric_rod(item,outlet,"FlexibleGasNeck",Vector3(x,1.2,1.6),Vector3(x,1.2,0),.16,p.co2)
		_metric_box(item,outlet,"GasIsolationValve",Vector3(.38,.38,.38),Vector3(x,1.2,0),p.metal)
	_metric_rod(item,outlet,"GasOnlyCommonOutlet",Vector3(-1,1.2,0),Vector3(2.2,1.2,0),.12,p.co2)
	_storage_cabinet(item,outlet,"CO2MeterCabinet",Vector3(1.5,1.8,.8),Vector3(3.4,0,0),p.blue,p)

static func _chemical_hall(item:EquipmentNode,parent:Node3D,p:Dictionary,size:Vector3,at:Vector3)->void:
	_metric_box(item,parent,"ProcessHallWalls",size,at+Vector3(0,size.y*.5+.2,0),p.hall)
	_mesh(item,parent,"PitchedProcessHallRoof",_metric_roof_mesh(size.x+.3,size.z+.3,.8),(at+Vector3(0,size.y+.25,0))*.1,p.metal)
	for x in [-size.x*.25,size.x*.25]:
		_metric_box(item,parent,"ProcessHallAccessDoor",Vector3(3,3.8,.06),at+Vector3(x,2.1,-size.z*.5-.035),p.ivory)
		_metric_box(item,parent,"HallVentilationLouver",Vector3(3,.8,.08),at+Vector3(x,size.y-1,-size.z*.5-.05),p.dark)

static func _chemical_process_frame(item:EquipmentNode,parent:Node3D,p:Dictionary,at:Vector3,height:float)->void:
	var frame:=_storage_stage(parent,"SynthesisAndSeparationSteelFrame",at)
	for x in [-6.5,0,6.5]:
		for z in [-6.5,6.5]:_metric_box(item,frame,"ProcessFrameColumn",Vector3(.22,height,.22),Vector3(x,height*.5+.2,z),p.metal)
	for y in [4.0,8.0,height]:
		for z in [-6.5,6.5]:
			_metric_box(item,frame,"ProcessFrameBeam",Vector3(13.2,.22,.22),Vector3(0,y,z),p.metal)
			_phase_rail(item,frame,Vector3(-6.5,y+1,z),Vector3(6.5,y+1,z),p)
		_metric_box(item,frame,"ServiceGallery",Vector3(1,.12,13),Vector3(-5.9,y,0),p.metal)
		_metric_rod(item,frame,"FrameBrace",Vector3(-6.5,maxf(.2,y-4),6.5),Vector3(0,y,6.5),.065,p.metal)
	for x in [-3.1,1.0]:
		_storage_vertical_tank(item,frame,"InternalReactionSeparationVessel",Vector3(x,0,0),.85,height-1.8,p.ivory,p)
	_metric_rod(item,frame,"ReactionRecycleHeader",Vector3(-3.1,height-2,0),Vector3(1,height-2,0),.13,p.metal)
	for y in range(int(height/.32)):_metric_rod(item,frame,"FrameAccessLadderRung",Vector3(-7.0,.4+y*.32,-.32),Vector3(-7.0,.4+y*.32,.32),.026,p.metal)
	for z in [-.32,.32]:_metric_rod(item,frame,"FrameAccessLadderRail",Vector3(-7,.2,z),Vector3(-7,height+1,z),.035,p.metal)

static func _chemical_synthesis_plant(item:EquipmentNode,p:Dictionary,methanol:bool)->void:
	item.set_meta("product_phase","liquid" if methanol else "gas")
	item.set_meta("has_product_network_output",false)
	item.set_meta("unmetered_external_heat",false)
	var hall:=_storage_stage(item,"MethanolProductionHall" if methanol else "AmmoniaProductionHall")
	hall.set_meta("reference_id","EUROPEAN_ENERGY_KASSO_CONSTRUCTION" if methanol else "TOPSOE_RAMME_REAL_PLANT")
	_chemical_hall(item,hall,p,Vector3(22,8 if methanol else 7,20 if methanol else 18),Vector3(-19 if methanol else -17,0,4))
	var process:=_storage_stage(item,"MethanolSynthesisAndDistillation" if methanol else "AmmoniaSynthesisRecycleAndSeparation")
	_chemical_process_frame(item,process,p,Vector3(8,0,4),15 if methanol else 11.5)
	if methanol:
		_storage_vertical_tank(item,process,"MethanolDistillationColumn",Vector3(20,0,5),1.1,17.4,p.ivory,p)
		_metric_rod(item,process,"DistillationFeedPipe",Vector3(9,4.4,4),Vector3(20,4.4,4),.16,p.metal)
	var thermal:=_storage_stage(item,"FiniteElectricHeatingAndHeatRejection",Vector3(-1,0,-13))
	_storage_cabinet(item,thermal,"ProcessElectricHeater",Vector3(4.6,2.7,2.6),Vector3(-3,0,0),p.thermal,p)
	_phase_dry_cooler(item,thermal,p,Vector3(4,0,0),5.0)
	_storage_turbomachine(item,item,"MaterialRecycleCompressor",Vector3(1,0,14 if not methanol else 18),p)
	var buffer:=_storage_stage(item,"FiniteMethanolLiquidProductBuffer" if methanol else "FiniteAmmoniaGasProductBuffer")
	if methanol:
		# 1000kg liquid methanol ~1.26m3; small buffered product, not a tank farm.
		_metric_box(item,buffer,"ProductContainmentPad",Vector3(6,.16,5),Vector3(26,.28,-15),p.metal)
		for z in [-17.5,-12.5]:_metric_box(item,buffer,"ProductContainmentBund",Vector3(6,.5,.16),Vector3(26,.53,z),p.concrete)
		for x in [23,29]:_metric_box(item,buffer,"ProductContainmentBund",Vector3(.16,.5,5),Vector3(x,.53,-15),p.concrete)
		_storage_vertical_tank(item,buffer,"SmallMethanolLiquidBuffer",Vector3(26,0,-15),.75,1.6,p.ivory,p)
	else:
		# Four narrow gas receivers, not the Morris 3000-gallon liquid tank.
		# Gas density/pressure/condensation are NOT inferred from this drawing.
		var g: Dictionary = item.get_meta("reference_site_geometry",{})
		for x in [12,16,20,24]:
			if g.is_empty(): _storage_vertical_tank(item,buffer,"AmmoniaGasReceiver",Vector3(x,0,-12),.85,7,p.gas,p)
			else:
				var body := CapsuleMesh.new()
				body.radius=float(g.outer_radius_m)*.1; body.height=float(g.outer_total_length_m)*.1; body.radial_segments=20; body.rings=6
				_mesh(item,buffer,"AmmoniaGasReceiver",body,Vector3(x,.55+float(g.outer_total_length_m)*.5,-12)*.1,p.gas)
				for z in [-12.5,-11.5]: _metric_box(item,buffer,"ReceiverSupportLeg",Vector3(.16,.9,.16),Vector3(x,.65,z),p.metal)
				_metric_rod(item,buffer,"ReceiverTopServicePipe",Vector3(x+.98,.55,-12),Vector3(x+.98,9.0,-12),.055,p.metal)
		_metric_rod(item,buffer,"AmmoniaGasProductHeader",Vector3(12,1.4,-12),Vector3(24,1.4,-12),.12,p.gas)
	# Product and thermal utility circuits are visible connections, not extra ports.
	var transfer:=_storage_stage(item,"ProductAndThermalUtilityConnections")
	var bx:float=26.0 if methanol else 12.0
	var bz:float=-15.0 if methanol else -12.0
	_metric_rod(item,transfer,"ProductTransferFromSeparator",Vector3(9,1.4,4),Vector3(bx,1.4,4),.09,p.gas if not methanol else p.metal)
	_metric_rod(item,transfer,"ProductTransferToFiniteBuffer",Vector3(bx,1.4,4),Vector3(bx,1.4,bz),.09,p.gas if not methanol else p.metal)
	for y in [.65,.95]:
		_metric_rod(item,transfer,"InternalThermalUtilityHeader",Vector3(-4,y,-13),Vector3(8,y,-13),.08,p.thermal)
		_metric_rod(item,transfer,"InternalThermalUtilityBranch",Vector3(8,y,-13),Vector3(8,y,4),.08,p.thermal)
	var utility:=_storage_stage(item,"SynthesisElectricalControlAndPipeRack")
	_storage_cabinet(item,utility,"PlantElectricalControl",Vector3(7.0,3.0,4.5),Vector3(-20,0,-13),p.blue,p)
	for z in [-7,10]:
		_metric_rod(item,utility,"InternalProcessPipeHeader",Vector3(-18,4.1,z),Vector3(21,4.1,z),.15,p.metal)
		for x in [-15,-5,5,15]:
			_metric_box(item,utility,"ProcessPipeRackPost",Vector3(.16,4,.16),Vector3(x,2.2,z),p.metal)
			_metric_box(item,utility,"ProcessPipeRackCrossbeam",Vector3(.18,.18,2),Vector3(x,4.2,z),p.metal)
	for x in [-3,8,20]:_metric_rod(item,utility,"InternalTransferBranch",Vector3(x,4.1,-7),Vector3(x,4.1,10),.10,p.metal)
	var w:float=72 if methanol else 60;var depth:float=50 if methanol else 40
	for x in [-w*.5+2,w*.5-2]:_metric_box(item,item,"PlantServiceRoad",Vector3(3,.025,depth-1),Vector3(x,.215,0),p.gravel)

## Reference-size steel cassettes. The 8x5x4.5 m net core is independent
## of the outer jacket; 20% of its volume is reserved for channels/voids.
static func _storage_solid_reference(item: EquipmentNode, module: Node3D, p: Dictionary) -> void:
	var g: Dictionary = item.get_meta("reference_site_geometry")
	var core_size: Vector3 = g.core_dimensions_m
	item.set_meta("storage_reference_revision","primary_photos_20261021_reference_size_v1")
	item.set_meta("storage_reference_ids",["ENERGYNEST_CASSETTE_2018","ENERGYNEST_HANDOVER_2020"])
	item.set_meta("geometry_is_capacity_proof",false)
	item.set_meta("source_product_temperature_is_adopted",false)
	var core := _storage_stage(module,"InsulatedSolidStorageBlock")
	core.set_meta("net_core_dimensions_m",core_size)
	core.set_meta("solid_volume_fraction",g.solid_fraction)
	_metric_box(item,core,"SolidThermalBlock",core_size,Vector3(0,3.0,.15),p.heat_primary)
	_metric_box(item,core,"InsulatedOuterJacket",Vector3(8.4,5.4,4.4),Vector3(0,3.0,.45),p.ivory)
	_metric_box(item,core,"InsulatedRoof",Vector3(8.8,.2,5.35),Vector3(0,5.85,.15),p.metal)
	var frame := _storage_stage(module,"SolidElementCassetteFrame")
	for x in [-4.3,0.0,4.3]:
		for z in [-2.5,2.8]:
			_metric_box(item,frame,"CassettePier",Vector3(.45,.3,.45),Vector3(x,.35,z),p.concrete)
			_metric_box(item,frame,"CassetteSteelPost",Vector3(.15,5.5,.15),Vector3(x,3.15,z),p.metal)
	for y in [.5,5.8]:
		for z in [-2.5,2.8]:_metric_box(item,frame,"CassetteLongitudinalBeam",Vector3(8.75,.16,.16),Vector3(0,y,z),p.metal)
	for x in [-4.3,4.3]:_metric_rod(item,frame,"CassetteDiagonalBrace",Vector3(x,.55,-2.5),Vector3(x,5.75,2.8),.065,p.metal)
	for x in [-3.2,-1.6,0.0,1.6,3.2]:
		_metric_box(item,core,"JacketPanelSeam",Vector3(.04,5.1,.06),Vector3(x,3.0,-1.78),p.metal)
		for y in [1.4,2.5,3.6,4.7]:
			_metric_rod(item,core,"SolidElementEndCap",Vector3(x,y,-2.09),Vector3(x,y,-2.35),.3,p.dark)
			_metric_rod(item,core,"EmbeddedChannelInspectionCap",Vector3(x,y,-2.35),Vector3(x,y,-2.48),.07,p.metal)
		_metric_rod(item,core,"HeatExchangeChannelEnd",Vector3(x,1.05,-2.12),Vector3(x,1.05,-3.05),.12,p.heat_primary)
		_metric_rod(item,core,"ClosedReturnBranch",Vector3(x,.65,-3.05),Vector3(x,.65,-2.12),.10,p.heat_return)
	_metric_rod(item,core,"HotWaterInletHeader",Vector3(-3.5,1.05,-3.05),Vector3(3.5,1.05,-3.05),.16,p.heat_primary)
	_metric_rod(item,core,"ReturnWaterHeader",Vector3(-3.5,.65,-3.05),Vector3(3.5,.65,-3.05),.14,p.heat_return)

## Dedicated metric builder avoids fitting the legacy illustrative water tank
## or its old GLB into a larger nominal envelope without enlarging the cavity.
static func _build_reference_water_store(item: EquipmentNode, d: Dictionary, p: Dictionary) -> void:
	if not d.valid:return
	var g: Dictionary = d.reference_site_geometry
	_thermal_metadata(item,"fixed_grade_two_zone_heat_store")
	item.set_meta("visual_backend","metric_reference_water_store")
	item.set_meta("fixed_temperature_profile","90/60°C")
	item.set_meta("storage_approximation","两只并联分层水库存；总净腔80%作工作水体积，20%顶空；不是两份全量库存")
	item.set_meta("soc_changes_temperature",false)
	item.set_meta("geometry_is_capacity_proof",false)
	var u: Vector3 = d.unit_dimensions_m
	_metric_box(item,item,"ThermalStoreFoundation",Vector3(u.x,.2,u.z),Vector3(0,.1,0),p.concrete)
	for index in 2:
		var x: float = -2.6+index*5.2
		var tank := _storage_stage(item,"ReferenceStratifiedWaterTank%d"%index,Vector3(x,0,0))
		tank.set_meta("internal_radius_m",g.inner_radius_m)
		tank.set_meta("internal_straight_length_m",g.inner_straight_length_m)
		var r: float = g.outer_radius_m
		var h: float = g.outer_total_length_m
		_cylinder(item,tank,"TankFoot%d"%index,(r+.12)*.1,(r+.12)*.1,.025,Vector3(0,.325,0)*.1,p.metal)
		_cylinder(item,tank,"FixedReturnZone%d"%index,r*.1,r*.1,h*.05,Vector3(0,.45+h*.25,0)*.1,p.heat_return)
		_cylinder(item,tank,"FixedSupplyZone%d"%index,r*.1,r*.1,h*.05,Vector3(0,.45+h*.75,0)*.1,p.heat_primary)
		_cylinder(item,tank,"FixedZoneDivider%d"%index,(r+.025)*.1,(r+.025)*.1,.012,Vector3(0,.45+h*.5,0)*.1,p.metal)
		_cylinder(item,tank,"TankInsulatedCap%d"%index,r*.1,(r-.2)*.1,.025,Vector3(0,.575+h,0)*.1,p.ivory)
		for y in [1.4,3.6,5.8]:_cylinder(item,tank,"InsulationBand",(r+.025)*.1,(r+.025)*.1,.008,Vector3(0,y,0)*.1,p.metal)
		_metric_box(item,tank,"TopServiceHatch",Vector3(.6,.15,.6),Vector3(0,h+.78,0),p.metal)
		for z in [-.35,.35]:_metric_rod(item,tank,"AccessLadderRail",Vector3(r+.22,.35,z),Vector3(r+.22,h+.8,z),.035,p.metal)
		for step in 20:_metric_rod(item,tank,"AccessLadderRung",Vector3(r+.22,.55+step*.32,-.35),Vector3(r+.22,.55+step*.32,.35),.025,p.metal)
	_metric_rod(item,item,"HotWaterSupplyHeader",Vector3(-2.6,1.1,-2.4),Vector3(2.6,1.1,-2.4),.13,p.heat_primary)
	_metric_rod(item,item,"WaterReturnHeader",Vector3(-2.6,.65,-2.4),Vector3(2.6,.65,-2.4),.11,p.heat_return)
	for x in [-2.6,2.6]:
		_metric_rod(item,item,"StoreServiceManifold",Vector3(x,1.1,-1.9),Vector3(x,1.1,-2.75),.13,p.heat_primary)
		_metric_rod(item,item,"StoreReturnManifold",Vector3(x,.65,-1.9),Vector3(x,.65,-2.75),.11,p.heat_return)
	# Physical closed-loop return nozzles remain separate from the two logical
	# supply-side graph ports; they never add another edge, flow or energy stock.
	for id in ["heat_in","heat_out"]:
		var x:float=-2.6 if id=="heat_in" else 2.6
		var return_position:=Vector3(x,.65,-3.35)*.1
		_metric_rod(item,item,"ReferenceReturnNozzle_"+id,Vector3(x,.65,-2.75),Vector3(x,.65,-3.35),.11,p.heat_return)
		item.physical_return_locals[id]=return_position
	_combine_static_meshes(item,"ReferenceWaterStoreGeometry")
	for id in ["heat_in","heat_out"]:
		_named_terminal(item,p,id,Vector3(-2.6 if id=="heat_in" else 2.6,1.1,-3.35)*.1,"input" if id=="heat_in" else "output","hw_primary_90_60")
		item.named_ports[id].scale=Vector3.ONE*.1
	item.thermal_soc_label=_thermal_label(item,"ThermalSOC","库存 SOC —",Vector3(0,.18,-.27),28)
	item.thermal_soc_label.no_depth_test=true
	item.set_process(false)
