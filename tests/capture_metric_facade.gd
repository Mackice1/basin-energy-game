extends SceneTree
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1440,900)
	var game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	assert(game.read_save("res://evidence/immersive/metric_gui_state.json"))
	game.selected_id=int(game.stations[0].id);game.refresh()
	var station:Dictionary=game.stations[0]
	game.camera.projection=Camera3D.PROJECTION_PERSPECTIVE;game.distance=8;game.yaw=-0.65;game.pitch=0.55
	game.target=Vector3(station.x,game.height_at(station.x,station.z)+0.3,station.z);game.update_camera()
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://immersive_facade_close.png")
	game.yaw=2.4;game.pitch=0.65;game.update_camera()
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://immersive_facade_reverse.png")
	print("METRIC_FACADE_GUI_PASS views=2");quit()
