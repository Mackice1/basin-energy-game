extends SceneTree
## Run: godot --headless --path . --script tests/test_energy_model.gd
const Model = preload("res://scripts/energy_model.gd")
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("ENERGY_MODEL_FAIL: " + label)

func near(actual: float, expected: float, label: String, tolerance: float = 1.0e-7) -> void:
	check(absf(actual - expected) <= tolerance, "%s (actual %.12f, expected %.12f)" % [label, actual, expected])

func dev(id: int, kind: String, params: Dictionary = {}) -> Dictionary:
	return {"id": id, "kind": kind, "params": params, "x": 0.0, "z": 0.0}

func link(a: int, b: int, cap: float = 10.0, loss: float = 0.0) -> Dictionary:
	return {"from": a, "to": b, "capacity_mw": cap, "loss_fraction": loss}

func invariants(result: Dictionary, label: String) -> void:
	near(result.balance_error_mw, 0.0, label + " conservation", 2.0e-7)
	check(result.delivered_mw <= 4.0 + 1.0e-7, label + " grid limit")
	check(result.generated_mw >= -1.0e-8 and result.delivered_mw >= -1.0e-8 and result.curtailed_mw >= -1.0e-8 and result.loss_mw >= -1.0e-8, label + " nonnegative balance")
	check(result.optimal, label + " dispatch reached optimum")
	var losses: float = 0.0
	var generation: float = 0.0
	var curtailment: float = 0.0
	var grid_received: float = 0.0
	for id in result.devices:
		var d: Dictionary = result.devices[id]
		if d.kind == "station":
			check(d.input_mw <= d.get("capacity_mw", 0.0) + 1.0e-7, label + " station input limit " + id)
			near(d.input_mw - d.output_mw, d.loss_mw, label + " station balance " + id)
			losses += d.loss_mw
		else:
			near(d.mw, d.sent_mw + d.curtailed_mw, label + " generator balance " + id)
			check(d.sent_mw <= d.mw + 1.0e-7, label + " generator shared cap " + id)
			generation += d.mw
			curtailment += d.curtailed_mw
	for l in result.lines:
		check(l.sent_mw <= l.capacity_mw + 1.0e-7, label + " line cap " + str(l.index))
		near(l.sent_mw - l.received_mw, l.loss_mw, label + " line balance " + str(l.index))
		if not l.valid:
			near(l.sent_mw, 0.0, label + " invalid line inactive")
		losses += l.loss_mw
		if l.to == -1:
			grid_received += l.received_mw
	near(losses, result.loss_mw, label + " losses summed once")
	near(generation, result.generated_mw, label + " generation summed once")
	near(curtailment, result.curtailed_mw, label + " curtailment sum")
	near(grid_received, result.delivered_mw, label + " grid delivery sum")

func _initialize() -> void:
	_test_validation()
	_test_wind()
	_test_pv()
	_test_network()
	_test_dispatch()
	_test_random_networks()
	print("ENERGY_MODEL_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_validation() -> void:
	for kind in ["wind", "pv", "station"]:
		check(Model.validate(kind, Model.defaults(kind)).is_empty(), kind + " defaults valid")
		check(Model.validate(kind, {}).is_empty(), kind + " partial parameters defaulted")
		check(not Model.validate(kind, {"typo": 1.0}).is_empty(), kind + " unknown keys rejected")
	check(not Model.validate("coal", {}).is_empty(), "unknown kind rejected")
	for bad in [0.0, -1.0, INF, NAN, "5", null, true]:
		check(not Model.validate("wind", {"rated_mw": bad}).is_empty(), "invalid wind rating rejected: " + str(bad))
	check(not Model.validate("wind", {"rated_speed_mps": 7.0}).is_empty(), "5MW at 7m/s violates available rotor power")
	check(not Model.validate("wind", {"rotor_diameter_m": 10.0}).is_empty(), "small rotor cannot support 5MW")
	check(not Model.validate("wind", {"rated_mw": 8.0}).is_empty(), "8MW not physically valid with default rotor and speed")
	check(not Model.validate("wind", {"cp_max": 0.6}).is_empty(), "Betz Cp limit enforced")
	check(not Model.validate("wind", {"drivetrain_efficiency": 0.3}).is_empty(), "drivetrain loss included in Cp feasibility")
	check(not Model.validate("wind", {"cut_in_mps": 12.0}).is_empty(), "cut-in ordering enforced")
	check(not Model.validate("wind", {"cut_out_mps": 10.0}).is_empty(), "cut-out ordering enforced")
	check(not Model.validate("wind", {"hub_height_m": 50.0}).is_empty(), "rotor ground clearance enforced")
	check(Model.validate("wind", {"rated_mw": 4.0}).is_empty(), "physically valid derating accepted")
	check(not Model.validate("pv", {"inverter_efficiency": 1.1}).is_empty(), "inverter cannot create energy")
	check(not Model.validate("pv", {"faiman_u0": 0.0}).is_empty(), "Faiman zero denominator rejected")
	check(not Model.validate("station", {"loss_fraction": 1.0}).is_empty(), "100 percent station loss rejected")

func _test_wind() -> void:
	var p: Dictionary = Model.defaults("wind")
	for speed in [0.0, 2.999, 3.0, 25.0, 40.0]:
		near(Model.generation("wind", p, {"wind_speed_mps": speed}).mw, 0.0, "wind boundary " + str(speed))
	near(Model.generation("wind", p, {"wind_speed_mps": 11.4}).mw, 5.0, "wind rated point")
	near(Model.generation("wind", p, {"wind_speed_mps": 20.0}).mw, 5.0, "wind above-rated plateau")
	var previous: float = 0.0
	for i in range(301, 2500):
		var speed: float = float(i) / 100.0
		var g: Dictionary = Model.generation("wind", p, {"wind_speed_mps": speed})
		check(g.mw >= previous - 1.0e-8, "wind monotonic before cut-out %.2f" % speed)
		check(g.cp_aero <= Model.BETZ_LIMIT + 1.0e-9 and g.cp_aero <= p.cp_max + 1.0e-9, "wind interior Cp bounded %.2f" % speed)
		previous = g.mw
	var standard: Dictionary = Model.generation("wind", p, {"wind_speed_mps": 8.0})
	var thin: Dictionary = Model.generation("wind", p, {"wind_speed_mps": 8.0, "air_density_kgm3": 0.9})
	near(thin.mw / standard.mw, 0.9 / 1.225, "wind density scaling")
	var shear: Dictionary = Model.generation("wind", p, {"wind_speed_mps": 8.0, "wind_height_m": 10.0})
	check(shear.mw > standard.mw, "explicit measurement height applies shear")
	for density in [0.1, 0.5, 0.9, 1.225, 2.0]:
		for speed in [3.1, 5.0, 8.0, 11.4, 14.0, 20.0, 24.9]:
			var g: Dictionary = Model.generation("wind", p, {"wind_speed_mps": speed, "air_density_kgm3": density})
			check(g.mw <= 5.0 + 1.0e-9 and g.cp_aero <= 0.49 + 1.0e-9, "density/speed constrained physical output")
	check(not Model.generation("wind", p, {"wind_speed_mps": NAN}).valid, "invalid weather rejected")
	check(not Model.generation("wind", p, {"wind_height_m": 0.0}).valid, "zero reference height rejected")

func _test_pv() -> void:
	var p: Dictionary = Model.defaults("pv")
	near(Model.generation("pv", p, {"irradiance_wm2": 0.0}).mw, 0.0, "PV night zero")
	var weather: Dictionary = {"irradiance_wm2": 800.0, "air_temp_c": 20.0, "pv_wind_speed_mps": 2.0}
	var g: Dictionary = Model.generation("pv", p, weather)
	near(g.module_temp_c, 20.0 + 800.0 / (25.0 + 6.84 * 2.0), "Faiman module temperature exact")
	near(g.cell_temp_c, g.module_temp_c + 2.4, "module-cell offset explicit")
	near(g.dc_mw, 1.2 * 0.8 * (1.0 - 0.004 * (g.cell_temp_c - 25.0)) * 0.98, "PV DC calculation")
	near(g.gross_dc_mw - g.dc_loss_mw, g.dc_mw, "DC system-loss balance")
	near(g.dc_mw, g.ac_mw + g.inverter_loss_mw + g.clipping_mw, "DC/inverter/clipping balance")
	var hot: Dictionary = weather.duplicate()
	hot.air_temp_c = 50.0
	check(Model.generation("pv", p, hot).mw < g.mw, "hotter PV lower power")
	var breezy: Dictionary = weather.duplicate()
	breezy.pv_wind_speed_mps = 10.0
	check(Model.generation("pv", p, breezy).mw > g.mw, "wind cooling increases PV output")
	var clipped: Dictionary = Model.generation("pv", {"dc_capacity_mw": 3.0, "temp_coefficient_per_c": 0.0}, {"irradiance_wm2": 1000.0})
	near(clipped.mw, 1.0, "inverter hard nameplate cap")
	check(clipped.clipping_mw > 1.0, "inverter clipping explicit")
	near(clipped.dc_mw, clipped.ac_mw + clipped.inverter_loss_mw + clipped.clipping_mw, "clipped DC balance")
	check(not Model.generation("pv", p, {"irradiance_wm2": -1.0}).valid, "negative irradiance rejected")
	check(not Model.generation("pv", p, {"air_temp_c": INF}).valid, "invalid temperature rejected")

func _test_network() -> void:
	var devices: Array = [dev(7, "wind"), dev(100, "station", {"capacity_mw": 10.0, "loss_fraction": 0.1})]
	var links: Array = [link(7, 100, 10.0, 0.1), link(100, -1, 10.0, 0.1)]
	var direct: Dictionary = {"7": {"mw": 3.0, "source": "csv:test.csv"}}
	var r: Dictionary = Model.solve(devices, links, {}, direct)
	near(r.generated_mw, 3.0, "direct power used")
	near(r.delivered_mw, 3.0 * 0.9 * 0.9 * 0.9, "three serial losses")
	near(r.lines[0].loss_mw, 0.3, "first link loss")
	near(r.devices["100"].loss_mw, 0.27, "station loss")
	near(r.lines[1].loss_mw, 0.243, "grid link loss")
	check(r.devices["7"].source == "csv:test.csv", "source provenance retained")
	invariants(r, "serial network")
	var original: String = JSON.stringify([devices, links, direct])
	Model.solve(devices, links, {"wind_speed_mps": 25.0}, direct)
	check(JSON.stringify([devices, links, direct]) == original, "pure solve leaves inputs untouched")
	r = Model.solve(devices, [], {"wind_speed_mps": 12.0})
	near(r.delivered_mw, 0.0, "disconnected generation not exported")
	near(r.curtailed_mw, 5.0, "disconnected generation curtailed")
	near(r.loss_mw, 0.0, "disconnected power produces no phantom losses")
	invariants(r, "disconnected")
	r = Model.solve(devices, [links[0]], {}, direct)
	near(r.loss_mw, 0.0, "dead-end station consumes no power")
	near(r.curtailed_mw, 3.0, "dead-end curtailment")
	r = Model.solve(devices, links + [links[0].duplicate(), links[1].duplicate()], {}, direct)
	near(r.delivered_mw, 2.187, "duplicate connections cannot duplicate power")
	check(not r.lines[2].valid and not r.lines[3].valid, "duplicates flagged")
	invariants(r, "duplicate links")
	r = Model.solve(devices + [dev(7, "wind")], links, {}, direct)
	near(r.generated_mw, 3.0, "duplicate device ID not counted")
	check(not r.errors.is_empty(), "duplicate ID reported")
	r = Model.solve(devices, [link(7, -1), link(100, 7), link(7, 7), link(999, 100)], {}, direct)
	near(r.delivered_mw, 0.0, "invalid topology cannot export")
	check(r.warnings.size() == 4, "all invalid topology diagnosed")
	invariants(r, "invalid links")
	r = Model.solve(devices, links, {"wind_speed_mps": 12.0}, {"7": {"mw": 0.0, "source": "zero measurement"}})
	near(r.generated_mw, 0.0, "explicit direct zero overrides modeled weather")
	r = Model.solve(devices, links, {"wind_speed_mps": NAN}, direct)
	near(r.generated_mw, 3.0, "valid direct power independent of invalid unused weather")
	r = Model.solve(devices, links, {"wind_speed_mps": 12.0}, {"7": {"mw": NAN}})
	near(r.generated_mw, 0.0, "invalid direct does not silently fall back to weather")
	check(not r.devices["7"].valid, "invalid direct flagged")
	r = Model.solve(devices, links, {}, {"7": {"mw": 12.0}})
	near(r.generated_mw, 5.0, "direct nameplate cap")
	near(r.nameplate_clipped_mw, 7.0, "direct excess separately disclosed")
	invariants(r, "nameplate clipping")
	var zero_cap: Array = [link(7, 100, 0.0), links[1]]
	r = Model.solve(devices, zero_cap, {}, direct)
	near(r.delivered_mw, 0.0, "zero-capacity line cannot transmit")
	invariants(r, "zero line capacity")
	for malformed in [null, 1, {}, {"from": "7", "to": 100}, link(7, 100, NAN), link(7, 100, 4.0, 1.0)]:
		r = Model.solve(devices, [malformed], {}, direct)
		check(not r.lines[0].valid, "malformed link rejected")
		invariants(r, "malformed")
	r = Model.solve([null, {}, {"id": 1.5}, dev(3, "bogus"), {"id": 4, "kind": "wind", "params": null}], [], {})
	near(r.generated_mw, 0.0, "malformed devices safe")
	check(r.errors.size() == 5, "malformed device errors explicit")

func _test_dispatch() -> void:
	# A greedy allocation of generator 1 to station 3 strands generator 2.
	# The LP reroutes 1 to station 4, using both generators and both stations.
	var devices: Array = [dev(1, "wind"), dev(2, "wind"),
		dev(3, "station", {"capacity_mw": 2.0, "loss_fraction": 0.0}),
		dev(4, "station", {"capacity_mw": 2.0, "loss_fraction": 0.0})]
	var links: Array = [link(1, 3), link(1, 4), link(2, 3), link(3, -1), link(4, -1)]
	var direct: Dictionary = {"1": {"mw": 2.0}, "2": {"mw": 2.0}}
	var r: Dictionary = Model.solve(devices, links, {}, direct)
	near(r.delivered_mw, 4.0, "dispatch reroutes shared bottleneck for optimum")
	near(r.curtailed_mw, 0.0, "rerouting avoids unnecessary curtailment")
	invariants(r, "reroute")
	# Shared generator across stations must never be copied.
	direct = {"1": {"mw": 1.0}, "2": {"mw": 0.0}}
	r = Model.solve(devices, links, {}, direct)
	near(r.delivered_mw, 1.0, "one MW across multiple paths remains one MW")
	invariants(r, "shared generator")
	# A source above grid capacity is curtailed at source, before losses.
	devices = [dev(1, "wind"), dev(3, "station", {"capacity_mw": 10.0, "loss_fraction": 0.01})]
	links = [link(1, 3, 10.0, 0.01), link(3, -1, 10.0, 0.01)]
	r = Model.solve(devices, links, {}, {"1": {"mw": 5.0}})
	near(r.delivered_mw, 4.0, "global 4MW grid cap")
	near(r.devices["1"].sent_mw, 4.0 / pow(0.99, 3.0), "downstream cap propagated through all losses")
	invariants(r, "grid cap")
	links[0].capacity_mw = 2.0
	r = Model.solve(devices, links, {}, {"1": {"mw": 5.0}})
	near(r.delivered_mw, 2.0 * pow(0.99, 3.0), "incoming capacity before line loss")
	invariants(r, "incoming cap")
	links[0].capacity_mw = 10.0
	links[1].capacity_mw = 2.0
	r = Model.solve(devices, links, {}, {"1": {"mw": 5.0}})
	near(r.delivered_mw, 1.98, "outgoing capacity before last line loss")
	invariants(r, "outgoing cap")
	devices[1].params.capacity_mw = 1.5
	r = Model.solve(devices, links, {}, {"1": {"mw": 5.0}})
	near(r.delivered_mw, 1.5 * 0.99 * 0.99, "station nameplate at receiving terminal")
	invariants(r, "station cap")
	# Direct PV is already AC and must not be converted or derated a second time.
	r = Model.solve([dev(1, "pv"), dev(3, "station", {"loss_fraction": 0.0})], [link(1, 3), link(3, -1)], {}, {"1": {"mw": 0.8}})
	near(r.delivered_mw, 0.8, "direct PV terminal AC not converted twice")
	invariants(r, "direct PV")

func _test_random_networks() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20261015
	for trial in 120:
		var devices: Array = []
		var links: Array = []
		var direct: Dictionary = {}
		for id in range(1, 7):
			devices.append(dev(id, "wind"))
			direct[str(id)] = {"mw": rng.randf_range(0.0, 6.0)}
		for station in range(10, 14):
			devices.append(dev(station, "station", {"capacity_mw": rng.randf_range(0.1, 5.0), "loss_fraction": rng.randf_range(0.0, 0.2)}))
			if rng.randf() > 0.15:
				links.append(link(station, -1, rng.randf_range(0.0, 5.0), rng.randf_range(0.0, 0.2)))
			for id in range(1, 7):
				if rng.randf() > 0.45:
					links.append(link(id, station, rng.randf_range(0.0, 5.0), rng.randf_range(0.0, 0.2)))
		if not links.is_empty() and trial % 3 == 0:
			links.append(links[0].duplicate())
		var r: Dictionary = Model.solve(devices, links, {}, direct)
		invariants(r, "random %d" % trial)
		var restored: Dictionary = Model.solve(JSON.parse_string(JSON.stringify(devices)), JSON.parse_string(JSON.stringify(links)), {}, JSON.parse_string(JSON.stringify(direct)))
		near(restored.delivered_mw, r.delivered_mw, "JSON roundtrip stable %d" % trial)
		links.reverse()
		devices.reverse()
		var reordered: Dictionary = Model.solve(devices, links, {}, direct)
		near(reordered.delivered_mw, r.delivered_mw, "order-independent optimum %d" % trial)
