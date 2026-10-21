extends SceneTree
const Spatial = preload("res://scripts/spatial_dimensions.gd")
const Visual = preload("res://scripts/equipment_visual.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)
func _init() -> void:
	var trough := Spatial.profile("parabolic_trough")
	check(trough.valid and trough.module_count == 1, "default trough one full module")
	check(is_equal_approx(trough.installed_aperture_area_m2, 69.24), "aperture")
	var partial := Spatial.profile("parabolic_trough", {"aperture_area_m2": 70.0})
	check(partial.module_count == 2 and partial.unit_dimensions_m == trough.unit_dimensions_m, "fractional last module full size")
	check(partial.last_module_utilization < .02, "fractional utilization")
	var huge := Spatial.profile("parabolic_trough", {"aperture_area_m2": 6924.0})
	check(huge.land_dimensions_m.x > 48 or huge.land_dimensions_m.z > 48, "oversize trough cannot fit station")
	var store := Spatial.profile("high_temp_store", {"capacity_mwhth": 1.0})
	check(absf(store.hot_full_volume_m3_each - 18.697) < .005, "each tank full hot inventory")
	check(absf(store.tank_geometric_volume_m3_each - 23.372) < .005, "each tank freeboard volume")
	check(is_equal_approx(PI * pow(store.tank_diameter_m, 3) / 4.0, store.tank_geometric_volume_m3_each), "cylinder actual volume")
	check(Spatial.profile("high_temp_store", {"capacity_mwhth": 100000.0}).land_dimensions_m.x > 48, "huge store grows")
	for kind in ["parabolic_trough", "high_temp_store", "oil_water_exchanger"]:
		for imported in [false, true]:
			var item = Visual.create(kind, {}, imported)
			root.add_child(item)
			check(item.get_meta("visual_dimension_profile") == "metric_v1", "metric only")
			check(item.get_meta("visual_backend") == ("blender_glb" if imported else "metric_procedural_fallback"), "backend " + kind)
			for key in item.named_ports:
				check(item.named_ports[key].get_meta("carrier") == ("electricity_ac" if key == "ac_in" else "heat_water" if key == "warm_out" else "heat_oil"), "carrier " + key)
			if kind == "parabolic_trough":
				check(item.solar_tracking_pivots.size() == 1, "tracking assembly")
				var clearance = item.get_meta("footprint_radius")
				for az in [0.0, 30.0, 60.0, 90.0, 120.0, 150.0, 180.0, 210.0, 240.0, 270.0, 300.0, 330.0]:
					item.set_solar_tracking(10.0, az)
					check(item.get_meta("footprint_radius") == clearance, "tracking invariant clearance")
					var sun := Vector3(cos(deg_to_rad(10.0)) * sin(deg_to_rad(az)), sin(deg_to_rad(10.0)), -cos(deg_to_rad(10.0)) * cos(deg_to_rad(az)))
					var normal: Vector3 = Visual._relative_transform(item.solar_tracking_pivots[0], item).basis.y.normalized()
					check(is_equal_approx(normal.dot(sun), sqrt(1.0 - sun.z * sun.z)), "north south tracking optical cosine")
					for surface in item.surfaces:
						if surface == item.selection_ring: continue
						var box: AABB = Visual._relative_transform(surface, item) * surface.mesh.get_aabb()
						check(box.position.x >= -.3251 and box.end.x <= .3251 and box.position.y >= -.0001 and box.end.y <= .6751 and box.position.z >= -.6501 and box.end.z <= .6501, "all-angle sweep envelope " + str(surface.name) + str(box))
				item.set_solar_tracking(-5.0, 90.0)
				check(is_zero_approx(item.solar_tracking_pivots[0].rotation.z), "night upward stow")
			item.free()
	print("HIGH_TEMP_GEOMETRY failures=", failures)
	quit(1 if failures else 0)
