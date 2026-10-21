extends SceneTree
## Run with isolated HOME/XDG dirs: godot --headless --path . --script tests/test_wind_curve.gd
const Model = preload("res://scripts/energy_model.gd")
const Validator = preload("res://scripts/save_validator.gd")
var checks: int = 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("WIND_CURVE_FAIL: " + label)

func near(actual: float, expected: float, label: String, tolerance: float = 1.0e-9) -> void:
	check(is_finite(actual) and absf(actual - expected) <= tolerance, "%s (actual %.12f, expected %.12f)" % [label, actual, expected])

func point(v: Variant, p: Variant) -> Dictionary:
	return {"wind_mps": v, "power_kw": p}

func params() -> Dictionary:
	return {"power_curve_kw": [point(3.0, 0.0), point(6.0, 200.0), point(8.0, 1000.0), point(12.0, 3500.0), point(20.0, 4500.0), point(25.0, 4500.0)]}

func invalid(p: Dictionary, label: String) -> void:
	var errors: Array[String] = Model.validate("wind", p)
	check(not errors.is_empty(), label + " rejected")
	var g: Dictionary = Model.generation("wind", p, {"wind_speed_mps": 8.0})
	check(not g.valid, label + " generation invalid")
	near(g.mw, 0.0, label + " invalid data cannot generate")

func kinetic(v: float, density: float = 1.225, diameter: float = 126.0) -> float:
	return 0.5 * density * PI * pow(diameter * 0.5, 2.0) * pow(v, 3.0) / 1.0e6

func _initialize() -> void:
	_test_schema()
	_test_interpolation_and_cutoffs()
	_test_cp_validation()
	_test_density_and_efficiency()
	_test_network_precedence_and_balance()
	_test_old_defaults_and_roundtrip()
	_test_seeded_segments()
	print("WIND_CURVE_TESTS: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_schema() -> void:
	var d: Dictionary = Model.defaults("wind")
	near(d.reference_air_density_kgm3, 1.225, "default reference density")
	check(d.power_curve_kw is Array and d.power_curve_kw.is_empty(), "default curve disabled")
	check(Model.validate("wind", params()).is_empty(), "custom curve fixture valid")
	for bad in [null, "3,0\n8,1000", {}, 5, true, PackedFloat64Array([3.0, 8.0])]:
		invalid({"power_curve_kw": bad}, "malformed curve " + str(bad))
	for curve in [[point(3.0, 0.0)], [null, point(8, 1000)], [point(3, 0), {}], [point(3, 0), [8, 1000]], [point(3, 0), {"wind_mps": 8, "power_kw": 1000, "typo": 1}]]:
		invalid({"power_curve_kw": curve}, "malformed curve point " + str(curve))
	for bad in [-0.1, 100.01, INF, NAN, "8", null, true]:
		invalid({"power_curve_kw": [point(3, 0), point(bad, 1000)]}, "invalid curve speed " + str(bad))
	for bad in [-0.1, 5000.001, INF, NAN, "1000", null, true]:
		invalid({"power_curve_kw": [point(3, 0), point(8, bad)]}, "invalid curve power " + str(bad))
	for curve in [[point(8, 0), point(8, 1000)], [point(8, 1000), point(3, 0)]]:
		invalid({"power_curve_kw": curve}, "unsorted or duplicate speeds")
	for bad in [0.4999, 2.0001, INF, NAN, "1.225", null, true]:
		invalid({"reference_air_density_kgm3": bad}, "invalid reference density " + str(bad))
	for density in [0.5, 2.0]:
		check(Model.validate("wind", {"reference_air_density_kgm3": density, "power_curve_kw": [point(0, 0), point(100, 0)]}).is_empty(), "inclusive density and curve speed bounds")
	var many: Array = []
	for i in 256:
		many.append(point(float(i) / 255.0 * 100.0, 0.0))
	check(Model.validate("wind", {"power_curve_kw": many}).is_empty(), "256-point curve accepted")
	many.append(point(100, 0))
	invalid({"power_curve_kw": many}, "257-point curve")
	invalid({"power_curve_kw": [point(3, 0), point(8, 1000)], "rated_mw": "5"}, "bad scalar with curve safe")
	var original: String = JSON.stringify(params())
	Model.validate("wind", params())
	check(JSON.stringify(params()) == original, "validation does not mutate curve")
	d.power_curve_kw.append(point(3, 0))
	check(Model.defaults("wind").power_curve_kw.is_empty(), "default arrays do not leak across calls")

func _test_interpolation_and_cutoffs() -> void:
	var p: Dictionary = params()
	for pair in [[3.0, 0.0], [4.5, 0.1], [6.0, 0.2], [7.0, 0.6], [8.0, 1.0], [10.0, 2.25], [12.0, 3.5], [16.0, 4.0], [20.0, 4.5], [24.999, 4.5]]:
		var g: Dictionary = Model.generation("wind", p, {"wind_speed_mps": pair[0]})
		check(g.valid and g.curve_mode == "custom", "custom branch " + str(pair[0]))
		near(g.mw, pair[1], "exact endpoint or linear interpolation " + str(pair[0]))
	for speed in [0.0, 2.999999, 25.0, 25.000001, 100.0, 150.0]:
		near(Model.generation("wind", p, {"wind_speed_mps": speed}).mw, 0.0, "operating cutoff " + str(speed))
	var bounded: Dictionary = {"power_curve_kw": [point(8, 1000), point(20, 2000)]}
	for pair in [[7.999999, 0.0], [8.0, 1.0], [14.0, 1.5], [20.0, 2.0], [20.000001, 0.0]]:
		near(Model.generation("wind", bounded, {"wind_speed_mps": pair[0]}).mw, pair[1], "point range inclusive without extrapolation " + str(pair[0]))
	bounded.cut_in_mps = 10.0
	bounded.cut_out_mps = 18.0
	for pair in [[9.999999, 0.0], [10.0, 7.0 / 6.0], [17.999999, 1.0 + 9.999999 / 12.0], [18.0, 0.0]]:
		near(Model.generation("wind", bounded, {"wind_speed_mps": pair[0]}).mw, pair[1], "cutoffs inside curve " + str(pair[0]))
	bounded.rated_speed_mps = 5.0
	check(Model.validate("wind", bounded).is_empty(), "unused rated speed need not lie between custom cutoffs")
	near(Model.generation("wind", bounded, {"wind_speed_mps": 14.0}).mw, 1.5, "custom curve ignores cubic rated-speed shape")
	bounded.cut_out_mps = 10.0
	invalid(bounded, "custom cut-in must be below cut-out")
	var descending: Dictionary = {"power_curve_kw": [point(8, 1000), point(12, 500), point(20, 0)]}
	check(Model.validate("wind", descending).is_empty(), "descending powers allowed")
	near(Model.generation("wind", descending, {"wind_speed_mps": 10.0}).mw, 0.75, "descending interpolation")
	var g: Dictionary = Model.generation("wind", p, {"wind_speed_mps": 7.0, "wind_height_m": 10.0})
	var hub: float = 7.0 * pow(90.0 / 10.0, 0.14)
	near(g.wind_speed_mps, hub, "shear before interpolation")
	near(g.mw, Model.generation("wind", p, {"wind_speed_mps": hub}).mw, "shear is not applied twice")

func _test_cp_validation() -> void:
	invalid({"power_curve_kw": [point(0, 1), point(8, 1000)]}, "nonzero output at zero wind")
	invalid({"power_curve_kw": [point(0, 0), point(8, 1.0e-12)]}, "arbitrarily small positive slope from zero has unbounded Cp")
	check(Model.validate("wind", {"power_curve_kw": [point(0, 0), point(3, 0), point(8, 100)]}).is_empty(), "zero interval before positive power")
	invalid({"power_curve_kw": [point(3, 1000), point(8, 1000)]}, "endpoint Cp limit")
	var cp: float = 0.4
	var p4: float = kinetic(4.0) * 0.944 * cp * 1000.0
	var p8: float = kinetic(8.0) * 0.944 * cp * 1000.0
	check(p4 / 1000.0 / (kinetic(4.0) * 0.944) < 0.49 and p8 / 1000.0 / (kinetic(8.0) * 0.944) < 0.49, "adversarial endpoints both feasible")
	var p: Dictionary = {"power_curve_kw": [point(4, p4), point(8, p8)]}
	var errors: String = "; ".join(Model.validate("wind", p))
	check(errors.contains("interior Cp="), "analytic interior maximum catches infeasible chord")
	invalid(p, "interior-violating curve is rejected, not silently clipped")
	# This plateau touches the envelope at its left endpoint and then decreases in Cp.
	p = {"power_curve_kw": [point(8, kinetic(8) * 0.944 * 0.49 * 1000), point(12, kinetic(8) * 0.944 * 0.49 * 1000)]}
	check(Model.validate("wind", p).is_empty(), "exact Cp boundary accepted")
	p.cp_max = 0.48
	invalid(p, "configured Cp bound stricter than Betz")
	p = params()
	p.cp_max = Model.BETZ_LIMIT + 0.000001
	invalid(p, "Betz bound remains strict")
	# Narrow segment and extremely small speeds must not cause a sampling gap or NaN.
	p = {"power_curve_kw": [point(8.0, 1000), point(8.000000000001, 1000.000000001)]}
	check(Model.validate("wind", p).is_empty(), "near-coincident distinct speeds remain valid")
	invalid({"power_curve_kw": [point(1.0e-100, 1.0), point(2.0e-100, 1.0)]}, "near-zero kinetic energy is rejected safely")
	check(Model.validate("wind", {"power_curve_kw": [point(1.0e-100, 0.0), point(2.0e-100, 0.0)]}).is_empty(), "near-zero all-zero segment remains valid")
	var tiny_kw: float = kinetic(0.001) * 0.944 * 0.4 * 1000.0
	p = {"cut_in_mps": 0.0, "power_curve_kw": [point(0.001, tiny_kw), point(0.002, tiny_kw)]}
	check(Model.validate("wind", p).is_empty(), "tiny valid electrical curve accepted")
	var tiny: Dictionary = Model.generation("wind", p, {"wind_speed_mps": 0.001})
	near(tiny.cp_aero, 0.4, "Cp remains accurate below generic MW epsilon")
	check(tiny.mw > 0.0, "tiny positive curve is not discarded")
	p = {"rotor_diameter_m": 1.0e-100, "drivetrain_efficiency": 1.0e-200, "power_curve_kw": [point(3, 0), point(6, 0)]}
	check(Model.validate("wind", p).is_empty(), "all-zero curve with underflowing electrical kinetic denominator valid")
	tiny = Model.generation("wind", p, {"wind_speed_mps": 4.0})
	near(tiny.cp_aero, 0.0, "zero divided by underflowed denominator never becomes NaN")

func _test_density_and_efficiency() -> void:
	var p: Dictionary = params()
	var low_eta: Dictionary = p.duplicate(true)
	low_eta.drivetrain_efficiency = 0.8
	check(Model.validate("wind", low_eta).is_empty(), "lower efficiency still feasible fixture")
	for speed in [6.0, 8.0, 10.0, 12.0, 20.0]:
		var g: Dictionary = Model.generation("wind", p, {"wind_speed_mps": speed})
		var g_eta: Dictionary = Model.generation("wind", low_eta, {"wind_speed_mps": speed})
		near(g_eta.mw, g.mw, "electrical curve not multiplied by efficiency " + str(speed))
		check(g_eta.cp_aero > g.cp_aero, "efficiency changes inferred aerodynamic Cp only")
	p.drivetrain_efficiency = 0.1
	invalid(p, "efficiency still constrains feasibility")
	p = params()
	for rho in [0.1, 0.5, 0.9, 1.225, 2.0]:
		for speed in [3.5, 6.0, 8.0, 10.0, 12.0, 20.0, 24.9]:
			var base: Dictionary = Model.generation("wind", p, {"wind_speed_mps": speed})
			var g: Dictionary = Model.generation("wind", p, {"wind_speed_mps": speed, "air_density_kgm3": rho})
			near(g.density_adjusted_mw, base.mw * rho / 1.225, "density applies once")
			near(g.mw, minf(5.0, base.mw * rho / 1.225), "density-corrected electrical output")
			near(g.density_adjusted_mw, g.mw + g.nameplate_clipped_mw, "density clipping explicitly accounted")
			check(g.cp_aero <= 0.49 + 1.0e-9, "validated density-independent Cp")
	p.reference_air_density_kgm3 = 1.6
	check(Model.validate("wind", p).is_empty(), "editable reference density accepted")
	var same_density: Dictionary = Model.generation("wind", p, {"wind_speed_mps": 8.0, "air_density_kgm3": 1.6})
	near(same_density.mw, 1.0, "reference equals actual reproduces curve")
	near(Model.generation("wind", p, {"wind_speed_mps": 8.0}).mw, 1.0 * 1.225 / 1.6, "missing weather density remains actual default, not reference parameter")
	near(Model.generation("wind", p, {"wind_speed_mps": 8.0, "air_density_kgm3": 0.8}).mw, 0.5, "reference and actual density distinguished")
	var infeasible: Dictionary = {"reference_air_density_kgm3": 0.5, "power_curve_kw": [point(8, 1500), point(12, 1500)]}
	invalid(infeasible, "reference density participates in validation")
	var cubic: Dictionary = {"reference_air_density_kgm3": 1.6}
	check(Model.validate("wind", cubic).is_empty(), "reference density available to default cubic")
	near(Model.generation("wind", cubic, {"wind_speed_mps": 8.0}).mw / Model.generation("wind", {}, {"wind_speed_mps": 8.0}).mw, 1.225 / 1.6, "cubic also uses configured reference density")

func devices(p: Dictionary) -> Array:
	return [{"id": 0, "kind": "wind", "params": p, "x": -20.0, "z": 0.0}, {"id": 1, "kind": "station", "params": {"capacity_mw": 10.0, "loss_fraction": 0.1}, "x": 20.0, "z": 0.0}]

func links() -> Array:
	return [{"from": 0, "to": 1, "capacity_mw": 10.0, "loss_fraction": 0.1}, {"from": 1, "to": -1, "capacity_mw": 10.0, "loss_fraction": 0.1}]

func balance(r: Dictionary, label: String) -> void:
	near(r.generated_mw, r.delivered_mw + r.curtailed_mw + r.loss_mw, label + " network conservation")
	near(r.balance_error_mw, 0.0, label + " reported residual")
	near(r.devices["0"].mw, r.devices["0"].sent_mw + r.devices["0"].curtailed_mw, label + " generator conservation")
	near(r.devices["1"].input_mw, r.devices["1"].output_mw + r.devices["1"].loss_mw, label + " station conservation")
	near(r.loss_mw, r.line_loss_mw + r.station_loss_mw, label + " loss classification")
	check(r.delivered_mw <= 4.0 + 1.0e-9 and r.curtailed_mw >= -1.0e-9, label + " capacity and nonnegative curtailment")
	for l in r.lines:
		near(l.sent_mw, l.received_mw + l.loss_mw, label + " line conservation")

func _test_network_precedence_and_balance() -> void:
	var ds: Array = devices(params())
	var ls: Array = links()
	var r: Dictionary = Model.solve(ds, ls, {"wind_speed_mps": 8.0})
	near(r.generated_mw, 1.0, "curve used without direct input")
	near(r.delivered_mw, pow(0.9, 3), "curve power losses counted once")
	balance(r, "custom curve network")
	for power in [0.0, 0.7, 4.0, 7.0]:
		r = Model.solve(ds, ls, {"wind_speed_mps": 8.0, "air_density_kgm3": 2.0}, {"0": {"mw": power, "source": "csv:test.csv"}})
		near(r.generated_mw, minf(power, 5.0), "direct overrides without curve, density or efficiency stacking")
		check(r.devices["0"].source == "csv:test.csv" and r.devices["0"].model == "direct AC terminal power", "direct provenance preserved")
		near(r.nameplate_clipped_mw, maxf(0.0, power - 5.0), "direct clipping remains explicit")
		balance(r, "direct override")
	r = Model.solve(ds, ls, {"wind_speed_mps": NAN, "air_density_kgm3": NAN}, {"0": {"mw": 0.7}})
	near(r.generated_mw, 0.7, "direct ignores unused malformed weather")
	r = Model.solve(ds, ls, {"wind_speed_mps": 8.0}, {"0": {"mw": NAN}})
	check(not r.devices["0"].valid, "invalid direct remains error")
	near(r.generated_mw, 0.0, "invalid direct cannot silently fall back to curve")
	for speed in [0.0, 3.0, 6.0, 8.0, 12.0, 20.0, 25.0]:
		for rho in [0.1, 1.225, 2.0]:
			r = Model.solve(ds, ls, {"wind_speed_mps": speed, "air_density_kgm3": rho})
			balance(r, "density and speed sweep")
			r = Model.solve(ds, [], {"wind_speed_mps": speed, "air_density_kgm3": rho})
			near(r.generated_mw, r.curtailed_mw, "disconnected curve generation curtailed")
			near(r.loss_mw, 0.0, "disconnected curve generates no phantom losses")
	r = Model.solve(ds, ls, {"wind_speed_mps": 20.0, "air_density_kgm3": 2.0})
	near(r.nameplate_clipped_mw, 4.5 * 2.0 / 1.225 - 5.0, "custom density nameplate clipping aggregated outside network balance")
	var encoded: String = JSON.stringify([ds, ls])
	Model.solve(ds, ls, {"wind_speed_mps": 12.0})
	check(JSON.stringify([ds, ls]) == encoded, "solve leaves nested curve and all input dictionaries unchanged")

func old_cubic(p: Dictionary, speed: float, rho: float) -> float:
	if speed < p.cut_in_mps or speed >= p.cut_out_mps:
		return 0.0
	var fraction: float = maxf(0.0, (pow(speed, 3.0) - pow(p.cut_in_mps, 3.0)) / (pow(p.rated_speed_mps, 3.0) - pow(p.cut_in_mps, 3.0)))
	return minf(minf(p.rated_mw, p.rated_mw * fraction * rho / 1.225), kinetic(speed, rho, p.rotor_diameter_m) * p.cp_max * p.drivetrain_efficiency)

func _test_old_defaults_and_roundtrip() -> void:
	var legacy: Dictionary = Model.defaults("wind")
	legacy.erase("reference_air_density_kgm3")
	legacy.erase("power_curve_kw")
	check(legacy.size() == 9 and Model.validate("wind", legacy).is_empty(), "old nine-parameter wind remains valid")
	for rho in [0.1, 0.5, 0.9, 1.225, 2.0]:
		for i in range(0, 301):
			var speed: float = float(i) / 10.0
			var expected: float = old_cubic(legacy, speed, rho)
			var result: Dictionary = Model.generation("wind", legacy, {"wind_speed_mps": speed, "air_density_kgm3": rho})
			near(result.mw, expected, "legacy formula identical", 0.0)
			near(Model.generation("wind", {}, {"wind_speed_mps": speed, "air_density_kgm3": rho}).mw, expected, "missing fields merge defaults", 0.0)
	var p: Dictionary = params()
	p.reference_air_density_kgm3 = 1.6
	p.power_curve_kw[2].power_kw = 1000.123456789
	var restored: Dictionary = JSON.parse_string(JSON.stringify(p))
	check(Model.validate("wind", restored).is_empty(), "JSON curve params valid")
	near(restored.reference_air_density_kgm3, p.reference_air_density_kgm3, "density JSON roundtrip")
	near(restored.power_curve_kw[2].power_kw, p.power_curve_kw[2].power_kw, "curve precision survives JSON", 1.0e-10)
	for speed in [4.0, 8.0, 9.0, 12.0, 20.0, 25.0]:
		near(Model.generation("wind", restored, {"wind_speed_mps": speed}).mw, Model.generation("wind", p, {"wind_speed_mps": speed}).mw, "restored generation matches")
	var state: Dictionary = {"schema": 3, "model_version": 11, "rebuild": true, "devices": devices(p), "links": links(),
		"templates": {"wind": p.duplicate(true), "pv": Model.defaults("pv"), "station": Model.defaults("station")},
		"imports": [], "next_id": 2, "elapsed_s": 0.0, "energy": {"generated": 0.0, "delivered": 0.0, "curtailed": 0.0, "loss": 0.0}, "physical_lines": true}
	check(Validator.validate(state).is_empty(), "custom device and template accepted by unchanged save validator")
	var loaded: Dictionary = JSON.parse_string(JSON.stringify(state))
	check(Validator.validate(loaded).is_empty(), "full custom save JSON roundtrip")
	near(Model.solve(state.devices, state.links, {"wind_speed_mps": 10.0}).generated_mw, Model.solve(loaded.devices, loaded.links, {"wind_speed_mps": 10.0}).generated_mw, "save roundtrip network result")
	state.devices[0].params = legacy
	state.templates.wind = legacy.duplicate(true)
	check(Validator.validate(JSON.parse_string(JSON.stringify(state))).is_empty(), "old device and template save remains valid")
	var undo: Dictionary = loaded.duplicate(true)
	loaded.devices[0].params.power_curve_kw[2].power_kw = 400.0
	near(undo.devices[0].params.power_curve_kw[2].power_kw, p.power_curve_kw[2].power_kw, "deep dictionary snapshot retains curve for undo")
	loaded = undo.duplicate(true)
	check(Validator.validate(loaded).is_empty(), "undo snapshot restores valid save state")

func _test_seeded_segments() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 202610150422
	var accepted: int = 0
	var rejected: int = 0
	for trial in 160:
		var v0: float = rng.randf_range(0.1, 10.0)
		var v1: float = v0 + rng.randf_range(0.1, 10.0)
		var rho: float = rng.randf_range(0.5, 2.0)
		var eta: float = rng.randf_range(0.4, 1.0)
		var p0: float = minf(5000.0, kinetic(v0, rho) * eta * rng.randf_range(0.0, 0.6) * 1000.0)
		var p1: float = minf(5000.0, kinetic(v1, rho) * eta * rng.randf_range(0.0, 0.6) * 1000.0)
		var p: Dictionary = {"reference_air_density_kgm3": rho, "drivetrain_efficiency": eta, "power_curve_kw": [point(v0, p0), point(v1, p1)]}
		var valid: bool = Model.validate("wind", p).is_empty()
		var largest_cp: float = 0.0
		for i in 501:
			var t: float = float(i) / 500.0
			var speed: float = lerpf(v0, v1, t)
			var power: float = lerpf(p0, p1, t) / 1000.0
			largest_cp = maxf(largest_cp, power / (kinetic(speed, rho) * eta))
		if valid:
			accepted += 1
			check(largest_cp <= 0.49 + 1.0e-9, "analytic acceptance implies densely sampled physical feasibility")
			for i in 17:
				var speed: float = lerpf(v0, v1, float(i) / 16.0)
				var g: Dictionary = Model.generation("wind", p, {"wind_speed_mps": speed, "air_density_kgm3": rng.randf_range(0.1, 2.0)})
				check(g.valid and g.cp_aero <= 0.49 + 1.0e-9 and g.mw <= 5.0 + 1.0e-9, "accepted random curve remains feasible at actual density")
		else:
			rejected += 1
			check(largest_cp > 0.49 - 1.0e-5, "analytic rejection agrees with independent dense sample")
	check(accepted > 30 and rejected > 30, "seeded cases exercise both acceptance and rejection")
