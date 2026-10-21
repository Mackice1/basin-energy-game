extends SceneTree
var game
func _initialize():call_deferred("run")
func capture(name:String):
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://"+name+".png")
func run():
	root.size=Vector2i(1440,900);game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.thermal_example();game.paused=true
	assert(game.devices.size()==8 and game.stations.size()==1 and game.links.size()==8)
	assert(game.tool_buttons.size()==5 and game.tool_buttons.has("thermal_station") and not game.tool_buttons.has("electric_boiler"))
	assert(game.nodes.size()==5 and game.station_nodes.size()==1)
	assert(game.advance(600.0));game.refresh();assert(game.result.valid)
	var sid:int=game.stations[0].id
	game.select_device(sid);game.find_child("RightDock",true,false).toggle_panel("energy")
	await process_frame;game.device_summary.get_parent().get_parent().ensure_control_visible(game.device_summary)
	await capture("station_base")
	game.find_child("RightDock",true,false).close_panels()
	var site:Vector3=game.station_nodes[str(sid)].global_position+Vector3(0,3,0)
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=game.camera.unproject_position(site)
	game._unhandled_input(click)
	assert(game.station_interior.visible,"clicking whole facility opens internal scene")
	await create_timer(0.3).timeout
	game.station_interior._select(4);game.station_interior.camera.size=48.0
	await capture("station_interior")
	var before:float=game.elapsed_s
	game.set_simulation_speed(5);game.paused=false;await create_timer(0.6).timeout;game.paused=true
	assert(game.elapsed_s>before,"single world clock continues inside")
	var frozen:float=game.elapsed_s;var stock:float=game.device(4).state.energy_mwhth
	await create_timer(0.3).timeout;assert(game.elapsed_s==frozen and game.device(4).state.energy_mwhth==stock)
	game.station_interior.close_station();assert(not game.station_interior.visible)
	assert(game.write_save("user://station_restart.json"))
	var f:=FileAccess.open("user://station_gui_record.json",FileAccess.WRITE);f.store_string(JSON.stringify(game.state(),"  "));f.close()
	print("STATION_WORLD_GUI_PASS base=1 internal=3 clock=",game.elapsed_s," stock=",stock);quit()
