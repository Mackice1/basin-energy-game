extends SceneTree
var game
var records:Dictionary={}
func _initialize():call_deferred("run")
func capture(name:String):
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://"+name+".png")
func run():
	root.size=Vector2i(1440,900);game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.thermal_example();game.paused=true;assert(game.advance(600));game.refresh()
	var sid:int=game.stations[0].id
	assert(game.station_nodes[str(sid)].get_meta("visual_backend","")=="blender_glb")
	game.distance=100;game.target=Vector3(game.stations[0].x-8,0,game.stations[0].z);game.update_camera()
	await capture("immersive_base")
	game.open_station(sid);game.station_interior._select(4)
	for id in [3,4,5]:assert(game.station_interior.equipment_nodes[id].get_meta("visual_backend")=="blender_glb")
	var frozen:=JSON.stringify(game.state())
	for shot in [["immersive_front",135.0,26.0,4.2],["immersive_reverse",-35.0,24.0,3.9],["immersive_elevated",45.0,42.0,4.6]]:
		game.station_interior.set_camera_view(shot[1],shot[2],shot[3]);await capture(shot[0])
		assert(JSON.stringify(game.state())==frozen,"view changes never change energy or saved layout")
		var samples:Array=[]
		for i in 8:
			var start:=Time.get_ticks_usec();await process_frame;samples.append((Time.get_ticks_usec()-start)/1000.0)
		samples.sort();records[shot[0]]={"median_frame_ms":samples[4],"camera":game.station_interior.camera.global_transform}
	game.station_interior.close_station();assert(game.paused and game.selected_id==sid)
	assert(game.write_save("user://immersive_station_restart.json"))
	var f:=FileAccess.open("user://immersive_station_records.json",FileAccess.WRITE);f.store_string(JSON.stringify(records,"  "));f.close()
	print("IMMERSIVE_STATION_GUI_PASS glb=4 views=3 visual_state_unchanged=true ",JSON.stringify(records));quit()
