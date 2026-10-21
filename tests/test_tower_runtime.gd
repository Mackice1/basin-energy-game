extends SceneTree
const Model = preload("res://scripts/energy_model.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
const Rankine = preload("res://scripts/rankine_cycle.gd")
const Tower = preload("res://scripts/solar_tower_thermal.gd")
var checks: int = 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("TOWER_RUNTIME_FAIL: " + label)
func near(a: float, b: float, label: String) -> void: check(absf(a-b)<1e-8,label+" "+str(a)+" != "+str(b))
func dev(id: int, kind: String, params: Dictionary = {}) -> Dictionary: return {"id":id,"kind":kind,"params":params}
func el(a: int,b: int,fp: String="out",tp: String="in") -> Dictionary: return {"from":a,"to":b,"from_port":fp,"to_port":tp,"carrier":"electricity_ac","unit":"MW","capacity_mw":10.0,"loss_fraction":0.0}
func salt(a: int,b: int,tp: String="salt_in") -> Dictionary: return {"from":a,"to":b,"from_port":"heat_out","to_port":tp,"carrier":"heat_salt","unit":"MWth","grade_id":"salt_565_290","capacity_mwth":1.0,"loss_fraction":0.0}
func mass(a: int,b: int,fp: String,tp: String,grade: String) -> Dictionary: return {"from":a,"to":b,"from_port":fp,"to_port":tp,"carrier":"water_steam","unit":"kg/s","grade_id":grade,"mass_flow_capacity_kg_s":1.0,"loss_fraction":0.0}
func weather(day: bool=true) -> Dictionary: return {"air_temp_c":25.0,"dni_wm2":800.0 if day else 0.0,"solar_altitude_deg":45.0 if day else -10.0,"solar_azimuth_deg":180.0,"is_day":day}
func ds(source: String="molten_salt_store") -> Array: return [dev(1,"wind"),dev(2,"station",{"loss_fraction":0.0}),dev(3,source,{"initial_soc":1.0,"self_discharge_per_h":0.0} if source=="molten_salt_store" else {}),dev(4,"salt_steam_generator"),dev(5,"steam_turbine"),dev(6,"steam_condenser"),dev(7,"feedwater_pump"),dev(8,"load",{"demand_mw":1.0})]
func ls() -> Array: return [el(1,2),el(2,4,"out","ac_in"),el(2,6,"out","ac_in"),el(2,7,"out","ac_in"),el(5,2,"ac_out","in"),el(2,8),salt(3,4),mass(4,5,"steam_out","steam_in","rankine_live_v1"),mass(5,6,"exhaust_out","exhaust_in","rankine_exhaust_v1"),mass(6,7,"condensate_out","condensate_in","rankine_condensate_v1"),mass(7,4,"feed_out","feed_in","rankine_feedwater_v1"),el(2,3,"out","ac_in")]
func run_case(d: Array,l: Array,power: float=.01,day: bool=true,dt: float=3600.0) -> Dictionary:
	var w: Dictionary = weather(day)
	var r: Dictionary = Model.dispatch(d,l,w,{"1":{"mw":power}},dt)
	check(r.valid,"valid "+str(r.errors)+str(r.warnings))
	var audited: Array = Model.audit_dispatch(d,l,r,{},w)
	check(audited.is_empty(),"replay "+str(audited))
	for v in [r.balance_error_mw,r.thermal.balance_error_mwth,r.tower.balance_error_mwth,r.tower.energy_balance_error_mwhth,r.get("rankine",{}).get("balance_error_mw",0.0),r.cross_carrier_balance_error_mw]: near(v,0.0,"balance")
	return r
func _initialize() -> void:
	var d: Array = ds()
	var l: Array = ls()
	var r: Dictionary = run_case(d,l,.01,false)
	check(r.rankine.gross_electric_mw>0.0,"night salt inventory generates")
	near(r.rankine.salt_input_mwth,.1,"salt SG input capacity")
	near(r.rankine.oil_input_mwth,0.0,"salt not booked as oil")
	check(not r.has("high_temp"),"isolated tower no oil ledger")
	near(r.tower.discharge_mwth,.1,"one salt draw")
	near(r.tower.store_auxiliary_electric_mw,.001,"salt circulation paid externally")
	near(r.tower.energy_mwhth,.5-.1/.98,"finite salt inventory")
	near(r.rankine.mass_flow_kg_s,.1*.97/((Rankine.H3-Rankine.H2)/1000.0),"fixed steam state reused")
	for idx in [0,1,2,3,4,5,6,7,8,9,10,11]:
		var disconnected: Array = l.duplicate(true)
		disconnected.remove_at(idx)
		var zero: Dictionary = run_case(d,disconnected,.01,false)
		near(zero.rankine.mass_flow_kg_s,0.0,"disconnected essential route "+str(idx))
		near(zero.tower.discharge_mwth,0.0,"no stranded salt "+str(idx))
		near(zero.rankine.auxiliary_electric_mw+zero.tower.auxiliary_electric_mw,0.0,"no stranded auxiliaries "+str(idx))
	r=run_case(d,l,0.0,false)
	near(r.rankine.gross_electric_mw,0.0,"no bootstrap without external power")
	r=run_case(d,l,.01,false,0.0)
	near(r.tower.energy_mwhth,.5,"paused store frozen")
	near(r.rankine.gross_electric_mw,0.0,"paused steam flow zero")
	var empty: Array = d.duplicate(true);empty[2].params.initial_soc=0.0
	r=run_case(empty,l,.01,false)
	near(r.rankine.gross_electric_mw,0.0,"empty store no energy")
	var near_empty: Array = d.duplicate(true);near_empty[2].params.initial_soc=.01
	r=run_case(near_empty,l,.01,false)
	near(r.tower.discharge_mwth,.005*.98,"finite interval discharge limit")
	near(r.tower.energy_mwhth,0.0,"near empty clipped by physical energy")
	var receiver: Array = ds("solar_tower_receiver")
	r=run_case(receiver,l)
	near(r.tower.incident_mw,1.28,"1600m2 mirror DNI")
	near(r.tower.available_mwth,.6912,"field and receiver efficiency")
	near(r.tower.useful_mwth,.1,"receiver direct SG use")
	near(r.tower.receiver_auxiliary_electric_mw,.002,"receiver auxiliary")
	r=run_case(receiver,l,.01,false)
	near(r.tower.available_mwth,0.0,"night receiver zero")
	near(r.rankine.gross_electric_mw,0.0,"no invented nighttime generation")
	# Receiver surplus charges a different finite salt inventory, with two auxiliaries.
	var charging: Array = [dev(1,"wind"),dev(2,"station",{"loss_fraction":0.0}),dev(3,"solar_tower_receiver"),dev(9,"molten_salt_store",{"initial_soc":0.0,"self_discharge_per_h":0.0})]
	var charging_l: Array = [el(1,2),el(2,3,"out","ac_in"),el(2,9,"out","ac_in"),salt(3,9,"heat_in")]
	r=run_case(charging,charging_l,1.0)
	near(r.tower.energy_mwhth,.5,"finite tank fills")
	near(r.tower.charge_mwth,.5/.98,"charge constrained by inventory")
	near(r.tower.receiver_auxiliary_electric_mw,r.tower.charge_mwth*.02,"charging receiver auxiliary")
	near(r.tower.store_auxiliary_electric_mw,r.tower.charge_mwth*.01,"charging salt pump auxiliary")
	near(r.tower.curtailed_mwth,.6912-.5/.98,"full tank curtails potential")
	var full: Array = charging.duplicate(true);full[3].params.initial_soc=1.0
	r=run_case(full,charging_l,1.0)
	near(r.tower.charge_mwth,0.0,"full store no charging")
	r=run_case(charging,charging_l,0.0)
	near(r.tower.charge_mwth,0.0,"no external electricity no charge")
	for idx in [1,2,3]:
		var cut: Array = charging_l.duplicate(true);cut.remove_at(idx)
		r=run_case(charging,cut,1.0)
		near(r.tower.charge_mwth,0.0,"disconnected charge path")
		near(r.tower.auxiliary_electric_mw,0.0,"charge atomic reservation")
	r=run_case(charging,charging_l,.001)
	near(r.tower.charge_mwth,.001/.03,"scarce external auxiliary jointly reserved")
	var battery_charge: Array = charging.duplicate(true)
	battery_charge.append(dev(12,"battery",{"initial_soc":.1}))
	var battery_charge_l: Array = charging_l.duplicate(true)
	battery_charge_l.append(el(12,2,"ac","in"))
	r=run_case(battery_charge,battery_charge_l,0.0)
	check(r.tower.charge_mwth>0.0,"stored external AC can operate solar collection and salt charging")
	check(r.devices["12"].mode=="discharge" and r.devices["12"].charge_mw==0.0,"solar auxiliary battery cannot recharge same interval")
	# Day receiver can charge while a different salt tank discharges, but not the same tank.
	var both: Array = d.duplicate(true);both.append(dev(10,"solar_tower_receiver"))
	var both_l: Array = l.duplicate(true);both_l.append(el(2,10,"out","ac_in"));both_l.append(salt(10,3,"heat_in"))
	r=run_case(both,both_l,.1)
	near(r.devices["3"].charge_mwth,0.0,"discharging tank cannot charge same interval")
	check(r.devices["3"].discharge_mwth>0.0,"tank discharges to demand")
	# Replay must reject any tower aggregate mutation and salt transport corruption.
	r=run_case(d,l,.01,false)
	for key in Tower.empty():
		var bad: Dictionary = r.duplicate(true);bad.tower[key]+=.1
		check(not Model.audit_dispatch(d,l,bad,{},weather(false)).is_empty(),"tamper tower ledger "+key)
	for key in ["salt_input_mwth", "oil_input_mwth"]:
		var bad: Dictionary = r.duplicate(true);bad.rankine[key]+=.1
		check(not Model.audit_dispatch(d,l,bad,{},weather(false)).is_empty(),"tamper Rankine heat identity "+key)
	var aliased: Dictionary = r.duplicate(true);aliased.devices["4"].oil_input_mwth=aliased.devices["4"].salt_input_mwth
	check(not Model.audit_dispatch(d,l,aliased,{},weather(false)).is_empty(),"reject salt SG oil ledger alias")
	for key in ["sent_mwth","received_mwth","capacity_mwth"]:
		var bad: Dictionary = r.duplicate(true);bad.lines[6][key]+=.1
		check(not Model.audit_dispatch(d,l,bad,{},weather(false)).is_empty(),"tamper salt line "+key)
	var rankine_energy: Dictionary = Rankine.initial_energy(true)
	for key in Rankine.POWER_FIELDS: rankine_energy[key.replace("_mw","_mwh")]=r.rankine[key]
	rankine_energy.salt_input_mwhth=r.rankine.salt_input_mwth
	rankine_energy.circulated_mass_kg=r.rankine.mass_flow_kg_s*3600.0
	check(Rankine.validate_energy(rankine_energy).is_empty(),"salt Rankine cumulative first law "+Rankine.validate_energy(rankine_energy))
	var tower_energy: Dictionary = Tower.initial_energy()
	for pair in [["incident_mwh","incident_mw"],["optical_rejection_mwh","optical_rejection_mw"],["thermal_loss_mwh","thermal_loss_mw"],["available_mwhth","available_mwth"],["useful_mwhth","useful_mwth"],["curtailed_mwhth","curtailed_mwth"],["auxiliary_mwh","auxiliary_electric_mw"],["receiver_auxiliary_mwh","receiver_auxiliary_electric_mw"],["store_auxiliary_mwh","store_auxiliary_electric_mw"],["rankine_salt_input_mwhth","rankine_salt_input_mwth"],["charge_mwhth","charge_mwth"],["discharge_mwhth","discharge_mwth"],["storage_conversion_loss_mwhth","storage_conversion_loss_mwth"],["self_discharge_mwhth","self_discharge_mwhth"]]: tower_energy[pair[0]]=r.tower[pair[1]]
	check(Tower.validate_energy(tower_energy).is_empty(),"tower cumulative first law "+Tower.validate_energy(tower_energy))
	for key in ["dni_wm2","solar_altitude_deg","solar_azimuth_deg","air_temp_c","is_day"]:
		var missing: Dictionary = weather();missing.erase(key)
		check(not Tower.evaluate({},missing).valid,"explicit weather "+key)
	# Separate oil and salt loops may share the external AC bus, never inventories.
	var mixed: Array = d.duplicate(true)
	mixed.append_array([dev(20,"high_temp_store",{"initial_soc":1.0,"self_discharge_per_h":0.0}),dev(21,"steam_generator"),dev(22,"steam_turbine"),dev(23,"steam_condenser"),dev(24,"feedwater_pump"),dev(25,"fuel_boiler")])
	var mixed_l: Array = l.duplicate(true)
	var oil_line: Dictionary = salt(20,21,"oil_in");oil_line.carrier="heat_oil";oil_line.grade_id="oil_300_200"
	mixed_l.append_array([oil_line,el(2,21,"out","ac_in"),el(2,23,"out","ac_in"),el(2,24,"out","ac_in"),el(22,2,"ac_out","in"),mass(21,22,"steam_out","steam_in","rankine_live_v1"),mass(22,23,"exhaust_out","exhaust_in","rankine_exhaust_v1"),mass(23,24,"condensate_out","condensate_in","rankine_condensate_v1"),mass(24,21,"feed_out","feed_in","rankine_feedwater_v1")])
	r=run_case(mixed,mixed_l,.03,false)
	check(r.rankine.oil_input_mwth>0.0 and r.rankine.salt_input_mwth>0.0,"oil and salt cycles both operate")
	near(r.rankine.oil_input_mwth,r.high_temp.discharge_mwth,"oil ledger remains oil only")
	near(r.rankine.salt_input_mwth,r.tower.discharge_mwth,"salt ledger remains salt only")
	near(r.high_temp.balance_error_mwth,0.0,"mixed oil first law")
	# A whole day of committed state steps keeps distinct finite salt inventory.
	var day_d: Array = ds("solar_tower_receiver")
	day_d.append(dev(9,"molten_salt_store",{"initial_soc":0.0}))
	var day_l: Array = l.duplicate(true)
	day_l.append_array([salt(3,9,"heat_in"),salt(9,4),el(2,9,"out","ac_in")])
	var sum_useful: float = 0.0
	var sum_draw: float = 0.0
	var sum_losses: float = 0.0
	var night_draw: float = 0.0
	for hour in 24:
		r=run_case(day_d,day_l,2.0 if hour<12 else .05,hour<12)
		sum_useful+=r.tower.useful_mwth
		sum_draw+=r.tower.rankine_salt_input_mwth
		sum_losses+=r.tower.storage_conversion_loss_mwth+r.tower.self_discharge_mwhth
		if hour>=12: night_draw+=r.tower.rankine_salt_input_mwth
		for node in day_d:
			if r.next_states.has(str(node.id)): node.state=r.next_states[str(node.id)].duplicate(true)
	near(sum_useful,sum_draw+sum_losses+r.tower.energy_mwhth,"24h salt energy closes")
	check(night_draw>0.4,"day charging actually powers night steam")
	near(r.tower.energy_mwhth,0.0,"overnight inventory eventually empty")
	var rng: RandomNumberGenerator = RandomNumberGenerator.new();rng.seed=210017
	for trial in 100:
		var random_d: Array = ds()
		random_d[2].params.initial_soc=rng.randf()
		random_d[2].params.self_discharge_per_h=rng.randf_range(0.0,.05)
		var random_l: Array = l.duplicate(true)
		random_l[6].capacity_mwth=rng.randf_range(0.0,.1)
		random_l[8].mass_flow_capacity_kg_s=rng.randf_range(0.0,.05)
		r=run_case(random_d,random_l,rng.randf_range(0.0,.02),trial%2==0,rng.randf_range(1.0,10000.0))
	var snap: Dictionary = Model.optimization_snapshot(receiver,l,weather(),{"1":{"mw":.01}},3600.0)
	check(snap.valid and snap.schema_version==6,"tower snapshot schema6")
	check(snap.devices[2].tower_physics.valid,"tower physics snapshot")
	for ep in snap.constraints.paths:
		if ep.source_kind=="steam_turbine": check(ep.sink_kind in ["load","battery","grid"],"no turbine auxiliary paths")
	print("TOWER_RUNTIME_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
