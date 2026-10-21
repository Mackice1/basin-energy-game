extends SceneTree
func _initialize():call_deferred("run")
func run():
	var game=load("res://main.tscn").instantiate();root.add_child(game);await process_frame
	var path:="res://evidence/immersive/metric_gui_state.json"
	var expected=JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(expected is Dictionary)
	var error:String=game.validate_state(expected);assert(error=="",error)
	assert(game.read_save(path))
	assert(game.dimension_profile=="metric_v1" and game.devices==expected.devices and game.stations==expected.stations and game.links==expected.links)
	assert(game.energy==expected.energy and game.thermal_energy==expected.thermal_energy)
	assert(game.paused and game.speed==1 and game.device(4).state.energy_mwhth>0)
	game.open_station(int(game.stations[0].id));assert(game.station_interior.visible)
	assert(root.disable_3d)
	game.station_interior.close_station();assert(not root.disable_3d)
	var before:=JSON.stringify(game.state())
	var service=game.optimization_controller
	var snapshot:Dictionary=service.snapshot({"horizon_hours":1.0,"step_minutes":30.0,"load_multiplier":1.0,"strict_supply":false,"timeout_s":20})
	assert(not snapshot.has("error"))
	assert(snapshot.devices.size()==8 and snapshot.links.size()==8)
	assert(snapshot.devices.all(func(d):return d.kind!="thermal_station"))
	var input:=FileAccess.open("user://metric_solver_input.json",FileAccess.WRITE);input.store_string(JSON.stringify(snapshot));input.close()
	var output:Array=[]
	var code:=OS.execute("python3",PackedStringArray([ProjectSettings.globalize_path("res://tools/dispatch_solver.py"),"--input",ProjectSettings.globalize_path("user://metric_solver_input.json"),"--output",ProjectSettings.globalize_path("user://metric_solver_output.json"),"--glpsol",(OS.get_environment("BASIN_GLPK") if not OS.get_environment("BASIN_GLPK").is_empty() else "glpsol")]),output,true)
	assert(code==0,str(output))
	var solved=JSON.parse_string(FileAccess.get_file_as_string("user://metric_solver_output.json"))
	assert(solved.get("validation",{}).get("valid",false),str(solved))
	assert(JSON.stringify(game.state())==before,"analysis cannot mutate real inventory/time/layout")
	print("METRIC_GLPK_PASS audit=true devices=8 links=8 intervals=2 world_unchanged=true")
	print("IMMERSIVE_RESTART_PASS schema=7 profile=metric_v1 devices=8 links=8 stocks_unchanged=true");quit()
