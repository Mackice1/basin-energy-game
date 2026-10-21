extends SceneTree
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1440,900);var game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.storage_example();game.paused=true
	DirAccess.make_dir_recursive_absolute("user://weather_animation")
	var index:=0
	for item in [{"name":"clear","scenario":"clear","t":2.0},{"name":"cloud","scenario":"partly_cloudy","t":2.0},{"name":"night","scenario":"clear","t":43202.0},{"name":"wind","scenario":"windy","t":2.0},{"name":"rain","scenario":"overcast","t":2.0}]:
		game.imports=[];var config=game.Climate.defaults();config.scenario=item.scenario;game.apply_climate(config)
		if item.name=="rain":
			var rain:Dictionary=game.Series.parse("t,v\n0,5\n60,5\n",{"field":"precipitation_mm_h","value_unit":"mm/h","time_unit":"s","time_column":"t","value_column":"v","target_device":""});game.apply_import(rain.series)
		for frame in 12:
			game.elapsed_s=float(item.t)+frame*0.25;game.refresh()
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().get_region(Rect2i(645,8,150,106)).save_png("user://weather_animation/frame_%03d_%s.png"%[index,item.name]);index+=1
	print("WEATHER_ANIMATION_CAPTURE_PASS frames=",index," simulation_step=0.25");quit()
