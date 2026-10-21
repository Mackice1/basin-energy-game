extends SceneTree
const Model = preload("res://scripts/energy_model.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
const Rankine = preload("res://scripts/rankine_cycle.gd")
var checks: int = 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("RANKINE_FAIL: " + label)
func near(a: float, b: float, label: String) -> void: check(absf(a-b) < 1e-8, label + " " + str(a) + " != " + str(b))
func dev(id: int, kind: String, params: Dictionary = {}) -> Dictionary: return {"id": id, "kind": kind, "params": params}
func el(a: int, b: int, fp: String = "out", tp: String = "in") -> Dictionary: return {"from": a, "to": b, "from_port": fp, "to_port": tp, "carrier": "electricity_ac", "unit": "MW", "capacity_mw": 10.0, "loss_fraction": 0.0}
func mass(a: int, b: int, fp: String, tp: String, grade: String) -> Dictionary: return {"from": a, "to": b, "from_port": fp, "to_port": tp, "carrier": "water_steam", "unit": "kg/s", "grade_id": grade, "mass_flow_capacity_kg_s": 1.0, "loss_fraction": 0.0}
func ds() -> Array: return [dev(1,"wind"), dev(2,"station",{"loss_fraction":0.0}),dev(3,"high_temp_store",{"initial_soc":1.0,"self_discharge_per_h":0.0}),dev(4,"steam_generator"),dev(5,"steam_turbine"),dev(6,"steam_condenser"),dev(7,"feedwater_pump"),dev(8,"load",{"demand_mw":1.0})]
func ls() -> Array: return [el(1,2),el(2,4,"out","ac_in"),el(2,6,"out","ac_in"),el(2,7,"out","ac_in"),el(5,2,"ac_out","in"),el(2,8),{"from":3,"to":4,"from_port":"heat_out","to_port":"oil_in","carrier":"heat_oil","unit":"MWth","grade_id":"oil_300_200","capacity_mwth":1.0,"loss_fraction":0.0},mass(4,5,"steam_out","steam_in","rankine_live_v1"),mass(5,6,"exhaust_out","exhaust_in","rankine_exhaust_v1"),mass(6,7,"condensate_out","condensate_in","rankine_condensate_v1"),mass(7,4,"feed_out","feed_in","rankine_feedwater_v1")]
func run_case(d: Array, l: Array, power: float = .01, air: float = 25.0, dt: float = 3600.0) -> Dictionary:
	var r := Model.dispatch(d,l,{"air_temp_c":air},{"1":{"mw":power}},dt)
	check(r.valid,"runtime " + str(r.errors) + str(r.warnings))
	var audit: Array = Model.audit_dispatch(d,l,r,{}, {"air_temp_c":air})
	check(audit.is_empty(),"replay " + str(audit))
	for value in [r.balance_error_mw,r.thermal.balance_error_mwth,r.high_temp.balance_error_mwth,r.rankine.balance_error_mw,r.cross_carrier_balance_error_mw]: near(value,0,"balance")
	return r
func _initialize() -> void:
	var d := ds()
	var l := ls()
	var r := run_case(d,l)
	check(r.rankine.gross_electric_mw>0,"cycle produces with shared-bus external starter")
	near(r.rankine.oil_input_mwth,.1,"SG cap")
	near(r.rankine.mass_flow_kg_s,.1*.97/((Rankine.H3-Rankine.H2)/1000),"mass from oil")
	near(r.high_temp.discharge_mwth,r.rankine.oil_input_mwth,"oil consumed exactly once")
	near(r.high_temp.energy_mwhth,.2-.1/.98,"oil inventory")
	near(r.generated_mw,.01+r.rankine.gross_electric_mw,"gross generation")
	near(r.available_mw,.01,"exogenous availability")
	for key in Rankine.empty():
		var bad := r.duplicate(true);bad.rankine[key]+=.1
		check(not Model.audit_dispatch(d,l,bad,{}, {"air_temp_c":25.0}).is_empty(),"tamper ledger " + key)
	for idx in [1,2,3,4,6,7,8,9,10]:
		var disconnected := l.duplicate(true);disconnected.remove_at(idx)
		var zero := run_case(d,disconnected)
		near(zero.rankine.mass_flow_kg_s,0,"missing essential route " + str(idx))
		near(zero.rankine.auxiliary_electric_mw,0,"no stranded auxiliary")
		near(zero.high_temp.discharge_mwth,0,"no stranded heat")
	r=run_case(d,l,0)
	near(r.rankine.mass_flow_kg_s,0,"no external AC no bootstrap")
	r=run_case(d,l,.01,36)
	near(r.rankine.mass_flow_kg_s,0,"dry cooling ambient cutoff")
	r=run_case(d,l,.01,30)
	near(r.rankine.condenser_rejection_mwth,.08*(45.806-30)/(45.806-25),"dry cooling derating")
	r=run_case(d,l,.01,25,0)
	near(r.rankine.mass_flow_kg_s,0,"pause")
	near(r.high_temp.energy_mwhth,.2,"pause inventory")
	r=run_case(d,l,2)
	near(r.rankine.mass_flow_kg_s,0,"sufficient renewable avoids oil draw")
	var capped := l.duplicate(true);capped[9].mass_flow_capacity_kg_s=.001
	r=run_case(d,capped)
	near(r.rankine.mass_flow_kg_s,.001,"mass pipe bottleneck")
	for i in [4,6]:
		var limited := d.duplicate(true);limited[i].params.mass_flow_capacity_kg_s=.002
		r=run_case(limited,l)
		near(r.rankine.mass_flow_kg_s,.002,"independent turbine/pump capacity")
	var no_weather := Model.dispatch(d,l,{}, {"1":{"mw":.01}},3600)
	check(not no_weather.valid,"explicit cooling weather required")
	var exported := l.duplicate(true);exported.remove_at(5);exported.append(el(2,-1))
	r=run_case(d,exported)
	check(r.delivered_mw>.01,"Rankine export preserves starter")
	var energy := Rankine.initial_energy()
	check(Rankine.validate_energy(energy).is_empty(),"zero cumulative ledger")
	for key in Rankine.POWER_FIELDS: energy[key.replace("_mw","_mwh")]=r.rankine[key]
	energy.circulated_mass_kg=r.rankine.mass_flow_kg_s*3600
	check(Rankine.validate_energy(energy).is_empty(),"cumulative cycle ledger")
	for key in energy:
		var bad_energy := energy.duplicate(true);bad_energy[key] += 0.1
		check(not Rankine.validate_energy(bad_energy).is_empty(), "reject cumulative tamper " + key)
	# Every mass stream has fixed-state enthalpy, direction and original capacity.
	r=run_case(d,l)
	for field in ["sent_kg_s", "received_kg_s", "enthalpy_kj_kg", "enthalpy_flow_mw", "mass_flow_capacity_kg_s"]:
		var corrupt := r.duplicate(true);corrupt.lines[7][field] += .1
		check(not Model.audit_dispatch(d,l,corrupt,{}, {"air_temp_c":25.0}).is_empty(), "mass stream tamper " + field)
	var snapshot := Model.optimization_snapshot(d,l,{"air_temp_c":25.0},{"1":{"mw":.01}},3600)
	check(snapshot.schema_version==5,"conditional snapshot schema5")
	for path in snapshot.constraints.paths:
		if path.source_kind == "steam_turbine": check(path.sink_kind in ["load","battery","grid"],"no turbine to any auxiliary path")
	# External electricity stored before this step can bootstrap the loop.
	var battery_d := d.duplicate(true);battery_d.append(dev(12,"battery",{"initial_soc":.1}))
	var battery_l := l.duplicate(true);battery_l.append(el(12,2,"ac","in"))
	r=run_case(battery_d,battery_l,0)
	check(r.rankine.gross_electric_mw>0,"existing battery inventory is external starter")
	check(r.devices["12"].mode=="discharge","starter battery exclusively discharges")
	# Without loads/export, a battery cannot discharge to auxiliary and charge itself.
	battery_l.remove_at(5)
	r=run_case(battery_d,battery_l,0)
	near(r.rankine.gross_electric_mw,0,"same battery charge-discharge self cycle blocked")
	near(r.devices["12"].charge_mw+r.devices["12"].discharge_mw,0,"no battery cycling")
	# Oil source must be shared by hot-water delivery and Rankine, never duplicated.
	var mixed := ds();mixed[2]=dev(3,"parabolic_trough",{"aperture_area_m2":500.0})
	mixed.append(dev(9,"oil_water_exchanger"));mixed.append(dev(10,"heat_exchanger"));mixed.append(dev(11,"heat_demand",{"priority":5}))
	var mixed_l := ls();mixed_l.append(el(2,3,"out","ac_in"));mixed_l.append(el(2,9,"out","ac_in"))
	mixed_l.append({"from":3,"to":9,"from_port":"heat_out","to_port":"hot_in","carrier":"heat_oil","unit":"MWth","grade_id":"oil_300_200","capacity_mwth":1.0,"loss_fraction":0.0})
	mixed_l.append({"from":9,"to":10,"from_port":"warm_out","to_port":"hot_in","carrier":"heat_water","unit":"MWth","grade_id":Catalog.PRIMARY_GRADE,"capacity_mwth":1.0,"loss_fraction":0.0})
	mixed_l.append({"from":10,"to":11,"from_port":"warm_out","to_port":"heat_in","carrier":"heat_water","unit":"MWth","grade_id":Catalog.SECONDARY_GRADE,"capacity_mwth":1.0,"loss_fraction":0.0})
	var weather := {"air_temp_c":25.0,"dni_wm2":800.0,"solar_altitude_deg":90.0,"solar_azimuth_deg":180.0,"is_day":true}
	var mix_report := Model.dispatch(mixed,mixed_l,weather,{"1":{"mw":.1}},3600)
	check(mix_report.valid,"mixed heat+Rankine " + str(mix_report.errors))
	check(Model.audit_dispatch(mixed,mixed_l,mix_report,{},weather).is_empty(),"mixed independent replay")
	near(mix_report.high_temp.useful_mwth,mix_report.rankine.oil_input_mwth+mix_report.devices["9"].input_mwth,"shared oil no double counting")
	near(mix_report.thermal.served_mwth,.1*.98*.98,"old heat service retained")
	check(mix_report.rankine.gross_electric_mw>0,"mixed Rankine runs")
	var paused_solar := Model.dispatch(mixed,mixed_l,weather,{"1":{"mw":.1}},0)
	check(paused_solar.valid,"paused direct trough cycle audit")
	near(paused_solar.rankine.mass_flow_kg_s,0,"direct trough Rankine pauses without inventory")
	# Cross-cycle electricity cannot provide a new source of auxiliary power.
	var doubled := ds();var doubled_l := ls()
	for item in ds():
		if int(item.id) in [3,4,5,6,7]:
			var copy: Dictionary = item.duplicate(true);copy.id += 20;doubled.append(copy)
	for edge in ls():
		if int(edge.from) in [3,4,5,6,7] or int(edge.to) in [3,4,5,6,7]:
			var copy: Dictionary=edge.duplicate(true)
			if int(copy.from)!=2:copy.from+=20
			if int(copy.to)!=2:copy.to+=20
			doubled_l.append(copy)
	r=run_case(doubled,doubled_l,0)
	near(r.rankine.gross_electric_mw,0,"two loops cannot cross-bootstrap")
	# A unique-port eight-device cross-loop is not a supported closed four-device cycle.
	var crossed := doubled_l.duplicate(true)
	for edge in crossed:
		if edge.get("from_port","") == "feed_out": edge.to = 24 if int(edge.from)==7 else 4
	r=run_case(doubled,crossed,.01)
	near(r.rankine.mass_flow_kg_s,0,"eight-device crossed return stays dormant")
	near(r.rankine.auxiliary_electric_mw,0,"crossed loop no stranded auxiliary")
	# JSON preserves numeric value while parsing IDs as floats: normalize before keys.
	var restored_d: Array = JSON.parse_string(JSON.stringify(d))
	var restored_l: Array = JSON.parse_string(JSON.stringify(l))
	r=run_case(restored_d,restored_l)
	check(r.rankine.gross_electric_mw>0,"JSON-restored float IDs dispatch and audit")
	var false_source := r.duplicate(true)
	false_source.lines[4].flow_from=1
	check(not Model.audit_dispatch(restored_d,restored_l,false_source,{}, {"air_temp_c":25.0}).is_empty(),"reject turbine source relabel as external wind")
	var old := Model.dispatch([dev(1,"wind"),dev(2,"station")],[el(1,2)],{}, {"1":{"mw":.1}},3600)
	check(not old.has("rankine"),"no new ledger on old scenario")
	# Source scaling is linear per bounded trial, not an auxiliary Cartesian product.
	var large := ds()
	var large_l := ls()
	var direct := {"1":{"mw":.0002}}
	for i in 128:
		var id: int = 100+i
		large.append(dev(id,"wind"));large_l.append(el(id,2));direct[str(id)]={"mw":.000001}
	var started: int = Time.get_ticks_usec()
	var large_r := Model.dispatch(large,large_l,{"air_temp_c":25.0},direct,3600)
	var elapsed: int = Time.get_ticks_usec()-started
	check(large_r.valid,"many-source atomic flow " + str(large_r.errors))
	check(large_r.rankine.gross_electric_mw>0,"split auxiliaries across many sources")
	check(Model.audit_dispatch(large,large_l,large_r,{}, {"air_temp_c":25.0}).is_empty(),"many-source independent conservation")
	check(elapsed<5000000,"bounded-source-planner elapsed " + str(elapsed))
	print("RANKINE_SOURCE_BENCHMARK: 129 external sources, elapsed_us=" + str(elapsed))
	print("RANKINE_DISPATCH_TESTS: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
