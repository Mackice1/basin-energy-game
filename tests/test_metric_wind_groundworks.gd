extends SceneTree
## Verify rendered ground works, including the batched imported GLB, against
## metric siting metadata without changing rotor, tower, ports or legacy assets.
const Visual = preload("res://scripts/equipment_visual.gd")
const Spatial = preload("res://scripts/spatial_dimensions.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("METRIC_WIND_GROUNDWORKS: " + label)

func near(a: float, b: float, label: String) -> void:
	check(absf(a - b) <= 0.0001, label)

func _initialize() -> void:
	call_deferred("run")

func points_for(item: Node3D, category: String) -> PackedVector3Array:
	var points := PackedVector3Array()
	for instance: MeshInstance3D in item.surfaces:
		for slot in instance.mesh.get_surface_count():
			var material := instance.mesh.surface_get_material(slot)
			var material_name: String = material.resource_name if material != null else ""
			var include := str(instance.name) == category
			if category == "Foundation":
				include = include or (str(instance.name) == "Structure" and material_name == "Warm concrete")
			elif category == "ServiceApron":
				include = include or str(instance.name) == "Service apron" or (str(instance.name) == "Structure" and material_name == "Fine aggregate")
			if not include:
				continue
			var relative := item.global_transform.affine_inverse() * instance.global_transform
			var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(slot)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				points.append(relative * vertex)
	return points

func bounds_for(item: Node3D, category: String) -> AABB:
	var points := points_for(item, category)
	check(not points.is_empty(), category + " actual mesh vertices exist")
	if points.is_empty():
		return AABB()
	var bounds := AABB(points[0], Vector3.ZERO)
	for point in points:
		bounds = bounds.expand(point)
	return bounds

func mesh_signature(node: Node) -> Array:
	var result: Array = []
	if node is Node3D:
		result.append(node.transform)
	if node is MeshInstance3D:
		for slot in node.mesh.get_surface_count():
			result.append(node.mesh.surface_get_arrays(slot))
	for child in node.get_children():
		result.append(mesh_signature(child))
	return result

func same_static_surface(before: Array, after: Array) -> bool:
	# ArrayMesh repacks octahedral normal/tangent directions on upload. Geometry,
	# UVs and indices stay exact; direction roundtrips differ by at most 0.0002.
	for slot in before.size():
		if slot not in [Mesh.ARRAY_NORMAL,Mesh.ARRAY_TANGENT]:
			if before[slot] != after[slot]: return false
			continue
		if before[slot] == null or after[slot] == null:
			if before[slot] != after[slot]: return false
			continue
		if before[slot].size() != after[slot].size(): return false
		for index in before[slot].size():
			if slot == Mesh.ARRAY_NORMAL:
				if before[slot][index].distance_to(after[slot][index]) > 0.0002: return false
			elif absf(before[slot][index] - after[slot][index]) > 0.0002: return false
	return true

func check_groundworks(item: Node3D, label: String) -> void:
	var foundation := bounds_for(item, "Foundation")
	var apron := bounds_for(item, "ServiceApron")
	var slab := bounds_for(item, "MetricFoundationBase")
	near(foundation.size.x, 1.8, label + " circular footing width18m")
	near(foundation.size.z, 1.8, label + " circular footing depth18m")
	near(foundation.get_center().x, 0.0, label + " circular footing centeredX")
	near(foundation.get_center().z, 0.0, label + " circular footing centeredZ")
	for point in points_for(item, "Foundation"):
		check(Vector2(point.x, point.z).length() <= 0.9001, label + " circular footing radius9m within1mm import precision")
	near(slab.size.x, 1.8, label + " square slab width18m")
	near(slab.size.z, 1.8, label + " square slab depth18m")
	near(slab.size.x * slab.size.z / 0.01, 324.0, label + " square slab matches324m2 foundation projection")
	near(apron.size.x, 3.2, label + " apron width32m")
	near(apron.size.z, 3.2, label + " apron depth32m")
	near(apron.get_center().x, 0.0, label + " apron centeredX")
	near(apron.get_center().z, 0.0, label + " apron centeredZ")
	near(apron.position.y, 0.0, label + " apron remains above grade")
	near(float(item.get_meta("body_area_m2")), 324.0, label + " metadata foundation area")
	near(float(item.get_meta("land_area_m2")), 1024.0, label + " metadata maintenance area")
	check(item.get_meta("foundation_dimensions_m") == Vector3(18,0,18), label + " foundation metadata dimensions")
	check(item.get_meta("land_dimensions_m") == Vector3(32,0,32), label + " apron metadata dimensions")
	for point in points_for(item, "ServiceApron"):
		check(Vector2(point.x,point.z).length() <= float(item.get_meta("footprint_radius")) + 0.00001, label + " apron contained by clearance circle")

func run() -> void:
	for imported in [false, true]:
		var label := "imported" if imported else "procedural"
		var params := {"hub_height_m":90.0, "rotor_diameter_m":126.0}
		var legacy = Visual.create("wind", params, imported)
		root.add_child(legacy)
		var legacy_signature := mesh_signature(legacy)
		var metric_params := params.duplicate(true)
		metric_params.visual_dimension_profile = "metric_v1"
		var params_before := var_to_bytes(metric_params)
		var metric = Visual.create("wind", metric_params, imported)
		root.add_child(metric)
		check(var_to_bytes(metric_params) == params_before, label + " parameters unchanged")
		check(metric.get_meta("visual_backend") == ("blender_glb" if imported else "procedural"), label + " requested backend used")
		check(mesh_signature(metric.rotor) == mesh_signature(legacy.rotor), label + " exact rotor geometry and transform unchanged")
		check(metric.port_local == legacy.port_local, label + " electrical endpoint unchanged")
		if imported:
			var original_structure := legacy.find_child("Structure",true,false) as MeshInstance3D
			var fitted_structure := metric.find_child("Structure",true,false) as MeshInstance3D
			check(original_structure.transform == fitted_structure.transform,label + " static mesh placement unchanged")
			for slot in original_structure.mesh.get_surface_count():
				var material := original_structure.mesh.surface_get_material(slot)
				if material.resource_name not in ["Fine aggregate","Warm concrete"]:
					check(same_static_surface(original_structure.mesh.surface_get_arrays(slot), fitted_structure.mesh.surface_get_arrays(slot)),label + " non-ground static surface unchanged " + material.resource_name)
		else:
			for name in ["Tower","Nacelle","Converter"]:
				check(mesh_signature(metric.get_node(name)) == mesh_signature(legacy.get_node(name)),label + " unchanged " + name)
		check_groundworks(metric, label)
		check(mesh_signature(legacy) == legacy_signature, label + " existing legacy geometry never mutated")
		var later_legacy = Visual.create("wind", params, imported)
		root.add_child(later_legacy)
		check(mesh_signature(later_legacy) == legacy_signature, label + " cached source retains original geometry")
		var old_apron := bounds_for(later_legacy, "ServiceApron")
		near(old_apron.size.x,3.5,label + " legacy apron width retained")
		near(old_apron.size.z,2.7,label + " legacy apron depth retained")
		near(old_apron.get_center().x,0.35,label + " legacy apron offsetX retained")
		near(old_apron.get_center().z,-0.15,label + " legacy apron offsetZ retained")
		var old_foundation := bounds_for(later_legacy,"Foundation")
		near(old_foundation.size.x,1.86 if imported else 1.9,label + " legacy foundation width retained")
		var holder := Node3D.new()
		root.add_child(holder)
		metric.reparent(holder)
		holder.position = Vector3(4,2,-6)
		holder.rotation.y = 0.57
		holder.scale = Vector3(1.2,1.2,1.2)
		metric.position = Vector3(-3,1,4)
		metric.rotation.y = -0.31
		check_groundworks(metric,label + " transformed")
		metric.set_preview(false)
		for surface: MeshInstance3D in metric.surfaces:
			check(surface.material_override == metric.preview_bad,label + " preview includes normalized grounds")
		metric.clear_preview()
		for index in metric.surfaces.size():
			check(metric.surfaces[index].material_override == metric.base_materials[index],label + " preview restores original materials")
		holder.free(); legacy.free(); later_legacy.free()
	# The smallest allowed geometric rotor still reserves the complete apron.
	var small = Visual.create("wind", {"hub_height_m":10.0,"rotor_diameter_m":2.0,"visual_dimension_profile":"metric_v1"},true)
	root.add_child(small)
	check(small.get_meta("visual_backend") == "procedural","custom wind falls back without changing metric grounds")
	check_groundworks(small,"small custom rotor")
	near(float(small.get_meta("footprint_radius")),Vector2(3.2,3.2).length()*0.5,"small rotor collision retains apron corners")
	small.free()
	print("METRIC_WIND_GROUNDWORKS checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
