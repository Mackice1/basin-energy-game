extends SceneTree
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1440,900)
	var game=load("res://main.tscn").instantiate();root.add_child(game)
	await process_frame
	game.storage_example()
	assert(not game.tool_buttons.has("load") and game.tool_buttons.size()==5)
	var dock=game.find_child("RightDock",true,false)
	dock.toggle_panel("demand")
	game.select_device(3)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://v13_demand_entry.png")
	game.edit_selected_demand()
	assert(game.parameter_kind()=="load" and game.param_dialog.visible)
	game.param_dialog.hide()
	game.start_demand_node()
	assert(game.build_kind=="load" and game.mode=="build")
	game.set_mode("select")
	assert(game.devices.size()==5 and game.result.demand_mw==2.0)
	print("DEMAND_GUI_PASS toolbar=5 demand_nodes=1 demand_mw=",game.result.demand_mw)
	quit()
