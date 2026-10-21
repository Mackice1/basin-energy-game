extends SceneTree
class Fixture:
	extends "res://scripts/world_game.gd"
	var last_notice:=""
	func _ready():pass
	func tell(t:String):last_notice=t
	func exclusion(_x:float,_z:float)->String:return ""
	func slope_at(_x:float,_z:float)->float:return 0.0
	func height_at(_x:float,_z:float)->float:return 0.0
	func rebuild_equipment():pass
	func rebuild_cables():pass
	func update_status():pass
	func update_camera():pass
	func set_mode(value:String):mode=value;pending_link=-2
	func ask(message:String,action:Callable):last_notice=message;confirm_action=action
var checks:=0
var failures:=0
var fixtures:Array=[]
func check(ok:bool,why:String):
	checks+=1
	if not ok:failures+=1;push_error("METRIC_CONTROLLER: "+why)
func create(profile:String="metric_v1"):
	var game:=Fixture.new();fixtures.append(game)
	for kind in game.KINDS:game.templates[kind]=game.model.defaults(kind)
	game.cfg={"max_build_slope_degrees":8.0}
	game.dimension_profile=profile;game.booted=true;return game
func _initialize():call_deferred("run")
func run():
	var game=create();check(game.add_station(Vector2.ZERO),"metric station creates")
	var sid:int=game.stations[0].id
	# Positions are world units at 0.1 world/m. Keep all full circular installation
	# allowances inside the 48 m square, with sufficient separation between them.
	for spec in [["electric_boiler",Vector2(-1.0,-0.7)],["thermal_store",Vector2(0.9,-0.6)],["heat_exchanger",Vector2(0,1.0)]]:
		check(game.add_internal_device(sid,spec[0],spec[1]),"true-meter internal placement "+spec[0])
	check(game.connect_internal_devices(0,1) and game.connect_internal_devices(0,2) and game.connect_internal_devices(1,2),"real internal network still connects")
	check(game.validate_state(game.state())=="","schema7 metric world validates")
	check(game.footprint("thermal_station")==5.0,"station 80x60m reserved circle radius50m")
	check(not game.can_place_internal(sid,"electric_boiler",Vector2(-0.3,-0.6),0).is_empty(),"12m center spacing rejects overlapping full installation allowances")
	var frozen:=var_to_bytes(game.state())
	check(not game.add_internal_device(sid,"electric_boiler",Vector2(12,0)),"old120m coordinate outside48m interior rejects")
	check(var_to_bytes(game.state())==frozen,"failed placement atomic")
	check(not game.can_place_internal(sid,"thermal_store",Vector2(0,0),1,{"capacity_mwhth":400.0}).is_empty(),"capacity uses additional modules and rejects space deficit")
	var legacy=create("legacy_illustrative")
	check(not legacy.add_station(Vector2.ZERO),"old-scale UI cannot silently create a reference station")
	# Restore historical data explicitly; constructing new legacy sites is no longer a UI operation.
	var oldsid:=1000000
	legacy.stations=[{"id":oldsid,"name":"Historical station","x":0.0,"z":0.0}]
	legacy.next_station_id=oldsid+1
	legacy.devices=[{"id":0,"kind":"thermal_store","x":0.0,"z":0.0,"parent_station_id":oldsid,"interior_x":12.0,"interior_z":0.0,"params":legacy.model.defaults("thermal_store"),"state":legacy.Catalog.initial_state("thermal_store",legacy.model.defaults("thermal_store")),"model_profile":legacy.Catalog.model_profile("thermal_store")}]
	legacy.next_id=1
	check(legacy.device(0).interior_x==12.0,"historical coordinate retained without new construction")
	legacy.device(0).state.energy_mwhth=0.625;var before:=var_to_bytes(legacy.state())
	legacy.request_metric_migration()
	check(var_to_bytes(legacy.state())==before and legacy.last_notice.contains("不能执行"),"unsafe migration refuses without scaling coordinates or inventory")
	var oldsave:=legacy.state();oldsave.schema=6;oldsave.model_version=15;oldsave.erase("dimension_profile")
	for storage_kind in legacy.Catalog.NEW_STORAGE_KINDS: oldsave.templates.erase(storage_kind)
	for material_kind in legacy.Catalog.Materials.KINDS: oldsave.templates.erase(material_kind)
	oldsave.erase("material_energy")
	oldsave.templates.erase("co2_liquid_cycle_store")
	for template_kind in oldsave.templates.keys():
		if not template_kind in legacy.SaveValidator.PRE_FUEL_KINDS: oldsave.templates.erase(template_kind)
	oldsave.erase("tower_energy"); oldsave.templates.erase("solar_tower_receiver"); oldsave.templates.erase("molten_salt_store"); oldsave.templates.erase("salt_steam_generator"); oldsave.erase("rankine_energy"); oldsave.templates.erase("steam_generator"); oldsave.templates.erase("steam_turbine"); oldsave.templates.erase("steam_condenser"); oldsave.templates.erase("feedwater_pump"); oldsave.erase("high_temp_energy"); oldsave.templates.erase("parabolic_trough"); oldsave.templates.erase("high_temp_store"); oldsave.templates.erase("oil_water_exchanger"); oldsave.erase("solar_energy"); oldsave.templates.erase("solar_thermal"); oldsave.erase("fuel_supply");oldsave.erase("fuel_energy");oldsave.templates.erase("fuel_boiler")
	check(legacy.validate_state(oldsave)=="","actual schema6 still validates")
	var restored=create();restored.restore(oldsave)
	check(restored.dimension_profile=="legacy_illustrative" and restored.device(0).interior_x==12,"oldsave explicit legacy profile no silent compression")
	check(restored.device(0).state.energy_mwhth==0.625,"legacy inventory unchanged")
	var empty=create("legacy_illustrative");empty.request_metric_migration();check(empty.confirm_action.is_valid(),"safe migration requests confirmation")
	empty.confirm_action.call();check(empty.dimension_profile=="metric_v1","explicit confirmation migrates")
	empty.undo();check(empty.dimension_profile=="legacy_illustrative","migration undo restores profile")
	for speed in [-1.0,0.0,2.99,25.0,30.0,NAN,INF]:check(game.wind_visual_speed(game.model.defaults("wind"),speed)==0,"wind visual stopped outside operating band")
	check(game.wind_visual_speed(game.model.defaults("wind"),8.0)>0,"wind visual rotates only valid operating band")
	for object in fixtures:
		for property in ["camera","lod_camera","terrain","labels","infrastructure","selection","overlay","equipment","cables","confirmation","param_dialog","param_errors","param_target","data_dialog","data_list","line_dialog","line_capacity","line_loss","line_choice"]:
			var value=object.get(property)
			if is_instance_valid(value) and value.get_parent()==null:value.free()
		object.free()
	print("METRIC_CONTROLLER checks=",checks," failures=",failures);quit(1 if failures else 0)
