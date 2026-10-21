extends SceneTree
const Model = preload("res://scripts/energy_model.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
func d(id: int, kind: String, p: Dictionary = {}, state: Dictionary = {}) -> Dictionary:
	return {"id": id, "kind": kind, "params": p, "state": state if not state.is_empty() else Catalog.initial_state(kind, p)}
func e(a: int, b: int, cap: float, loss: float, boiler: bool = false) -> Dictionary:
	var x: Dictionary = {"from": a, "to": b, "capacity_mw": cap, "loss_fraction": loss}
	if boiler: x.merge({"from_port": "out", "to_port": "ac_in", "carrier": "electricity_ac", "unit": "MW"})
	return x
func h(a: int, b: int, ap: String, bp: String, cap: float) -> Dictionary:
	return {"from": a, "to": b, "from_port": ap, "to_port": bp, "carrier": "heat_water", "unit": "MWth", "capacity_mwth": cap, "loss_fraction": 0.0, "grade_id": Catalog.SECONDARY_GRADE if ap == "warm_out" else Catalog.PRIMARY_GRADE}
func _initialize() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 4137
	var results: Array = []
	for trial in 300:
		var ds: Array = [d(1,"wind"), d(2,"station",{"capacity_mw": rng.randf_range(.1,10), "loss_fraction": rng.randf_range(0,.2)}), d(3,"battery",{}, {"energy_mwh": rng.randf_range(0,10)}), d(4,"load",{"demand_mw":rng.randf_range(0,4),"priority":rng.randi_range(0,20)})]
		var ls: Array = [e(1,2,rng.randf_range(0,6),rng.randf_range(0,.2)), e(3,2,rng.randf_range(0,6),rng.randf_range(0,.2)), e(2,4,rng.randf_range(0,6),rng.randf_range(0,.2)),e(2,-1,4,.01)]
		if trial >= 100:
			ds += [d(5,"electric_boiler",{"rated_electric_mw":rng.randf_range(.1,4),"thermal_efficiency":rng.randf_range(.3,1)}),d(6,"heat_exchanger",{"capacity_mwth":rng.randf_range(.1,4),"transfer_efficiency":rng.randf_range(.3,1)}),d(7,"heat_demand",{"demand_mwth":rng.randf_range(0,4),"priority":rng.randi_range(0,20)}),d(8,"thermal_store",{}, {"energy_mwhth":rng.randf_range(0,4)})]
			ls += [e(2,5,4,.01,true),h(5,6,"heat_out","hot_in",4),h(6,7,"warm_out","heat_in",4),h(5,8,"heat_out","heat_in",4),h(8,6,"heat_out","hot_in",4)]
		var direct: Dictionary = {"1":{"mw":rng.randf_range(0,6)}}
		if trial >= 200:
			ds.append(d(9,"fuel_boiler",{"rated_fuel_mw":rng.randf_range(.01,3),"thermal_efficiency":rng.randf_range(.4,1),"auxiliary_electric_ratio":rng.randf_range(.001,.2)}))
			ls += [e(2,9,4,.01,true),h(9,6,"heat_out","hot_in",4),h(9,8,"heat_out","heat_in",4)]
			direct["_fuel_supply"]={"enabled":trial%3!=0,"max_input_mw":rng.randf_range(0,4),"lower_heating_value_kwh_per_nm3":10.0,"price_per_mwh":300.0}
		var dt: float = rng.randf_range(0,10000)
		results.append({"report":Model.dispatch(ds,ls,{},direct,dt),"snapshot":Model.optimization_snapshot(ds,ls,{},direct,dt)})
	var file: FileAccess = FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
	file.store_string(JSON.stringify(results))
	file.close()
	quit()
