extends SceneTree
class Fixture:
	extends "res://scripts/world_game.gd"
	func _ready(): pass
	func update_status(): pass
	func tell(_message:String): pass
	func rebuild_equipment(): pass
	func set_mode(value:String): mode=value
	func height_at(_x:float,_z:float)->float:return 0.0
	func exclusion(_x:float,_z:float)->String:return ""
	func slope_at(_x:float,_z:float)->float:return 0.0
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,what:String):
	checks+=1
	if not ok:failures.append(what);print("FAIL ",what)
func fixture():
	var game:=Fixture.new()
	game.booted=true;game.cfg={"max_build_slope_degrees":8.0}
	for kind in game.KINDS:game.templates[kind]=game.model.defaults(kind)
	game.devices=[{"id":0,"kind":"pv","x":-30.0,"z":0.0,"params":{"dc_capacity_mw":8.0,"inverter_capacity_mw":8.0}},
	{"id":1,"kind":"station","x":0.0,"z":0.0,"params":{"capacity_mw":10.0,"loss_fraction":0.01}},
	{"id":2,"kind":"load","x":20.0,"z":0.0,"params":{"demand_mw":2.0,"priority":10}},
	{"id":3,"kind":"battery","x":40.0,"z":0.0,"params":game.model.defaults("battery"),"state":{"energy_mwh":5.0}}]
	game.links=[{"from":0,"to":1,"capacity_mw":8.0,"loss_fraction":0.01},{"from":1,"to":2,"capacity_mw":8.0,"loss_fraction":0.01},{"from":3,"to":1,"capacity_mw":3.0,"loss_fraction":0.01},{"from":1,"to":-1,"capacity_mw":4.0,"loss_fraction":0.01}]
	game.next_id=4
	return game
func _initialize():call_deferred("run")
func run():
	var game=fixture();root.add_child(game)
	var service=load("res://scripts/optimization_controller.gd").new();root.add_child(service);service.setup(game)
	service.solver_executable=(OS.get_environment("BASIN_GLPK") if not OS.get_environment("BASIN_GLPK").is_empty() else "glpsol")
	var options={"horizon_hours":6.0,"step_minutes":60.0,"load_multiplier":1.0,"strict_supply":false,"terminal_soc_fraction":0.5,"timeout_s":20}
	var before:String=JSON.stringify(game.state())
	service.request_id="test"
	var snapshot:Dictionary=service.snapshot(options)
	check(not snapshot.has("error") and snapshot.steps.size()==6,"fixed forecast snapshot")
	check(snapshot.devices.size()==4,"no device expansion")
	check(snapshot.forecast.capacity_expansion==false,"no expansion metadata")
	var base:Dictionary=service.make_baseline(snapshot)
	check(base.steps.size()==6,"baseline same steps")
	check(JSON.stringify(game.state())==before,"snapshot and baseline do not mutate live scene")
	var invalid:Dictionary=options.duplicate();invalid.horizon_hours=169
	check(service.snapshot(invalid).has("error"),"horizon upper bound")
	invalid=options.duplicate();invalid.step_minutes=0
	check(service.snapshot(invalid).has("error"),"zero step rejected")
	check(game.set_simulation_speed(1) and game.set_simulation_speed(5) and game.set_simulation_speed(10) and game.set_simulation_speed(60),"range includes standard rates")
	check(not game.set_simulation_speed(0) and not game.set_simulation_speed(100),"unsupported speed rejected")
	check(not game.set_simulation_speed(1.25) and game.set_simulation_speed(7) and game.speed_text()=="7","integer rate only and readable value")
	check(not game.set_simulation_speed(NAN) and not game.set_simulation_speed(INF) and not game.set_simulation_speed(0.99),"nonfinite and below range rejected")
	game.elapsed_s=3661.5;check(game.simulation_clock()=="01:01:01","readable clock");game.elapsed_s=0
	# All rates advance the same 60 simulated seconds; same dispatch clock and SOC.
	var energies:Array=[]
	for rate in [1.0,5.0,10.0,60.0]:
		var g=fixture();g.set_simulation_speed(rate)
		for i in int(60/rate):check(g.advance(rate),"advance at selected speed")
		energies.append(g.devices[3].state.energy_mwh)
		check(absf(g.elapsed_s-60)<1e-8,"single elapsed clock")
		cleanup(g)
	for e in energies:check(absf(e-energies[0])<1e-9,"rate independent SOC")
	var imported:Dictionary=game.Series.parse("time,value\n0,0\n10.2,8\n11.3,0\n60,0\n",{"time_column":"time","value_column":"value","field":"power","value_unit":"MW","time_unit":"s","target_device":"0"})
	check(imported.ok,"CSV speed boundary fixture")
	for rate in [1.0,2.0,3.0,7.0,10.0,59.0,60.0]:
		var g=fixture();g.imports=[imported.series];g.set_simulation_speed(rate)
		while g.elapsed_s<60:g.advance(minf(rate,60.0-g.elapsed_s))
		check(absf(float(g.energy.generated)-8.0*1.1/3600.0)<1e-10,"accelerated CSV fractional boundaries preserved")
		check(not g.advance(1) and g.elapsed_s==60 and g.paused,"CSV endpoint pauses without extrapolation")
		var saved:Dictionary=g.state();g.speed=60;g.restore(saved)
		check(g.paused and g.speed==1 and g.elapsed_s==60,"restore pauses resets speed and retains clock")
		cleanup(g)
	game.set_simulation_speed(1)
	service.start(options)
	check(service.pid>0,"async process launched")
	var heartbeat:=0
	var deadline:=Time.get_ticks_msec()+30000
	while service.pid>0 and Time.get_ticks_msec()<deadline:
		heartbeat+=1;await create_timer(0.02).timeout
	check(heartbeat>0,"UI event loop remains responsive")
	check(service.pid<0,"solver terminated")
	check(service.last_result.get("status","")=="optimal","real GLPK optimal result")
	check(service.last_result.get("validation",{}).get("valid",false),"independent validator passed")
	check(JSON.stringify(game.state())==before,"optimization never changes actual state")
	if not service.last_result.is_empty():
		var f:=FileAccess.open("user://v13_actual_result.json",FileAccess.WRITE);f.store_string(JSON.stringify(service.last_result,"  "));f.close()
	game.scene_revision+=1;await create_timer(0.05).timeout
	check(service.last_result.is_empty(),"changed scene invalidates result")
	service.start(options);service.cancel()
	deadline=Time.get_ticks_msec()+5000
	while service.pid>0 and Time.get_ticks_msec()<deadline:await create_timer(0.02).timeout
	check(service.pid<0 and service.last_result.is_empty(),"cancel cannot surface old result")
	service.solver_executable="/missing/glpsol";service.start(options)
	deadline=Time.get_ticks_msec()+5000
	while service.pid>0 and Time.get_ticks_msec()<deadline:await create_timer(0.02).timeout
	check(service.pid<0 and service.last_result.is_empty(),"missing solver fails safely")
	service.queue_free();cleanup(game);await process_frame
	print("OPTIMIZATION_CONTROLLER checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func cleanup(controller):
	for key in ["camera","lod_camera","terrain","labels","infrastructure","selection","overlay","equipment","cables","confirmation","param_dialog","param_errors","param_target","data_dialog","data_list","line_dialog","line_capacity","line_loss","line_choice"]:
		var node=controller.get(key)
		if is_instance_valid(node) and node.get_parent()==null:node.free()
	controller.free()
