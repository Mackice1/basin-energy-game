extends SceneTree
const Visual = preload("res://scripts/equipment_visual.gd")
const Tower = preload("res://scripts/tower_visual.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _init() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	Tower.build(fixture)
	var bounds := AABB()
	var first := true
	for child in fixture.get_children():
		var mesh := child as MeshInstance3D
		var box := mesh.transform * mesh.mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	check(absf(bounds.end.y - 2.5) < .00001, "25m unchanged")
	check(absf(bounds.position.x + .4) < .00001 and absf(bounds.end.x - .4) < .00001, "8m footing unchanged")
	check(fixture.find_child("TaperedConcreteShaft",true,false) != null, "concrete shaft replaces lattice")
	check(fixture.find_child("DarkReceiver",true,false) != null, "receiver compatibility marker")
	var receiver := fixture.find_child("DarkReceiver",true,false) as MeshInstance3D
	check((receiver.transform * receiver.mesh.get_aabb()).has_point(Vector3(0,2.4,0)), "aim target still inside receiver")
	fixture.free()
	for interior in [false,true]:
		var item = Visual.create("tower_station", {"preview_interior":interior}, true)
		root.add_child(item)
		check(item.get_meta("heliostat_count") == 100, "mirror inventory unchanged")
		check(item.find_children("MirrorSurface*","MeshInstance3D",true,false).size()==100, "tracking surfaces intact")
		check(item.named_ports.is_empty(), "facade has no extra ports")
		check(item.get_meta("capacity_added")==0, "no capacity mutation")
		check(item.find_child("TowerDetail_concrete",true,false)!=null, "new imported tower in both contexts")
		check((item.find_child("ExteriorSite",true,false)==null)==interior,"exterior hide contract")
		item.free()
	print("CSP_TOWER_VISUAL ",checks," checks ",failures," failures")
	quit(1 if failures else 0)
