extends SceneTree
const F = preload("res://tests/test_chemical_process_physics.gd")
const P = preload("res://tests/test_phase_hydrogen_physics.gd")
const M = preload("res://scripts/energy_model.gd")
const C = M.Catalog
const D = M.Dispatch.Materials
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("MATERIAL_BOUNDARY_FAIL: ", label)
func verify(f: Dictionary, dt: float, label: String, power: float = 0.2) -> void:
	var before: Dictionary = f.duplicate(true)
	var ledger: Dictionary = D.initial_energy(f.devices)
	var report: Dictionary = M.dispatch(f.devices, f.links, {}, {"1":{"mw":power}}, dt)
	check(f == before, label + " pure reservation")
	check(report.valid, label + " valid " + str(report.errors) + str(report.warnings))
	if not report.valid: return
	check(M.audit_dispatch(f.devices, f.links, report).is_empty(), label + " independent audit")
	for device in f.devices:
		var id: String = str(device.id)
		if not report.next_states.has(id): continue
		device.state = report.next_states[id].duplicate(true)
		if device.kind in C.Materials.INVENTORY_KINDS:
			var kg: float = device.state.material_inventory_kg[C.Materials.species(device.kind)]
			check(is_finite(kg) and kg >= 0.0 and kg <= C.inventory_capacity(device.kind, device.params), label + " strict stock " + id)
	ledger = D.accumulate_energy(ledger, report, dt)
	check(not ledger.is_empty(), label + " cumulative account")
	check(D.validate_energy(ledger, f.devices).is_empty(), label + " actual-world account")
func _initialize() -> void:
	var helper = F.new()
	for kind in C.Materials.SYNTHESIS_KINDS:
		var cc: Dictionary = C.Materials.chemical_coefficients(kind)
		for store in C.Materials.HYDROGEN_STORE_KINDS:
			for dt in [0.26229763235041564, 0.04617816977261927, 0.999999999999, 1e-8, 1e-12]:
				for boundary in ["hydrogen", "feed", "product", "shared_fc"]:
					var f: Dictionary = helper.fixture(kind, store)
					if boundary == "hydrogen" or boundary == "shared_fc": f.devices[2].state.material_inventory_kg.H2 = 1.4937960025933568e-6 if kind == "ammonia_synthesis_station" else 9.373835549277832e-8
					if boundary == "feed": f.devices[3].state.material_inventory_kg[cc.feed] = 1.4937960025933568e-6
					if boundary == "product": f.devices[4].state.material_inventory_kg[cc.product] = C.inventory_capacity(kind) - 1e-10
					if boundary == "shared_fc":
						f.devices.append(helper.node(7, "fuel_cell_station"))
						f.devices.append(helper.node(8, "station", {"capacity_mw":10.0, "loss_fraction":0.0}))
						f.links.remove_at(3) # Renewable AC cannot bypass the FC into this load.
						f.links.append(helper.edge(f.devices, 3, 7, "h2_out", "h2_in"))
						f.links.append(helper.edge(f.devices, 7, 8, "ac_out", "in"))
						f.links.append(helper.edge(f.devices, 8, 6, "out", "in"))
						f.devices[5].params.demand_mw = minf(1.0, f.devices[2].state.material_inventory_kg.H2 * 3.6 * C.Materials.coefficients().lhv_kwh_per_kg * 0.5 / dt * 0.5)
					verify(f, dt, kind + "/" + store + "/" + boundary + "/" + str(dt))
	helper.free()
	var phase = P.new()
	for kind in C.Materials.PHASE_KINDS:
		for dt in [0.26229763235041564, 1e-8, 1e-12]:
			var f: Dictionary = phase.fixture(kind)
			f.devices[4].state.material_inventory_kg.H2 = C.inventory_capacity(kind) - 1e-10
			verify(f, dt, "charge headroom " + kind + "/" + str(dt))
	phase.free()
	var m: Dictionary = D.empty()
	m.inventory_by_reference_kg = D.Ledger.empty_inventory()
	m.inventory_by_reference_kg.H2_liquid_20k = -1e-19
	D._chemical_balance({"nodes":{}, "report":{"dt_s":0.1}}, m)
	check(not is_finite(m.enthalpy_balance_error_mw) and not is_finite(m.hydrogen_element_error_kg), "invalid reference map fails closed rather than zero atoms")
	print("MATERIAL_REPRESENTABLE_BOUNDARIES: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
