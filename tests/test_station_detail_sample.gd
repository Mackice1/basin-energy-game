extends SceneTree
const Detail = preload("res://scripts/station_detail_sample.gd")
const Visual = preload("res://scripts/equipment_visual.gd")
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
 if not ok: failures.append(label)
func _initialize() -> void:
 var node := Detail.new()
 root.add_child(node)
 var bounds := AABB()
 var first := true
 var triangles := 0
 for child in node.get_children():
  check(child is MeshInstance3D, "Display has only baked geometry, no simulation scripts or collision")
  var box: AABB = child.transform * child.mesh.get_aabb()
  bounds = box if first else bounds.merge(box)
  first = false
  check(child.mesh.get_surface_count() == 1, "One surface per batched material")
  triangles += child.mesh.surface_get_array_index_len(0) / 3
 check(node.device_kind == "station", "Inspector kind contract")
 check(node.get_meta("representative_only"), "Representative rather than full field")
 check(not node.get_meta("voltage_is_simulated"), "No invented voltage simulation")
 check(node.get_child_count() == 9, "Nine material batches")
 check(triangles > 2000 and triangles < 25000, "Bounded detailed geometry")
 check(bounds.position.y >= -0.001 and bounds.end.y < 2.95, "Grounded and within reference package height")
 check(bounds.size.x < 6.813 and bounds.size.z < 5.538, "Within reference package envelope")
 check(not node.has_method("get_port_position"), "Detail does not claim a real electrical endpoint")
 var stats := {"bounds_m":str(bounds),"triangles":triangles,"materials":9,"components":node.get_meta("component_count"),"failures":failures}
 print("STATION_DETAIL ",JSON.stringify(stats))
 var output := "res://evidence/station_detail_1002"
 DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
 var file := FileAccess.open(output+"/geometry_stats.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(stats,"  ")); file.close()
 # Export real generated meshes for offline visual review, not an app screenshot.
 var doc := GLTFDocument.new()
 var state := GLTFState.new()
 check(doc.append_from_scene(node,state)==OK,"Export detail for review")
 check(doc.write_to_filesystem(state,output+"/after.glb")==OK,"Save detail review mesh")
 var before := Visual.create("station",{"visual_dimension_profile":"metric_v1","capacity_mw":2.0},true)
 before.scale = Vector3.ONE*10.0
 root.add_child(before)
 var before_state := GLTFState.new()
 check(doc.append_from_scene(before,before_state)==OK,"Export legacy comparison")
 check(doc.write_to_filesystem(before_state,output+"/before.glb")==OK,"Save legacy comparison")
 before.free(); node.free()
 print("STATION_DETAIL_RESULT ","PASS" if failures.is_empty() else str(failures))
 quit(0 if failures.is_empty() else 1)
