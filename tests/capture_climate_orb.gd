extends SceneTree
var game
var records:Array=[]
func _initialize():call_deferred("run")
func snap(file:String)->Image:
	await process_frame;await RenderingServer.frame_post_draw
	var picture:=root.get_texture().get_image();picture.save_png("user://"+file+".png")
	var crop:=picture.get_region(Rect2i(650,10,140,105));crop.save_png("user://"+file+"_orb.png")
	return crop
func run():
	root.size=Vector2i(1440,900);game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	game.storage_example();game.paused=true
	var dock=game.find_child("RightDock",true,false);dock.toggle_panel("location")
	for scenario in ["clear","partly_cloudy","overcast","windy"]:
		var config=game.Climate.defaults();config.scenario=scenario;game.apply_climate(config)
		game.elapsed_s=2;game.refresh();var a:Image=await snap("climate_"+scenario+"_a")
		game.elapsed_s=3.2;game.refresh();var b:Image=await snap("climate_"+scenario+"_b")
		assert(a.get_data()!=b.get_data(),scenario+" internal icon animates")
		var state:Dictionary=game.weather_orb.get_display_state();records.append({"scenario":scenario,"state":state,"weather":game.weather_snapshot})
		var paused:Image=await snap("climate_"+scenario+"_paused")
		assert(b.get_data()==paused.get_data(),scenario+" pauses exactly")
	game.elapsed_s=43203;game.refresh();var night_a:Image=await snap("climate_night_a")
	game.elapsed_s=43204.2;game.refresh();var night_b:Image=await snap("climate_night_b")
	assert(not game.weather_snapshot.is_day and night_a.get_data()!=night_b.get_data(),"night based on solar height and animates")
	game.elapsed_s=0
	var rain:Dictionary=game.Series.parse("t,v\n0,3\n100,3\n",{"field":"precipitation_mm_h","value_unit":"mm/h","time_unit":"s","time_column":"t","value_column":"v","target_device":""})
	game.apply_import(rain.series);game.elapsed_s=2;game.refresh();var rain_a:Image=await snap("climate_rain_a")
	game.elapsed_s=2.7;game.refresh();var rain_b:Image=await snap("climate_rain_b")
	assert(rain_a.get_data()!=rain_b.get_data(),"only explicit imported rain animates raindrops")
	assert(game.weather_snapshot.precipitation_mm_h==3,"render rain matches actual snapshot")
	game.imports=[];game.apply_climate(game.Climate.defaults())
	var radiation:Dictionary=game.Series.parse("t,v\n0,0\n100,0\n",{"field":"irradiance_wm2","value_unit":"W/m2","time_unit":"s","time_column":"t","value_column":"v","target_device":""})
	game.apply_import(radiation.series);game.elapsed_s=2;game.refresh();var resource_a:Image=await snap("climate_unknown_a")
	game.elapsed_s=3;game.refresh();var resource_b:Image=await snap("climate_unknown_b")
	assert(game.weather_snapshot.is_day and not game.weather_snapshot.has("cloud_cover"),"low irradiance no fake night/cloud")
	assert(resource_a.get_data()!=resource_b.get_data(),"unknown resource has internal animation")
	var before:=JSON.stringify(game.state());var orb_before:Dictionary=game.weather_orb.get_display_state()
	game.optimization_controller.snapshot({"horizon_hours":0.01,"step_minutes":5.0})
	assert(before==JSON.stringify(game.state()) and orb_before==game.weather_orb.get_display_state(),"analysis isolated from visible live weather")
	var f:=FileAccess.open("user://climate_orb_records.json",FileAccess.WRITE);f.store_string(JSON.stringify(records,"  "));f.close()
	print("CLIMATE_ORB_GUI_PASS 4 teaching states + solar night + imported rain + unknown; actual successive pixels differ, paused pixels identical")
	quit()
