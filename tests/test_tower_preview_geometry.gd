extends SceneTree
const Spatial = preload("res://scripts/spatial_dimensions.gd")
const Visual = preload("res://scripts/equipment_visual.gd")
var failures := 0
var checks := 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func _init() -> void:
	var d := Spatial.profile("tower_station_preview")
	check(d.valid and d.land_dimensions_m == Vector3(160,0,160), "full 160m tower site")
	check(d.interior_dimensions_m == Vector3(120,0,120), "full 120m net preview")
	check(d.land_area_m2 == 25600 and d.interior_area_m2 == 14400, "land and interior areas distinct")
	check(absf(d.clearance_radius_world - sqrt(128.0)) < .0001, "full circumscribed clearance")
	check(d.tower_height_m == 25 and d.mirror_aperture_area_m2 == 1600 and d.heliostat_count == 100, "explicit physical preview inventory")
	check(not d.commissioned and d.preview_only and d.body_area_m2 == 0, "site is not claimed building or power output")
	var layout := Spatial.tower_mirror_layout()
	var ring_counts := [0, 0, 0, 0]
	check(layout.size() == 100, "geometry-derived 100 mirrors")
	for i in range(layout.size()):
		var center: Vector3 = layout[i].center_m
		var normal: Vector3 = layout[i].normal
		var ring: int = layout[i].ring
		ring_counts[ring] += 1
		check(absf(Vector2(center.x, center.z).length() - Spatial.TOWER_RING_RADII_M[ring]) < .0001, "exact concentric radius")
		check(absf(center.z) >= 5.0, "radial access corridor clear")
		var reflected := -Spatial.TOWER_SUN_DIRECTION + 2.0 * Spatial.TOWER_SUN_DIRECTION.dot(normal) * normal
		check(reflected.distance_to((Spatial.TOWER_RECEIVER_M-center).normalized()) < .0001, "specular reflection targets central receiver")
		for j in range(i):
			# Circumscribed 3D sphere is conservative for any mirror orientation.
			check(center.distance_to(layout[j].center_m) > 2.0 * sqrt(8.01), "mirror sweep envelopes do not overlap")
	check(ring_counts == [14,20,30,36], "derived population of each staggered ring")
	for imported in [false,true]:
		for interior in [false,true]:
			var item = Visual.create("tower_station_preview", {"preview_interior":interior}, imported)
			root.add_child(item)
			check(item.get_meta("visual_backend") == ("blender_glb" if imported else "metric_procedural_fallback"), "preview backend")
			check(item.named_ports.is_empty() and item.named_port_locals.is_empty() and item.port == null, "preview has zero terminals")
			check(item.get_meta("energy_output_mw") == 0 and item.get_meta("capacity_added") == 0, "preview adds no energy")
			var floor: MeshInstance3D = item.find_child("Usable120m",true,false)
			var floor_material: StandardMaterial3D = floor.get_active_material(0)
			check(maxf(floor_material.albedo_color.r,maxf(floor_material.albedo_color.g,floor_material.albedo_color.b)) < .37, "muted floor retains mirror contrast")
			check(not item.is_processing(), "preview has no runtime")
			check(item.find_children("Heliostat*", "Node3D", true, false).size() == 100, "100 distinct heliostats")
			check(item.find_children("MirrorSurface*", "MeshInstance3D", true, false).size() == 100, "100 actual mirror meshes")
			check((item.find_child("ExteriorSite", true, false) == null) == interior, "interior removes only exterior site")
			var actual_mirrors := item.find_children("MirrorSurface*", "MeshInstance3D", true, false)
			for index in range(actual_mirrors.size()):
				var mirror: MeshInstance3D = actual_mirrors[index]
				var transform := Visual._relative_transform(mirror,item)
				var center_m := transform.origin / Spatial.WORLD_UNITS_PER_METER
				var normal := transform.basis.y.normalized()
				var closest := INF
				for entry in layout:
					closest = minf(closest, center_m.distance_to(entry.center_m))
				check(closest < .001, "actual mesh center matches ring geometry")
				var reflected := -Spatial.TOWER_SUN_DIRECTION + 2.0 * Spatial.TOWER_SUN_DIRECTION.dot(normal) * normal
				check(reflected.distance_to((Spatial.TOWER_RECEIVER_M-center_m).normalized()) < .001, "actual mirror normal satisfies reflection")
			var receiver: MeshInstance3D = item.find_child("DarkReceiver",true,false)
			var receiver_box: AABB = Visual._relative_transform(receiver,item) * receiver.mesh.get_aabb()
			check(Vector2(receiver_box.get_center().x,receiver_box.get_center().z).length() < .0001, "receiver tower centered at site origin")
			var span := 6.0 if interior else 8.0
			var maximum_y := 0.0
			for surface in item.surfaces:
				if surface == item.selection_ring: continue
				var a: AABB = Visual._relative_transform(surface,item) * surface.mesh.get_aabb()
				check(a.position.x >= -span-.0001 and a.end.x <= span+.0001 and a.position.z >= -span-.0001 and a.end.z <= span+.0001, "physical geometry stays within unscaled site: " + surface.name)
				check(a.position.y >= -.0001, "physical geometry above grade")
				maximum_y = maxf(maximum_y,a.end.y)
			check(absf(maximum_y-2.5) < .0001, "tower actual25m height")
			item.set_preview(false)
			check(item.preview_enabled, "placement preview")
			item.clear_preview()
			check(not item.preview_enabled and item.named_ports.is_empty(), "clear preview does not add ports")
			item.free()
	print("TOWER_PREVIEW_GEOMETRY checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
