extends SceneTree
var game
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1440,900)
	game=load("res://main.tscn").instantiate();root.add_child(game)
	await process_frame
	game.storage_example()
	game.select_device(2);game.link_to(-1)
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://v13_map.png")
	var dock=game.find_child("RightDock",true,false)
	dock.toggle_panel("energy");game.set_simulation_speed(5)
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://v13_energy_speed.png")
	dock.close_panels()
	var service=game.optimization_controller
	service.solver_executable="/workspace/shared/glpk/bin/glpsol"
	service.open()
	service.panel.configure({"horizon_hours":24,"step_minutes":60,"terminal_soc_fraction":0.5,"load_multiplier":1.5,"strict_supply":false,"timeout_s":30})
	service.start(service.panel.get_options())
	var deadline=Time.get_ticks_msec()+45000
	while service.pid>0 and Time.get_ticks_msec()<deadline:await create_timer(0.05).timeout
	if service.last_result.is_empty():print("CAPTURE_FAILED: ",FileAccess.get_file_as_string(service.output_path));quit(1);return
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	service.panel.get_texture().get_image().save_png("user://v13_optimization_chart.png")
	service.panel._tabs.current_tab=1
	await process_frame;await RenderingServer.frame_post_draw
	service.panel.get_texture().get_image().save_png("user://v13_optimization_comparison.png")
	service.panel._tabs.current_tab=2;service.panel._select_step(12)
	await process_frame;await RenderingServer.frame_post_draw
	service.panel.get_texture().get_image().save_png("user://v13_optimization_detail.png")
	print("CAPTURE_OK status=",service.last_result.status," output=",service.output_path)
	quit()
