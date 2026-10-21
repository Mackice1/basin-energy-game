extends SceneTree
func _initialize():call_deferred("run")
func run():
	root.size=Vector2i(1440,900)
	var game=load("res://main.tscn").instantiate();root.add_child(game)
	await process_frame
	game.storage_example()
	var dock=game.find_child("RightDock",true,false)
	dock.toggle_panel("energy")
	game.speed_control._slider.value=7
	assert(game.speed==7 and game.speed_control._input.text=="7","drag synchronizes numeric input and simulation rate")
	game.speed_control._input.text="23";game.speed_control._input.text_submitted.emit("23")
	assert(game.speed==23 and game.speed_control._slider.value==23,"numeric edit synchronizes slider")
	game.speed_control._input.text="3.5";game.speed_control._input.text_submitted.emit("3.5")
	assert(game.speed==23 and game.speed_control._input.text=="23","fractional input rejected")
	assert(game.paused,"editing speed does not start simulation")
	game.speed_control._slider.value=7
	game.toggle_run()
	await create_timer(1.0).timeout
	game.toggle_run()
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://v13_slider_weather.png")
	var f:=FileAccess.open("user://v13_weather_tooltip.txt",FileAccess.WRITE);f.store_string(game.weather_orb.tooltip_text);f.close()
	var imported:Dictionary=game.Series.parse("time,value\n0,21.5\n1200,21.5\n",{"time_column":"time","value_column":"value","field":"temp_c","value_unit":"C","time_unit":"s","target_device":""})
	assert(imported.ok)
	game.apply_import(imported.series)
	assert(game.weather_orb.tooltip_text.contains("21.5") and game.weather_orb.tooltip_text.contains("CSV"),"weather orb follows imported temperature and source")
	assert(game.paused,"weather import remains paused")
	print("WEATHER_CSV_INTEGRATION_PASS ",game.weather_orb.tooltip_text)
	print("SPEED_WEATHER_GUI speed=",game.speed," paused=",game.paused," time=",game.elapsed_s," sources=",game.last_weather)
	quit()
