extends SceneTree
var game
var records:Dictionary={}
func _initialize():call_deferred("run")
func capture(filename:String)->void:
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://"+filename+".png")
func benchmark(enabled:bool)->Dictionary:
	game.weather_effects_enabled=enabled;game.update_status();game.set_simulation_speed(60);game.paused=false
	var samples:Array=[]
	for i in 24:
		var started:=Time.get_ticks_usec();await process_frame
		if i>=4:samples.append((Time.get_ticks_usec()-started)/1000.0)
	game.paused=true;game.update_status();samples.sort()
	return {"enabled":enabled,"frames":samples.size(),"median_ms":samples[samples.size()/2],"p95_ms":samples[int(samples.size()*0.95)],"sim_time_s":game.elapsed_s}
func run():
	root.size=Vector2i(1440,900);game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.storage_example();game.paused=true
	var dock=game.find_child("RightDock",true,false);dock.toggle_panel("weather")
	for scenario in ["clear","overcast","windy"]:
		var config=game.Climate.defaults();config.scenario=scenario;game.apply_climate(config)
		game.elapsed_s=4;game.refresh();await capture("scene_"+scenario)
		records[scenario]={"weather":game.weather_snapshot.duplicate(true),"visual":game.weather_effects.get_display_state()}
	game.elapsed_s=43204;game.refresh();await capture("scene_night")
	records.night={"weather":game.weather_snapshot.duplicate(true),"visual":game.weather_effects.get_display_state()}
	assert(not game.weather_snapshot.is_day,"night classification from sun")
	var before_energy:=JSON.stringify(game.energy);var before_devices:=JSON.stringify(game.devices)
	var visual_before:Dictionary=game.weather_effects.get_display_state();var orb_before:Dictionary=game.weather_orb.get_display_state()
	var rotor=game.nodes["0"].rotor;var rotation_before:Vector3=rotor.rotation
	await create_timer(0.3).timeout
	assert(game.weather_effects.get_display_state()==visual_before and game.weather_orb.get_display_state()==orb_before and rotor.rotation==rotation_before,"pause freezes scene, orb and rotor")
	game.weather_effects_toggle.button_pressed=false;await capture("scene_effects_off")
	assert(not game.weather_effects_enabled,"visible toggle switches off")
	assert(before_energy==JSON.stringify(game.energy) and before_devices==JSON.stringify(game.devices),"effects do not alter model or battery")
	assert(game.write_save("user://climate_restart.json"),"save climate snapshot")
	var expected:=FileAccess.open("user://climate_restart_expected.json",FileAccess.WRITE);expected.store_string(JSON.stringify(game.weather_snapshot));expected.close()
	game.imports=[];game.apply_climate(game.Climate.defaults());game.weather_effects_enabled=false
	records.performance_off=await benchmark(false)
	records.performance_on=await benchmark(true)
	assert(game.speed==60 and game.paused,"60x benchmark finishes paused")
	var f:=FileAccess.open("user://climate_scene_records.json",FileAccess.WRITE);f.store_string(JSON.stringify(records,"  "));f.close()
	print("CLIMATE_SCENE_GUI_PASS ",JSON.stringify({"off":records.performance_off,"on":records.performance_on}));quit()
