extends SceneTree
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1440,900);var game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	assert(game.read_save("user://climate_restart.json"),"restart reads saved climate scene")
	var expected=JSON.parse_string(FileAccess.get_file_as_string("user://climate_restart_expected.json"))
	for key in expected:
		var actual=game.weather_snapshot.get(key)
		if (expected[key] is float or expected[key] is int) and (actual is float or actual is int):
			assert(absf(float(actual)-float(expected[key]))<0.000001,"restart numeric value "+key)
		else:assert(actual==expected[key],"restart exact state "+key)
	assert(game.paused and game.speed==1 and not game.weather_effects_enabled,"restart preserves effects preference and resets paused 1x")
	var dock=game.find_child("RightDock",true,false);dock.toggle_panel("location")
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://scene_restart.png")
	print("CLIMATE_RESTART_GUI_PASS");quit()
