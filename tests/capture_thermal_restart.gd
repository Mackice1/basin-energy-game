extends SceneTree
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1440,900)
	var game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	assert(game.read_save("user://thermal_restart.json"))
	assert(game.paused and game.speed==1 and game.device(4).state.energy_mwhth>0.7)
	var record=JSON.parse_string(FileAccess.get_file_as_string("user://thermal_gui_record.json"))
	assert(is_equal_approx(float(game.device(4).state.energy_mwhth),float(record.devices[4].state.energy_mwhth)))
	assert(game.energy==record.energy and game.thermal_energy==record.thermal_energy)
	assert(game.advance(60.0) and game.result.valid)
	assert(game.device(4).state.energy_mwhth>float(record.devices[4].state.energy_mwhth))
	game.select_device(4);game.find_child("RightDock",true,false).toggle_panel("energy");await process_frame
	game.thermal_detail.get_parent().get_parent().ensure_control_visible(game.thermal_detail)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://thermal_restarted.png")
	print("THERMAL_RESTART_GUI_PASS stored=",game.device(4).state.energy_mwhth);quit()
