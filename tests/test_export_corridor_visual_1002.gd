extends SceneTree
const Corridor = preload("res://scripts/export_corridor_visual.gd")
var failures: Array[String] = []

class Ground:
	extends Node3D
	var image: Image
	func _init() -> void:
		image = Image.create_from_data(1024,1024,false,Image.FORMAT_RF,FileAccess.get_file_as_bytes("res://generated/height.raw"))
	func height_at(x: float, z: float) -> float:
		var px := clampf((x+128.0)*4.0,0,1022.99)
		var pz := clampf((z+128.0)*4.0,0,1022.99)
		var ix := int(px)
		var iz := int(pz)
		return lerpf(lerpf(image.get_pixel(ix,iz).r,image.get_pixel(ix+1,iz).r,px-ix),lerpf(image.get_pixel(ix,iz+1).r,image.get_pixel(ix+1,iz+1).r,px-ix),pz-iz)

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func _initialize() -> void:
	var map := Ground.new()
	var parent := Node3D.new()
	root.add_child(map)
	root.add_child(parent)
	var start := Time.get_ticks_msec()
	var corridor := Corridor.build(map,parent)
	check(corridor.get_meta("visual_only"),"Visual-only contract")
	check(not corridor.get_meta("voltage_is_simulated"),"No simulated voltage claim")
	check(corridor.get_meta("tower_count") == 3,"Three existing supports only")
	check(corridor.get_meta("topology") == "68,3 -> 80,3 -> 94,3 -> 100,3","Existing route topology preserved")
	check(corridor.get_child_count() == 2,"Exactly two prebuilt zoom levels")
	var near: Node3D = corridor.get_node("Near")
	var far: Node3D = corridor.get_node("Far")
	check(far.visible and not near.visible,"Map starts with coarse overview geometry")
	Corridor.set_detail(corridor,true)
	check(near.visible and not far.visible,"Close zoom selects detailed geometry exclusively")
	Corridor.set_detail(corridor,false)
	check(far.visible and not near.visible,"Zooming out restores overview exclusively")
	var levels: Dictionary = {}
	for level in [far,near]:
		var triangles := 0
		var bounds := AABB()
		var first := true
		check(level.get_child_count() == 5,"Five material draw batches per LOD")
		for child in level.get_children():
			check(child is MeshInstance3D,"Only baked geometry, no colliders or network ports")
			check(child.mesh.get_surface_count() == 1,"Single surface per material batch")
			var box: AABB = child.mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
			triangles += child.mesh.surface_get_array_index_len(0)/3
			var arrays: Array = child.mesh.surface_get_arrays(0)
			for vertex in arrays[Mesh.ARRAY_VERTEX]:
				check(vertex.is_finite(),"All mesh vertices finite")
		check(bounds.position.x > 66.5 and bounds.end.x < 100.2,"No extension beyond existing corridor other than foundation width")
		check(bounds.position.z > -0.6 and bounds.end.z < 6.6,"Crossarm bounded to existing route vicinity")
		check(bounds.end.y < 10.0,"Schematic map-scale support height bounded")
		check(triangles == level.get_meta("triangle_count"),"Geometry budget metadata accurate")
		levels[level.name] = {"triangles":triangles,"bounds":str(bounds),"batches":level.get_child_count(),"components":level.get_meta("component_count")}
	check(int(levels["Near"]["triangles"]) < 23000,"Near triangle budget below 23,000")
	check(int(levels["Far"]["triangles"]) < 6500,"Far triangle budget below 6,500")
	check(int(levels["Far"]["triangles"])*2 < int(levels["Near"]["triangles"]),"Overview removes more than half of detailed triangles")
	for i in 5:
		check(near.get_child(i).material_override == far.get_child(i).material_override,"Materials shared between zoom levels")
	var minimum_clearance := INF
	for span in 3:
		for lateral in Corridor.BUNDLE_Z:
			var path := Corridor.conductor_path(map,Corridor.ROUTE_X[span],Corridor.ROUTE_X[span+1],lateral)
			check(path.size() == 13,"Twelve cable subdivisions for close zoom")
			check(is_equal_approx(path[0].x,Corridor.ROUTE_X[span]),"Cable start remains at tower X")
			check(is_equal_approx(path[-1].x,Corridor.ROUTE_X[span+1]),"Cable end remains at tower or original map edge")
			check(is_equal_approx(path[0].y,map.height_at(path[0].x,3)+Corridor.CONDUCTOR_HEIGHT),"Cable anchored at insulator lower end")
			check(path[6].y < (path[0].y+path[-1].y)*0.5-0.2,"Span sags below straight chord, not terrain-hugging")
			for p in path:
				# The overview's .14 radius is larger than near bundle offset+radius (.115).
				minimum_clearance = minf(minimum_clearance,p.y-map.height_at(p.x,p.z)-0.14)
	check(minimum_clearance > 5.0,"All bundled strands remain above existing terrain")
	check(not corridor.has_method("get_port_position"),"Does not fabricate live network endpoints")
	var stats := {"levels":levels,"minimum_ground_clearance_map_units":minimum_clearance,"build_ms":Time.get_ticks_msec()-start,"failures":failures}
	var output := "res://evidence/export_corridor_1002"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var file := FileAccess.open(output+"/geometry_stats.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(stats,"  "))
	file.close()
	# Offline geometry export is useful to review without starting an interactive app.
	if "--export-mesh" in OS.get_cmdline_user_args():
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		check(document.append_from_scene(near,state) == OK,"Export close corridor mesh")
		check(document.write_to_filesystem(state,output+"/near.glb") == OK,"Save close corridor mesh")
	print("EXPORT_CORRIDOR_STATS ",JSON.stringify(stats))
	print("EXPORT_CORRIDOR_RESULT ","PASS" if failures.is_empty() else str(failures))
	parent.free()
	map.free()
	quit(0 if failures.is_empty() else 1)
