extends SceneTree
const Model = preload("res://scripts/energy_model.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("THERMAL_RUNTIME_FAIL: " + label)

func near(a: float, b: float, label: String, tol: float = 2.0e-7) -> void:
	check(is_finite(a) and absf(a - b) <= tol, "%s: %.12f != %.12f" % [label, a, b])

func dev(id: int, kind: String, params: Dictionary = {}, state: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"id": id, "kind": kind, "params": params}
	if kind in ["battery", "thermal_store"]:
		d.state = state if not state.is_empty() else Catalog.initial_state(kind, params)
	if Catalog.is_thermal(kind):
		d.model_profile = Catalog.model_profile(kind)
	return d

func el(a: int, b: int, cap: float = 100.0, loss: float = 0.0, boiler: bool = false) -> Dictionary:
	var edge: Dictionary = {"from": a, "to": b, "capacity_mw": cap, "loss_fraction": loss}
	if b == 3 or boiler:
		edge.merge({"from_port":"out", "to_port":"ac_in", "carrier":"electricity_ac", "unit":"MW"})
	return edge

func hl(a: int, b: int, from_port: String = "heat_out", to_port: String = "hot_in", cap: float = 100.0) -> Dictionary:
	return {"from": a, "to": b, "from_port": from_port, "to_port": to_port, "carrier": "heat_water", "unit": "MWth",
		"grade_id": Catalog.SECONDARY_GRADE if from_port == "warm_out" else Catalog.PRIMARY_GRADE, "capacity_mwth": cap, "loss_fraction": 0.0}

func devices() -> Array:
	return [dev(1, "wind"), dev(2, "station", {"capacity_mw": 20.0, "loss_fraction": 0.0}),
		dev(3, "electric_boiler"), dev(4, "heat_exchanger"), dev(5, "heat_demand", {"demand_mwth": 2.0})]

func links() -> Array:
	return [el(1, 2), el(2, 3), hl(3, 4), hl(4, 5, "warm_out", "heat_in")]

func run_case(ds: Array, ls: Array, power: float = 2.0, dt: float = 3600.0) -> Dictionary:
	var before: String = JSON.stringify([ds, ls])
	var r: Dictionary = Model.dispatch(ds, ls, {}, {"1": {"mw": power}}, dt)
	check(JSON.stringify([ds, ls]) == before, "pure transaction")
	check(r.valid, "valid runtime: " + str(r.errors) + str(r.warnings))
	var audit_errors: Array[String] = Model.audit_dispatch(ds, ls, r)
	check(audit_errors.is_empty(), "independent replay audit " + str(audit_errors))
	near(r.balance_error_mw, 0.0, "electric balance")
	near(r.energy_balance_error_mwh, 0.0, "electric energy balance")
	near(r.thermal.balance_error_mwth, 0.0, "thermal network balance")
	near(r.thermal.energy_balance_error_mwhth, 0.0, "thermal inventory balance")
	return r

func _initialize() -> void:
	catalog_tests()
	acceptance_tests()
	continuous_surplus_test()
	topology_tests()
	random_tests()
	print("THERMAL_RUNTIME_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func catalog_tests() -> void:
	for kind in ["electric_boiler", "thermal_store", "heat_exchanger", "heat_demand"]:
		check(Model.validate(kind, Catalog.defaults(kind)).is_empty(), kind + " defaults")
		check(not Model.validate(kind, {"junk": 3}).is_empty(), "unknown parameter rejected")
		check(Catalog.model_profile(kind) == "thermal_stage1_v1", "fixed profile")
		for p in Catalog.ports(kind):
			check(p.carrier in ["electricity_ac", "heat_water"], "explicit carrier")
	for bad in [NAN, INF, true, "1", -1.0, 100001.0]:
		check(not Model.validate("thermal_store", {"capacity_mwhth": bad}).is_empty(), "invalid capacity")
		check(not Catalog.validate_state("thermal_store", {}, {"energy_mwhth": bad}).is_empty(), "invalid state")
	for bad in [0, -1, 1.1, true, INF, NAN]:
		check(not Model.validate("electric_boiler", {"thermal_efficiency": bad}).is_empty(), "invalid efficiency")
	check(not Model.validate("heat_exchanger", {"min_approach_k": 20.1}).is_empty(), "both endpoint approaches")
	check(Model.validate("heat_exchanger", {"min_approach_k": 20.0}).is_empty(), "20K endpoint allowed")
	check(not Model.validate("heat_demand", {"priority": 2.5}).is_empty(), "integral priority")
	check(not Catalog.validate_state("thermal_store", {}, {"energy_mwh": 1}).is_empty(), "separate storage fields")
	check(not Catalog.validate_state("thermal_store", {}, {"energy_mwhth": 1, "junk": 0}).is_empty(), "unknown state")
	check(not Catalog.validate_state("electric_boiler", {}, {"energy_mwhth": 1}).is_empty(), "stateless device")
	var ds: Array = devices()
	for bad in ["unknown", 3, true, null]:
		ds[2].model_profile = bad
		check(not Model.dispatch(ds, links(), {}, {}, 1).valid, "unknown profile rejected")
	ds = devices()
	ds[2].model_profile_version = true
	check(not Model.dispatch(ds, links(), {}, {}, 1).valid, "boolean profile version rejected")

func acceptance_tests() -> void:
	var ds: Array = devices()
	var ls: Array = links()
	var r: Dictionary = run_case(ds, ls)
	near(r.boiler_electric_mw, 2, "A electric input")
	near(r.thermal.boiler_heat_mwth, 1.96, "A boiler output")
	near(r.thermal.served_mwth, 1.9208, "A heat served")
	near(r.thermal.unserved_mwth, .0792, "A heat shortfall")
	near(r.boiler_conversion_loss_mw, .04, "A boiler loss")
	near(r.thermal.exchanger_loss_mwth, .0392, "A exchanger loss")
	near(r.unserved_mw, 0, "A no fictional electric demand")
	ds[4].params.demand_mwth = .9604
	ds.append(dev(6, "load", {"demand_mw": 1.0}))
	ls.append(el(2, 6))
	r = run_case(ds, ls)
	near(r.boiler_electric_mw, 1, "B boiler endogenous 1MW")
	near(r.served_mw, 1, "B electric demand")
	near(r.thermal.served_mwth, .9604, "B heat demand")
	# C: greedy surplus charging then next-period discharge, four conversion factors.
	ds = devices()
	ds[4].params.demand_mwth = 0.0
	ds.append(dev(6, "thermal_store", {"self_discharge_per_h": 0.0}))
	ls = links() + [hl(3, 6, "heat_out", "heat_in"), hl(6, 4)]
	r = run_case(ds, ls)
	near(r.thermal.charge_mwth, 1.96, "C charge terminal")
	near(r.next_states["6"].energy_mwhth, 1.9208, "C stored inventory")
	ds[5].state = r.next_states["6"]
	ds[4].params.demand_mwth = 2.0
	r = run_case(ds, ls, 0.0)
	near(r.thermal.discharge_mwth, 1.882384, "C storage output")
	near(r.thermal.served_mwth, 1.84473632, "C demand delivery")
	near(r.boiler_electric_mw, 0.0, "C no boiler without power")
	near(r.thermal.charge_mwth, 0.0, "C mode exclusivity")
	# D: isolated storage decays, split durations agree exactly.
	ds = [dev(6, "thermal_store", {}, {"energy_mwhth": 1.0})]
	r = run_case(ds, [], 0)
	near(r.next_states["6"].energy_mwhth, exp(-.002), "D self discharge")
	near(r.thermal.self_discharge_mwhth, 1 - exp(-.002), "D self loss")
	var half: Dictionary = run_case(ds, [], 0, 1800)
	ds[0].state = half.next_states["6"]
	half = run_case(ds, [], 0, 1800)
	near(half.next_states["6"].energy_mwhth, r.next_states["6"].energy_mwhth, "D duration composition")
	ds[0].state = {"energy_mwhth": 1.0}
	r = run_case(ds, [], 0, 0)
	near(r.next_states["6"].energy_mwhth, 1, "E dt0 freeze")
	near(r.thermal.self_discharge_mwhth, 0, "E no pause self loss")
	# E/G: no free sinks; full and empty limits, exchanger bottleneck.
	ds = devices()
	ds[4].params.demand_mwth = 0.0
	ds.append(dev(6, "thermal_store", {"self_discharge_per_h": 0.0}, {"energy_mwhth": 4.0}))
	ls = links() + [hl(3, 6, "heat_out", "heat_in"), hl(6, 4)]
	r = run_case(ds, ls)
	near(r.boiler_electric_mw, 0, "G full store and no demand")
	near(r.curtailed_mw, 2, "G surplus curtailed")
	ds[5].state.energy_mwhth = 0.0
	ds[4].params.demand_mwth = 2.0
	r = run_case(ds, ls, 0)
	near(r.thermal.discharge_mwth, 0, "E empty cannot discharge")
	r = run_case(ds, ls, 2, 0)
	near(r.thermal.charge_mwth, 0, "E pause no charge")
	near(r.thermal.discharge_mwth, 0, "E pause no discharge")
	ds[3].params.capacity_mwth = .5
	r = run_case(ds, links())
	near(r.thermal.served_mwth, .49, "G exchanger bottleneck")
	near(r.boiler_electric_mw, .5/.98, "G no extra boiler consumption")
	r = run_case(ds, [el(1,2),el(2,3)])
	near(r.boiler_electric_mw, 0, "G disconnected heat outlet")
	# Losses of the electric path are accounted once, boiler input is delivered power.
	ds = devices()
	ls = links()
	ls[0].loss_fraction = .1
	ls[1].loss_fraction = .1
	ds[1].params.loss_fraction = .1
	r = run_case(ds, ls)
	near(r.boiler_electric_mw, 2 * pow(.9,3), "electric line and station loss")
	near(r.thermal.served_mwth, 2 * pow(.9,3) * .98 * .98, "conversion after electric delivery")
	# Replay rejects forged flows, metadata, inventories, and reported-zero residuals.
	var forged: Dictionary = r.duplicate(true)
	forged.lines[2].sent_mwth += .1
	check(not Model.audit_dispatch(ds,ls,forged).is_empty(), "audit rejects forged heat flow")
	forged = r.duplicate(true)
	forged.devices["3"].heat_output_mwth += .1
	check(not Model.audit_dispatch(ds,ls,forged).is_empty(), "audit rejects forged boiler output")
	forged = r.duplicate(true)
	forged.lines[2].capacity_mwth = 200.0
	check(not Model.audit_dispatch(ds,ls,forged).is_empty(), "audit capacity uses original topology")
	var snapshot: Dictionary = Model.optimization_snapshot(ds,ls,{}, {"1":{"mw":2.0}},3600)
	check(snapshot.valid and snapshot.schema_version == 2, "schema2 snapshot")
	check(snapshot.devices[2].model_profile == "thermal_stage1_v1", "snapshot thermal profile")
	check(snapshot.edges[2].unit == "MWth" and not snapshot.edges[2].has("capacity_mw"), "snapshot typed heat edge")

func topology_tests() -> void:
	var ds: Array = devices()
	var ls: Array = links()
	check(Catalog.validate_topology(ds,ls).is_empty(), "valid electrothermal topology")
	for field in ["from_port", "to_port", "carrier", "unit"]:
		var missing: Dictionary = el(2,3)
		missing.erase(field)
		check(not Catalog.validate_link(ds,[],missing).is_empty(), "explicit boiler input " + field)
	for changes in [{"unit":"MW"}, {"grade_id":Catalog.SECONDARY_GRADE}, {"capacity_mw":2}, {"loss_fraction":.1}, {"from_port":"ac_in"}, {"carrier":"electricity_ac"}]:
		var bad: Dictionary = hl(3,4)
		bad.merge(changes,true)
		check(not Catalog.validate_link(ds,[],bad).is_empty(), "typed thermal rejection")
	for field in ["from_port","to_port","carrier","unit","grade_id","capacity_mwth","loss_fraction"]:
		var bad: Dictionary = hl(3,4)
		bad.erase(field)
		check(not Catalog.validate_link(ds,[],bad).is_empty(), "explicit heat field " + field)
	check(not Catalog.validate_link(ds,[],hl(3,5,"heat_out","heat_in")).is_empty(), "no primary direct secondary")
	check(not Catalog.validate_link(ds,[],hl(4,3,"warm_out","heat_out")).is_empty(), "no reverse exchanger")
	check(not Catalog.validate_link(ds,[hl(3,4)],hl(3,4)).is_empty(), "duplicate same ports")
	# F: fan-out shares boiler rating, merge shares exchanger capacity.
	ds.append(dev(6,"heat_exchanger"))
	ds.append(dev(7,"heat_demand",{"demand_mwth":2.0}))
	ls += [hl(3,6),hl(6,7,"warm_out","heat_in")]
	var r: Dictionary = run_case(ds,ls)
	near(r.thermal.served_mwth,1.9208,"F fan-out never duplicates power")
	ds = devices()
	ds.append(dev(6,"electric_boiler"))
	ls = links() + [el(2,6,100,0,true),hl(6,4)]
	r = run_case(ds,ls,5)
	near(r.thermal.served_mwth,1.96,"F merged exchanger shared capacity")
	near(r.boiler_electric_mw,2.0/.98,"F boilers share heat absorption")
	# Battery energy may supply real heat demand, never heat-storage charging.
	ds = devices()
	ds.append(dev(6,"battery",{}, {"energy_mwh":5.0}))
	ds.append(dev(7,"thermal_store",{"self_discharge_per_h":0.0}))
	ls = links() + [el(6,2),hl(3,7,"heat_out","heat_in")]
	r = run_case(ds,ls,0)
	near(r.thermal.served_mwth,1.9208,"battery can power boiler demand")
	near(r.thermal.charge_mwth,0,"battery cannot discharge for heat charging")
	near(r.charge_mw,0,"discharged battery cannot charge")

func random_tests() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261015
	for trial in 80:
		var ds: Array = devices()
		ds[2].params = {"rated_electric_mw":rng.randf_range(.1,4.0),"thermal_efficiency":rng.randf_range(.4,1.0)}
		ds[3].params = {"capacity_mwth":rng.randf_range(.1,4),"transfer_efficiency":rng.randf_range(.4,1.0)}
		ds[4].params.demand_mwth = rng.randf_range(0,4)
		ds.append(dev(6,"thermal_store",{"self_discharge_per_h":rng.randf_range(0,.2),"charge_efficiency":rng.randf_range(.4,1.0),"discharge_efficiency":rng.randf_range(.4,1.0)}, {"energy_mwhth":rng.randf_range(0,4)}))
		ds.append(dev(7,"load",{"demand_mw":rng.randf_range(0,4),"priority":rng.randi_range(0,20)}))
		var ls: Array = links() + [hl(3,6,"heat_out","heat_in"),hl(6,4),el(2,7),el(2,-1)]
		ls[0].loss_fraction = rng.randf_range(0,.2)
		ls[1].loss_fraction = rng.randf_range(0,.2)
		ls[2].capacity_mwth = rng.randf_range(0,3)
		ds[1].params.loss_fraction = rng.randf_range(0,.2)
		var dt: float = rng.randf_range(.01,10800)
		var power: float = rng.randf_range(0,5)
		var r: Dictionary = run_case(ds,ls,power,dt)
		check(r.thermal.charge_mwth <= EPSILON or r.thermal.discharge_mwth <= EPSILON,"random storage exclusivity")
		ds.reverse()
		ls.reverse()
		var reverse: Dictionary = run_case(ds,ls,power,dt)
		near(reverse.thermal.served_mwth,r.thermal.served_mwth,"stable order heat")
		near(reverse.thermal.energy_mwhth,r.thermal.energy_mwhth,"stable order inventory")

const EPSILON: float = 1.0e-8

func continuous_surplus_test() -> void:
	var ds: Array = devices()
	ds[4].params.demand_mwth = .9604
	ds.append(dev(6,"thermal_store",{"self_discharge_per_h":0.002}))
	ds.append(dev(7,"load",{"demand_mw":.5}))
	var ls: Array = links() + [hl(3,6,"heat_out","heat_in"),hl(6,4),el(2,7)]
	var previous: float = 0.0
	for step in 60:
		var r: Dictionary = run_case(ds,ls,2.0,60.0)
		near(r.thermal.served_mwth,.9604,"constant renewable heat service")
		near(r.served_mw,.5,"constant electric service")
		near(r.thermal.discharge_mwth,0.0,"surplus never pointlessly drains thermal store")
		check(r.next_states["6"].energy_mwhth > previous,"constant surplus inventory increases")
		previous = r.next_states["6"].energy_mwhth
		ds[5].state = r.next_states["6"]
	check(previous > .47,"one-hour surplus accumulates useful heat")
	# With no renewable, use saved heat before consuming battery electricity.
	ds.append(dev(8,"battery",{}, {"energy_mwh":5.0}))
	ls.append(el(8,2))
	ds[6].params.demand_mw = 0.0
	var r: Dictionary = run_case(ds,ls,0.0,60.0)
	near(r.thermal.served_mwth,.9604,"stored heat serves lull")
	near(r.boiler_electric_mw,0.0,"stored heat preferred to battery boiler")
	near(r.discharge_mw,0.0,"stored heat preserves battery")
	# Timed small-scene sample is informational, never a performance guarantee.
	var start: int = Time.get_ticks_usec()
	for iteration in 200:
		Model.dispatch(ds,ls,{}, {"1":{"mw":2.0}},1.0)
	print("THERMAL_RUNTIME_BENCHMARK: ", ds.size(), " devices / ", ls.size(), " edges, 200 dispatches, mean_us=", (Time.get_ticks_usec()-start)/200.0)
