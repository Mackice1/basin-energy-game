extends SceneTree
## End-to-end first-level placement -> AC wiring -> timed state -> save roundtrip.
## No scene boot, GUI, terrain, user slot access, or baseline writes.
const Catalog = preload("res://scripts/device_catalog.gd")
class Fixture:
	extends "res://scripts/world_game.gd"
	var last_notice := ""
	func _ready(): pass
	func tell(message:String): last_notice=message
	func exclusion(_x:float,_z:float)->String:return ""
	func slope_at(_x:float,_z:float)->float:return 0.0
	func height_at(_x:float,_z:float)->float:return 0.0
	func rebuild_equipment():pass
	func rebuild_cables():pass
	func update_status():pass
	func set_mode(value:String):mode=value;pending_link=-2
	func select_device(id:int):selected_id=id
	func weather_at(_t:float)->Dictionary:return {"wind_speed_mps":12.0,"irradiance_wm2":1000.0,"air_temp_c":25.0}
var checks := 0
var failures:Array[String]=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func fixture()->Fixture:
	var game:=Fixture.new()
	game.cfg={"max_build_slope_degrees":8.0};game.booted=true;game.dimension_profile="metric_v1"
	for kind in game.KINDS:game.templates[kind]=game.model.defaults(kind)
	return game
func run():
	var game:=fixture()
	for spec in [["pv",Vector2(-40,0)],["station",Vector2.ZERO],["load",Vector2(40,0)],["caes_aboveground",Vector2(0,40)]]:
		check(game.add_equipment(spec[0],spec[1]),"place chart fixture")
	check(game.devices.all(func(item):return item.get("site_geometry_profile","")=="reference_size_v1"),"normal new construction has reference geometry markers")
	# The historical 12/10 MW test source exceeds today's finite PV installation.
	# Use a separate unmarked legacy-data fixture, never an invalid new reference
	# device, so the real solver can still exercise constrained nonzero dispatch.
	var historical_devices: Array = game.devices.duplicate(true)
	for item in historical_devices: item.erase("site_geometry_profile")
	cleanup(game)
	game=fixture();game.devices=historical_devices;game.next_id=4
	check(not game.is_reference_layout() and game.layout_mode_error().is_empty(),"historical high-power fixture is explicitly unmarked and not mixed")
	game.devices[0].params={"dc_capacity_mw":12.0,"inverter_capacity_mw":10.0}
	game.devices[1].params={"capacity_mw":20.0,"loss_fraction":0.0}
	game.devices[2].params={"demand_mw":0.1,"priority":10.0}
	for pair in [[0,1],[1,2],[3,1]]:
		game.mode="link";game.pending_link=pair[0];game.link_to(pair[1])
	for line in game.links:line.loss_fraction=0.0;line.capacity_mw=20.0
	var chart=load("res://scripts/device_runtime_chart.gd").new()
	game.add_child(chart);game.runtime_chart=chart;chart.setup(game)
	game.selected_id=3;game.paused=true
	game.refresh();check(chart.sample_count==0,"refresh is not committed history")
	game.solve_at(5.0);check(chart.sample_count==0,"prediction is not history")
	game.paused=false
	check(game.advance(1.0),"real advancing charge")
	check(chart.sample_count==1,"world commit hook records")
	if chart.history().is_empty():
		cleanup(game)
		print("RUNTIME_CHART_WORLD_1003 checks=",checks," failures=",failures.size())
		quit(1);return # A failed commit must fail promptly, not hang on an invalid index.
	var first:Dictionary=chart.history()[0]
	check(float(first.values[0])>0.0 and float(first.values[1])==0.0,"chart actual charging not future discharge")
	var expected:float=float(game.devices[3].state.energy_mwh)/float(game.devices[3].params.capacity_mwh)*100.0
	check(is_equal_approx(float(first.soc),expected),"hook after state update")
	check(float(first.t)==game.elapsed_s,"actual committed time")
	game.paused=true;chart.sync_target();check(not chart.visible,"pause hides real graph")
	var old_count:int=chart.sample_count
	game.refresh();check(chart.sample_count==old_count,"paused refresh does not extend graph")
	game.selected_id=0;chart.sync_target();check(chart.sample_count==0,"switch to PV clears CAES curve")
	game.paused=false;check(game.advance(1.0),"PV actual step")
	check(chart.sample_count==1 and chart.power_unit=="MW" and not chart.has_soc,"PV curve correct units")
	check(chart.sample_count>0 and float(chart.history()[0].values[0])<10.0,"PV constrained real output not 10MW availability")
	game.checkpoint();check(chart.sample_count==0,"checkpoint reset prevents edited topology history mixing")
	game.advance(1.0);var state:Dictionary=game.state();game.restore(state)
	check(chart.sample_count==0,"same-ID same-time restore clears")
	cleanup(game)
	print("RUNTIME_CHART_WORLD_1003 checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
func cleanup(controller):
	for key in ["camera","lod_camera","terrain","labels","infrastructure","selection","overlay","equipment","cables","confirmation","param_dialog","param_errors","param_target","data_dialog","data_list","line_dialog","line_capacity","line_loss","line_choice"]:
		var node=controller.get(key)
		if is_instance_valid(node) and node.get_parent()==null:node.free()
	controller.free()
