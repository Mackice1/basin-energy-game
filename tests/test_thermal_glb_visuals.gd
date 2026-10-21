extends SceneTree
## Requires actual imported Blender GLBs. Procedural geometry contracts remain
## covered independently by test_thermal_device_ui and test_station_facade.
const Visual = preload("res://scripts/equipment_visual.gd")
const Facade = preload("res://scripts/station_facade.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
const Model = preload("res://scripts/energy_model.gd")
const Spatial = preload("res://scripts/spatial_dimensions.gd")
const KINDS := ["electric_boiler", "thermal_store", "heat_exchanger"]

var checks := 0
var failures: Array[String] = []

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var signatures: Array = []
	for kind in KINDS:
		var signature := _test_equipment(kind)
		if not signature.is_empty():
			signatures.append(signature)
	for i in signatures.size():
		for j in range(i + 1, signatures.size()):
			check(signatures[i] != signatures[j], "thermal models have distinct actual mesh geometry")
	_test_facade()
	_test_metric_electrical()
	_test_safe_fallbacks()
	print("THERMAL_GLB_VISUALS_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _test_equipment(kind: String) -> Dictionary:
	var path: String = Visual.BLENDER_ASSETS[kind]
	if not _check_raw_asset(path, kind):
		return {}
	var params: Dictionary = Model.defaults(kind)
	params.visual_dimension_profile = "metric_v1"
	var original := params.duplicate(true)
	var definition: Dictionary = Visual.thermal_asset_definition(kind)
	var dimensions: Dictionary = Spatial.profile(kind, params)
	var ports: Dictionary = definition.ports
	var item = Visual.create(kind, params, true)
	root.add_child(item)
	check(item.get_meta("visual_backend") == "blender_glb", kind + ": true opts into actual imported mesh")
	check(item.get_meta("asset_source", "") == path and item.has_node("BlenderAsset"), kind + ": source is inspectable")
	check(item.device_kind == kind and item.rotor == null, kind + ": has independent thermal role")
	check(item.get_meta("visual_only") and item.get_meta("capacity_added") == 0.0, kind + ": adds no capacity")
	check(params == original, kind + ": parameters remain untouched")
	check(not item.get_meta("temperature_is_dynamic"), kind + ": no invented temperature state")
	check(item.get_meta("thermal_boundary").contains("已充水") and item.get_meta("thermal_boundary").contains("循环辅机"), kind + ": thermal boundary is preserved")
	var fallback = Visual.create(kind)
	check(fallback.get_meta("visual_backend") == "procedural", kind + ": default API retains procedural geometry")
	for key in ["representation", "geometry_assumption", "thermal_boundary", "temperature_is_dynamic", "fixed_temperature_profile"]:
		check(item.get_meta(key) == fallback.get_meta(key), kind + ": shared metadata matches fallback " + key)
	check(item.named_ports.size() == 2 and item.named_port_locals.size() == 2, kind + ": exposes only agreed ports")
	for port_id in ports:
		check(item.has_named_port(port_id), kind + ": exact endpoint exists " + port_id)
		var terminal: Node3D = item.named_ports[port_id]
		var expected: Vector3 = Visual._vector3(ports[port_id]) + dimensions.module_origins_world[0]
		check(terminal.name == "Port_" + port_id, kind + ": original Blender empty is reused")
		check(terminal.global_position.is_equal_approx(expected), kind + ": Blender axes and coordinates are exact")
		check(item.named_port_locals[port_id].is_equal_approx(expected), kind + ": authoritative endpoint stays unchanged")
		check(item.get_named_port_position(port_id).is_equal_approx(terminal.global_position), kind + ": picking uses rendered endpoint")
		check(not fallback.named_port_locals[port_id].is_equal_approx(expected), kind + ": metric endpoint never silently overwrites legacy coordinates")
		var contract: Dictionary = Catalog.port(kind, port_id)
		for key in ["direction", "carrier", "unit"]:
			check(terminal.get_meta(key) == contract[key], kind + ": catalog contract " + port_id + "/" + key)
		check(terminal.get_meta("port_id") == port_id, kind + ": port id metadata")
		var caption := terminal.get_node("PortLabel") as Label3D
		check(caption != null, kind + ": runtime carrier label remains controllable")
		if contract.carrier == "electricity_ac":
			check(terminal.get_meta("voltage_level") == "AC_BUS" and not terminal.has_meta("grade_id"), kind + ": AC is not a thermal grade")
			check(caption.text.contains("电AC"), kind + ": runtime AC label")
		else:
			check(terminal.get_meta("grade_id") == contract.grade_id, kind + ": fixed thermal grade")
			check(caption.text.contains("热90" if contract.grade_id == "hw_primary_90_60" else "热70"), kind + ": explicit grade label")
		check(caption.text.contains("入" if contract.direction == "input" else "出"), kind + ": explicit direction label")
	check(not item.has_named_port("missing"), kind + ": unknown endpoint is not advertised")
	check(item.port_local.is_equal_approx(item.named_port_locals[ports.keys()[0]]), kind + ": legacy endpoint API resolves first metric carrier")
	check(item.get_meta("footprint_radius") == dimensions.clearance_radius_world, kind + ": shared metric clearance")
	check(item.get_meta("world_units_per_meter") == 0.1 and item.get_meta("module_count") == dimensions.module_count, kind + ": meter scale and module count")
	var signature := _check_geometry(item, Visual.footprint(kind, params), kind)
	var originals := _material_snapshot(item)
	_test_preview(item, originals, kind)
	if kind == "thermal_store":
		check(item.get_meta("storage_approximation") == fallback.get_meta("storage_approximation") and not item.get_meta("soc_changes_temperature"), "store: fixed-quality two-zone semantics")
		check(is_instance_valid(item.thermal_soc_label), "store: runtime inventory gauge exists")
		check(item.thermal_soc_label.get_parent().name == "ThermalSOCAnchor", "store: gauge uses authored empty")
		check(item.thermal_soc_label.global_position.is_equal_approx(Visual._vector3(definition.soc_anchor) + dimensions.module_origins_world[0]), "store: gauge follows front-plaque coordinate")
		check(item.thermal_soc_label.no_depth_test, "store: oblique camera does not bury inventory")
		for value in [-1.0, 0.0, 0.25, 1.0, 2.0]:
			item.set_thermal_soc(value)
			check(item.thermal_soc_label.text == "库存 SOC %.1f%%" % (clampf(value, 0.0, 1.0) * 100.0), "store: SOC is a clamped runtime text gauge")
			_check_unchanged_materials(item, originals, "store: SOC never changes fixed zones")
		for value in [NAN, INF, -INF]:
			item.set_thermal_soc(value)
			check(item.thermal_soc_label.text == "库存 SOC —", "store: unknown SOC invents no inventory")
	var sibling = Visual.create(kind, params, true)
	root.add_child(sibling)
	var sibling_originals := _material_snapshot(sibling)
	item.set_preview(false)
	_check_unchanged_materials(sibling, sibling_originals, kind + ": shared GLB materials stay unchanged")
	item.clear_preview()
	sibling.free()
	var holder := Node3D.new()
	root.add_child(holder)
	item.reparent(holder)
	holder.position = Vector3(-3, 1, 4)
	holder.rotation.y = -0.3
	item.position = Vector3(5, 2, -4)
	item.rotation.y = 0.7
	item.scale = Vector3(1.2, 1.2, 1.2)
	for port_id in ports:
		check(item.get_named_port_position(port_id).is_equal_approx(item.named_ports[port_id].global_position), kind + ": full placement reaches rendered endpoint")
	check(item.get_port_position().is_equal_approx(item.port.global_position), kind + ": legacy endpoint follows transform")
	check(params == original, kind + ": rendering and SOC never mutate source data")
	fallback.free()
	holder.free()
	return signature

func _check_raw_asset(path: String, label: String) -> bool:
	check(FileAccess.file_exists(path), label + ": GLB source exists")
	check(ResourceLoader.exists(path, "PackedScene"), label + ": GLB has actually been imported")
	if not FileAccess.file_exists(path) or not ResourceLoader.exists(path, "PackedScene"):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	check(file.get_buffer(4).get_string_from_ascii() == "glTF", label + ": source is genuine binary glTF")
	var packed := load(path) as PackedScene
	check(packed != null, label + ": import loads as scene")
	if packed == null:
		return false
	var asset := packed.instantiate() as Node3D
	check(asset != null and asset.transform.is_equal_approx(Transform3D.IDENTITY), label + ": Y-up root has unit scale without correction")
	if asset == null:
		return false
	check(asset.find_children("*", "Label3D", true, false).is_empty(), label + ": no state/UI text is baked in")
	check(asset.find_children("*", "CollisionObject3D", true, false).is_empty(), label + ": no imported physics bodies")
	asset.free()
	return true

func _check_geometry(item: Node3D, radius: float, label: String) -> Dictionary:
	var mesh_count := 0
	var draw_surfaces := 0
	var triangles := 0
	var vertex_count := 0
	var bounds := AABB()
	var have_bounds := false
	check(item.surfaces.size() == item.base_materials.size(), label + ": picking/material arrays cover every mesh")
	for instance: MeshInstance3D in item.surfaces:
		if instance == item.selection_ring:
			continue
		mesh_count += 1
		check(instance.mesh is ArrayMesh and instance.material_override == null, label + ": authored slots remain intact")
		for slot in instance.mesh.get_surface_count():
			draw_surfaces += 1
			check(instance.get_active_material(slot) != null, label + ": imported material slot is populated")
			var arrays: Array = instance.mesh.surface_get_arrays(slot)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			vertex_count += vertices.size()
			triangles += indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
			for vertex in vertices:
				var point: Vector3 = instance.global_transform * vertex
				if not have_bounds:
					bounds = AABB(point, Vector3.ZERO)
					have_bounds = true
				else:
					bounds = bounds.expand(point)
				check(point.y >= -0.0001, label + ": actual geometry stays above ground")
				check(Vector2(point.x, point.z).length() <= radius + 0.0001, label + ": actual geometry respects siting radius")
	check(mesh_count == 1, label + ": static parts form one picking mesh")
	check(draw_surfaces >= 3 and draw_surfaces <= 8, label + ": multisurface draw calls stay bounded")
	check(triangles > 500 and triangles < 18000, label + ": bounded detailed silhouette")
	var definition := Visual.thermal_asset_definition("thermal_station" if label == "facade" else label)
	var expected_bounds: Array = definition.bounds_godot
	var expected_min := Visual._vector3(expected_bounds[0])
	var expected_max := Visual._vector3(expected_bounds[1])
	check(bounds.position.distance_to(expected_min) < 0.0001 and bounds.end.distance_to(expected_max) < 0.0001, label + ": imported bounds equal exact metric export")
	check(bounds.size.y > 0.1 and bounds.size.y < 2.0, label + ": metre-scale upright height, not legacy enlargement")
	check(item.find_children("*", "CollisionObject3D", true, false).is_empty(), label + ": no runtime physics bodies")
	return {"bounds": bounds, "vertices": vertex_count, "triangles": triangles}

func _material_snapshot(item: Node3D) -> Array:
	var result: Array = []
	for instance: MeshInstance3D in item.surfaces:
		var slots: Array = []
		for slot in instance.mesh.get_surface_count():
			slots.append({"mesh": instance.mesh.surface_get_material(slot), "override": instance.get_surface_override_material(slot), "active": instance.get_active_material(slot)})
		result.append({"instance": instance, "mesh": instance.mesh, "transform": instance.transform, "override": instance.material_override, "slots": slots})
	return result

func _check_unchanged_materials(item: Node3D, snapshots: Array, label: String) -> void:
	check(item.surfaces.size() == snapshots.size(), label + ": mesh count")
	for snapshot: Dictionary in snapshots:
		var instance: MeshInstance3D = snapshot.instance
		check(instance.mesh == snapshot.mesh and instance.transform == snapshot.transform, label + ": geometry unchanged")
		check(instance.material_override == snapshot.override, label + ": original mesh override restored")
		for slot in snapshot.slots.size():
			var original: Dictionary = snapshot.slots[slot]
			check(instance.mesh.surface_get_material(slot) == original.mesh, label + ": underlying material unchanged")
			check(instance.get_surface_override_material(slot) == original.override, label + ": surface override unchanged")
			check(instance.get_active_material(slot) == original.active, label + ": effective material restored")

func _test_preview(item: Node3D, snapshots: Array, label: String) -> void:
	item.set_highlight(true)
	check(item.selection_ring.visible, label + ": selection ring works")
	for valid in [true, false, true]:
		item.set_preview(valid)
		check(not item.selection_ring.visible and item.selected, label + ": preview preserves selection")
		var expected: Material = item.preview_good if valid else item.preview_bad
		for instance: MeshInstance3D in item.surfaces:
			check(instance.material_override == expected, label + ": preview tints entire mesh")
			for slot in instance.mesh.get_surface_count():
				check(instance.get_active_material(slot) == expected, label + ": preview covers every imported material slot")
	item.clear_preview()
	check(item.selection_ring.visible, label + ": clear preview restores selection")
	_check_unchanged_materials(item, snapshots, label + ": clear preview")
	item.set_preview(false)
	item.set_preview_disabled()
	_check_unchanged_materials(item, snapshots, label + ": legacy preview-disable")

func _test_facade() -> void:
	if not _check_raw_asset(Facade.BLENDER_ASSET, "facade"):
		return
	var station = Facade.new()
	var data := {"visual_dimension_profile": "metric_v1", "id": 100, "name": "北区电热储能站", "devices": [{"kind": "thermal_store", "stored_mwhth": 123.0}]}
	var original := data.duplicate(true)
	station.setup(data)
	root.add_child(station)
	check(station.get_meta("visual_backend", "") == "blender_glb", "facade: explicit metric setup uses actual GLB")
	check(station.get_meta("asset_source", "") == Facade.BLENDER_ASSET, "facade: source recorded")
	check(station.get_meta("visual_only") and station.get_meta("capacity_added") == 0.0, "facade: adds no capacity")
	check(station.get("devices") == null and station.get("stored_mwhth") == null, "facade: retains no simulation state")
	check(not station.is_processing() and not station.is_physics_processing(), "facade: runs no simulation")
	check(station.title_label.text == data.name and not station.title_label.no_depth_test, "facade: runtime title obeys depth occlusion")
	check(station.named_ports.size() == 2, "facade: only external carriers advertised")
	for port_id in Facade.PORT_LOCALS:
		check(station.has_named_port(port_id), "facade: named port exists")
		var terminal: Node3D = station.named_ports[port_id]
		check(terminal.name == "Port_" + port_id, "facade: authored empty reused")
		check(terminal.global_position.is_equal_approx(Visual._vector3(Visual.thermal_asset_definition("thermal_station").ports[port_id])), "facade: Blender axes and endpoint preserved")
		check(station.get_port_position(port_id).is_equal_approx(terminal.global_position), "facade: port API matches geometry")
		check(terminal.get_node("PortLabel").text == ("AC 输入" if port_id == "ac_in" else "热70/40 输出"), "facade: runtime caption")
	check(station.named_ports.ac_in.get_meta("carrier") == "electricity_ac" and station.named_ports.ac_in.get_meta("direction") == "input", "facade: AC input semantics")
	check(station.named_ports.heat_out.get_meta("grade_id") == "hw_secondary_70_40" and station.named_ports.heat_out.get_meta("direction") == "output", "facade: 70/40 output semantics")
	check(not station.has_named_port("hot_in"), "facade: no internal exchanger port")
	_check_geometry(station, float(Spatial.profile("thermal_station").clearance_radius_world), "facade")
	var originals := _material_snapshot(station)
	_test_preview(station, originals, "facade")
	station.set_preview(false)
	check(not station.status_label.visible, "facade: ghost suppresses runtime status")
	station.clear_preview()
	check(station.status_label.visible, "facade: status restored")
	station.set_status(2.4, 2.35, 18.75)
	check(station.status_label.text == "电 2.4 MW · 热 2.4 MWth\n储热 18.8 MWhth", "facade: exact external status and units")
	station.set_status(NAN, INF, -INF)
	check(station.status_label.text == "电 — MW · 热 — MWth\n储热 — MWhth", "facade: unknown operation values not invented")
	_check_unchanged_materials(station, originals, "facade: text-only status")
	var mesh_count: int = station.surfaces.size()
	var child_count: int = station.get_child_count()
	station.set_preview(false)
	station.setup({"title": "南区热站", "visual_dimension_profile": "metric_v1"})
	check(station.surfaces.size() == mesh_count and station.get_child_count() == child_count, "facade: rebuild never duplicates geometry")
	check(station.preview_enabled and station.selected and not station.selection_ring.visible and not station.status_label.visible, "facade: rebuild preserves preview")
	check(station.title_label.text == "南区热站", "facade: rebuild updates title")
	station.set_preview_disabled()
	station.position = Vector3(5, 2, -4)
	station.rotation.y = 0.7
	station.scale = Vector3(1.2, 1.2, 1.2)
	var holder := Node3D.new()
	root.add_child(holder)
	station.reparent(holder)
	holder.position = Vector3(-3, 1, 4)
	holder.rotation.y = -0.3
	for port_id in Facade.PORT_LOCALS:
		check(station.get_named_port_position(port_id).is_equal_approx(station.named_ports[port_id].global_position), "facade: full placement reaches authored marker")
	check(station.port_global().is_equal_approx(station.named_ports.ac_in.global_position), "facade: legacy endpoint stays AC")
	check(station.get_port_position("missing").is_equal_approx(station.global_position), "facade: unknown endpoint stays neutral")
	check(data == original, "facade: display never mutates authoritative input")
	holder.free()

func _test_metric_electrical() -> void:
	for kind in ["pv", "battery", "station"]:
		var params := {"visual_dimension_profile": "metric_v1"}
		var dimensions: Dictionary = Spatial.profile(kind, params)
		var item = Visual.create(kind, params, true)
		root.add_child(item)
		check(item.get_meta("visual_backend") == "metric_batched", kind + ": metric primitive batch replaces illustrative GLB")
		check(item.get_meta("world_units_per_meter") == 0.1, kind + ": common metre-to-world scale")
		check(item.get_meta("unit_dimensions_m") == dimensions.unit_dimensions_m, kind + ": fixed individual module dimensions")
		check(item.get_meta("module_count") == dimensions.module_count, kind + ": correct physical module count")
		check(item.get_meta("footprint_radius") == Visual.footprint(kind, params), kind + ": footprint matches shared spatial contract")
		check(item.get_meta("capacity_added") == 0.0 and item.get_meta("modules_share_simulation_limits"), kind + ": modules add no energy or power")
		check(item.surfaces.size() == 3, kind + ": one batched body, one endpoint, one selection ring")
		if kind == "pv":
			check(item.get_meta("panel_count") == 2182 and item.get_meta("rendered_panel_count") == 2182, "PV: every default 550 Wp module is real metric geometry")
			check(item.get_meta("visual_lod") == "individual_metric_panels" and not item.get_meta("field_representation"), "PV: no enlarged twelve-panel proxy")
			check(is_equal_approx(item.get_meta("module_area_m2"), 2182.0 * 2.278 * 1.134), "PV: actual component area")
			check(is_equal_approx(item.get_meta("module_surface_area_world"), item.get_meta("module_area_m2") * 0.01), "PV: square-metre conversion")
		else:
			check(item.get_meta("module_count") == 2, kind + ": default capacity uses two equal-size modules")
			var modules := item.find_children("PhysicalModule*", "Node3D", false, false)
			check(modules.size() == 2, kind + ": both physical module centers retained")
			for index in modules.size():
				check(modules[index].position.is_equal_approx(dimensions.module_origins_world[index]), kind + ": physical module layout")
		for instance: MeshInstance3D in item.surfaces:
			if instance == item.selection_ring:
				continue
			for slot in instance.mesh.get_surface_count():
				var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(slot)[Mesh.ARRAY_VERTEX]
				for vertex in vertices:
					var point: Vector3 = instance.global_transform * vertex
					check(point.y >= -0.0001, kind + ": physical modules are above grade")
					check(Vector2(point.x, point.z).length() <= float(dimensions.clearance_radius_world), kind + ": physical modules and terminal fit installation clearance")
		var originals := _material_snapshot(item)
		_test_preview(item, originals, kind)
		check(item.named_ports.size() == (2 if kind == "station" else 1), kind + ": old aggregate port semantics retained")
		item.free()
	for kind in ["load", "heat_demand"]:
		var item = Visual.create(kind, {"visual_dimension_profile": "metric_v1"}, true)
		check(item.get_meta("land_area_m2") == 0.0 and item.get_meta("body_area_m2") == 0.0, kind + ": service marker does not invent a building")
		check(item.get_meta("footprint_radius") == 0.25, kind + ": interaction radius only")
		item.free()

func _test_safe_fallbacks() -> void:
	# Malformed replacement imports must not move connected cables.
	var malformed := PackedScene.new()
	var empty := Node3D.new()
	malformed.pack(empty)
	empty.free()
	for kind in KINDS:
		var path: String = Visual.BLENDER_ASSETS[kind]
		var saved: Variant = Visual._blender_scenes.get(path)
		Visual._blender_scenes[path] = malformed
		var item = Visual.create(kind, {"visual_dimension_profile": "metric_v1"}, true)
		check(item.get_meta("visual_backend") == "metric_procedural_fallback" and item.has_meta("asset_fallback"), kind + ": invalid import safely falls back")
		check(not item.has_node("BlenderAsset") and item.named_ports.size() == 2, kind + ": no partial imported remnants")
		item.free()
		if saved == null:
			Visual._blender_scenes.erase(path)
		else:
			Visual._blender_scenes[path] = saved
	var saved_facade: PackedScene = Facade._blender_scene
	Facade._blender_scene = malformed
	var station = Facade.new()
	station.setup({"visual_dimension_profile": "metric_v1"})
	check(station.has_node("PlantBuilding") and station.has_node("TankSilhouette1") and not station.has_node("BlenderAsset"), "facade: invalid import uses whole-site fallback")
	check(station.has_meta("asset_fallback") and station.named_ports.size() == 2, "facade: explicit fallback retains ports")
	station.free()
	Facade._blender_scene = saved_facade
