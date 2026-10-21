extends SceneTree
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("CHEM_DT_FAIL: ", label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var w = load("res://main.tscn").instantiate()
	root.add_child(w)
	await process_frame
	w.set_process(false)
	w.chemical_example()
	check(w.devices.size() == 12 and w.links.size() == 20, "actual example topology")
	var rng := RandomNumberGenerator.new()
	rng.seed = 8244632
	for i in 600:
		var dt: float = rng.randf_range(0.00001, 0.49)
		var before: Dictionary = w.state().duplicate(true)
		var ok: bool = w.advance(dt)
		check(ok, "fractional advance %d dt=%s t=%s" % [i, str(dt), str(w.elapsed_s)])
		if not ok:
			w.dispatch_dt_s = dt
			var diagnostic: Dictionary = w.solve_at(w.elapsed_s)
			w.dispatch_dt_s = 1.0
			print("DT_DIAGNOSTIC ", JSON.stringify({"before": before, "requested_dt": dt, "report": diagnostic}))
			break
		check(w.Materials.validate_energy(w.material_energy, w.devices).is_empty(), "live ledger %d" % i)
	if failures.is_empty():
		for dt in [1e-12, 1e-10, 1e-8, 1e-6, 0.0001, 0.0, 37.123456789]:
			var ok: bool = w.advance(dt)
			check(ok, "tiny/zero/long advance " + str(dt))
			if not ok:
				w.dispatch_dt_s = dt
				print("EXTREME_DT_DIAGNOSTIC ", JSON.stringify({"dt": dt, "report": w.solve_at(w.elapsed_s)}))
				w.dispatch_dt_s = 1.0
				break
	if failures.is_empty():
		for i in 180:
			w.speed = [1.0, 7.0, 60.0][i % 3]
			var dt: float = rng.randf_range(0.001, 0.31)
			w.paused = true
			var time_before: float = w.elapsed_s
			w._process(dt)
			check(w.elapsed_s == time_before, "paused process preserves time " + str(i))
			w.paused = false
			w._process(dt)
			check(not w.paused and w.elapsed_s > time_before, "real variable-dt process " + str(i))
			check(w.Materials.validate_energy(w.material_energy, w.devices).is_empty(), "process ledger " + str(i))
			if w.paused: break
	check(w.validate_state(JSON.parse_string(JSON.stringify(w.state()))).is_empty(), "fractional run JSON save")
	w.paused = true
	w.queue_free()
	await process_frame
	await process_frame
	print("CHEMICAL_VARIABLE_DT_WORLD: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
