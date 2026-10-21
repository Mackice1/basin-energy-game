extends SceneTree
class Fixture:
	extends "res://scripts/world_game.gd"
	func _ready():pass
	func update_status():pass
	func tell(_message:String):pass
	func rebuild_equipment():pass
	func set_mode(value:String):mode=value
	func height_at(_x:float,_z:float)->float:return 0.0
	func exclusion(_x:float,_z:float)->String:return ""
	func slope_at(_x:float,_z:float)->float:return 0.0
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,what:String)->void:
	checks+=1
	if not ok:failures.append(what);print("FAIL ",what)
func series(field:String,unit:String,values:String,target:String="",time_unit:String="s")->Dictionary:
	var parsed:Dictionary=preload("res://scripts/series_import.gd").parse("t,v\n"+values,{"field":field,"value_unit":unit,"time_unit":time_unit,"time_column":"t","value_column":"v","target_device":target})
	check(parsed.ok,"parse "+field)
	return parsed.series
func _initialize():call_deferred("run")
func run():
	var game:=Fixture.new();root.add_child(game);game.booted=true;game.cfg={"max_build_slope_degrees":8.0}
	for kind in game.KINDS:game.templates[kind]=game.model.defaults(kind)
	game.devices=[{"id":0,"kind":"pv","x":-30.0,"z":0.0,"params":game.model.defaults("pv")},{"id":1,"kind":"station","x":0.0,"z":0.0,"params":game.model.defaults("station")},{"id":2,"kind":"load","x":20.0,"z":0.0,"params":game.model.defaults("load")},{"id":3,"kind":"battery","x":40.0,"z":0.0,"params":game.model.defaults("battery"),"state":{"energy_mwh":5.0}}]
	game.links=[{"from":0,"to":1,"capacity_mw":8.0,"loss_fraction":0.01},{"from":1,"to":2,"capacity_mw":8.0,"loss_fraction":0.01},{"from":3,"to":1,"capacity_mw":3.0,"loss_fraction":0.01}];game.next_id=4
	var noon:Dictionary=game.sampled(0).weather
	check(noon.is_day and noon.solar_altitude_deg>0,"calendar noon is day")
	var night:Dictionary=game.sampled(43200).weather
	check(not night.is_day and night.irradiance_wm2==0,"night from solar geometry")
	var cloudy:=game.climate_config.duplicate(true);cloudy.scenario="overcast";game.apply_climate(cloudy)
	check(game.sampled(0).weather.cloud_cover>0.8,"teaching clouds explicit")
	var saved:=game.state();check(game.validate_state(saved)=="","new climate save valid")
	game.restore(saved);check(game.climate_config==cloudy and game.paused and game.speed==1,"save restores climate, paused 1x")
	var legacy:=saved.duplicate(true);legacy.erase("climate_config");legacy.erase("weather_effects_enabled");game.restore(legacy)
	check(game.climate_config==game.Climate.defaults(),"legacy save receives documented defaults")
	var bad:=game.state();bad.climate_config.latitude_deg=91;check(game.validate_state(bad)!="","invalid stored geography rejected")
	game.apply_import(series("irradiance_wm2","W/m2","0,0\n100000,0\n"))
	var dark_day:Dictionary=game.sampled(0).weather
	check(dark_day.is_day and dark_day.irradiance_wm2==0,"zero imported irradiance is still astronomical daytime")
	check(not dark_day.has("cloud_cover") and not dark_day.has("precipitation_mm_h"),"missing imported cloud rain unknown")
	game.apply_import(series("cloud_cover","%","0,65\n100000,65\n"))
	check(is_equal_approx(game.sampled(0).weather.cloud_cover,0.65),"explicit cloud import in snapshot")
	game.apply_import(series("precipitation_mm_h","mm/h","0,2\n100000,2\n"))
	check(game.sampled(0).weather.precipitation_mm_h==2,"explicit rain import in snapshot")
	game.apply_import(series("power","MW","0,1.25\n100000,1.25\n","0"))
	var dat:Dictionary=game.dispatch_inputs(0)
	check(dat.direct["0"].mw==1.25,"direct power overrides zero weather irradiance")
	var service=load("res://scripts/optimization_controller.gd").new();root.add_child(service);service.setup(game)
	var original:=JSON.stringify(game.state());var before_weather:Dictionary=game.sampled(0).weather
	var forecast:Dictionary=service.snapshot({"horizon_hours":1.0,"step_minutes":15.0,"load_multiplier":1.0})
	check(not forecast.has("error"),"forecast valid")
	for row in forecast.steps:check(is_equal_approx(row.available_mw["0"],minf(game.dispatch_inputs(row.time_s).direct["0"].mw,game.devices[0].params.inverter_capacity_mw)),"GLPK and live identical direct source")
	check(JSON.stringify(game.state())==original and game.sampled(0).weather==before_weather,"forecast never shifts live weather or save")
	game.imports=[];game.elapsed_s=0;game.energy=game.ENERGY_ZERO.duplicate(true)
	forecast=service.snapshot({"horizon_hours":24.0,"step_minutes":60.0,"load_multiplier":1.0})
	for row in forecast.steps:
		var w:Dictionary=game.sampled(row.time_s).weather
		var generated:Dictionary=game.model.generation("pv",game.devices[0].params,w)
		check(is_equal_approx(row.available_mw["0"],generated.mw),"GLPK/live teaching solar same sample")
	game.imports=[];game.apply_import(series("cloud_cover","0..1","0,1\n1000,1\n"))
	check(game.sampled(0).weather.irradiance_wm2<100 and game.sampled(0).weather.is_day,"explicit cloud influences fallback teaching POA without making night")
	game.imports=[]
	var iso:=series("temp_c","C","2026-12-21T00:00:00Z,10\n2026-12-22T00:00:00Z,12\n","","iso_utc")
	game.apply_import(iso)
	check(game.climate_config.start_local=="2026-12-21T08:00:00","ISO UTC aligns calendar local t0")
	check(game.sampled(0).weather.utc_datetime.begins_with("2026-12-21T00:00:00"),"ISO sampled UTC is real input origin")
	var wrong_iso:=series("wind_ms","m/s","2026-12-20T00:00:00Z,6\n2026-12-22T00:00:00Z,8\n","","iso_utc")
	original=JSON.stringify(game.state());game.apply_import(wrong_iso)
	check(JSON.stringify(game.state())==original,"mismatched UTC origins rejected atomically")
	game.imports=[];game.apply_import(series("temp_c","C","0,10\n0.25,20\n0.75,30\n2,30\n"))
	forecast=service.snapshot({"horizon_hours":2.0/3600.0,"step_minutes":5.0,"load_multiplier":1.0})
	check(not forecast.has("error") and forecast.steps.size()==3,"GLPK splits all fractional CSV boundaries")
	check(is_equal_approx(forecast.steps[0].dt_h*3600.0,0.25) and is_equal_approx(forecast.steps[1].dt_h*3600.0,0.5),"GLPK CSV interval lengths exact")
	game.advance(0.25);check(game.elapsed_s==0.25 and game.sampled(game.elapsed_s).weather.air_temp_c==20,"fractional CSV boundary exact")
	game.advance(5);check(game.paused and game.elapsed_s==2,"range endpoint stops; no extrapolation")
	service.queue_free();cleanup(game);await process_frame
	print("CLIMATE_INTEGRATION checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)

func cleanup(controller):
	for key in ["camera","lod_camera","terrain","labels","infrastructure","selection","overlay","equipment","cables","confirmation","param_dialog","param_errors","param_target","data_dialog","data_list","line_dialog","line_capacity","line_loss","line_choice"]:
		var node=controller.get(key)
		if is_instance_valid(node) and node.get_parent()==null:node.free()
	controller.free()
