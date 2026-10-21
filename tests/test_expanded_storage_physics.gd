extends SceneTree
## Pure finite-inventory regression for expanded storage. No live save or GUI.
const C = preload("res://scripts/device_catalog.gd")
const M = preload("res://scripts/energy_model.gd")
const V = preload("res://scripts/save_validator.gd")
const Old = preload("res://tests/test_high_temp_catalog.gd")
const OldElectric = preload("res://tests/test_storage_save.gd")
const R = preload("res://scripts/rankine_cycle.gd")
const T = preload("res://scripts/solar_tower_thermal.gd")
const Opt = preload("res://scripts/optimization_controller.gd")
const TowerFixture = preload("res://tests/test_tower_runtime.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("EXPANDED_STORAGE_FAIL: " + label)
func near(a: float, b: float, label: String) -> void:
	check(is_finite(a) and absf(a-b) < 2e-7 * maxf(1.0, absf(b)), label + " " + str(a) + " != " + str(b))
func device(id: int, kind: String, params: Dictionary = {}) -> Dictionary:
	var p: Dictionary = C.defaults(kind)
	p.merge(params, true)
	var d := {"id":id,"kind":kind,"params":p}
	if C.is_storage(kind): d.state = C.initial_state(kind, p)
	if C.is_thermal(kind): d.model_profile = C.model_profile(kind)
	return d
func cable(a: int, b: int, fp: String = "out", tp: String = "in", loss: float = 0.0, cap: float = 20.0) -> Dictionary:
	return {"from":a,"to":b,"from_port":fp,"to_port":tp,"carrier":C.CARRIER,"unit":"MW","capacity_mw":cap,"loss_fraction":loss}
func heat(a: int, b: int, fp: String = "heat_out", tp: String = "hot_in") -> Dictionary:
	return {"from":a,"to":b,"from_port":fp,"to_port":tp,"carrier":C.THERMAL_CARRIER,"unit":"MWth","grade_id":C.SECONDARY_GRADE if fp == "warm_out" else C.PRIMARY_GRADE,"capacity_mwth":10.0,"loss_fraction":0.0}
func run_case(ds: Array, ls: Array, power: float, seconds: float = 3600.0) -> Dictionary:
	var before := JSON.stringify([ds,ls])
	var r: Dictionary = M.dispatch(ds,ls,{}, {"1":{"mw":power}},seconds)
	check(r.valid,"valid dispatch: " + str(r.errors) + str(r.warnings))
	check(JSON.stringify([ds,ls]) == before,"pure original inputs")
	var audit := M.audit_dispatch(ds,ls,r)
	check(audit.is_empty(),"independent audit: " + str(audit))
	near(r.balance_error_mw,0.0,"AC energy flow conservation")
	near(r.energy_balance_error_mwh,0.0,"finite electric inventory conservation")
	near(r.thermal.energy_balance_error_mwhth,0.0,"finite thermal inventory conservation")
	return r
func electric_devices(kind: String, soc: float = 0.0) -> Array:
	return [device(1,"wind"),device(2,"station",{"capacity_mw":20.0,"loss_fraction":0.0}),device(3,kind,{"initial_soc":soc,"self_discharge_per_h":0.0}),device(4,"load",{"demand_mw":0.0})]
func electric_links(reverse: bool = false) -> Array:
	return [cable(1,2),cable(3,2,"ac","in") if reverse else cable(2,3,"out","ac"),cable(2,4),cable(2,-1)]
func catalog_checks() -> void:
	for kind in C.NEW_STORAGE_KINDS:
		check(C.implemented_kinds().count(kind) == 1,"catalog unique " + kind)
		check(M.validate(kind,{}).is_empty(),"valid defaults " + kind)
		check(not C.storage_technology(kind).assumptions.is_empty(),"explicit assumptions " + kind)
		var field: String = "energy_mwhth" if C.is_thermal_storage(kind) else "energy_mwh"
		near(C.initial_state(kind)[field],0.0,"empty initial inventory " + kind)
		for key in C.defaults(kind):
			for bad in [NAN,INF,true,"1",null]:
				check(not M.validate(kind,{key:bad}).is_empty(),"reject malformed " + kind + "/" + key)
		for bad in [-1.0,NAN,INF,true,"1",null]:
			check(not C.validate_state(kind,{}, {field:bad}).is_empty(),"reject bad inventory " + kind)
		check(not C.validate_state(kind,{}, {field:0.0,"extra":0.0}).is_empty(),"reject unknown inventory")
	check(not M.validate("caes_aboveground",{"capacity_mwh":10.01}).is_empty(),"aboveground capacity guardrail")
	check(not M.validate("caes_aboveground",{"charge_mw":2.01}).is_empty(),"aboveground power guardrail")
	check(not C.implemented_kinds().has("caes_underground"),"no underground equipment")
	check(C.implemented_kinds().count("molten_salt_store") == 1,"reuse existing molten salt kind")
	near(C.initial_state("battery").energy_mwh,5.0,"legacy lithium default inventory unchanged")
	check(C.ports("solid_thermal_store").all(func(p): return p.carrier == C.THERMAL_CARRIER),"solid has no electric generation port")
func electric_checks() -> void:
	for kind in C.ELECTRIC_STORAGE_KINDS:
		for reverse in [false,true]:
			var ds := electric_devices(kind)
			var ls := electric_links(reverse)
			var p: Dictionary = ds[2].params
			var r := run_case(ds,ls,5.0)
			var q: float = minf(5.0,minf(p.charge_mw,p.capacity_mwh / p.charge_efficiency))
			near(r.charge_mw,q,"rated charge " + kind)
			near(r.next_states["3"].energy_mwh,q * p.charge_efficiency,"charge efficiency " + kind)
			near(r.discharge_mw,0.0,"one mode charging")
			near(r.devices["3"].charge_conversion_loss_mw,q * (1.0 - p.charge_efficiency),"charge stage loss")
			ds[2].state = r.next_states["3"].duplicate(true)
			ds[3].params.demand_mw = 5.0
			r = run_case(ds,ls,0.0)
			var out: float = minf(p.discharge_mw,ds[2].state.energy_mwh*p.discharge_efficiency)
			near(r.discharge_mw,out,"rated finite discharge " + kind)
			near(r.next_states["3"].energy_mwh,ds[2].state.energy_mwh-out/p.discharge_efficiency,"discharge inventory " + kind)
			near(r.delivered_mw,0.0,"no storage export")
			near(r.devices["3"].discharge_conversion_loss_mw,out * (1.0/p.discharge_efficiency-1.0),"discharge stage loss")
			var forged: Dictionary = r.duplicate(true)
			forged.devices["3"].discharge_conversion_loss_mw += 0.1
			check(not M.audit_dispatch(ds,ls,forged).is_empty(),"reject fabricated stage loss")
			r = run_case(ds,ls,5.0,0.0)
			near(r.charge_mw+r.discharge_mw,0.0,"paused exchange frozen")
			near(r.next_states["3"].energy_mwh,ds[2].state.energy_mwh,"paused inventory frozen")
			ds[2].state.energy_mwh = 0.0
			r = run_case(ds,ls,0.0)
			near(r.discharge_mw,0.0,"empty cannot invent power")
			ds[2].state.energy_mwh = p.capacity_mwh
			ds[3].params.demand_mw = 0.0
			r = run_case(ds,ls,5.0)
			near(r.charge_mw,0.0,"full cannot overcharge")
			ds[2].params.self_discharge_per_h = 0.01
			r = run_case(ds,[],0.0,7200.0)
			near(r.next_states["3"].energy_mwh,p.capacity_mwh*exp(-0.02),"disconnected exact decay")
			var snap := M.optimization_snapshot(ds,ls,{}, {},3600.0)
			check(snap.valid,"valid storage snapshot")
			check(snap.initial_states.has("3"),"snapshot finite initial state")
			check(snap.edges[1].bidirectional,"snapshot reversible cable")
			if kind != "battery": check(snap.schema_version == 7,"extension schema7")
		# Two different stores cannot transfer/round-trip from one another.
		var ds := electric_devices(kind,1.0)
		ds.append(device(5,"battery_sodium"))
		var ls := electric_links(); ls.append(cable(2,5,"out","ac"))
		var r := run_case(ds,ls,0.0)
		near(r.charge_mw+r.discharge_mw,0.0,"no cross-technology cycling")
		# Shared cable/station bottlenecks still apply to reverse flow.
		ds[3].params.demand_mw = 5.0
		ls[1].capacity_mw = 0.03; ls[1].loss_fraction = 0.1
		r = run_case(ds,ls,0.0)
		near(r.discharge_mw,0.03,"shared discharge line cap")
		near(r.served_mw,0.027,"sending-side cap and loss")
func hydrogen_checks() -> void:
	var ds := electric_devices("hydrogen_storage_system")
	var ls := electric_links()
	var r := run_case(ds,ls,2.0)
	near(r.devices["3"].hydrogen_produced_mw_lhv,1.3,"electrolyzer net H2 LHV")
	near(r.devices["3"].hydrogen_charge_loss_mw,0.7,"electrolysis compression loss")
	near(r.devices["3"].hydrogen_mass_kg,1300.0/33.33,"explicit LHV mass")
	ds[2].state = r.next_states["3"].duplicate(true); ds[3].params.demand_mw = 2.0
	r = run_case(ds,ls,0.0)
	near(r.discharge_mw,0.65,"no-loss-wait hydrogen roundtrip 32.5 percent")
	near(r.devices["3"].hydrogen_consumed_mw_lhv,1.3,"fuel-cell LHV withdrawal")
	near(r.devices["3"].hydrogen_discharge_loss_mw,0.65,"fuel-cell inverter loss")
	for field in ["hydrogen_mass_kg","hydrogen_produced_mw_lhv","hydrogen_consumed_mw_lhv","hydrogen_charge_loss_mw","hydrogen_discharge_loss_mw"]:
		var bad := r.duplicate(true); bad.devices["3"][field] += 0.1
		check(not M.audit_dispatch(ds,ls,bad).is_empty(),"independent hydrogen field " + field)
func adversarial_checks() -> void:
	var ds := electric_devices("hydrogen_storage_system",1.0)
	ds[3].params.demand_mw = 0.1
	var ls := electric_links()
	var r := run_case(ds,ls,0.0)
	for field in ["storage_loss_mw","storage_conversion_loss_mw","self_discharge_mwh"]:
		var bad := r.duplicate(true); bad[field] += 0.1
		check(not M.audit_dispatch(ds,ls,bad).is_empty(),"forged aggregate inventory loss rejected " + field)
	# Conserve every node/energy equation while redirecting real storage output
	# from the served load to an actual grid edge. Provenance must still reject.
	var bad := r.duplicate(true)
	var power: float = bad.served_mw
	bad.served_mw=0.0; bad.unserved_mw=power; bad.delivered_mw=power
	for field in ["input_mw","received_mw","served_mw"]: bad.devices["4"][field]=0.0
	bad.devices["4"].unserved_mw=power
	for field in ["sent_mw","received_mw","signed_mw"]:
		bad.lines[2][field]=0.0; bad.lines[3][field]=power
	var errors: Array = M.audit_dispatch(ds,ls,bad)
	check("storage cannot supply" in str(errors),"even energy-conserving storage export is rejected by original-source provenance")
func thermal_checks() -> void:
	var ds: Array = [device(1,"wind"),device(2,"station",{"loss_fraction":0.0}),device(3,"electric_boiler"),device(4,"solid_thermal_store",{"self_discharge_per_h":0.0}),device(5,"heat_exchanger"),device(6,"heat_demand",{"demand_mwth":0.0})]
	var ls: Array = [cable(1,2),cable(2,3,"out","ac_in"),heat(3,4,"heat_out","heat_in"),heat(4,5),heat(5,6,"warm_out","heat_in")]
	var r := run_case(ds,ls,2.0)
	near(r.thermal.charge_mwth,1.96,"electric boiler charges solid via heat only")
	near(r.next_states["4"].energy_mwhth,1.96*0.95,"solid heat storage efficiency")
	ds[3].state = r.next_states["4"].duplicate(true); ds[5].params.demand_mwth = 1.0
	r = run_case(ds,ls,0.0)
	near(r.thermal.discharge_mwth,1.0,"solid power rating")
	near(r.thermal.served_mwth,0.98,"fixed-grade exchanger loss")
	near(r.discharge_mw,0.0,"solid not electric generation")
	check(not C.validate_link(ds,[],cable(4,2,"ac","in")).is_empty(),"no solid electric connector")
	var wrong := heat(4,6,"heat_out","heat_in")
	check(not C.validate_link(ds,[],wrong).is_empty(),"solid primary grade cannot directly feed secondary demand")
	r = run_case(ds,ls,2.0,0.0)
	near(r.thermal.charge_mwth+r.thermal.discharge_mwth,0.0,"paused thermal exchange")
func mixed_tower_checks() -> void:
	# Every electric technology can supply essential external auxiliary power.
	var fixture := TowerFixture.new()
	for kind in C.ELECTRIC_STORAGE_KINDS:
		var ds: Array = fixture.ds(); var ls: Array = fixture.ls()
		ds[0] = device(1,kind,{"initial_soc":1.0,"self_discharge_per_h":0.0})
		ls[0].from_port = "ac"
		var w: Dictionary = fixture.weather(false)
		var r: Dictionary = M.dispatch(ds,ls,w,{},3600.0)
		check(r.valid,"tower auxiliary " + kind + str(r.errors) + str(r.warnings))
		check(r.rankine.gross_electric_mw>0.0,"stored electric auxiliary runs salt cycle " + kind)
		check(M.audit_dispatch(ds,ls,r,{},w).is_empty(),"mixed cycle audit " + kind)
	fixture.free()
func blank(schema: int) -> Dictionary:
	var old := Old.new(); var s: Dictionary = old.blank(); old.free()
	s.schema = schema; s.model_version = 22 if schema == 13 else 21
	s.rankine_energy = R.initial_energy(); s.tower_energy = T.initial_energy()
	for kind in C.implemented_kinds():
		if schema == 13 or not kind in C.NEW_STORAGE_KINDS: s.templates[kind] = C.defaults(kind)
	return s
func save_checks() -> void:
	var old := OldElectric.new()
	check(V.validate(old.fixture()).is_empty(),"legacy schema4 lithium state unchanged")
	check(V.validate(old.legacy_fixture()).is_empty(),"legacy schema3 unchanged")
	old.free()
	var s := blank(12); var encoded := JSON.stringify(s)
	check(V.validate(s).is_empty(),"legacy schema12 template set: " + V.validate(s))
	check(JSON.stringify(s) == encoded,"legacy validator pure")
	s.templates.battery_sodium = C.defaults("battery_sodium")
	check(not V.validate(s).is_empty(),"legacy schema rejects expanded storage")
	s = blank(13)
	check(V.validate(s).is_empty(),"schema13 full catalog: " + V.validate(s))
	for kind in C.NEW_STORAGE_KINDS + ["molten_salt_store"]:
		s = blank(13)
		var d := device(0,kind); d.x = -40.0; d.z = -40.0
		s.devices = [d]; s.next_id = 1
		check(V.validate(s).is_empty(),"standalone save " + kind + ": " + V.validate(s))
		encoded = JSON.stringify(s)
		check(V.validate(JSON.parse_string(encoded)).is_empty(),"expanded save roundtrip " + kind)
		check(JSON.stringify(s) == encoded,"save validation no mutation " + kind)
		s.devices[0].erase("state")
		check(not V.validate(s).is_empty(),"cannot silently restore default inventory " + kind)
	check(V._validate_station_link({"kind":"solar_tower_receiver","parent_station_id":1000000},{"kind":"molten_salt_store"}).is_empty(),"tower to external salt boundary")
	check(V._validate_station_link({"kind":"molten_salt_store"},{"kind":"salt_steam_generator","parent_station_id":1000000}).is_empty(),"external salt to SG boundary")
	check(V._validate_station_link({"kind":"solid_thermal_store"},{"kind":"heat_exchanger","parent_station_id":1000000}).is_empty(),"external solid to HX boundary")
	check(not V._validate_station_link({"kind":"solar_tower_receiver","parent_station_id":1000000},{"kind":"molten_salt_store","parent_station_id":1000001}).is_empty(),"unrelated internal crossing still blocked")
func baseline_checks() -> void:
	var controller := Opt.new()
	for kind in C.ELECTRIC_STORAGE_KINDS:
		var ds := electric_devices(kind)
		var data: Dictionary = {"devices":ds,"links":electric_links(),"steps":[
			{"time_s":0.0,"dt_h":1.0,"available_mw":{"1":5.0},"demand_mw":{"4":0.0},"heat_demand_mwth":{}},
			{"time_s":3600.0,"dt_h":1.0,"available_mw":{"1":0.0},"demand_mw":{"4":5.0},"heat_demand_mwth":{}}]}
		var before := JSON.stringify(data)
		var baseline: Dictionary = controller.make_baseline(data)
		check(not baseline.has("error"),"forecast baseline accepts " + kind)
		check(JSON.stringify(data)==before,"forecast does not mutate live inputs")
		if baseline.has("error"): continue
		check(baseline.steps[0].charge_mw>0.0,"forecast charges " + kind)
		check(baseline.steps[1].discharge_mw>0.0,"forecast retains next inventory " + kind)
		near(baseline.steps[1].devices["3"].energy_before_mwh,baseline.steps[0].devices["3"].next_energy_mwh,"forecast exact carry " + kind)
	controller.free()
func _initialize() -> void:
	catalog_checks()
	electric_checks()
	hydrogen_checks()
	adversarial_checks()
	thermal_checks()
	mixed_tower_checks()
	baseline_checks()
	save_checks()
	print("EXPANDED_STORAGE_PHYSICS: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
