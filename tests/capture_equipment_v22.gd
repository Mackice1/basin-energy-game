extends SceneTree
const Interior = preload("res://scripts/station_interior.gd")
const TestHost = preload("res://tests/test_station_interior.gd")
func _initialize(): call_deferred("run")
func run():
	root.size = Vector2i(1500,1000)
	root.gui_embed_subwindows = true
	var host = TestHost.Host.new()
	host.dimension_profile = "metric_v1"
	root.add_child(host)
	host.add_internal_device(0,"electric_boiler",Vector2(-1.35,0))
	host.add_internal_device(0,"thermal_store",Vector2(0,.2))
	host.add_internal_device(0,"heat_exchanger",Vector2(1.35,0))
	host.connect_internal_devices(0,1)
	host.connect_internal_devices(1,2)
	var interior = Interior.new()
	host.add_child(interior)
	interior.setup(host)
	interior.open_station(0)
	await process_frame
	interior.camera_target=Vector3(0,.25,-.1)
	interior.set_camera_view(-.38,.55,4.3)
	for visual in interior.equipment_nodes.values(): visual.set_annotation_visibility(false)
	for label in interior.name_labels.values(): label.visible=false
	for node in interior.connections_root.find_children("*","Label3D",true,false):node.visible=false
	var snapshot := Node3D.new()
	root.add_child(snapshot)
	for child in [interior.equipment_root,interior.connections_root]:
		snapshot.add_child(child.duplicate())
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	var result := document.append_from_scene(snapshot,state)
	assert(result == OK)
	assert(document.write_to_filesystem(state,"res://evidence/equipment_v22/station_piping.glb") == OK)
	print("CAPTURE_EQUIPMENT_V22_DONE runtime GLB snapshot")
	quit()
