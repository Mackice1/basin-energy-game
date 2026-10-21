extends SceneTree
## godot --headless --path . --script tests/test_network_dispatch.gd
const Model = preload("res://scripts/energy_model.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("NETWORK_DISPATCH_FAIL: " + label)

func near(a: float, b: float, label: String, tolerance: float = 1.0e-7) -> void:
	check(is_finite(a) and absf(a-b) <= tolerance, "%s: %.12f vs %.12f" % [label, a, b])

func dev(id: int, kind: String, params: Dictionary = {}, state: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"id": id, "kind": kind, "params": params}
	if kind == "battery":
		d.state = state if not state.is_empty() else Catalog.initial_state(kind, params)
	return d

func line(a: int, b: int, cap: float = 100.0, loss: float = 0.0) -> Dictionary:
	return {"from": a, "to": b, "capacity_mw": cap, "loss_fraction": loss}

func base_devices(energy: float = 0.0) -> Array:
	return [dev(1, "wind"), dev(2, "wind"), dev(3, "station", {"capacity_mw": 20.0, "loss_fraction": 0.0}),
		dev(4, "load", {"demand_mw": 6.0}), dev(5, "battery", {}, {"energy_mwh": energy})]

func base_links() -> Array:
	return [line(1,3), line(2,3), line(3,4), line(5,3)]

func invariants(r: Dictionary, label: String) -> void:
	near(r.balance_error_mw, 0.0, label + " AC power conservation", 2.0e-7)
	near(r.storage_balance_error_mwh, 0.0, label + " storage state conservation", 2.0e-7)
	near(r.energy_balance_error_mwh, 0.0, label + " combined energy conservation", 2.0e-7)
	check(not r.optimal and r.dispatch_policy == "priority_then_stable_id", label + " no optimality claim")
	for key in ["generated_mw", "delivered_mw", "curtailed_mw", "served_mw", "unserved_mw", "charge_mw", "discharge_mw", "storage_loss_mw", "loss_mw"]:
		check(is_finite(r[key]) and r[key] >= -1.0e-8, label + " finite nonnegative " + key)
	check(r.delivered_mw <= 4.0 + 1.0e-7, label + " grid cap")
	for l in r.lines:
		check(l.sent_mw <= l.capacity_mw + 1.0e-7, label + " line cap")
		near(l.sent_mw - l.received_mw, l.loss_mw, label + " line loss")
		if not l.valid:
			near(l.sent_mw, 0.0, label + " rejected edge inactive")
	for id in r.devices:
		var d: Dictionary = r.devices[id]
		if not d.valid:
			continue
		match d.kind:
			"wind", "pv":
				near(d.mw, d.sent_mw + d.curtailed_mw, label + " renewable cap")
			"load":
				near(d.demand_mw, d.served_mw + d.unserved_mw, label + " demand balance")
			"station":
				check(d.input_mw <= d.capacity_mw + 1.0e-7, label + " station capacity")
				near(d.input_mw-d.output_mw, d.loss_mw, label + " station loss")
			"battery":
				check(d.charge_mw <= d.charge_limit_mw + 1.0e-7 and d.discharge_mw <= d.discharge_limit_mw + 1.0e-7, label + " storage limits")
				check(d.charge_mw <= 1.0e-9 or d.discharge_mw <= 1.0e-9, label + " mutually exclusive modes")
				check(d.next_energy_mwh >= -1.0e-9 and d.next_energy_mwh <= d.capacity_mwh + 1.0e-9, label + " bounded storage")
				near(r.next_states[id].energy_mwh, d.next_energy_mwh, label + " state return")

func _initialize() -> void:
	_test_catalog()
	_test_acceptance()
	_test_islands_priority()
	_test_loss_capacity()
	_test_storage()
	_test_purity_time()
	_test_snapshot()
	_test_invalid_inputs()
	_test_random()
	print("NETWORK_DISPATCH_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_catalog() -> void:
	for kind in Catalog.implemented_kinds():
		check(Model.validate(kind, Model.defaults(kind)).is_empty(), kind + " defaults valid")
		for p in Catalog.ports(kind):
			if p.carrier=="electricity_ac":
				check(p.unit=="MW" and p.voltage_level=="AC_BUS","typed AC ports")
			else:
				check((p.carrier=="water_steam" and p.unit=="kg/s" and p.grade_id in ["rankine_live_v1","rankine_exhaust_v1","rankine_condensate_v1","rankine_feedwater_v1"]) or (p.unit=="MWth" and ((p.carrier=="heat_water" and p.grade_id in ["hw_primary_90_60","hw_secondary_70_40"]) or (p.carrier=="heat_oil" and p.grade_id=="oil_300_200") or (p.carrier=="heat_salt" and p.grade_id=="salt_565_290"))),"typed thermal ports")
	check(Catalog.ports("hydrogen").is_empty(), "unimplemented carrier not runnable")
	check(Catalog.port("battery", "ac").direction == "bidirectional", "battery terminal bidirectional")
	for bad in [NAN, INF, -1.0, "2", true, null]:
		check(not Model.validate("load", {"demand_mw": bad}).is_empty(), "invalid demand")
		check(not Model.validate("battery", {"capacity_mwh": bad}).is_empty(), "invalid storage capacity")
	for bad in [0, -1.0, 1.01, INF, NAN]:
		check(not Model.validate("battery", {"charge_efficiency": bad}).is_empty(), "invalid charge efficiency")
		check(not Model.validate("battery", {"discharge_efficiency": bad}).is_empty(), "invalid discharge efficiency")
	check(not Model.validate("load", {"priority": 1.5}).is_empty(), "integer priority")
	check(not Model.validate("battery", {"imaginary": 1.0}).is_empty(), "unknown storage key")
	check(not Model.validate("battery", {"initial_soc": 1.1}).is_empty(), "SOC initial range")
	check(not Model.validate("battery", {"self_discharge_per_h": -0.1}).is_empty(), "self loss nonnegative")
	var ds: Array = base_devices()
	check(Catalog.validate_topology(ds, base_links()).is_empty(), "minimal star valid")
	for bad in [line(1,1), line(1,4), line(4,3), line(3,1), line(3,99), line(-1,3), line(1,3,-1), line(1,3,1,1)]:
		check(not Catalog.validate_link(ds, [], bad).is_empty(), "invalid connection")
	for prop in [{"from_port":"ac"}, {"to_port":"out"}, {"carrier":"heat_low"}, {"unit":"kg/s"}, {"voltage_level":"OTHER"}]:
		var bad: Dictionary = line(1,3)
		bad.merge(prop, true)
		check(not Catalog.validate_link(ds, [], bad).is_empty(), "typed port validation")
	check(not Catalog.validate_link(ds, [line(5,3)], line(3,5)).is_empty(), "battery reverse duplicate rejected")
	ds.append(dev(6, "station"))
	check(not Catalog.validate_link(ds, [line(1,3)], line(1,6)).is_empty(), "generator two stations rejected")
	check(not Catalog.validate_link(ds, [line(3,4)], line(6,4)).is_empty(), "load two stations rejected")
	check(not Catalog.validate_link(ds, [line(5,3)], line(5,6)).is_empty(), "battery two stations rejected")
	check(not Catalog.validate_link(ds, [], line(3,6)).is_empty(), "station mesh rejected")

func _test_acceptance() -> void:
	var ds: Array = base_devices()
	var ls: Array = base_links()
	var r: Dictionary = Model.dispatch(ds, ls, {}, {"1":{"mw":5.0},"2":{"mw":5.0}}, 3600.0)
	near(r.generated_mw,10.0,"acceptance available")
	near(r.served_mw,6.0,"acceptance serve6")
	near(r.charge_mw,3.0,"acceptance charge3")
	near(r.curtailed_mw,1.0,"acceptance curtail1")
	near(r.next_states["5"].energy_mwh,2.7,"acceptance store2.7MWh")
	near(r.storage_loss_mw,0.3,"acceptance charge loss")
	check(r.devices["5"].mode == "charge", "charge mode")
	check(r.lines[3].flow_from == 3 and r.lines[3].flow_to == 5 and r.lines[3].direction == -1, "single battery cable reverse charge flow")
	invariants(r,"charge acceptance")
	ds[4].state = r.next_states["5"]
	r = Model.dispatch(ds,ls,{}, {"1":{"mw":0.0},"2":{"mw":0.0}},3600.0)
	near(r.discharge_mw,2.43,"acceptance discharge2.43")
	near(r.served_mw,2.43,"acceptance serve2.43")
	near(r.unserved_mw,3.57,"acceptance unmet3.57")
	near(r.next_states["5"].energy_mwh,0.0,"acceptance empty")
	near(r.storage_loss_mw,0.27,"acceptance discharge loss")
	check(r.lines[3].direction == 1 and r.devices["5"].mode == "discharge", "same cable discharge")
	invariants(r,"discharge acceptance")
	r = Model.dispatch(ds, ls + [line(3,-1)], {}, {"1":{"mw":5.0},"2":{"mw":5.0}},3600.0)
	near(r.delivered_mw,1.0,"explicit export after load and charge")
	near(r.curtailed_mw,0.0,"export reduces curtailment")
	invariants(r,"export acceptance")

func _test_islands_priority() -> void:
	var ds: Array = [dev(1,"wind"),dev(2,"station",{"capacity_mw":20.0,"loss_fraction":0.0}),
		dev(3,"station",{"capacity_mw":20.0,"loss_fraction":0.0}),dev(4,"load",{"demand_mw":2.0})]
	var r: Dictionary = Model.dispatch(ds,[line(1,2),line(3,4)],{}, {"1":{"mw":5.0}},3600.0)
	near(r.served_mw,0.0,"island cannot supply other station")
	near(r.curtailed_mw,5.0,"island curtailment")
	near(r.loss_mw,0.0,"no phantom island losses")
	ds.append(dev(5,"load",{"demand_mw":4.0,"priority":1}))
	ds.append(dev(6,"battery",{}, {"energy_mwh":5.0}))
	r = Model.dispatch(ds,[line(1,2),line(2,4),line(2,5),line(6,2)],{}, {"1":{"mw":3.0}},3600.0)
	near(r.devices["5"].served_mw,4.0,"critical first using renewable and battery")
	near(r.devices["4"].served_mw,2.0,"normal remainder")
	near(r.discharge_mw,3.0,"discharge cap split loads")
	near(r.charge_mw,0.0,"cannot recharge discharged battery")
	invariants(r,"priority")
	ds[3].params.priority = 1
	r = Model.dispatch(ds,[line(1,2),line(2,4),line(2,5)],{}, {"1":{"mw":3.0}},3600.0)
	near(r.devices["4"].served_mw,2.0,"equal priority lower ID first")
	near(r.devices["5"].served_mw,1.0,"equal priority higher ID remainder")
	r = Model.dispatch([dev(1,"battery",{}, {"energy_mwh":10.0}),dev(2,"station",{"loss_fraction":0.0})],[line(1,2),line(2,-1)],{}, {},3600.0)
	near(r.discharge_mw,0.0,"battery never discharges just for export")
	near(r.delivered_mw,0.0,"no export without renewable")

func _test_loss_capacity() -> void:
	var ds: Array = [dev(1,"wind"),dev(2,"station",{"capacity_mw":20.0,"loss_fraction":0.1}),dev(3,"load",{"demand_mw":10.0})]
	var ls: Array = [line(1,2,100.0,0.1),line(2,3,100.0,0.1)]
	var r: Dictionary = Model.dispatch(ds,ls,{}, {"1":{"mw":3.0}},3600.0)
	near(r.served_mw,3.0*pow(0.9,3),"three serial losses in delivered service")
	near(r.lines[0].sent_mw,3.0,"generator terminal input")
	near(r.lines[0].received_mw,2.7,"station input after line loss")
	invariants(r,"loss path")
	ds[2].params.demand_mw = 1.0
	r = Model.dispatch(ds,ls,{}, {"1":{"mw":3.0}},3600.0)
	near(r.devices["1"].sent_mw,1.0/pow(0.9,3),"demand propagates loss upstream")
	near(r.served_mw,1.0,"limited demand")
	ds[2].params.demand_mw = 10.0
	ls[0].capacity_mw = 1.0
	r = Model.dispatch(ds,ls,{}, {"1":{"mw":5.0}},3600.0)
	near(r.served_mw,pow(0.9,3),"input line capacity")
	ls[0].capacity_mw = 100.0
	ls[1].capacity_mw = 1.0
	r = Model.dispatch(ds,ls,{}, {"1":{"mw":5.0}},3600.0)
	near(r.served_mw,0.9,"output sending capacity")
	ds[1].params.capacity_mw = 0.5
	r = Model.dispatch(ds,ls,{}, {"1":{"mw":5.0}},3600.0)
	near(r.served_mw,0.405,"station input capacity")
	invariants(r,"all bottlenecks")

func _test_storage() -> void:
	var ds: Array = base_devices(9.9)
	var r: Dictionary = Model.dispatch(ds,base_links(),{}, {"1":{"mw":5.0},"2":{"mw":5.0}},3600.0)
	near(r.charge_mw,0.1/0.9,"full boundary charge limited")
	near(r.next_states["5"].energy_mwh,10.0,"exact full")
	invariants(r,"almost full")
	ds[4].state.energy_mwh = 10.0
	r = Model.dispatch(ds,base_links(),{}, {"1":{"mw":5.0},"2":{"mw":5.0}},3600.0)
	near(r.charge_mw,0.0,"full battery consumes no power")
	ds[4].state.energy_mwh = 0.0
	r = Model.dispatch(ds,base_links(),{}, {},3600.0)
	near(r.discharge_mw,0.0,"empty battery creates no power")
	ds[4].state.energy_mwh = 5.0
	ds[4].params.self_discharge_per_h = 0.1
	r = Model.dispatch(ds,[],{}, {},3600.0)
	near(r.next_states["5"].energy_mwh,5.0*exp(-0.1),"continuous self discharge")
	near(r.self_discharge_mwh,5.0*(1.0-exp(-0.1)),"self loss explicit")
	invariants(r,"disconnected self loss")
	var battery: Dictionary = dev(1,"battery",{}, {"energy_mwh":2.0})
	var bad_states: Array = [{"energy_mwh":-1.0},{"energy_mwh":11.0},{"energy_mwh":NAN},{"energy_mwh":"1"},{"energy_mwh":1.0,"junk":1.0},null]
	for state in bad_states:
		battery.state = state
		r = Model.dispatch([battery],[],{}, {},3600.0)
		check(not r.devices["1"].valid and not r.errors.is_empty(),"invalid battery state rejected")
		check(r.next_states.is_empty(),"invalid battery state not overwritten")
	battery.erase("state")
	r = Model.dispatch([battery],[],{}, {},3600.0)
	near(r.next_states["1"].energy_mwh,5.0,"absent state initialization only")

func _test_purity_time() -> void:
	var ds: Array = base_devices(1.0)
	var ls: Array = base_links()
	var direct: Dictionary = {"1":{"mw":5.0},"2":{"mw":5.0}}
	var before: String = JSON.stringify([ds,ls,direct])
	var r: Dictionary = Model.dispatch(ds,ls,{},direct,3600.0)
	check(JSON.stringify([ds,ls,direct]) == before,"dispatch never mutates input")
	var r2: Dictionary = Model.dispatch(ds,ls,{},direct,3600.0)
	check(JSON.stringify(r) == JSON.stringify(r2),"repeat dispatch deterministic")
	ds.reverse()
	ls.reverse()
	r2 = Model.dispatch(ds,ls,{},direct,3600.0)
	for key in ["served_mw","charge_mw","discharge_mw","curtailed_mw","loss_mw"]:
		near(r2[key],r[key],"input reorder stable " + key)
	near(r2.next_states["5"].energy_mwh,r.next_states["5"].energy_mwh,"reordered battery state")
	ds = base_devices(1.0)
	var half: Dictionary = Model.dispatch(ds,base_links(),{},direct,1800.0)
	ds[4].state = half.next_states["5"]
	half = Model.dispatch(ds,base_links(),{},direct,1800.0)
	near(half.next_states["5"].energy_mwh,r.next_states["5"].energy_mwh,"split fixed charge timestep")
	ds = base_devices(1.0)
	for dt in [0.0,-1.0,NAN,INF]:
		r = Model.dispatch(ds,base_links(),{},direct,dt)
		near(r.next_states["5"].energy_mwh,1.0,"zero/invalid dt preserves SOC")
		near(r.charge_mw,0.0,"zero/invalid dt no charge")
		near(r.discharge_mw,0.0,"zero/invalid dt no discharge")
		check(r.step_valid == (dt == 0.0),"invalid dt signaled")
		invariants(r,"guard dt " + str(dt))

func _test_snapshot() -> void:
	var ds: Array = base_devices(2.0)
	var ls: Array = base_links()
	var before: String = JSON.stringify([ds,ls])
	var s: Dictionary = Model.optimization_snapshot(ds,ls,{}, {"1":{"mw":5.0}},3600.0,{"request_id":"test","scene_revision":7,"simulation_time":12.0})
	check(s.status == "snapshot_only" and not s.solver_invoked,"snapshot invokes no solver")
	check(s.valid and s.scene_revision == 7 and s.request_id == "test","snapshot revision metadata")
	near(s.initial_states["5"].energy_mwh,2.0,"snapshot captures exact current SOC")
	check(s.constraints.storage_modes_mutually_exclusive,"snapshot includes exclusivity")
	check(not s.constraints.paths.is_empty() and not s.constraints.resource_limits.is_empty(),"snapshot uses explicit path capacities")
	check(s.edges.size() == 4 and s.ports.size() >= 6,"snapshot explicit edges and typed ports")
	check(JSON.stringify([ds,ls]) == before,"snapshot leaves input unchanged")
	check(JSON.parse_string(JSON.stringify(s)) is Dictionary,"snapshot JSON exportable")
	var broken: Dictionary = Model.optimization_snapshot(ds,[line(1,4)],{}, {},1.0)
	check(not broken.valid and broken.edges.is_empty(),"invalid topology cannot masquerade as solver input")

func _test_random() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 246810
	for trial in 150:
		var ds: Array = []
		var ls: Array = []
		var direct: Dictionary = {}
		for station in range(1,4):
			var sid: int = station*100
			ds.append(dev(sid,"station",{"capacity_mw":rng.randf_range(0.1,15.0),"loss_fraction":rng.randf_range(0.0,0.3)}))
			for j in range(1,4):
				ds.append(dev(sid+j,"wind"))
				direct[str(sid+j)] = {"mw":rng.randf_range(0.0,6.0)}
				if rng.randf()>0.1:
					ls.append(line(sid+j,sid,rng.randf_range(0.0,6.0),rng.randf_range(0.0,0.2)))
			for j in range(4,7):
				ds.append(dev(sid+j,"load",{"demand_mw":rng.randf_range(0.0,5.0),"priority":rng.randi_range(0,3)}))
				if rng.randf()>0.1:
					ls.append(line(sid,sid+j,rng.randf_range(0.0,5.0),rng.randf_range(0.0,0.2)))
			for j in range(7,9):
				ds.append(dev(sid+j,"battery",{"self_discharge_per_h":rng.randf_range(0.0,0.1),"charge_efficiency":rng.randf_range(0.5,1.0),"discharge_efficiency":rng.randf_range(0.5,1.0)}, {"energy_mwh":rng.randf_range(0.0,10.0)}))
				if rng.randf()>0.1:
					ls.append(line(sid+j,sid,rng.randf_range(0.0,5.0),rng.randf_range(0.0,0.2)) if trial%2 else line(sid,sid+j,rng.randf_range(0.0,5.0),rng.randf_range(0.0,0.2)))
			if rng.randf()>0.4:
				ls.append(line(sid,-1,rng.randf_range(0.0,5.0),rng.randf_range(0.0,0.2)))
		var dt: float = rng.randf_range(1.0,7200.0)
		var r: Dictionary = Model.dispatch(ds,ls,{},direct,dt)
		check(r.valid,"random valid "+str(trial))
		invariants(r,"random "+str(trial))
		ds.reverse()
		ls.reverse()
		var rr: Dictionary = Model.dispatch(ds,ls,{},direct,dt)
		for key in ["served_mw","charge_mw","discharge_mw","delivered_mw","curtailed_mw"]:
			near(r[key],rr[key],"random reordered "+key)

func _test_invalid_inputs() -> void:
	var ds: Array = base_devices(2.0)
	var r: Dictionary = Model.dispatch(ds,base_links()+[line(1,4)],{}, {"1":{"mw":5.0}},3600.0)
	check(not r.valid and r.step_valid and not r.warnings.is_empty(),"invalid topology diagnostics require valid gate before state commit")
	near(r.lines[-1].sent_mw,0.0,"illegal shortcut never transmits")
	invariants(r,"invalid edge safe subgraph")
	for malformed in [null,1,{}, {"from":"1","to":3},line(1,3,NAN),line(1,3,1.0,INF)]:
		r = Model.dispatch(ds,[malformed],{}, {"1":{"mw":5.0}},3600.0)
		check(not r.valid and not r.lines[0].valid,"malformed link report safe")
		invariants(r,"malformed line")
	r = Model.dispatch([null,{}, {"id":1.5},dev(3,"bogus"),{"id":4,"kind":"wind","params":null}],[],{})
	check(not r.valid and r.errors.size()==5,"malformed devices diagnosed")
	near(r.generated_mw,0.0,"malformed sources cannot generate")
	var no_recharge: Array = [dev(1,"station",{"loss_fraction":0.0}),dev(2,"battery",{}, {"energy_mwh":10.0}),dev(3,"battery",{}, {"energy_mwh":0.0})]
	r = Model.dispatch(no_recharge,[line(1,2),line(3,1)],{}, {},3600.0)
	near(r.charge_mw,0.0,"full battery cannot cycle into empty battery")
	near(r.discharge_mw,0.0,"battery-to-battery has no dispatch path")
	var battery: Dictionary = dev(1,"battery",{"self_discharge_per_h":0.5},{"energy_mwh":4.0})
	var whole: Dictionary = Model.dispatch([battery],[],{}, {},3600.0)
	var half: Dictionary = Model.dispatch([battery],[],{}, {},1800.0)
	battery.state = half.next_states["1"]
	half = Model.dispatch([battery],[],{}, {},1800.0)
	near(whole.next_states["1"].energy_mwh,half.next_states["1"].energy_mwh,"continuous self discharge timestep partition invariant")
