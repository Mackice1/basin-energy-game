extends SceneTree
const Model = preload("res://scripts/energy_model.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
const Supply = preload("res://scripts/fuel_supply.gd")
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("FUEL_DISPATCH_FAIL: " + label)

func near(a: float, b: float, label: String, tol: float = 2.0e-7) -> void:
	check(is_finite(a) and absf(a - b) <= tol, "%s: %.12f != %.12f" % [label, a, b])

func dev(id: int, kind: String, params: Dictionary = {}, state: Dictionary = {}) -> Dictionary:
	var d: Dictionary = {"id": id, "kind": kind, "params": params}
	if kind in ["battery", "thermal_store"]:
		d.state = state if not state.is_empty() else Catalog.initial_state(kind, params)
	return d

func el(a: int, b: int, cap: float = 100.0, loss: float = 0.0, boiler: bool = false) -> Dictionary:
	var l: Dictionary = {"from": a, "to": b, "capacity_mw": cap, "loss_fraction": loss}
	if boiler:
		l.merge({"from_port": "out", "to_port": "ac_in", "carrier": "electricity_ac", "unit": "MW"})
	return l

func hl(a: int, b: int, from_port: String = "heat_out", to_port: String = "hot_in", cap: float = 100.0) -> Dictionary:
	return {"from": a, "to": b, "from_port": from_port, "to_port": to_port, "carrier": "heat_water", "unit": "MWth",
		"grade_id": Catalog.SECONDARY_GRADE if from_port == "warm_out" else Catalog.PRIMARY_GRADE,
		"capacity_mwth": cap, "loss_fraction": 0.0}

func devices() -> Array:
	return [dev(1, "wind"), dev(2, "station", {"capacity_mw": 20.0, "loss_fraction": 0.0}),
		dev(3, "fuel_boiler"), dev(4, "heat_exchanger", {"capacity_mwth": 20.0}),
		dev(5, "heat_demand", {"demand_mwth": 10.0})]

func links() -> Array:
	return [el(1, 2), el(2, 3, 100.0, 0.0, true), hl(3, 4), hl(4, 5, "warm_out", "heat_in")]

func supply(cap: float = 2.0) -> Dictionary:
	var s: Dictionary = Supply.defaults()
	s.enabled = true
	s.max_input_mw = cap
	return s

func run_case(ds: Array, ls: Array, power: float = 1.0, cap: float = 2.0, dt: float = 3600.0) -> Dictionary:
	var direct: Dictionary = {"1": {"mw": power}, "_fuel_supply": supply(cap)}
	var before: String = JSON.stringify([ds, ls, direct])
	var r: Dictionary = Model.dispatch(ds, ls, {}, direct, dt)
	check(JSON.stringify([ds, ls, direct]) == before, "pure inputs")
	check(r.valid, "runtime valid: " + str(r.errors) + str(r.warnings))
	check(r.audit_errors.is_empty(), "live independent audit")
	check(Model.audit_dispatch(ds, ls, r, supply(cap)).is_empty(), "replay with original supply")
	near(r.balance_error_mw, 0.0, "AC balance")
	near(r.energy_balance_error_mwh, 0.0, "AC inventory balance")
	near(r.thermal.balance_error_mwth, 0.0, "heat balance")
	near(r.thermal.energy_balance_error_mwhth, 0.0, "heat inventory balance")
	near(r.cross_carrier_balance_error_mw, 0.0, "whole system balance")
	near(r.fuel.input_mw + r.fuel.auxiliary_electric_mw, r.fuel.heat_output_mwth + r.fuel.conversion_loss_mw + r.fuel.auxiliary_electric_loss_mw, "fuel cross-carrier balance")
	check(r.fuel.input_mw <= cap + 0.000001, "fleet cap")
	return r

func _initialize() -> void:
	basic_tests()
	sharing_tests()
	storage_and_policy_tests()
	audit_and_snapshot_tests()
	boundary_and_priority_tests()
	random_tests()
	print("FUEL_DISPATCH_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func basic_tests() -> void:
	var ds: Array = devices()
	var ls: Array = links()
	var r: Dictionary = run_case(ds, ls)
	near(r.fuel.input_mw, 2, "nominal fuel")
	near(r.fuel.heat_output_mwth, 1.8, "nominal heat")
	near(r.thermal.served_mwth, 1.764, "HX loss downstream")
	near(r.fuel.conversion_loss_mw, .2, "LHV conversion loss")
	near(r.fuel.auxiliary_electric_mw, .02, "mandatory auxiliary AC")
	near(r.fuel.auxiliary_electric_loss_mw, .02, "auxiliary dissipated separately")
	near(r.fuel.volume_nm3_per_h, 200, "MW to Nm3 per h")
	near(r.fuel.cost_per_h, 600, "fuel cost per h")
	near(r.boiler_electric_mw, 0, "old boiler electric meaning")
	near(r.thermal.boiler_heat_mwth, 0, "old electric boiler heat meaning")
	check(not r.next_states.has("3"), "fuel boiler has no inventory")
	r = run_case(ds, ls, 1, .75)
	near(r.fuel.input_mw, .75, "fuel supply cap")
	r = run_case(ds, ls, .005)
	near(r.fuel.input_mw, .5, "available AC constrains fuel")
	r = run_case(ds, ls, 0)
	near(r.fuel.input_mw, 0, "no AC generation")
	ls[1].capacity_mw = .005
	r = run_case(ds, ls)
	near(r.fuel.input_mw, .5, "auxiliary line bottleneck")
	ls = links()
	ds[1].params.capacity_mw = .01
	r = run_case(ds, ls)
	near(r.fuel.input_mw, 1.0, "station bottleneck")
	ds = devices()
	r = run_case(ds, [ls[0], ls[2], ls[3]])
	near(r.fuel.input_mw, 0, "no AC connection")
	r = run_case(ds, [ls[0], ls[1]])
	near(r.fuel.input_mw, 0, "no heat path")
	ds[4].params.demand_mwth = 0.0
	r = run_case(ds, ls)
	near(r.fuel.input_mw, 0, "no heat sink")
	ds = devices()
	for config in [{}, Supply.defaults(), supply(0)]:
		r = Model.dispatch(ds, ls, {}, {"1": {"mw": 1.0}, "_fuel_supply": config}, 3600)
		check(r.valid, "absent/disabled/zero-cap valid idle")
		near(r.fuel.input_mw, 0, "absent/disabled/zero-cap no fuel")
	r = Model.dispatch(ds, ls, {}, {"1": {"mw": 1.0}}, 3600)
	near(r.fuel.input_mw, 0, "missing resource never free energy")
	for config in [{"enabled": true, "max_input_mw": -1}, {"enabled": 1}, {"max_input_mw": INF}, {"lower_heating_value_kwh_per_nm3": 0}, {"price_per_mwh": -1}, {"junk": 1}, false]:
		r = Model.dispatch(ds, ls, {}, {"1": {"mw": 1.0}, "_fuel_supply": config}, 3600)
		check(not r.valid and not r.commit_allowed, "invalid resource rejects transaction")
		near(r.fuel.input_mw, 0, "invalid resource fails closed")
	ls[0].loss_fraction = .1
	ls[1].loss_fraction = .1
	ds[1].params.loss_fraction = .1
	r = run_case(ds, ls, .02 / pow(.9, 3))
	near(r.fuel.input_mw, 2, "lossy delivered auxiliary")
	near(r.loss_mw, .02 / pow(.9, 3) - .02, "electrical network losses once")

func sharing_tests() -> void:
	var ds: Array = devices()
	var ls: Array = links()
	ds.append(dev(6, "fuel_boiler"))
	ls += [el(2, 6, 100.0, 0.0, true), hl(6, 4)]
	var r: Dictionary = run_case(ds, ls)
	near(r.devices["3"].fuel_input_mw, 1, "equal share first boiler")
	near(r.devices["6"].fuel_input_mw, 1, "equal share second boiler")
	ds.reverse()
	ls.reverse()
	var reversed: Dictionary = run_case(ds, ls)
	near(reversed.devices["3"].fuel_input_mw, r.devices["3"].fuel_input_mw, "device/edge ordering stable")
	near(reversed.devices["6"].fuel_input_mw, r.devices["6"].fuel_input_mw, "second ordering stable")
	ds.reverse()
	ls.reverse()
	ds[2].params.rated_fuel_mw = .5
	r = run_case(ds, ls)
	near(r.devices["3"].fuel_input_mw, .5, "small rating share")
	near(r.devices["6"].fuel_input_mw, 1.5, "redistribute unused share")
	ds[2].params.rated_fuel_mw = 2.0
	ls[1].capacity_mw = .002
	r = run_case(ds, ls)
	near(r.devices["3"].fuel_input_mw, .2, "AC-limited fair share")
	near(r.devices["6"].fuel_input_mw, 1.8, "AC-limited share redistributed")
	ls[1].capacity_mw = 100.0
	ds[3].params.capacity_mwth = .9
	r = run_case(ds, ls, 1, 10)
	near(r.devices["3"].fuel_input_mw, .5, "shared HX also fair first")
	near(r.devices["6"].fuel_input_mw, .5, "shared HX also fair second")
	ds = devices()
	ls = links()
	ds.append(dev(6, "heat_exchanger"))
	ds.append(dev(7, "heat_demand", {"demand_mwth": 5.0}))
	ls += [hl(3, 6), hl(6, 7, "warm_out", "heat_in")]
	r = run_case(ds, ls, 1, 10)
	near(r.fuel.input_mw, 2, "fan-out shares device rating")
	near(r.thermal.served_mwth, 1.764, "fan-out cannot duplicate heat")
	ds.append(dev(3, "fuel_boiler"))
	r = Model.dispatch(ds, ls, {}, {"1": {"mw": 1.0}, "_fuel_supply": supply()}, 3600)
	check(not r.valid and not r.commit_allowed, "duplicate device rejected")
	check(r.fuel.input_mw <= 2.000001, "duplicate cannot increase fleet fuel")
	ds = devices()
	ls = links()
	ls.append(ls[2].duplicate(true))
	r = Model.dispatch(ds, ls, {}, {"1": {"mw": 1.0}, "_fuel_supply": supply()}, 3600)
	check(not r.valid and not r.commit_allowed, "duplicate edge rejected")
	near(r.fuel.input_mw, 2, "duplicate edge no double count")

func storage_and_policy_tests() -> void:
	var ds: Array = devices()
	var ls: Array = links()
	ds[4].params.demand_mwth = 0.0
	ds.append(dev(6, "thermal_store", {"self_discharge_per_h": 0.0}))
	ls += [hl(3, 6, "heat_out", "heat_in"), hl(6, 4)]
	var r: Dictionary = run_case(ds, ls)
	near(r.fuel.input_mw, 2, "fuel can charge actual heat store")
	near(r.thermal.charge_mwth, 1.8, "heat store terminal charging")
	near(r.next_states["6"].energy_mwhth, 1.764, "stored heat after efficiency")
	ds[5].state.energy_mwhth = 4.0
	r = run_case(ds, ls)
	near(r.fuel.input_mw, 0, "full store blocks fuel")
	ds[5].state.energy_mwhth = 3.9
	r = run_case(ds, ls)
	near(r.thermal.charge_mwth, .1 / .98, "nearly full exact room")
	near(r.next_states["6"].energy_mwhth, 4.0, "no storage overfill")
	ds[5].state.energy_mwhth = 0.0
	r = run_case(ds, ls, 1, 2, 0)
	near(r.fuel.input_mw, 0, "paused store no fuel draw")
	ds.append(dev(7, "battery", {}, {"energy_mwh": 5.0}))
	ls.append(el(7, 2))
	r = run_case(ds, ls, 0)
	near(r.fuel.input_mw, 0, "battery auxiliary never speculative storage charge")
	near(r.discharge_mw, 0, "battery stays idle for heat charge")
	ds[4].params.demand_mwth = 1.764
	r = run_case(ds, ls, 0)
	near(r.fuel.input_mw, 2, "battery auxiliary allowed for service")
	near(r.discharge_mw, .02, "battery pays auxiliary input")
	near(r.thermal.charge_mwth, 0, "no simultaneous heat charge/discharge")
	ds[5].state.energy_mwhth = 4.0
	r = run_case(ds, ls, 0)
	near(r.fuel.input_mw, 0, "stored heat before fuel")
	near(r.discharge_mw, 0, "stored heat preserves AC battery")
	# Renewable electric heat precedes fuel, which precedes battery electric heat.
	ds = devices()
	ls = links()
	ds[4].params.demand_mwth = .9604
	ds.append(dev(6, "electric_boiler"))
	ls += [el(2, 6, 100, 0, true), hl(6, 4)]
	r = run_case(ds, ls, 1.0)
	near(r.boiler_electric_mw, 1, "renewable electric boiler first")
	near(r.fuel.input_mw, 0, "no avoidable gas for served heat")
	ds.append(dev(7, "battery", {}, {"energy_mwh": 5.0}))
	ls.append(el(7, 2))
	r = run_case(ds, ls, 0)
	near(r.boiler_electric_mw, 0, "gas backup before battery electric boiler")
	near(r.fuel.input_mw, .9604 / .98 / .9, "gas serves residual heat")

func audit_and_snapshot_tests() -> void:
	var ds: Array = devices()
	var ls: Array = links()
	var r: Dictionary = run_case(ds, ls)
	for field in ["fuel_input_mw", "heat_output_mwth", "conversion_loss_mw", "auxiliary_electric_mw", "auxiliary_electric_loss_mw", "fuel_volume_nm3_per_h", "fuel_cost_per_h"]:
		var forged: Dictionary = r.duplicate(true)
		forged.devices["3"][field] += .1
		check(not Model.audit_dispatch(ds, ls, forged, supply()).is_empty(), "reject forged device " + field)
	for field in r.fuel:
		var forged: Dictionary = r.duplicate(true)
		forged.fuel[field] += .1
		check(not Model.audit_dispatch(ds, ls, forged, supply()).is_empty(), "reject forged aggregate " + field)
	var forged: Dictionary = r.duplicate(true)
	forged.fuel_supply.max_input_mw = 100.0
	check(not Model.audit_dispatch(ds, ls, forged, supply()).is_empty(), "original supply cap cannot be changed")
	forged = r.duplicate(true)
	forged.fuel_supply.max_input_mw = 1.0
	check(not Model.audit_dispatch(ds, ls, forged).is_empty(), "aggregate cap audited")
	forged = r.duplicate(true)
	forged.fuel_supply.enabled = false
	check(not Model.audit_dispatch(ds, ls, forged).is_empty(), "disabled resource cannot have draw")
	var snapshot: Dictionary = Model.optimization_snapshot(ds, ls, {}, {"1": {"mw": 1.0}, "_fuel_supply": supply()}, 3600)
	check(snapshot.valid and snapshot.fuel_supply == supply(), "snapshot resource exposed")
	check(snapshot.device_catalog_version == 3, "fuel snapshot uses catalog3")
	near(snapshot.constraints.resource_limits["fuel:supply"], 2, "snapshot fleet cap once")
	near(snapshot.constraints.resource_limits["fuel_boiler:3"], 2, "snapshot rating")
	near(snapshot.constraints.resource_limits["fuel_aux:3"], .02, "snapshot auxiliary cap")
	check(not snapshot.constraints.fuel_inventory, "snapshot no fuel inventory")
	check(snapshot.constraints.thermal_paths.size() == 1, "snapshot fuel heat path")
	# Empty resource metadata is omitted entirely from legacy scenes.
	ds[2].kind = "electric_boiler"
	r = Model.dispatch(ds, ls, {}, {"1": {"mw": 1.0}}, 3600)
	check(r.valid and not r.has("fuel") and not r.has("fuel_supply"), "legacy report shape")
	near(r.boiler_electric_mw, 1, "legacy electric dispatch")
	near(r.thermal.boiler_heat_mwth, .98, "legacy electric heat")
	snapshot = Model.optimization_snapshot(ds, ls, {}, {"1": {"mw": 1.0}}, 3600)
	check(snapshot.valid and not snapshot.has("fuel_supply"), "legacy snapshot shape")
	check(snapshot.device_catalog_version == 2, "legacy snapshot retains catalog2")

func random_tests() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261016
	for trial in 100:
		var ds: Array = devices()
		var ls: Array = links()
		ds[2].params = {"rated_fuel_mw": rng.randf_range(.1, 4), "thermal_efficiency": rng.randf_range(.3, 1), "auxiliary_electric_ratio": rng.randf_range(.001, .2)}
		ds[3].params = {"capacity_mwth": rng.randf_range(.1, 4), "transfer_efficiency": rng.randf_range(.4, 1)}
		ds[4].params.demand_mwth = rng.randf_range(0, 4)
		ds.append(dev(6, "fuel_boiler", {"rated_fuel_mw": rng.randf_range(.1, 4), "thermal_efficiency": rng.randf_range(.3, 1), "auxiliary_electric_ratio": rng.randf_range(.001, .2)}))
		ds.append(dev(7, "thermal_store", {"self_discharge_per_h": rng.randf_range(0, .1)}, {"energy_mwhth": rng.randf_range(0, 4)}))
		ds.append(dev(8, "load", {"demand_mw": rng.randf_range(0, 2), "priority": rng.randi_range(0, 20)}))
		ls += [el(2, 6, rng.randf_range(.001, .2), 0, true), hl(6, 4), hl(3, 7, "heat_out", "heat_in"), hl(6, 7, "heat_out", "heat_in"), hl(7, 4), el(2, 8), el(2, -1)]
		ls[0].loss_fraction = rng.randf_range(0, .2)
		ds[1].params.loss_fraction = rng.randf_range(0, .2)
		var cap: float = rng.randf_range(0, 5)
		var power: float = rng.randf_range(0, 3)
		var dt: float = rng.randf_range(1, 7200)
		var r: Dictionary = run_case(ds, ls, power, cap, dt)
		check(r.thermal.charge_mwth <= .000001 or r.thermal.discharge_mwth <= .000001, "random store exclusive mode")
		ds.reverse()
		ls.reverse()
		var reversed: Dictionary = run_case(ds, ls, power, cap, dt)
		near(reversed.fuel.input_mw, r.fuel.input_mw, "random stable fuel")
		near(reversed.thermal.served_mwth, r.thermal.served_mwth, "random stable heat")
		near(reversed.thermal.energy_mwhth, r.thermal.energy_mwhth, "random stable store")

func boundary_and_priority_tests() -> void:
	var ds: Array = devices()
	var ls: Array = links()
	for dt in [-1.0, NAN, INF]:
		var rejected: Dictionary = Model.dispatch(ds, ls, {}, {"1": {"mw": 1.0}, "_fuel_supply": supply()}, dt)
		check(not rejected.valid and not rejected.commit_allowed, "invalid interval rejected")
		near(rejected.fuel.input_mw, 0, "invalid interval no fuel")
	# A disabled fleet remains disabled even with a large advertised cap.
	var disabled: Dictionary = supply(100)
	disabled.enabled = false
	var r: Dictionary = Model.dispatch(ds, ls, {}, {"1": {"mw": 1.0}, "_fuel_supply": disabled}, 3600)
	check(r.valid, "disabled finite resource is valid")
	near(r.fuel.input_mw, 0, "enable gate independent of cap")
	# Service priority decides which real load receives the shared resource.
	ds[4].params.demand_mwth = .882
	ds[4].params.priority = 20
	ds.append(dev(6, "heat_exchanger"))
	ds.append(dev(7, "heat_demand", {"demand_mwth": .882, "priority": 0}))
	ls += [hl(3, 6), hl(6, 7, "warm_out", "heat_in")]
	r = run_case(ds, ls, 1, 1)
	near(r.devices["7"].served_mwth, .882, "heat service priority before stable ID")
	near(r.devices["5"].served_mwth, 0, "lower priority fuel shortfall")
	# A second disconnected boiler never reserves fuel that a live boiler needs.
	ds = devices()
	ls = links()
	ds.append(dev(6, "fuel_boiler"))
	ls.append(hl(6, 4))
	r = run_case(ds, ls)
	near(r.devices["3"].fuel_input_mw, 2, "idle boiler receives no fair share reservation")
	near(r.devices["6"].fuel_input_mw, 0, "disconnected auxiliary blocks boiler")
	# When one heat route fills, progressive filling reroutes to a second HX.
	ls.append(el(2, 6, 100, 0, true))
	ds[3].params.capacity_mwth = .45
	ds.append(dev(7, "heat_exchanger", {"capacity_mwth": 3.0}))
	ds.append(dev(8, "heat_demand", {"demand_mwth": 3.0}))
	ls += [hl(3, 7), hl(6, 7), hl(7, 8, "warm_out", "heat_in")]
	r = run_case(ds, ls)
	near(r.fuel.input_mw, 2, "later heat route uses remaining fleet resource")
	near(r.thermal.served_mwth, 1.764, "multiple HX routes conserve heat")
	# No finite fuel stock is invented; every interval has the same configured cap.
	var again: Dictionary = run_case(ds, ls)
	near(again.fuel.input_mw, r.fuel.input_mw, "resource cap resets per interval")
	# Numerical threshold must terminate without fictitious auxiliary allocation.
	r = run_case(devices(), links(), 1.0e-12)
	near(r.fuel.input_mw, 0, "sub-epsilon AC safely idle")
	# Forged cross-carrier residuals and fuel metadata on legacy scenes reject.
	r = run_case(devices(), links())
	var forged: Dictionary = r.duplicate(true)
	forged.cross_carrier_balance_error_mw = 1.0
	check(not Model.audit_dispatch(devices(), links(), forged, supply()).is_empty(), "reject forged cross-carrier residual")
	ds = devices()
	ds[2].kind = "electric_boiler"
	r = Model.dispatch(ds, links(), {}, {"1": {"mw": 1.0}}, 3600)
	r.fuel = {}
	check(not Model.audit_dispatch(ds, links(), r).is_empty(), "reject unexpected fuel metadata")
