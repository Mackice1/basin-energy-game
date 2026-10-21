extends SceneTree
var game
func _initialize():call_deferred("run")
func capture(name:String):
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://"+name+".png")
func run():
	root.size=Vector2i(1440,900);game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.thermal_example();game.paused=true
	assert(game.devices.size()==8 and game.links.size()==8)
	assert(game.tool_buttons.size()==5 and not game.tool_buttons.has("load") and not game.tool_buttons.has("heat_demand"))
	assert(game.result.valid,JSON.stringify(game.result))
	await capture("thermal_chain_map")
	game.advance(3600.0);game.refresh();assert(game.result.valid)
	var dock=game.find_child("RightDock",true,false);dock.toggle_panel("energy")
	for id in [3,4,5,6]:
		game.select_device(id);await process_frame
		game.thermal_detail.get_parent().get_parent().ensure_control_visible(game.thermal_detail)
		await capture("thermal_device_"+str(id))
	assert(game.write_save("user://thermal_restart.json"))
	var f:=FileAccess.open("user://thermal_gui_record.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"devices":game.devices,"result":game.result,"energy":game.energy,"thermal_energy":game.thermal_energy},"  "));f.close()
	print("THERMAL_WORLD_GUI_PASS devices=8 lines=8 build_buttons=5 state=",JSON.stringify(game.device(4).state));quit()
