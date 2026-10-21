extends SceneTree
const Spatial = preload("res://scripts/spatial_dimensions.gd")
const Visual = preload("res://scripts/equipment_visual.gd")
var checks := 0
var failures: Array[String] = []
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)
func _initialize() -> void:
	call_deferred("_run")
func _run() -> void:
	var base := Spatial.profile("solar_thermal", {"absorber_area_m2":30.3})
	check(base.valid and base.module_count == 10 and base.tube_count == 240, "default uses ten full 24-tube collectors")
	check(is_equal_approx(base.installed_absorber_area_m2, 30.3) and is_equal_approx(base.installed_aperture_area_m2, 31.9) and is_equal_approx(base.installed_gross_area_m2, 46.2), "absorber/aperture/gross are distinct")
	check(base.land_dimensions_m.x < 48 and base.land_dimensions_m.z < 48, "default fits real station interior")
	check(base.land_area_m2 > base.installed_gross_area_m2 and base.land_area_m2 > base.requested_absorber_area_m2, "placement counts rows and perimeter, not absorber only")
	check(base.tilt_deg == 30.0 and base.row_pitch_m == 3.6 and base.maintenance_margin_m == 2, "fixed documented teaching installation")
	check(base.collector_dimensions_m.is_equal_approx(Vector3(2.061,.15,2.241)), "historical collector full-size envelope")
	for area in [3.03, 3.04, 30.3, 31.0, 303.0, 3030.0]:
		var d := Spatial.profile("solar_thermal", {"absorber_area_m2":area}, false)
		check(d.valid and d.module_count == int(ceil(area/3.03 - 0.000000001)), "whole-module ceiling %s" % area)
		check(d.unit_dimensions_m.is_equal_approx(base.unit_dimensions_m), "no compressed module at %s" % area)
		check(d.module_origins_world.is_empty() and not d.origins_complete, "cheap placement does not allocate modules")
		check(Spatial.module_origin_m(d, d.module_count-1).is_finite(), "analytical origin remains valid")
	var partial := Spatial.profile("solar_thermal", {"absorber_area_m2":3.04})
	check(partial.module_count == 2 and partial.last_module_utilization > 0 and partial.last_module_utilization < .01, "fractional last module honest utilization")
	var huge := Spatial.profile("solar_thermal", {"absorber_area_m2":3030}, false)
	check(huge.land_dimensions_m.x > 48 and huge.land_dimensions_m.z > 48, "oversized fields cannot fit by scaling")
	for bad in [0,-1,3030.01,INF,NAN,"bad"]:
		check(not Spatial.profile("solar_thermal", {"absorber_area_m2":bad}).valid, "invalid absorber geometry rejected")
	for imported in [false,true]:
		var params := {"absorber_area_m2":3.04,"visual_dimension_profile":"metric_v1"}
		var unchanged := params.duplicate(true)
		var item = Visual.create("solar_thermal", params, imported)
		root.add_child(item)
		check(params == unchanged, "visual does not mutate source params")
		check(item.get_meta("visual_backend") == ("blender_glb" if imported else "metric_procedural_fallback"), "expected real backend")
		check(item.get_meta("module_count") == 2 and item.get_meta("world_units_per_meter") == .1, "full-size whole module rendering")
		check(item.named_ports.size() == 2 and item.has_named_port("ac_in") and item.has_named_port("heat_out"), "exact agreed named ports")
		check(item.named_ports.ac_in.get_meta("direction") == "input" and item.named_ports.heat_out.get_meta("grade_id") == "hw_primary_90_60", "port contract")
		if imported:
			check(item.get_node("BlenderAsset").get_child_count() == 2, "actual imported full-module count")
		else:
			check(item.find_children("EvacuatedTube*", "MeshInstance3D", true, false).size() == 48, "fallback contains actual 24 tubes per whole module")
		check(item.rotor == null and item.get_meta("tilt_deg") == 30.0, "fixed non-tracking collector")
		check(item.find_child("PartialUtilizationLabel", true, false) != null, "fractional utilization is visibly disclosed")
		for id in ["ac_in","heat_out"]:
			var expected: Vector3 = Visual._vector3(Visual.thermal_asset_definition("solar_thermal").ports[id]) + partial.module_origins_world[0]
			check(item.named_port_locals[id].is_equal_approx(expected), "GLB and fallback agree on port " + id)
		var bounds := AABB()
		var found := false
		var original_materials: Array = []
		for mesh in item.surfaces:
			original_materials.append(mesh.material_override)
			if mesh == item.selection_ring: continue
			var box: AABB = Visual._relative_transform(mesh, item) * mesh.mesh.get_aabb()
			bounds = bounds.merge(box) if found else box
			found = true
		check(bounds.size.x <= partial.body_dimensions_m.x * .1 + .00001 and bounds.size.z <= partial.body_dimensions_m.z * .1 + .00001, "real meshes fit conservative full body footprint")
		check(bounds.size.y <= partial.body_dimensions_m.y * .1 + .00001 and bounds.position.y >= -.00001, "rack height and grade match")
		item.set_preview(false); item.clear_preview()
		for i in item.surfaces.size():
			check(item.surfaces[i].material_override == original_materials[i], "preview restores material")
		item.free()
	print("SOLAR_THERMAL_GEOMETRY checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
