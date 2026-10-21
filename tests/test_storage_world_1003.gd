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
	for kind in ["battery_sodium","battery_flow","caes_aboveground","liquid_air_store","hydrogen_storage_system"]:
		var game:=fixture()
		for spec in [["pv",Vector2(-40,0)],["station",Vector2(0,0)],["load",Vector2(40,0)],[kind,Vector2(0,40)]]:
			check(game.add_equipment(spec[0],spec[1]),kind+" place "+str(spec[0])+" "+game.last_notice)
		if game.devices.size()!=4:cleanup(game);continue
		var store:Dictionary=game.devices[3]
		check(float(store.state.energy_mwh)==0.0,kind+" begins empty")
		game.devices[0].params={"dc_capacity_mw":12.0,"inverter_capacity_mw":10.0}
		game.devices[1].params={"capacity_mw":20.0,"loss_fraction":0.0}
		game.devices[2].params={"demand_mw":0.1,"priority":10.0}
		for pair in [[0,1],[1,2],[3,1]]:
			game.mode="link";game.pending_link=pair[0];game.link_to(pair[1])
		check(game.links.size()==3,kind+" first-level AC wiring")
		for line in game.links:line.loss_fraction=0.0;line.capacity_mw=20.0
		game.refresh()
		check(bool(game.result.get("valid",false)),kind+" valid dispatch "+str(game.result.get("errors",[])))
		check(game.advance(60),kind+" charge minute accepted")
		var charged:=float(store.state.energy_mwh)
		check(charged>0.0 and charged<=float(store.params.capacity_mwh),kind+" charges finite inventory")
		var frozen:=charged
		for i in 5:game.refresh();game.solve_at(0)
		check(float(store.state.energy_mwh)==frozen,kind+" paused inspection cannot alter inventory")
		var saved:Dictionary=game.state()
		check(int(saved.schema)==13,kind+" new schema")
		check(game.validate_state(saved)=="",kind+" save validation: "+game.validate_state(saved))
		check(game.validate_state(JSON.parse_string(JSON.stringify(saved)))=="",kind+" JSON roundtrip")
		game.links=game.links.filter(func(l):return int(l.from)!=0)
		game.refresh()
		check(float(game.result.discharge_mw)>0.0,kind+" can return power via station")
		check(game.advance(3600),kind+" discharge accepted")
		check(float(store.state.energy_mwh)>=0.0 and float(store.state.energy_mwh)<charged,kind+" finite depletion")
		check(absf(float(game.result.get("balance_error_mw",0)))<1e-7,kind+" AC balance")
		cleanup(game)
	for kind in ["solid_thermal_store","molten_salt_store"]:
		var game:=fixture()
		check(game.add_equipment(kind,Vector2.ZERO),kind+" independently placeable "+game.last_notice)
		if not game.devices.is_empty():
			check(not game.devices[0].has("parent_station_id"),kind+" no required station wrapper")
			check(game.validate_state(game.state())=="",kind+" standalone save: "+game.validate_state(game.state()))
			for port in Catalog.ports(kind):
				check(not (port.carrier==Catalog.CARRIER and port.direction in ["output","bidirectional"]),kind+" cannot output electricity")
		cleanup(game)
	print("STORAGE_WORLD_1003 checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
func cleanup(controller):
	for key in ["camera","lod_camera","terrain","labels","infrastructure","selection","overlay","equipment","cables","confirmation","param_dialog","param_errors","param_target","data_dialog","data_list","line_dialog","line_capacity","line_loss","line_choice"]:
		var node=controller.get(key)
		if is_instance_valid(node) and node.get_parent()==null:node.free()
	controller.free()
