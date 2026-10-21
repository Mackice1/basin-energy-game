extends SceneTree
## Real controller state/integration with isolated terrain and UI seams, no user slots.
class Fixture:
	extends "res://scripts/world_game.gd"
	var last_notice := ""
	func _ready():pass
	func tell(message:String):last_notice=message
	func exclusion(_x:float,_z:float)->String:return ""
	func slope_at(_x:float,_z:float)->float:return 0.0
	func height_at(_x:float,_z:float)->float:return 0.0
	func rebuild_equipment():pass
	func rebuild_cables():pass
	func update_status():pass
	func set_mode(value:String):mode=value;pending_link=-2
	func select_device(id:int):selected_id=id
	func weather_at(_t:float)->Dictionary:return {"wind_speed_mps":12.0,"irradiance_wm2":1000.0,"air_temp_c":25.0}
var game:Fixture
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);print("FAIL ",label)
func _initialize():call_deferred("run")
func run():
	game=Fixture.new();check(game.footprint("load")==5.5,"load placement matches visual footprint");game.cfg={"max_build_slope_degrees":8.0};game.booted=true
	for kind in game.KINDS:game.templates[kind]=game.model.defaults(kind)
	for spec in [["pv",Vector2(-30,0)],["station",Vector2(0,0)],["load",Vector2(20,0)],["battery",Vector2(40,0)]]:check(game.add_equipment(spec[0],spec[1]),"place "+spec[0])
	game.devices[0].params={"dc_capacity_mw":12.0,"inverter_capacity_mw":10.0}
	game.devices[1].params={"capacity_mw":20.0,"loss_fraction":0.0}
	game.devices[2].params={"demand_mw":2.0,"priority":10.0}
	game.devices[3].params={"capacity_mwh":10.0,"charge_mw":3.0,"discharge_mw":3.0,"charge_efficiency":0.9,"discharge_efficiency":0.9,"self_discharge_per_h":0.0,"initial_soc":0.0}
	game.devices[3].state={"energy_mwh":0.0}
	for pair in [[0,1],[1,2],[3,1]]:
		game.mode="link";game.pending_link=pair[0];game.link_to(pair[1])
	check(game.links.size()==3,"UI link routes support load and battery")
	for line in game.links:line.loss_fraction=0.0;line.capacity_mw=20.0
	game.refresh();check(game.result.served_mw==2.0,"load served")
	var before:float=game.devices[3].state.energy_mwh
	for i in 10:game.refresh();game.solve_at(0)
	check(game.devices[3].state.energy_mwh==before,"refresh and paused reports never commit battery state")
	check(game.advance(60.0),"advance charge minute")
	check(absf(game.devices[3].state.energy_mwh-0.045)<1e-8,"charge MW to MWh integration")
	check(absf(game.energy.generated+game.energy.discharge-game.energy.curtailed-game.energy.loss-game.energy.delivered-game.energy.served-game.energy.charge)<1e-9,"integrated energy balance")
	var saved:Dictionary=game.state();check(game.validate_state(saved)=="","schema4 valid after charging")
	check(game.write_save("user://storage_test/slot0.json"),"write isolated slot")
	game.checkpoint();game.links=game.links.filter(func(l):return int(l.from)!=3);game.refresh()
	check(game.result.devices["3"].charge_mw==0.0 and game.result.devices["3"].discharge_mw==0.0,"disconnected battery idle")
	game.undo();check(game.links.size()==3 and absf(game.devices[3].state.energy_mwh-0.045)<1e-8,"undo restores cable and stored energy")
	game.devices[3].state.energy_mwh=0.0;check(game.read_save("user://storage_test/slot0.json"),"read isolated slot")
	check(absf(game.devices[3].state.energy_mwh-0.045)<1e-8 and game.paused,"read restores stored energy and pauses")
	game.links=game.links.filter(func(l):return int(l.from)!=0);game.refresh()
	check(game.result.discharge_mw>0 and game.result.charge_mw==0,"battery serves shortage only")
	check(game.advance(120),"empty battery integration")
	check(game.devices[3].state.energy_mwh>=0 and game.devices[3].state.energy_mwh<1e-9,"battery empty boundary")
	check(game.result.unserved_mw>1.999 and game.result.discharge_mw<1e-9,"empty battery cannot serve load")
	game.checkpoint();game.devices=game.devices.filter(func(d):return int(d.id)!=2);game.links=game.links.filter(func(l):return int(l.to)!=2);game.undo()
	check(game.devices.size()==4 and game.links.size()==2,"demolition undo restores load and links")
	# Reload in a separate controller, proving persistence doesn't rely on old object state.
	var fresh:=Fixture.new();fresh.cfg=game.cfg;fresh.booted=true
	check(fresh.read_save("user://storage_test/slot0.json"),"separate controller reads full state")
	check(absf(fresh.devices[3].state.energy_mwh-0.045)<1e-8,"separate controller preserves SOC")
	var frozen:float=game.devices[3].state.energy_mwh
	game.links.append({"from":3,"to":999,"capacity_mw":3.0,"loss_fraction":0.0})
	check(not game.advance(1.0) and game.devices[3].state.energy_mwh==frozen,"invalid live topology rejects atomic state commit")
	cleanup(fresh);cleanup(game)
	print("STORAGE_CONTROLLER checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func cleanup(controller):
	for key in ["camera","lod_camera","terrain","labels","infrastructure","selection","overlay","equipment","cables","confirmation","param_dialog","param_errors","param_target","data_dialog","data_list","line_dialog","line_capacity","line_loss","line_choice"]:
		var node=controller.get(key)
		if is_instance_valid(node) and node.get_parent()==null:node.free()
	controller.free()
