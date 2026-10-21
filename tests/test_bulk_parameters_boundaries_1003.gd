extends SceneTree
## Independent atomicity tests; real controller validation with no scene/user slots.
const BaseTest=preload("res://tests/test_storage_world_1003.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func run():
	var test=BaseTest.new()
	var game=test.fixture()
	for x in [-60.0,-30.0,0.0,30.0,60.0]:check(game.add_equipment("wind",Vector2(x,-50)),"install wind fixture")
	check(game.devices.size()==5,"five installed wind devices")
	game.devices[0].params.shear_exponent=0.1
	game.devices[2].params.shear_exponent=0.3
	var before:Dictionary=game.state().duplicate(true)
	var response:Dictionary=game.apply_bulk_parameters("wind",[0,2,4],{"rated_mw":4.0})
	check(bool(response.get("ok",false)),"apply arbitrary 3 of 5: "+str(response))
	for d in game.devices:
		var original:Dictionary=before.devices[int(d.id)]
		check(float(d.params.rated_mw)==(4.0 if int(d.id) in [0,2,4] else 5.0),"only selected IDs changed "+str(d.id))
		check(float(d.params.shear_exponent)==float(original.params.shear_exponent),"mixed untouched field preserved "+str(d.id))
		for key in original:
			if key!="params":check(d[key]==original[key],"non-parameter field unchanged "+key)
	check(game.paused,"batch pauses simulation")
	check(game.validate_state(game.state())=="","successful batch saves")
	check(game.validate_state(JSON.parse_string(JSON.stringify(game.state())))=="","batch params JSON roundtrip")
	var updated:Dictionary=game.state().duplicate(true)
	for spec in [
		["wind",[],{"rated_mw":3.0}],
		["wind",[0,0],{"rated_mw":3.0}],
		["wind",[0,999],{"rated_mw":3.0}],
		["pv",[0,2],{"inverter_capacity_mw":1.0}],
		["wind",[0,2],{"rated_mw":-1.0}],
		["wind",[0,2],{"unknown":1.0}],
		["wind",[0,2],{"initial_soc":1.0}],
		["wind",[0,1],{"rotor_diameter_m":500.0,"hub_height_m":300.0}],
	]:
		var prior:Dictionary=game.state().duplicate(true)
		response=game.apply_bulk_parameters(spec[0],spec[1],spec[2])
		check(not bool(response.get("ok",false)),"reject invalid/stale/subset/overlap "+str(spec))
		check(game.state()==prior,"invalid batch atomic no mutation")
	game.undo()
	check(game.devices==before.devices,"single undo restores full three-device edit")
	var battery_game=test.fixture()
	check(battery_game.add_equipment("battery",Vector2.ZERO),"battery fixture")
	var stock:float=battery_game.devices[0].state.energy_mwh
	var stock_before:Dictionary=battery_game.state().duplicate(true)
	response=battery_game.apply_bulk_parameters("battery",[0],{"capacity_mwh":stock/2.0})
	check(not bool(response.get("ok",false)),"capacity below stored energy rejected")
	check(battery_game.state()==stock_before,"capacity rejection preserves energy and parameters")
	response=battery_game.apply_bulk_parameters("battery",[0],{"charge_mw":1.0})
	check(bool(response.get("ok",false)),"valid battery batch applies")
	check(battery_game.devices[0].state.energy_mwh==stock,"valid parameter edit cannot reset SOC")
	test.cleanup(battery_game);test.cleanup(game);test.free()
	print("BULK_BOUNDARIES_1003 checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
