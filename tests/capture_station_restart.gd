extends SceneTree
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1440,900)
	var game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	var expected=JSON.parse_string(FileAccess.get_file_as_string("user://station_gui_record.json"))
	assert(game.read_save("user://station_restart.json"))
	assert(game.stations==expected.stations and game.devices==expected.devices and game.links==expected.links)
	assert(game.energy==expected.energy and game.thermal_energy==expected.thermal_energy)
	assert(game.paused and game.speed==1 and game.device(4).state.energy_mwhth>0)
	game.open_station(int(game.stations[0].id));assert(game.station_interior.visible)
	game.station_interior._select(4);game.station_interior.camera.size=48.0
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://station_restarted.png")
	print("STATION_RESTART_GUI_PASS parents=",game.stations.size()," stock=",game.device(4).state.energy_mwhth);quit()
