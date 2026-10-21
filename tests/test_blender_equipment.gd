extends SceneTree
## Real imported Blender assets retain the procedural EquipmentNode interface.
const Visual = preload("res://scripts/equipment_visual.gd")
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
	for kind in ["wind", "pv"]:
		var item = Visual.create(kind, {}, true)
		root.add_child(item)
		check(item.get_meta("visual_backend") == "blender_glb", kind + ": opted-in reference geometry uses the actual GLB")
		check(item.has_node("BlenderAsset"), kind + ": imported scene is attached")
		check(item.has_node("ElectricityPort"), kind + ": standard electricity terminal exists")
		check(item.get_meta("visual_only") and item.get_meta("capacity_added") == 0.0, kind + ": imported assets remain display-only")
		check(item.surfaces.size() == item.base_materials.size(), kind + ": every mesh participates in preview restoration")
		check(item.surfaces.size() <= (7 if kind == "wind" else 3), kind + ": static meshes are consolidated")
		var triangles := 0
		var authored_meshes := 0
		for mesh in item.surfaces:
			if mesh == item.selection_ring or mesh.get_parent() == item.port:
				continue
			authored_meshes += 1
			check(mesh.material_override == null, kind + ": original material comes from GLB surface slots")
			for surface in mesh.mesh.get_surface_count():
				check(mesh.get_active_material(surface) != null, kind + ": surface material is present")
				var arrays: Array = mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				triangles += indices.size() / 3 if not indices.is_empty() else vertices.size() / 3
				for vertex in vertices:
					var point: Vector3 = mesh.global_transform * vertex
					check(point.y >= -0.0001, kind + ": actual imported vertices remain above ground")
					check(Vector2(point.x, point.z).length() <= Visual.footprint(kind), kind + ": imported vertices fit siting footprint")
		check(authored_meshes == (5 if kind == "wind" else 1), kind + ": expected exported mesh hierarchy")
		check(triangles > 1000 and triangles < 12000, kind + ": triangle count is meaningful and bounded")
		item.set_highlight(true)
		check(item.selection_ring.visible, kind + ": selection ring works")
		for valid in [true, false]:
			item.set_preview(valid)
			for mesh in item.surfaces:
				check(mesh.material_override == (item.preview_good if valid else item.preview_bad), kind + ": all GLB material slots are covered by preview override")
		item.clear_preview()
		for index in item.surfaces.size():
			check(item.surfaces[index].material_override == item.base_materials[index], kind + ": imported surface material is restored")
		if kind == "wind":
			check(item.rotor != null, "wind: Rotor is wired for animation")
			check(item.rotor.global_position.is_equal_approx(Vector3(0, 9, -0.89)), "wind: reference hub location is preserved")
			check(item.rotor.get_child_count() == 4, "wind: rotor contains three blades and a spinner")
			var before: float = item.rotor.rotation.z
			item.set_operating(2.0)
			item._process(0.5)
			check(is_equal_approx(item.rotor.rotation.z, fposmod(before + 1.0, TAU)), "wind: imported rotor rotates around its own Z axis")
			item.set_preview(true)
			before = item.rotor.rotation.z
			item._process(1.0)
			check(is_equal_approx(before, item.rotor.rotation.z), "wind: construction preview does not animate")
			item.clear_preview()
			check(item.port_local.is_equal_approx(Vector3(1.15, 0.65, -0.37)), "wind: original electrical port retained")
		else:
			check(item.port_local.is_equal_approx(Vector3(3.75, 0.38, -0.30)), "PV: original electrical port retained")
			check(item.get_meta("module_area_m2") == 16000.0 and item.get_meta("field_representation"), "PV: compressed-field area is documented")
		item.position = Vector3(3, 2, -6)
		item.rotation.y = 0.7
		check(item.port_global().is_equal_approx(item.to_global(item.port_local)), kind + ": terminal follows scene placement and rotation")
		item.free()
	var wind = Visual.create("wind", {"rated_mw": 3.0}, true)
	check(wind.get_meta("visual_backend") == "blender_glb", "electrical-only wind edits keep the Blender geometry")
	wind.free()
	for profile in [{"hub_height_m": 100.0}, {"rotor_diameter_m": 130.0}, {"geometry": {"rotor_diameter_m": 110.0}}]:
		wind = Visual.create("wind", profile, true)
		check(wind.get_meta("visual_backend") == "procedural", "custom wind dimensions use parameterized fallback")
		check(wind.has_node("Tower") and wind.has_meta("asset_fallback"), "wind fallback is real geometry with an explicit reason")
		wind.free()
	for profile in [{"tilt_deg": 40.0}, {"module_area_m2": 20000.0}, {"geometry": {"panel_tilt_deg": 10.0}}]:
		var pv = Visual.create("pv", profile, true)
		check(pv.get_meta("visual_backend") == "procedural", "custom PV geometry uses parameterized fallback")
		check(pv.has_node("Panel_0_0/Cells") and pv.has_meta("asset_fallback"), "PV fallback is real geometry with an explicit reason")
		pv.free()
	for kind in ["wind", "pv"]:
		var legacy = Visual.create(kind)
		check(legacy.get_meta("visual_backend") == "procedural", kind + ": legacy two-argument interface stays compatible")
		legacy.free()
	for kind in ["station", "load", "battery"]:
		var independent = Visual.create(kind, {}, true)
		check(independent.get_meta("visual_backend") == "procedural" and not independent.has_node("Placeholder"), kind + ": uses its own supported model")
		independent.free()
	print("BLENDER_EQUIPMENT_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
