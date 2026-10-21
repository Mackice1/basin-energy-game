extends Node3D
## Whole-facility map representation. The internal station scene owns devices,
## capacities and dispatch; this facade only draws externally supplied status.
## ac_in is the shared visual boundary for each mapped electric-boiler input
## and fuel-boiler auxiliary input. The host picker resolves individual devices.

const FOOTPRINT_RADIUS := 8.0
const Spatial = preload("res://scripts/spatial_dimensions.gd")
const Visual = preload("res://scripts/equipment_visual.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
const PORT_LOCALS := {
	"ac_in": Vector3(-7.1, 1.05, 0.8),
	"heat_out": Vector3(7.1, 1.05, 0.8),
}
const UI_FONT = preload("res://assets/InterfaceCJK.ttc")
const BLENDER_ASSET := "res://assets/models/thermal_station.glb"
static var _blender_scene: PackedScene

var surfaces: Array[MeshInstance3D] = []
var base_materials: Array[Material] = []
var selection_ring: MeshInstance3D
var title_label: Label3D
var status_label: Label3D
var named_ports: Dictionary = {}
var named_port_locals: Dictionary = PORT_LOCALS.duplicate()
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
var preview_good: StandardMaterial3D
var preview_bad: StandardMaterial3D
var footprint_radius := FOOTPRINT_RADIUS
var preview_only := false
var tower_site := false
var tower_geometry:Node3D
var installed_device_nodes: Dictionary = {}

func setup(station_data: Dictionary, prefer_blender_assets: bool = true) -> void:
	# Rebuilding is safe for restored saves and placement previews. Input is never
	# retained or mutated, so this display cannot become a second energy model.
	for child in get_children():
		remove_child(child)
		child.free()
	installed_device_nodes.clear()
	tower_geometry = null
	surfaces.clear()
	base_materials.clear()
	named_ports.clear()
	annotation_labels.clear()
	named_port_locals = PORT_LOCALS.duplicate()
	for key in ["visual_backend", "asset_source", "asset_fallback", "visual_only", "capacity_added", "visual_dimension_profile", "footprint_radius", "world_units_per_meter", "body_dimensions_m", "land_area_m2", "energy_port_count", "preview_only", "commissioned", "installed_device_count", "installed_device_ids", "installed_geometry_contract", "legacy_scale_migration_required"]:
		if has_meta(key):
			remove_meta(key)
	name = "ThermalStationFacade"
	var title := str(station_data.get("name", station_data.get("title", "电热储能站"))).strip_edges()
	if title.is_empty():
		title = "电热储能站"
	var p := {
		"wall": _material(Color("c8d8c7")),
		"roof": _material(Color("69877a"), 0.2),
		"tank": _material(Color("e2e7d9"), 0.18),
		"concrete": _material(Color("a1aea2")),
		"yard": _material(Color("7c9180")),
		"metal": _material(Color("577268"), 0.5),
		"dark": _material(Color("2c4742")),
		"electric": _material(Color("70c89f"), 0.2, true),
		"heat": _material(Color("e4ac58"), 0.2, true),
		"return": _material(Color("648fa5"), 0.2),
		"gold": _material(Color("f4d476"), 0.1, true),
	}
	preview_good = _material(Color(0.15, 0.95, 0.58, 0.45))
	preview_bad = _material(Color(1.0, 0.19, 0.15, 0.45))
	preview_only = station_data.get("kind", "thermal_station") == "tower_station_preview"
	tower_site = station_data.get("kind", "") in ["tower_station","tower_station_preview"]
	if tower_site:
		_build_tower_facade(title, p, prefer_blender_assets)
		if not preview_only:
			_build_installed_devices(station_data, prefer_blender_assets)
			if preview_enabled: set_preview(preview_valid)
		return
	var metric := str(station_data.get("visual_dimension_profile", "legacy_illustrative")) == "metric_v1"
	# Metric mode is an installation, not a pre-authored two-tank symbol. Keep
	# the shared site dimensions while rendering only the supplied real members.
	if metric:
		_build_metric_courtyard(p)
		_build_installed_devices(station_data, prefer_blender_assets)
	else:
		_build_courtyard(p)
		_build_building(p)
		_build_tanks(p)
	_build_ports(p, false, metric)
	footprint_radius = FOOTPRINT_RADIUS
	if metric:
		var dimensions: Dictionary = Spatial.profile("thermal_station")
		footprint_radius = dimensions.clearance_radius_world
		set_meta("visual_backend", "metric_installed_equipment")
		set_meta("asset_source", "installed_devices")
		set_meta("visual_dimension_profile", "metric_v1")
		set_meta("footprint_radius", footprint_radius)
		set_meta("world_units_per_meter", Spatial.WORLD_UNITS_PER_METER)
		set_meta("body_dimensions_m", dimensions.body_dimensions_m)
		set_meta("land_area_m2", dimensions.land_area_m2)
		set_meta("visual_only", true)
		set_meta("capacity_added", 0.0)
	if metric and station_data.get("has_primary_storage_boundary", false):
		# Separate primary ports preserve the established secondary heat_out.
		_add_thermal_boundary("heat_primary_in", Vector3(-1.4, .25, -2.8), "hw_primary_90_60", "input", "热90/60 输入", p)
		_add_thermal_boundary("heat_primary_out", Vector3(1.4, .25, -2.8), "hw_primary_90_60", "output", "热90/60 输出", p)
	if station_data.get("has_rankine_output",false):
		var port:=Node3D.new();port.name="ac_out";port.position=Vector3(0,0.105,-2.8) if metric else Vector3(0,1.05,-4.0);add_child(port)
		named_ports["ac_out"]=port;named_port_locals["ac_out"]=port.position
		_box(port,"ACOutputMarker",Vector3.ONE*(0.12 if metric else 0.9),Vector3.ZERO,p.electric)
		_label(port,"PortLabel","AC 发电输出",Vector3(0,0.2 if metric else 1.5,0),30,0.01)
	var ring := TorusMesh.new()
	ring.inner_radius = footprint_radius - (0.025 if metric else 0.09)
	ring.outer_radius = footprint_radius + (0.025 if metric else 0.09)
	ring.rings = 64
	ring.ring_segments = 6
	selection_ring = _mesh(self, "SelectionRing", ring, Vector3(0, 0.025 if metric else 0.15, 0), p.gold)
	hint_materials = Visual.interaction_hint_materials(p.gold)
	title_label = _label(self, "StationTitle", title, Vector3(0, 1.4, -0.3) if metric else Vector3(0, 6.5, -1.2), 44, 0.012 if metric else 0.035)
	# Place the readout beyond the front gate so it does not collide with the
	# two carrier labels at the standard elevated base-map camera angle.
	status_label = _label(self, "StationStatus", "", Vector3(0, 0.14, 3.6) if metric else Vector3(0, 0.7, 6.7), 28, 0.010 if metric else 0.04)
	if not metric and station_data.has("visual_dimension_profile"):
		set_meta("visual_dimension_profile", "legacy_illustrative")
		set_meta("legacy_scale_migration_required", true)
		_label(self, "LegacyScaleNotice", "旧版图标化尺度 · 非真实尺寸 · 需显式米制迁移", Vector3(0, 5.7, -0.3), 24, .02)
	set_status(NAN, NAN, NAN)
	if preview_enabled:
		set_preview(preview_valid)
	else:
		set_selected(selected)

## The yard is a real 80x60 m container (48x48 m clear internal zone), not
## an enclosing process building. Device coordinates already use world units.
func _build_metric_courtyard(p: Dictionary) -> void:
	var dimensions: Dictionary = Spatial.profile("thermal_station")
	var land: Vector3 = dimensions.land_dimensions_m * Spatial.WORLD_UNITS_PER_METER
	var interior: Vector3 = dimensions.interior_dimensions_m * Spatial.WORLD_UNITS_PER_METER
	_box(self, "FacilityFoundation", Vector3(land.x, .05, land.z), Vector3(0, -.025, 0), p.concrete)
	_box(self, "Courtyard", Vector3(interior.x, .008, interior.z), Vector3(0, -.004, 0), p.yard)
	_box(self, "ServiceRoad", Vector3(land.x-.4, .01, .4), Vector3(0, .005, -land.z*.5+.30), p.concrete)
	for x in [-land.x*.5+.04, land.x*.5-.04]:
		_box(self, "FenceSide", Vector3(.018, .018, land.z-.08), Vector3(x, .12, 0), p.metal)
		for z in [-land.z*.5+.04, 0.0, land.z*.5-.04]:
			_box(self, "FencePost", Vector3(.025, .14, .025), Vector3(x, .07, z), p.metal)
	_box(self, "FenceBack", Vector3(land.x-.08, .018, .018), Vector3(0, .12, -land.z*.5+.04), p.metal)
	for x in [-land.x*.25-.25, land.x*.25+.25]:
		_box(self, "FenceFront", Vector3(land.x*.5-.54, .018, .018), Vector3(x, .12, land.z*.5-.04), p.metal)
	for x in [-.5, .5]:
		_box(self, "GatePost", Vector3(.04, .18, .04), Vector3(x, .09, land.z*.5-.04), p.metal)

func _build_installed_devices(station_data: Dictionary, prefer_assets: bool) -> void:
	var equipment := Node3D.new()
	equipment.name = "InstalledEquipment"
	add_child(equipment)
	var snapshots: Variant = station_data.get("installed_devices", [])
	var ids: Array[int] = []
	if snapshots is Array:
		for item in snapshots:
			if not item is Dictionary or not item.get("kind", "") in Catalog.implemented_kinds(): continue
			var id := int(item.get("id", -1))
			if id < 0 or installed_device_nodes.has(id): continue
			if station_data.has("id") and item.has("parent_station_id") and int(item.parent_station_id) != int(station_data.id): continue
			var x: float = float(item.get("interior_x", 0.0))
			var z: float = float(item.get("interior_z", 0.0))
			if not is_finite(x) or not is_finite(z): continue
			var params: Dictionary = item.get("params", {}).duplicate(true)
			params.visual_dimension_profile = "metric_v1"
			params.visual_site_geometry_profile = str(item.get("site_geometry_profile", ""))
			if item.kind == "battery_flow": params.visual_geometry_profile = item.get("geometry_profile", "flow_icon_v1")
			var visual: Node3D = Visual.create(item.kind, params, prefer_assets)
			visual.name = "InstalledDevice_%d" % id
			visual.position = Vector3(x, 0, z)
			visual.set_meta("source_device_id", id)
			visual.set_meta("source_station_id", int(station_data.get("id", -1)))
			equipment.add_child(visual)
			visual.set_annotation_visibility(false, false)
			visual.set_highlight(false)
			_register_asset_meshes(visual)
			installed_device_nodes[id] = visual
			ids.append(id)
	set_meta("installed_device_count", ids.size())
	set_meta("installed_device_ids", ids)
	set_meta("installed_geometry_contract", "same Visual.create; metric_v1; unscaled interior world coordinates; no simulation copy")

func _build_metric_ports(p: Dictionary) -> void:
	var definition: Dictionary = Visual.thermal_asset_definition("thermal_station")
	for id in PORT_LOCALS:
		var coordinates: Array = definition.get("ports", {}).get(id, [])
		var local: Vector3 = Visual._vector3(coordinates) if not coordinates.is_empty() else Vector3(-3.9 if id=="ac_in" else 3.9, .105, .8)
		var port := Node3D.new()
		port.name = "Port_" + id; port.position = local; add_child(port)
		named_ports[id] = port; named_port_locals[id] = local
		port.set_meta("port_id", id); port.set_meta("mapped_boundary_only", true)
		port.set_meta("direction", "input" if id=="ac_in" else "output")
		port.set_meta("carrier", "electricity_ac" if id=="ac_in" else "heat_water")
		port.set_meta("unit", "MW" if id=="ac_in" else "MWth")
		if id=="ac_in":
			port.set_meta("voltage_level", "AC_BUS")
			_box(port, "ACSquare", Vector3.ONE*.12, Vector3.ZERO, p.electric)
		else:
			port.set_meta("grade_id", "hw_secondary_70_40")
			_cylinder(port, "HeatOuterFlange", .07, .07, .025, Vector3.ZERO, p.heat).rotation.z=PI*.5
			_cylinder(port, "HeatInnerFlange", .04, .04, .03, Vector3.ZERO, p.return).rotation.z=PI*.5
		_label(port, "PortLabel", "AC 输入" if id=="ac_in" else "热70/40 输出", Vector3(0,.16,0), 30, .01)

## Authored mesh slots remain intact. Placement tint uses material_override,
## which masks every slot and is restored to its original value (usually null).
func _try_build_blender() -> bool:
	if _blender_scene == null:
		if not ResourceLoader.exists(BLENDER_ASSET, "PackedScene"):
			set_meta("asset_fallback", "station asset unavailable or not imported")
			return false
		_blender_scene = load(BLENDER_ASSET) as PackedScene
	if _blender_scene == null:
		set_meta("asset_fallback", "station asset could not load")
		return false
	var asset := _blender_scene.instantiate() as Node3D
	if asset == null:
		return false
	var anchors: Dictionary = {}
	var definition := Visual.thermal_asset_definition("thermal_station")
	for port_id in PORT_LOCALS:
		var anchor := asset.find_child("Port_" + port_id, true, false) as Node3D
		var expected: Array = definition.get("ports", {}).get(port_id, [])
		if anchor == null or (not expected.is_empty() and not _position_relative_to(anchor, asset).is_equal_approx(Visual._vector3(expected))):
			asset.free()
			set_meta("asset_fallback", "station asset lacks the agreed external-port coordinates")
			return false
		anchors[port_id] = anchor
	asset.name = "BlenderAsset"
	add_child(asset)
	_register_asset_meshes(asset)
	named_ports = anchors
	for port_id in anchors:
		named_port_locals[port_id] = _position_relative_to(anchors[port_id], self)
	set_meta("visual_only", true)
	set_meta("capacity_added", 0.0)
	set_meta("visual_backend", "blender_glb")
	set_meta("asset_source", BLENDER_ASSET)
	return true

## Asset-unavailable fallback is deliberately schematic. It shares the metric
## site boundary and manifest endpoints rather than silently growing the yard.
func _scale_metric_fallback() -> void:
	var factor := Vector3(8.0 / 12.6, 0.7 / 3.86, 6.0 / 9.4)
	for child in get_children():
		if child is Node3D:
			child.position *= factor
			child.scale *= factor
	var definition := Visual.thermal_asset_definition("thermal_station")
	for port_id in named_ports:
		var coords: Array = definition.get("ports", {}).get(port_id, [])
		var local := Visual._vector3(coords) if not coords.is_empty() else Vector3(-3.9 if port_id == "ac_in" else 3.9, 0.105, 0.8)
		named_ports[port_id].position = local
		named_ports[port_id].scale = Vector3(0.18, 0.18, 0.18)
		named_port_locals[port_id] = local
	set_meta("visual_backend", "metric_procedural_fallback")

func _position_relative_to(node: Node3D, ancestor: Node3D) -> Vector3:
	var relative := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != null and cursor != ancestor:
		if cursor is Node3D:
			relative = cursor.transform * relative
		cursor = cursor.get_parent()
	return relative.origin

func _register_asset_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		surfaces.append(node)
		base_materials.append(node.material_override)
	for child in node.get_children():
		_register_asset_meshes(child)

func has_named_port(port_id: String) -> bool:
	return not preview_only and named_port_locals.has(port_id)

func get_port_position(port_id: String = "ac_in") -> Vector3:
	# An unknown name resolves to the facade origin, never silently to a carrier.
	# Connection validation should call has_named_port() before choosing a port.
	var local: Vector3 = named_port_locals.get(port_id, Vector3.ZERO)
	return to_global(local) if is_inside_tree() else transform * local

func get_named_port_position(port_id: String) -> Vector3:
	return get_port_position(port_id)

func port_global() -> Vector3:
	return get_port_position("ac_in")

func set_selected(enabled: bool) -> void:
	selected = enabled
	_update_interaction_hint()
	set_annotation_visibility(enabled)

func set_highlight(enabled: bool) -> void:
	set_selected(enabled)

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
		Visual.fit_screen_label(label, view_camera, 22.0 if label.name == "StationTitle" else 18.0)

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
	_update_interaction_hint()
	_update_annotation_visibility()

func set_preview_disabled() -> void:
	clear_preview()

func set_status(electric_mw: float, heat_mwth: float, stored_mwhth: float) -> void:
	if is_instance_valid(status_label):
		if preview_only:
			status_label.text="未投运预览 · 无能量端口 · 零发电"
			return
		status_label.text = "电 %s MW · 热 %s MWth\n储热 %s MWhth" % [
			_readout(electric_mw), _readout(heat_mwth), _readout(stored_mwhth),
		]

func _readout(value: float) -> String:
	return "%.1f" % value if is_finite(value) else "—"

func _build_courtyard(p: Dictionary) -> void:
	_box(self, "FacilityFoundation", Vector3(12.6, 0.22, 9.4), Vector3(0, 0.11, 0), p.concrete)
	_box(self, "Courtyard", Vector3(12.1, 0.04, 8.9), Vector3(0, 0.24, 0), p.yard)
	_box(self, "ServiceRoad", Vector3(10.4, 0.025, 1.8), Vector3(0, 0.275, 3.25), p.concrete)
	# Low solid rails and sparse posts retain the fenced-site silhouette without
	# a dense mesh grid or visual noise at the base-map camera distance.
	for x in [-6.05, 6.05]:
		_box(self, "FenceSide", Vector3(0.10, 0.10, 8.7), Vector3(x, 1.05, 0), p.metal)
		for z in [-4.35, -2.2, 0.0, 2.2, 4.35]:
			_box(self, "FencePost", Vector3(0.14, 0.95, 0.14), Vector3(x, 0.735, z), p.metal)
	_box(self, "FenceBack", Vector3(12.1, 0.10, 0.10), Vector3(0, 1.05, -4.35), p.metal)
	for x in [-3.4, 0.0, 3.4]:
		_box(self, "FencePostBack", Vector3(0.14, 0.95, 0.14), Vector3(x, 0.735, -4.35), p.metal)
	for x in [-3.95, 3.95]:
		_box(self, "FenceFront", Vector3(4.2, 0.10, 0.10), Vector3(x, 1.05, 4.35), p.metal)
	for x in [-1.8, 1.8]:
		_box(self, "GatePost", Vector3(0.20, 1.15, 0.20), Vector3(x, 0.835, 4.35), p.metal)

func _build_building(p: Dictionary) -> void:
	_box(self, "PlantBuilding", Vector3(5.8, 3.0, 4.2), Vector3(-1.8, 1.76, -1.15), p.wall)
	_box(self, "PlantRoof", Vector3(6.1, 0.22, 4.5), Vector3(-1.8, 3.37, -1.15), p.roof)
	_box(self, "RoofLight", Vector3(3.6, 0.34, 1.0), Vector3(-1.8, 3.65, -1.3), p.tank)
	_box(self, "WindowBand", Vector3(4.9, 0.48, 0.05), Vector3(-1.8, 2.52, 0.98), p.dark)
	_box(self, "ServiceDoor", Vector3(1.25, 1.65, 0.07), Vector3(-2.8, 1.085, 1.0), p.roof)
	_box(self, "EntranceCanopy", Vector3(1.7, 0.13, 1.0), Vector3(-2.8, 2.0, 1.35), p.metal)
	_box(self, "ControlAnnex", Vector3(1.65, 1.55, 2.15), Vector3(-4.9, 1.035, -0.7), p.tank)
	_box(self, "ControlAnnexRoof", Vector3(1.85, 0.13, 2.35), Vector3(-4.9, 1.875, -0.7), p.roof)
	for x in [-0.65, 0.1, 0.85]:
		_box(self, "VentLouvre", Vector3(0.12, 0.8, 0.08), Vector3(x, 1.28, 1.0), p.metal)
	_box(self, "ElectricalCabinet", Vector3(0.75, 1.3, 1.0), Vector3(-5.25, 0.91, 1.55), p.electric)

func _build_tanks(p: Dictionary) -> void:
	# These silhouettes represent the facility as a whole. They do not instantiate
	# storage equipment and their dimensions never encode installed capacity/SOC.
	for i in 2:
		var z := -2.3 + float(i) * 2.8
		var tank := Node3D.new()
		tank.name = "TankSilhouette%d" % (i + 1)
		tank.position = Vector3(3.5, 0, z)
		add_child(tank)
		_cylinder(tank, "TankPlinth", 1.35, 1.35, 0.22, Vector3(0, 0.37, 0), p.concrete)
		_cylinder(tank, "TankShell", 1.15, 1.15, 3.1, Vector3(0, 2.03, 0), p.tank)
		_cylinder(tank, "TankCap", 1.18, 0.9, 0.28, Vector3(0, 3.72, 0), p.tank)
		_cylinder(tank, "TankRim", 1.18, 1.18, 0.12, Vector3(0, 3.50, 0), p.metal)
		_cylinder(tank, "TankBand", 1.17, 1.17, 0.12, Vector3(0, 1.55, 0), p.roof)
	_box(self, "UtilityPipeBridge", Vector3(2.7, 0.20, 0.20), Vector3(1.8, 2.4, 0.6), p.heat)
	_box(self, "UtilityPipeRiser", Vector3(0.20, 1.6, 0.20), Vector3(2.85, 1.7, 0.6), p.heat)

func _build_ports(p: Dictionary, imported_geometry: bool = false, metric: bool = false) -> void:
	if metric and not imported_geometry:
		_build_metric_ports(p)
		return
	for port_id in PORT_LOCALS:
		var port: Node3D
		if imported_geometry:
			port = named_ports[port_id]
		else:
			port = Node3D.new()
			port.name = port_id
			port.position = PORT_LOCALS[port_id]
			add_child(port)
			named_ports[port_id] = port
		port.set_meta("port_id", port_id)
		port.set_meta("direction", "input" if port_id == "ac_in" else "output")
		port.set_meta("carrier", "electricity_ac" if port_id == "ac_in" else "heat_water")
		port.set_meta("unit", "MW" if port_id == "ac_in" else "MWth")
		if port_id == "ac_in":
			port.set_meta("voltage_level", "AC_BUS")
		else:
			port.set_meta("grade_id", "hw_secondary_70_40")
		if imported_geometry:
			_label(port, "PortLabel", "AC 输入" if port_id == "ac_in" else "热70/40 输出", Vector3(0, 0.16, 0) if metric else Vector3(0, 1.45, 0), 30, 0.010 if metric else 0.035)
			continue
		if port_id == "ac_in":
			_box(port, "ACSquare", Vector3(0.9, 0.9, 0.9), Vector3.ZERO, p.electric)
			_box(self, "ACCableTray", Vector3(1.9, 0.12, 0.22), Vector3(-6.15, 0.76, 0.8), p.metal)
			_label(port, "PortLabel", "AC 输入", Vector3(0, 1.45, 0), 30, 0.035)
		else:
			_cylinder(port, "HeatOuterFlange", 0.52, 0.52, 0.18, Vector3.ZERO, p.heat).rotation.z = PI / 2.0
			_cylinder(port, "HeatInnerFlange", 0.31, 0.31, 0.22, Vector3.ZERO, p.return).rotation.z = PI / 2.0
			_box(self, "HeatSupplyPipe", Vector3(3.6, 0.19, 0.19), Vector3(5.3, 1.05, 0.55), p.heat)
			_box(self, "HeatReturnPipe", Vector3(3.6, 0.19, 0.19), Vector3(5.3, 0.72, 1.05), p.return)
			_label(port, "PortLabel", "热70/40 输出", Vector3(0, 1.45, 0), 30, 0.035)

func _material(color: Color, metallic: float = 0.0, glow: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = 0.75
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.25
	return material

func _mesh(parent: Node3D, node_name: String, mesh: Mesh, position_local: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position_local
	instance.material_override = material
	parent.add_child(instance)
	surfaces.append(instance)
	base_materials.append(material)
	return instance

func _box(parent: Node3D, node_name: String, dimensions: Vector3, position_local: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	return _mesh(parent, node_name, mesh, position_local, material)

func _cylinder(parent: Node3D, node_name: String, bottom: float, top: float, height: float, position_local: Vector3, material: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 1
	return _mesh(parent, node_name, mesh, position_local, material)

func _label(parent: Node3D, node_name: String, text: String, position_local: Vector3, size: int, _pixel_scale: float) -> Label3D:
	var label := Label3D.new()
	label.name = node_name
	label.text = text
	label.font = UI_FONT
	label.font_size = size
	label.pixel_size = 0.00055
	label.fixed_size = true
	label.set_disable_scale(true)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.modulate = Color("f5f5e8")
	label.outline_modulate = Color("29483d")
	label.outline_size = 7
	label.position = position_local
	parent.add_child(label)
	annotation_labels.append(label)
	return label

func _build_tower_facade(title: String, palette: Dictionary, prefer_blender_assets: bool) -> void:
	name = "TowerStationPreviewFacade"
	named_port_locals.clear()
	named_ports.clear()
	var geometry := Visual.create("tower_station_preview" if preview_only else "tower_station", {"visual_dimension_profile":"metric_v1"}, prefer_blender_assets)
	tower_geometry=geometry
	add_child(geometry)
	geometry.set_annotation_visibility(false, false)
	_register_asset_meshes(geometry)
	var dimensions: Dictionary = Spatial.profile("tower_station_preview")
	footprint_radius = dimensions.clearance_radius_world
	for key in ["body_dimensions_m", "land_area_m2", "land_dimensions_m", "interior_dimensions_m", "heliostat_count", "mirror_aperture_area_m2"]:
		set_meta(key, dimensions.get(key))
	set_meta("footprint_radius", footprint_radius)
	set_meta("visual_dimension_profile", "metric_v1")
	set_meta("world_units_per_meter", Spatial.WORLD_UNITS_PER_METER)
	set_meta("visual_only", true)
	set_meta("preview_only", preview_only)
	set_meta("commissioned", not preview_only)
	set_meta("capacity_added", 0.0)
	set_meta("energy_port_count", 0 if preview_only else 4)
	if not preview_only:
		for key in ["ac_in","ac_out"]:
			var port:=Node3D.new();port.name=key;port.position=Vector3(-7.8 if key=="ac_in" else 7.8,0.15,0);add_child(port)
			named_ports[key]=port;named_port_locals[key]=port.position
			port.set_meta("port_id", key);port.set_meta("carrier", "electricity_ac");port.set_meta("unit", "MW")
			port.set_meta("direction", "input" if key == "ac_in" else "output");port.set_meta("voltage_level", "AC_BUS")
			port.set_meta("mapped_boundary_only", true)
			_box(port,"ACBoundaryMarker",Vector3.ONE*0.2,Vector3.ZERO,palette.electric)
			_label(port,"PortLabel","AC 辅机输入" if key=="ac_in" else "AC 毛发电输出",Vector3(0,0.3,0),30,0.01)
		_add_thermal_boundary("heat_in", Vector3(-1.4, .25, -7.8), "salt_565_290", "input", "盐565/290 输入", palette)
		_add_thermal_boundary("heat_out", Vector3(1.4, .25, -7.8), "salt_565_290", "output", "盐565/290 输出", palette)
	var ring := TorusMesh.new()
	ring.inner_radius = footprint_radius - 0.025
	ring.outer_radius = footprint_radius + 0.025
	ring.rings = 64
	ring.ring_segments = 6
	selection_ring = _mesh(self, "SelectionRing", ring, Vector3(0, 0.025, 0), palette.gold)
	hint_materials = Visual.interaction_hint_materials(palette.gold)
	title_label = _label(self, "StationTitle", title + (" · 未投运预览" if preview_only else " · 熔盐运行站"), Vector3(0, 2.9, 0), 44, 0.012)
	status_label = _label(self, "StationStatus", "", Vector3(0, 0.25, 8.2), 28, 0.010)
	set_status(0,0,0)
	if preview_enabled: set_preview(preview_valid)
	else: set_selected(selected)

func set_tower_tracking(altitude:float,azimuth:float)->void:
	if tower_site and not preview_only and is_instance_valid(tower_geometry) and tower_geometry.has_method("set_tower_tracking"):
		tower_geometry.set_tower_tracking(altitude,azimuth)


## Typed visual boundary only. The host resolves each route to its real child
## port; no shared capacity, stock, fuel, or hidden conversion is added here.
func _add_thermal_boundary(port_id: String, local: Vector3, grade: String, direction: String, caption: String, p: Dictionary) -> void:
	var port := Node3D.new()
	port.name = port_id
	port.position = local
	add_child(port)
	named_ports[port_id] = port
	named_port_locals[port_id] = local
	port.set_meta("port_id", port_id)
	port.set_meta("direction", direction)
	port.set_meta("carrier", "heat_salt" if grade == "salt_565_290" else "heat_water")
	port.set_meta("grade_id", grade)
	port.set_meta("unit", "MWth")
	port.set_meta("mapped_boundary_only", true)
	_box(port, "ThermalBoundaryPad", Vector3(.50, .06, .45), Vector3(0, -.19, .02), p.concrete)
	for supply in [true, false]:
		var tint: Material = p.heat if supply else p.return
		var y := .07 if supply else -.07
		var pipe := _cylinder(port, "SupplyPipe" if supply else "ReturnPipe", .026, .026, .30, Vector3(0, y, .02), tint)
		pipe.rotation.x = PI * .5
		var ring := TorusMesh.new()
		ring.inner_radius = .028; ring.outer_radius = .068; ring.rings = 12; ring.ring_segments = 6
		var flange := _mesh(port, "SupplyFlange" if supply else "ReturnFlange", ring, Vector3(0, y, -.13), p.metal)
		flange.rotation.x = PI * .5
		_box(port, "PipeSupport", Vector3(.12, .15, .09), Vector3(0, -.10, .12), p.metal)
	var arrow := _cylinder(port, "HeatDirectionArrow", .045, 0.0, .12, Vector3(.18, .03, -.01), p.heat)
	arrow.rotation.x = PI * .5 if direction == "input" else -PI * .5
	_label(port, "PortLabel", caption + " · MWth", Vector3(0, .30, 0), 30, .01)
