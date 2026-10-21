extends SceneTree

const Visual = preload("res://scripts/equipment_visual.gd")
var checks := 0
var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		push_error(label)

func triangle_count(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		for surface in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			count += indices.size() / 3 if not indices.is_empty() else arrays[Mesh.ARRAY_VERTEX].size() / 3
	for child in node.get_children(): count += triangle_count(child)
	return count

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var wind = Visual.create("wind", {"source_values": {"hub_height_m": 90.0, "rotor_diameter_m": 126.0}})
	root.add_child(wind)
	check(is_equal_approx(wind.rotor.position.y, 9.0), "90 m hub displayed at 9 world units")
	var blades := 0
	for child in wind.rotor.get_children():
		if child.get_meta("rotor_blade", false):
			blades += 1
			check(is_equal_approx(child.mesh.get_aabb().end.y, 6.3), "blade reaches parameterized rotor radius")
			check(wind.rotor.position.y - child.mesh.get_aabb().end.y > 0.0, "swept rotor remains above ground")
			check(triangle_count(child) >= 28, "blade uses closed solid mesh")
			var arrays: Array = child.mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for vertex_index in vertices.size():
				if absf(normals[vertex_index].z) > 0.9:
					check(vertices[vertex_index].z * normals[vertex_index].z > 0.0, "blade face normals point outwards")
	check(blades == 3, "exactly three independent blades")
	check(triangle_count(wind) > 500, "wind is real triangle geometry")
	var first_blade: MeshInstance3D = wind.rotor.get_node("Blade1")
	var original_material: Material = first_blade.material_override
	wind.set_highlight(true)
	check(wind.selection_ring.visible, "selection outline visible")
	wind.set_preview(true)
	check(first_blade.material_override == wind.preview_good, "valid preview is green")
	check(not wind.selection_ring.visible, "preview suppresses selection outline")
	wind.set_preview(false)
	check(first_blade.material_override == wind.preview_bad, "invalid preview is red")
	wind.clear_preview()
	check(first_blade.material_override == original_material, "preview removal restores authored materials")
	check(wind.selection_ring.visible, "preview removal restores selection")
	wind.rotor.rotation.z = 0.0
	wind.set_operating(2.0)
	wind._process(0.5)
	check(is_equal_approx(wind.rotor.rotation.z, 1.0), "operating speed animates rotor")
	wind.set_operating(0.0)
	wind._process(0.5)
	check(is_equal_approx(wind.rotor.rotation.z, 1.0), "zero operating speed stops rotor")
	wind.position = Vector3(7, 3, -4)
	wind.rotation.y = 0.7
	check(wind.port_global().is_equal_approx(wind.to_global(wind.port_local)), "port follows placement and rotation")
	check(wind.get_node("ElectricityPort").get_meta("port_type") == "electricity", "single typed electricity port")
	check(Visual.footprint("wind_turbine") == 7.0, "wind siting accounts for rotor sweep")
	for tilt in [0.0, 25.0, 75.0]:
		var pv = Visual.create("pv_array", {"design_assumptions": {"module_area_m2": 16000.0, "tilt_deg": tilt}})
		root.add_child(pv)
		var panels := 0
		for mesh in pv.surfaces:
			if mesh.get_meta("pv_panel", false): panels += 1
			if mesh == pv.selection_ring: continue
			var aabb: AABB = mesh.mesh.get_aabb()
			for vertex in range(8):
				var world_point: Vector3 = mesh.global_transform * aabb.get_endpoint(vertex)
				check(world_point.y >= -0.00001, "PV mesh remains above ground at tilt %s" % tilt)
				check(Vector2(world_point.x, world_point.z).length() <= 5.0, "PV mesh fits advertised footprint")
		check(panels == 12, "PV has twelve individually tilted panels")
		check(pv.get_meta("module_area_m2") == 16000.0, "source module area retained")
		check(is_equal_approx(pv.get_meta("module_surface_area_world") / pow(pv.get_meta("world_units_per_meter"), 2), 16000.0), "display area scales from source module area")
		check(triangle_count(pv) > 1000, "PV panels and supports contain real geometry")
		pv.free()
	var station = Visual.create("substation")
	root.add_child(station)
	check(station.has_node("Transformer") and station.has_node("FenceBack0"), "station has transformer and fence")
	check(station.has_node("ElectricityPort"), "station has electricity port")
	check(triangle_count(station) > 1000, "station contains real solid geometry")
	for physical in [true, false]:
		var line = Visual.create_line(wind.port_global(), station.port_global(), physical, true)
		check(line.get_child_count() == (12 if physical else 1), "route has expected segment count")
		check(line.get_meta("capacity_added") == 0.0, "line visualization adds no capacity")
		check(triangle_count(line) > 0, "route is renderable geometry")
		line.free()
	var empty_line = Visual.create_line(Vector3.ZERO, Vector3.ZERO)
	check(empty_line.get_child_count() == 0, "coincident endpoints create no invalid segments")
	empty_line.free()
	wind.free()
	station.free()
	print("EQUIPMENT_VISUAL_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
