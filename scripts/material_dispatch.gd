extends RefCounted
## Pure bounded 2A transactions. No live node is mutated here. A transaction
## reserves all material and terminal-AC paths before publishing any flow.
const MC = preload("res://scripts/material_catalog.gd")
const Ledger3 = preload("res://scripts/material_ledger_v3.gd")
const Ledger = preload("res://scripts/material_ledger_v2.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
const EPS := 1.0e-10
const ABS_TOL := 2.0e-6
const REL_TOL := 2.0e-12
const FIELDS := ["water_withdrawn_kg_s","hydrogen_produced_kg_s","hydrogen_consumed_kg_s","hydrogen_charged_kg_s","hydrogen_discharged_kg_s","hydrogen_leaked_kg","oxygen_vented_kg_s","oxygen_from_air_kg_s","water_released_kg_s","electrolyzer_electric_mw","compression_electric_mw","fuel_cell_output_mw","heat_rejected_mwth","hydrogen_inventory_kg","water_inventory_kg","hydrogen_lhv_mwh","hydrogen_leak_lhv_mwh","mass_balance_error_kg","hydrogen_element_error_kg","oxygen_element_error_kg","enthalpy_balance_error_mw"]
const CHEMICAL_FIELDS := ["chemical_electric_mw","ammonia_produced_kg_s","methanol_produced_kg_s","nitrogen_withdrawn_kg_s","co2_withdrawn_kg_s","chemical_hydrogen_consumed_kg_s","chemical_water_released_kg_s","ammonia_inventory_kg","methanol_inventory_kg","nitrogen_inventory_kg","co2_inventory_kg","carbon_element_error_kg","nitrogen_element_error_kg"]
const CHEMICAL_DETAIL_FIELDS := ["nitrogen_in_kg_s","nitrogen_out_kg_s","co2_in_kg_s","co2_out_kg_s","product_produced_kg_s"]
const PHASE_FIELDS := ["phase_store_electric_mw","environment_heat_in_mwth","phase_enthalpy_mwh","phase_enthalpy_change_mwh"]
const PHASE_DETAIL_FIELDS := ["phase_enthalpy_before_mwh","phase_enthalpy_mwh","phase_enthalpy_change_mwh","environment_heat_in_mwth"]
const REFERENCE_IDS := ["H2O_liquid_25c","H2_gas_25c","H2_liquid_20k","H2_bound_lani5","O2_gas_25c","N2_gas_25c","CO2_gas_25c","NH3_gas_25c","CH3OH_liquid_25c"]
const DETAIL_FIELDS := ["water_in_kg_s","water_out_kg_s","hydrogen_in_kg_s","hydrogen_out_kg_s","electric_input_mw","electric_output_mw","oxygen_vented_kg_s","oxygen_from_air_kg_s","water_released_kg_s","heat_rejected_mwth","inventory_before_kg","inventory_after_leak_kg","next_inventory_kg","leaked_kg"]
const RATE_LEDGER := {"water_withdrawn_kg":"water_withdrawn_kg_s","hydrogen_produced_kg":"hydrogen_produced_kg_s","hydrogen_consumed_kg":"hydrogen_consumed_kg_s","hydrogen_charged_kg":"hydrogen_charged_kg_s","hydrogen_discharged_kg":"hydrogen_discharged_kg_s","oxygen_vented_kg":"oxygen_vented_kg_s","oxygen_from_air_kg":"oxygen_from_air_kg_s","water_released_kg":"water_released_kg_s"}
const POWER_LEDGER := {"electrolyzer_electric_mwh":"electrolyzer_electric_mw","compression_electric_mwh":"compression_electric_mw","fuel_cell_output_mwh":"fuel_cell_output_mw","heat_rejected_mwhth":"heat_rejected_mwth"}

static func empty() -> Dictionary:
	var result: Dictionary = {}
	for key in FIELDS: result[key] = 0.0
	return result

static func initial_energy_v1() -> Dictionary:
	var result: Dictionary = {"hydrogen_leaked_kg":0.0,"hydrogen_leak_lhv_mwh":0.0}
	for key in RATE_LEDGER: result[key] = 0.0
	for key in POWER_LEDGER: result[key] = 0.0
	return result

static func _number(x: Variant) -> bool:
	return (x is int or x is float) and is_finite(float(x))

static func _validate_energy_v1(ledger: Variant) -> Array[String]:
	if not ledger is Dictionary: return ["Material cumulative ledger must be a dictionary"]
	var expected: Dictionary = initial_energy_v1()
	if ledger.size() != expected.size(): return ["Material cumulative ledger has incompatible fields"]
	for key in expected:
		if not _number(ledger.get(key)) or float(ledger[key]) < 0.0: return ["Invalid material cumulative field: " + key]
	var c: Dictionary = MC.coefficients()
	var errors: Array[String] = []
	_near(errors, ledger.hydrogen_produced_kg * c.water_per_h2, ledger.water_withdrawn_kg, "cumulative electrolysis water")
	_near(errors, ledger.hydrogen_produced_kg * c.oxygen_per_h2, ledger.oxygen_vented_kg, "cumulative electrolysis oxygen")
	_near(errors, ledger.hydrogen_consumed_kg * c.water_per_h2, ledger.water_released_kg, "cumulative fuel-cell water")
	_near(errors, ledger.hydrogen_consumed_kg * c.oxygen_per_h2, ledger.oxygen_from_air_kg, "cumulative fuel-cell oxygen")
	_near(errors, ledger.hydrogen_charged_kg, ledger.hydrogen_produced_kg, "cumulative H2 charge")
	_near(errors, ledger.hydrogen_discharged_kg, ledger.hydrogen_consumed_kg, "cumulative H2 discharge")
	_near(errors, ledger.hydrogen_leak_lhv_mwh, ledger.hydrogen_leaked_kg * c.lhv_kwh_per_kg / 1000.0, "cumulative H2 leak LHV")
	_near(errors, ledger.electrolyzer_electric_mwh + ledger.compression_electric_mwh - ledger.fuel_cell_output_mwh - ledger.heat_rejected_mwhth, (ledger.hydrogen_produced_kg - ledger.hydrogen_consumed_kg) * c.hhv_kwh_per_kg / 1000.0, "cumulative reference-state enthalpy")
	return errors

static func _accumulate_energy_v1(ledger: Dictionary, report: Dictionary, dt_s: float) -> Dictionary:
	if not validate_energy(ledger).is_empty() or not is_finite(dt_s) or dt_s < 0.0 or not report.get("material") is Dictionary: return {}
	if not _number(report.get("dt_s")) or absf(float(report.dt_s)-dt_s)>1e-7: return {}
	var result: Dictionary = ledger.duplicate(true)
	var m: Dictionary = report.material
	for key in FIELDS:
		if not _number(m.get(key)): return {}
	for key in RATE_LEDGER: result[key] += float(m[RATE_LEDGER[key]]) * dt_s
	for key in POWER_LEDGER: result[key] += float(m[POWER_LEDGER[key]]) * dt_s / 3600.0
	result.hydrogen_leaked_kg += m.hydrogen_leaked_kg
	result.hydrogen_leak_lhv_mwh += m.hydrogen_leak_lhv_mwh
	return result if validate_energy(result).is_empty() else {}

static func initial_energy(devices: Array = []) -> Dictionary:
	return Ledger3.initial_energy(devices)

static func initial_energy_v2(devices: Array = []) -> Dictionary:
	return Ledger.initial_energy(devices)

static func validate_energy_v2(ledger: Variant, devices: Variant = null) -> Array[String]:
	return Ledger.validate_energy(ledger,devices)

static func upgrade_ledger_v2_to_v3(ledger: Variant, devices: Array) -> Dictionary:
	return Ledger3.upgrade_ledger_v2_to_v3(ledger,devices)

static func validate_energy(ledger: Variant, devices: Variant = null) -> Array[String]:
	if ledger is Dictionary and _number(ledger.get("ledger_version")) and ledger.ledger_version == 3: return Ledger3.validate_energy(ledger,devices)
	return Ledger.validate_energy(ledger,devices) if ledger is Dictionary and ledger.has("ledger_version") else Ledger.validate_energy_v1(ledger)

static func accumulate_energy(ledger: Dictionary, report: Dictionary, dt_s: float) -> Dictionary:
	if _number(ledger.get("ledger_version")) and ledger.ledger_version == 3: return Ledger3.accumulate_energy(ledger,report,dt_s)
	return Ledger.accumulate_energy(ledger,report,dt_s) if ledger.has("ledger_version") else _accumulate_energy_v1(ledger,report,dt_s)

static func bootstrap_from_legacy(old_ledger: Variant, devices: Array) -> Dictionary:
	return Ledger.bootstrap_from_legacy(old_ledger,devices)

static func import_inventory_event(ledger: Dictionary, device: Dictionary) -> Dictionary:
	return Ledger3.import_inventory_event(ledger,device) if _number(ledger.get("ledger_version")) and ledger.ledger_version==3 else Ledger.import_inventory_event(ledger,device)

static func remove_inventory_event(ledger: Dictionary, device: Dictionary) -> Dictionary:
	return Ledger3.remove_inventory_event(ledger,device) if _number(ledger.get("ledger_version")) and ledger.ledger_version==3 else Ledger.remove_inventory_event(ledger,device)

static func cumulative_electric_input_mwh(ledger: Variant) -> float:
	return Ledger3.cumulative_electric_input_mwh(ledger) if ledger is Dictionary and _number(ledger.get("ledger_version")) and ledger.ledger_version==3 else Ledger.cumulative_electric_input_mwh(ledger)

static func initialize_node(id: String, kind: String, p: Dictionary, state: Dictionary, dt_s: float, d: Dictionary, resources: Dictionary) -> void:
	for key in DETAIL_FIELDS: d[key] = 0.0
	if kind in MC.CHEMICAL_KINDS:
		for key in CHEMICAL_DETAIL_FIELDS: d[key] = 0.0
	d.model_profile = MC.model_profile(kind)
	d.model_profile_version = MC.model_profile_version(kind)
	d.mode = "idle"
	var c: Dictionary = MC.coefficients()
	if kind in MC.INVENTORY_KINDS:
		d.inventory_before_kg = float(state.material_inventory_kg[MC.species(kind)])
		d.inventory_after_leak_kg = d.inventory_before_kg * (exp(-float(p.leak_per_h) * dt_s / 3600.0) if kind == "hydrogen_gas_store" else 1.0)
		d.leaked_kg = d.inventory_before_kg - d.inventory_after_leak_kg
		d.next_inventory_kg = d.inventory_after_leak_kg
	if kind in MC.PHASE_KINDS:
		var pc: Dictionary = MC.phase_coefficients(kind)
		d.inventory_after_leak_kg = d.inventory_before_kg * exp(-float(pc.leak_per_h)*dt_s/3600.0)
		d.leaked_kg = d.inventory_before_kg-d.inventory_after_leak_kg
		d.next_inventory_kg = d.inventory_after_leak_kg
		d.reference_id = MC.reference_id(kind)
		d.phase_enthalpy_before_mwh = d.inventory_before_kg*pc.enthalpy_kwh_per_kg/1000.0
		d.phase_enthalpy_mwh = d.inventory_after_leak_kg*pc.enthalpy_kwh_per_kg/1000.0
		d.phase_enthalpy_change_mwh = d.phase_enthalpy_mwh-d.phase_enthalpy_before_mwh
		d.environment_heat_in_mwth = 0.0
		if kind == "hydrogen_metal_hydride_store": d.host_dry_mass_kg = state.host_dry_mass_kg
		var ce: float = float(p.liquefier_electric_mw if kind == "hydrogen_liquid_store" else p.charge_aux_electric_mw)
		var de: float = float(p.discharge_aux_electric_mw if kind == "hydrogen_liquid_store" else p.discharge_heater_electric_mw)
		var charge_heat: float = pc.charge_kwh_per_kg-pc.enthalpy_kwh_per_kg
		var discharge_heat: float = pc.discharge_kwh_per_kg+pc.ambient_kwh_per_kg+pc.enthalpy_kwh_per_kg
		resources["material_charge:"+id] = minf(minf(p.charge_kg_s,(MC.inventory_capacity(kind,p)-d.inventory_after_leak_kg)/dt_s),minf(ce/(3.6*pc.charge_kwh_per_kg),p.heat_rejection_mwth/(3.6*charge_heat))) if dt_s>0 else 0.0
		resources["material_discharge:"+id] = minf(minf(p.discharge_kg_s,d.inventory_after_leak_kg/dt_s),minf(de/(3.6*pc.discharge_kwh_per_kg),p.heat_rejection_mwth/(3.6*discharge_heat))) if dt_s>0 else 0.0
		if kind == "hydrogen_liquid_store": resources["material_discharge:"+id] = minf(resources["material_discharge:"+id],p.ambient_vaporizer_mwth/(3.6*pc.ambient_kwh_per_kg))
		resources["material_aux:"+id] = maxf(ce,de) if dt_s>0 else 0.0
	if kind in MC.FEED_KINDS:
		resources["material_feed:"+id] = minf(p.max_outflow_kg_s,d.inventory_before_kg/dt_s) if dt_s>0 else 0.0
	if kind in MC.SYNTHESIS_KINDS:
		var cc: Dictionary = MC.chemical_coefficients(kind)
		resources["material_product:"+id] = minf(minf(p.max_product_kg_s,(p.capacity_kg-d.inventory_before_kg)/dt_s),minf(minf(p.rated_electric_mw/(3.6*cc.electric_kwh_per_kg),p.heater_electric_mw/(3.6*cc.heater_kwh_per_kg)),p.heat_rejection_mwth/(3.6*cc.heat_rejected_kwh_per_kg))) if dt_s>0 else 0.0
		resources["material_aux:"+id] = p.rated_electric_mw if dt_s>0 else 0.0
	match kind:
		"water_supply_boundary": resources["material_water:"+id] = minf(p.max_outflow_kg_s, d.inventory_before_kg / dt_s) if dt_s > 0 else 0.0
		"electrolyzer_station":
			resources["material_prod:"+id] = minf(p.max_hydrogen_kg_s, p.rated_electric_mw / (3.6 * p.electricity_kwh_per_kg)) if dt_s > 0 else 0.0
			resources["material_aux:"+id] = p.rated_electric_mw if dt_s > 0 else 0.0
		"hydrogen_gas_store":
			resources["material_charge:"+id] = minf(minf(p.charge_kg_s, (p.capacity_kg - d.inventory_after_leak_kg) / dt_s), p.compressor_electric_mw / (3.6 * p.compression_kwh_per_kg)) if dt_s > 0 else 0.0
			resources["material_discharge:"+id] = minf(p.discharge_kg_s, d.inventory_after_leak_kg / dt_s) if dt_s > 0 else 0.0
			resources["material_aux:"+id] = p.compressor_electric_mw if dt_s > 0 else 0.0
		"fuel_cell_station":
			resources["material_fc:"+id] = minf(p.max_hydrogen_kg_s, p.rated_electric_mw / (3.6 * c.lhv_kwh_per_kg * p.net_efficiency_lhv)) if dt_s > 0 else 0.0
			resources["source:"+id] = p.rated_electric_mw if dt_s > 0 else 0.0

static func prepare(prepared: Dictionary) -> void:
	prepared.material_lines = []
	var enabled: bool = false
	for n in prepared.nodes.values(): enabled = enabled or n.kind in MC.KINDS
	if not enabled: return
	prepared.report.material = empty()
	for line in prepared.report.lines:
		if line.valid and line.carrier in MC.CARRIERS: prepared.material_lines.append(line.index)

static func _add(target: Dictionary, key: String, value: float) -> void:
	target[key] = float(target.get(key, 0.0)) + value

static func _limit(coefficients: Dictionary, resources: Dictionary) -> float:
	var q: float = INF
	for key in coefficients:
		if float(coefficients[key]) > 0.0: q = minf(q, maxf(0.0, float(resources.get(key, 0.0))) / float(coefficients[key]))
	return q if is_finite(q) else 0.0

## Choose a representable transaction extent before publishing any coupled flow.
## (stock / dt / stoichiometry) * stoichiometry * dt can exceed stock by an ULP.
## Never repair live stocks, change an audit tolerance, or trim only one species.
static func _inventory_feasible(prepared: Dictionary, mass: Dictionary, q: float) -> bool:
	var dt: float = prepared.report.dt_s
	for key in mass:
		var increment: float = q * float(mass[key])
		if float(prepared.resources[key]) - increment < 0.0: return false
		var family: String = String(key).get_slice(":", 0)
		if not family in ["material_water", "material_feed", "material_charge", "material_discharge", "material_product"]: continue
		var id: String = String(key).get_slice(":", 1)
		var n: Dictionary = prepared.nodes[id]
		var d: Dictionary = prepared.report.devices[id]
		var stock: float = d.inventory_before_kg
		match family:
			"material_water": stock -= (d.water_out_kg_s + increment) * dt
			"material_feed":
				var field: String = "nitrogen" if n.kind == "nitrogen_supply_boundary" else "co2"
				stock -= (d[field + "_out_kg_s"] + increment) * dt
			"material_charge": stock = d.inventory_after_leak_kg + ((d.hydrogen_in_kg_s + increment) - d.hydrogen_out_kg_s) * dt
			"material_discharge": stock = d.inventory_after_leak_kg + (d.hydrogen_in_kg_s - (d.hydrogen_out_kg_s + increment)) * dt
			"material_product":
				var ratio: float = MC.chemical_coefficients(n.kind).hydrogen_per_product
				stock += ((d.hydrogen_in_kg_s + q * ratio) / ratio) * dt
		if not is_finite(stock) or stock < 0.0 or stock > MC.inventory_capacity(n.kind, n.params): return false
	return true

static func _representable_rate(prepared: Dictionary, mass: Dictionary, proposed: float) -> float:
	var q: float = proposed
	var bits := PackedByteArray()
	bits.resize(8)
	for retry in 32:
		if not is_finite(q) or q <= EPS: return 0.0
		if _inventory_feasible(prepared, mass, q): return q
		# q is positive, so decrementing its binary64 encoding is nextafter(q, 0).
		bits.encode_double(0, q)
		bits.encode_u64(0, bits.decode_u64(0) - 1)
		q = bits.decode_double(0)
	# An unrepresentable residual is left in its source, never created or erased.
	return 0.0

static func _reserve(prepared: Dictionary, electric: Array, mass: Dictionary, q: float, allocate: Callable) -> bool:
	if q <= EPS: return false
	var trial_r: Dictionary = prepared.report.duplicate(true)
	var trial_resources: Dictionary = prepared.resources.duplicate(true)
	for item in electric:
		var needed: float = float(item.factor) * q
		var actual: float = allocate.call(item.path, trial_resources, trial_r, needed)
		if absf(actual - needed) > 1.0e-10 * maxf(1.0, needed): return false
	for key in mass:
		var left: float = float(trial_resources[key]) - q * float(mass[key])
		if left < 0.0: return false
		trial_resources[key] = left
	prepared.resources.clear()
	prepared.resources.merge(trial_resources, true)
	prepared.report.clear()
	prepared.report.merge(trial_r, true)
	return true

static func _record_line(prepared: Dictionary, index: int, kg_s: float) -> void:
	var line: Dictionary = prepared.report.lines[index]
	line.sent_kg_s += kg_s
	line.received_kg_s += kg_s
	line.signed_kg_s = line.sent_kg_s
	line.direction = 1 if line.sent_kg_s > EPS else 0
	line.active = line.sent_kg_s > EPS
	line.utilization = line.sent_kg_s / line.mass_flow_capacity_kg_s if line.mass_flow_capacity_kg_s > 0.0 else 0.0

static func serve_load(prepared: Dictionary, load_id: String, allocate: Callable) -> void:
	if not prepared.report.has("material"): return
	var c: Dictionary = MC.coefficients()
	for path in prepared.paths:
		if path.source_kind != "fuel_cell_station" or path.sink_id != load_id: continue
		var fc: String = path.source_id
		var factor: float = 3.6 * c.lhv_kwh_per_kg * prepared.nodes[fc].params.net_efficiency_lhv
		for index in prepared.material_lines:
			var line: Dictionary = prepared.report.lines[index]
			if str(line.to) != fc or not prepared.nodes[str(line.from)].kind in MC.HYDROGEN_STORE_KINDS: continue
			var store: String = str(line.from)
			if prepared.report.devices[store].mode == "charge": continue
			var mass: Dictionary = {"material_discharge:"+store:1.0,"material_fc:"+fc:1.0,"material_line:"+str(index):1.0}
			var all: Dictionary = mass.duplicate()
			for key in path.coefficients: _add(all, key, factor * float(path.coefficients[key]))
			var phase: bool = prepared.nodes[store].kind in MC.PHASE_KINDS
			var aux_paths: Array = []
			if phase:
				for ap in prepared.paths:
					if ap.sink_id == store and (ap.source_kind in ["wind","pv"] or Catalog.is_electric_storage(ap.source_kind)): aux_paths.append(ap)
			else: aux_paths.append({})
			for ap in aux_paths:
				var combined: Dictionary = all.duplicate()
				var electric: Array = [{"path":path,"factor":factor}]
				if phase:
					var af: float = 3.6*MC.phase_coefficients(prepared.nodes[store].kind).discharge_kwh_per_kg/ap.received
					for key in ap.coefficients: _add(combined,key,af*float(ap.coefficients[key]))
					electric.append({"path":ap,"factor":af})
				var q: float = _representable_rate(prepared, mass, _limit(combined, prepared.resources))
				if not _reserve(prepared,electric,mass,q,allocate): continue
				_record_line(prepared,index,q)
				prepared.report.devices[store].hydrogen_out_kg_s += q
				prepared.report.devices[store].mode = "discharge"
				prepared.report.devices[fc].hydrogen_in_kg_s += q
				prepared.report.devices[fc].mode = "produce"

static func charge_surplus(prepared: Dictionary, allocate: Callable) -> void:
	if not prepared.report.has("material"): return
	var c: Dictionary = MC.coefficients()
	for hi in prepared.material_lines:
		var hline: Dictionary = prepared.report.lines[hi]
		var electro: String = str(hline.from)
		var store: String = str(hline.to)
		if prepared.nodes[electro].kind != "electrolyzer_station" or not prepared.nodes[store].kind in MC.HYDROGEN_STORE_KINDS: continue
		if prepared.report.devices[store].mode == "discharge": continue
		for wi in prepared.material_lines:
			var wline: Dictionary = prepared.report.lines[wi]
			if str(wline.to) != electro or prepared.nodes[str(wline.from)].kind != "water_supply_boundary": continue
			var water: String = str(wline.from)
			for ep in prepared.paths:
				if ep.sink_id != electro or not ep.source_kind in ["wind","pv"]: continue
				for cp in prepared.paths:
					if cp.sink_id != store or not cp.source_kind in ["wind","pv"]: continue
					var ef: float = 3.6 * prepared.nodes[electro].params.electricity_kwh_per_kg / ep.received
					var charge_kwh: float = MC.phase_coefficients(prepared.nodes[store].kind).charge_kwh_per_kg if prepared.nodes[store].kind in MC.PHASE_KINDS else prepared.nodes[store].params.compression_kwh_per_kg
					var cf: float = 3.6 * charge_kwh / cp.received
					var mass: Dictionary = {"material_prod:"+electro:1.0,"material_charge:"+store:1.0,"material_water:"+water:c.water_per_h2,"material_line:"+str(wi):c.water_per_h2,"material_line:"+str(hi):1.0}
					var all: Dictionary = mass.duplicate()
					for key in ep.coefficients: _add(all, key, ef * float(ep.coefficients[key]))
					for key in cp.coefficients: _add(all, key, cf * float(cp.coefficients[key]))
					var q: float = _representable_rate(prepared, mass, _limit(all, prepared.resources))
					if not _reserve(prepared, [{"path":ep,"factor":ef},{"path":cp,"factor":cf}], mass, q, allocate): continue
					_record_line(prepared, wi, q * c.water_per_h2)
					_record_line(prepared, hi, q)
					prepared.report.devices[water].water_out_kg_s += q * c.water_per_h2
					prepared.report.devices[electro].water_in_kg_s += q * c.water_per_h2
					prepared.report.devices[electro].hydrogen_out_kg_s += q
					prepared.report.devices[electro].mode = "produce"
					prepared.report.devices[store].hydrogen_in_kg_s += q
					prepared.report.devices[store].mode = "charge"

static func finish(prepared: Dictionary) -> void:
	if not prepared.report.has("material"): return
	var r: Dictionary = prepared.report
	var m: Dictionary = empty()
	var c: Dictionary = MC.coefficients()
	for key in PHASE_FIELDS: m[key] = 0.0
	for key in CHEMICAL_FIELDS: m[key] = 0.0
	m.inventory_by_reference_kg = {}
	for key in REFERENCE_IDS: m.inventory_by_reference_kg[key] = 0.0
	m.dry_host_by_device_kg = {}
	var water_before: float = 0.0
	var h2_before: float = 0.0
	for id in prepared.nodes:
		var node: Dictionary = prepared.nodes[id]
		if not node.valid or not node.kind in MC.KINDS: continue
		var d: Dictionary = r.devices[id]
		var p: Dictionary = node.params
		match node.kind:
			"water_supply_boundary":
				d.next_inventory_kg = clampf(d.inventory_before_kg - d.water_out_kg_s * r.dt_s, 0.0, p.capacity_kg)
				water_before += d.inventory_before_kg
				m.water_inventory_kg += d.next_inventory_kg
				m.water_withdrawn_kg_s += d.water_out_kg_s
			"electrolyzer_station":
				d.electric_input_mw = d.input_mw
				d.oxygen_vented_kg_s = d.hydrogen_out_kg_s * c.oxygen_per_h2
				d.heat_rejected_mwth = maxf(0.0, d.electric_input_mw - d.hydrogen_out_kg_s * 3.6 * c.hhv_kwh_per_kg)
				m.hydrogen_produced_kg_s += d.hydrogen_out_kg_s
				m.electrolyzer_electric_mw += d.electric_input_mw
				m.oxygen_vented_kg_s += d.oxygen_vented_kg_s
			"hydrogen_gas_store":
				d.electric_input_mw = d.input_mw
				d.heat_rejected_mwth = d.electric_input_mw
				d.next_inventory_kg = clampf(d.inventory_after_leak_kg + (d.hydrogen_in_kg_s - d.hydrogen_out_kg_s) * r.dt_s, 0.0, p.capacity_kg)
				h2_before += d.inventory_before_kg
				m.hydrogen_inventory_kg += d.next_inventory_kg
				m.hydrogen_leaked_kg += d.leaked_kg
				m.hydrogen_charged_kg_s += d.hydrogen_in_kg_s
				m.hydrogen_discharged_kg_s += d.hydrogen_out_kg_s
				m.compression_electric_mw += d.electric_input_mw
			"hydrogen_liquid_store", "hydrogen_metal_hydride_store":
				var pc: Dictionary = MC.phase_coefficients(node.kind)
				d.electric_input_mw = d.input_mw
				d.next_inventory_kg = d.inventory_after_leak_kg + (d.hydrogen_in_kg_s-d.hydrogen_out_kg_s)*r.dt_s
				d.phase_enthalpy_mwh = d.next_inventory_kg*pc.enthalpy_kwh_per_kg/1000.0
				# Integrate actual mass flows, not subtraction of two large stocks.
				d.phase_enthalpy_change_mwh = ((d.hydrogen_in_kg_s-d.hydrogen_out_kg_s)*r.dt_s-d.leaked_kg)*pc.enthalpy_kwh_per_kg/1000.0
				d.environment_heat_in_mwth = (d.hydrogen_out_kg_s+d.leaked_kg/r.dt_s)*3.6*pc.ambient_kwh_per_kg if r.dt_s>0 else 0.0
				d.heat_rejected_mwth = d.hydrogen_in_kg_s*3.6*(pc.charge_kwh_per_kg-pc.enthalpy_kwh_per_kg)+d.hydrogen_out_kg_s*3.6*(pc.discharge_kwh_per_kg+pc.ambient_kwh_per_kg+pc.enthalpy_kwh_per_kg)
				h2_before += d.inventory_before_kg
				m.hydrogen_inventory_kg += d.next_inventory_kg
				m.hydrogen_leaked_kg += d.leaked_kg
				m.hydrogen_charged_kg_s += d.hydrogen_in_kg_s
				m.hydrogen_discharged_kg_s += d.hydrogen_out_kg_s
				m.phase_store_electric_mw += d.electric_input_mw
				m.environment_heat_in_mwth += d.environment_heat_in_mwth
				m.phase_enthalpy_mwh += d.phase_enthalpy_mwh
				m.phase_enthalpy_change_mwh += d.phase_enthalpy_change_mwh
				if node.kind == "hydrogen_metal_hydride_store": m.dry_host_by_device_kg[id] = d.host_dry_mass_kg
			"nitrogen_supply_boundary", "co2_supply_boundary":
				var field: String = "nitrogen" if node.kind == "nitrogen_supply_boundary" else "co2"
				d.next_inventory_kg = d.inventory_before_kg-d[field+"_out_kg_s"]*r.dt_s
				m[field+"_withdrawn_kg_s"] += d[field+"_out_kg_s"]
				m[field+"_inventory_kg"] += d.next_inventory_kg
			"ammonia_synthesis_station", "methanol_synthesis_station":
				var cc: Dictionary = MC.chemical_coefficients(node.kind)
				var field: String = "ammonia" if node.kind == "ammonia_synthesis_station" else "methanol"
				d.product_produced_kg_s = d.hydrogen_in_kg_s/cc.hydrogen_per_product
				d.next_inventory_kg = d.inventory_before_kg+d.product_produced_kg_s*r.dt_s
				d.electric_input_mw = d.input_mw
				d.heat_rejected_mwth = d.product_produced_kg_s*3.6*cc.heat_rejected_kwh_per_kg
				d.water_released_kg_s = d.product_produced_kg_s*cc.water_per_product
				m[field+"_produced_kg_s"] += d.product_produced_kg_s
				m[field+"_inventory_kg"] += d.next_inventory_kg
				m.chemical_electric_mw += d.electric_input_mw
				m.chemical_hydrogen_consumed_kg_s += d.hydrogen_in_kg_s
				m.chemical_water_released_kg_s += d.water_released_kg_s
				m.water_released_kg_s += d.water_released_kg_s
			"fuel_cell_station":
				d.electric_output_mw = d.output_mw
				d.water_released_kg_s = d.hydrogen_in_kg_s * c.water_per_h2
				d.oxygen_from_air_kg_s = d.hydrogen_in_kg_s * c.oxygen_per_h2
				d.heat_rejected_mwth = d.hydrogen_in_kg_s * 3.6 * c.hhv_kwh_per_kg - d.electric_output_mw
				m.hydrogen_consumed_kg_s += d.hydrogen_in_kg_s
				m.water_released_kg_s += d.water_released_kg_s
				m.oxygen_from_air_kg_s += d.oxygen_from_air_kg_s
				m.fuel_cell_output_mw += d.electric_output_mw
				r.generated_mw += d.electric_output_mw
		# Report mode follows the common audited activity threshold, not the
		# transaction's product extent (which has different stoichiometric units).
		if node.kind in MC.HYDROGEN_STORE_KINDS: d.mode = "charge" if d.hydrogen_in_kg_s > EPS else "discharge" if d.hydrogen_out_kg_s > EPS else "idle"
		elif node.kind in MC.FEED_KINDS: d.mode = "supply" if d["nitrogen_out_kg_s" if node.kind == "nitrogen_supply_boundary" else "co2_out_kg_s"] > EPS else "idle"
		elif node.kind in MC.SYNTHESIS_KINDS: d.mode = "produce" if d.product_produced_kg_s > EPS else "idle"
		elif node.kind == "electrolyzer_station": d.mode = "produce" if d.hydrogen_out_kg_s > EPS else "idle"
		elif node.kind == "fuel_cell_station": d.mode = "produce" if d.hydrogen_in_kg_s > EPS else "idle"
		m.heat_rejected_mwth += d.heat_rejected_mwth
		if node.kind in MC.INVENTORY_KINDS:
			r.next_states[id] = {"material_inventory_kg":{MC.species(node.kind):d.next_inventory_kg}}
			if node.kind == "hydrogen_metal_hydride_store": r.next_states[id].host_dry_mass_kg = d.host_dry_mass_kg
			m.inventory_by_reference_kg[MC.reference_id(node.kind)] += d.next_inventory_kg
	m.hydrogen_lhv_mwh = m.hydrogen_inventory_kg * c.lhv_kwh_per_kg / 1000.0
	m.hydrogen_leak_lhv_mwh = m.hydrogen_leaked_kg * c.lhv_kwh_per_kg / 1000.0
	var dw: float = water_before - m.water_inventory_kg - m.water_released_kg_s * r.dt_s
	var dh: float = h2_before - m.hydrogen_inventory_kg - m.hydrogen_leaked_kg
	var oxygen: float = (m.oxygen_from_air_kg_s - m.oxygen_vented_kg_s) * r.dt_s
	m.mass_balance_error_kg = dw + dh + oxygen
	m.hydrogen_element_error_kg = dw * c.hydrogen_fraction_water + dh
	m.oxygen_element_error_kg = dw * (1.0 - c.hydrogen_fraction_water) + oxygen
	m.enthalpy_balance_error_mw = m.electrolyzer_electric_mw + m.compression_electric_mw + m.phase_store_electric_mw + m.environment_heat_in_mwth - m.fuel_cell_output_mw - m.heat_rejected_mwth - (m.hydrogen_produced_kg_s - m.hydrogen_consumed_kg_s) * 3.6 * c.hhv_kwh_per_kg - (m.phase_enthalpy_change_mwh*3600.0/r.dt_s if r.dt_s>0 else 0.0)
	if prepared.nodes.values().any(func(n): return n.kind in MC.CHEMICAL_KINDS): _chemical_balance(prepared,m)
	r.material = m

static func _near(errors: Array[String], actual: Variant, expected: float, label: String) -> void:
	if not _number(actual) or absf(float(actual)-expected) > ABS_TOL + REL_TOL * maxf(absf(float(actual)),absf(expected)):
		errors.append("Independent material audit: " + label)

## Reconstruct chemistry from original line endpoints and states, never reported
## balances or state derivatives. Returns trusted aggregate for AC-domain audit.
static func audit(prepared: Dictionary, errors: Array[String]) -> Dictionary:
	var original: Dictionary = prepared.report
	var enabled: bool = false
	for n in prepared.nodes.values(): enabled = enabled or n.kind in MC.KINDS
	if not enabled:
		if original.has("material"): errors.append("Unexpected material report")
		return empty()
	if not original.get("material") is Dictionary:
		errors.append("Missing material report")
		return empty()
	var scratch: Dictionary = {"nodes":prepared.nodes,"report":{"devices":{},"next_states":{},"material":empty(),"dt_s":original.dt_s,"dt_h":original.dt_h,"generated_mw":0.0}}
	var resources: Dictionary = {}
	for id in prepared.nodes:
		var n: Dictionary = prepared.nodes[id]
		if not n.valid or not n.kind in MC.KINDS: continue
		var d: Dictionary = {"input_mw":0.0,"output_mw":0.0}
		initialize_node(id,n.kind,n.params,n.state,original.dt_s,d,resources)
		scratch.report.devices[id] = d
	var renewable_at_bus: Dictionary = {}
	var process_from_bus: Dictionary = {}
	var phase_from_bus: Dictionary = {}
	var chemical_from_bus: Dictionary = {}
	var storage_at_bus: Dictionary = {}
	var fuel_cell_at_bus: Dictionary = {}
	var loads_from_bus: Dictionary = {}
	for line in original.lines:
		if not line.valid: continue
		var index: int = int(line.index)
		var raw: Dictionary = prepared.raw_links[index]
		if line.carrier in MC.CARRIERS:
			for key in ["from","to","from_port","to_port","carrier","unit","species_id","phase_id","grade_id"]:
				if line.get(key) != raw.get(key): errors.append("Material edge identity changed: " + key)
			for key in ["sent_mw","received_mw","loss_mw","capacity_mw","sent_mwth","capacity_mwth"]:
				if line.has(key): errors.append("Material edge mixed energy units")
			var sent: Variant = line.get("sent_kg_s")
			if not _number(sent):
				errors.append("Material edge nonfinite flow")
				continue
			var q: float = float(sent)
			if q < -1.0e-9 or q > float(raw.mass_flow_capacity_kg_s) + 1.0e-9 or (original.dt_s == 0.0 and absf(q) > 1.0e-9): errors.append("Material edge capacity/duration violated")
			if line.get("flow_from") != raw.from or line.get("flow_to") != raw.to: errors.append("Material edge direction changed")
			_near(errors,line.get("mass_flow_capacity_kg_s"),raw.mass_flow_capacity_kg_s,"material line capacity")
			_near(errors,line.get("received_kg_s"),q,"material line delivery")
			_near(errors,line.get("signed_kg_s"),q,"material line signed flow")
			_near(errors,line.get("loss_kg_s"),0.0,"material pipe loss")
			_near(errors,line.get("loss_fraction"),0.0,"material pipe loss setting")
			var a: String = str(int(raw.from))
			var b: String = str(int(raw.to))
			if not scratch.report.devices.has(a) or not scratch.report.devices.has(b):
				errors.append("Material edge references non-material device")
				continue
			var field: String = {"H2O":"water","H2":"hydrogen","N2":"nitrogen","CO2":"co2"}.get(raw.species_id, "unknown")
			scratch.report.devices[a][field+"_out_kg_s"] += q
			scratch.report.devices[b][field+"_in_kg_s"] += q
		elif line.carrier == "electricity_ac":
			var a: String = str(int(line.flow_from))
			var b: String = str(int(line.flow_to))
			if not prepared.nodes.has(a) or (b != "-1" and not prepared.nodes.has(b)):
				errors.append("Material AC path references missing node")
				continue
			if scratch.report.devices.has(a): scratch.report.devices[a].output_mw += float(line.sent_mw)
			if scratch.report.devices.has(b): scratch.report.devices[b].input_mw += float(line.received_mw)
			if prepared.nodes.has(b) and Catalog.is_electric_station(prepared.nodes[b].kind):
				if prepared.nodes[a].kind in ["wind","pv"]: _add(renewable_at_bus,b,line.received_mw)
				elif prepared.nodes[a].kind == "fuel_cell_station": _add(fuel_cell_at_bus,b,line.received_mw)
				elif Catalog.is_electric_storage(prepared.nodes[a].kind): _add(storage_at_bus,b,line.received_mw)
			if prepared.nodes.has(a) and Catalog.is_electric_station(prepared.nodes[a].kind) and prepared.nodes.has(b):
				if prepared.nodes[b].kind in ["electrolyzer_station","hydrogen_gas_store"]: _add(process_from_bus,a,line.sent_mw)
				elif prepared.nodes[b].kind in MC.SYNTHESIS_KINDS: _add(chemical_from_bus,a,line.sent_mw)
				elif prepared.nodes[b].kind in MC.PHASE_KINDS:
					if original.devices[b].get("mode") is String and original.devices[b].mode == "discharge": _add(phase_from_bus,a,line.sent_mw)
					else: _add(process_from_bus,a,line.sent_mw)
				elif prepared.nodes[b].kind == "load": _add(loads_from_bus,a,line.sent_mw)
	for id in process_from_bus:
		var allowed: float = float(renewable_at_bus.get(id,0.0)) * (1.0-float(prepared.nodes[id].params.loss_fraction))
		if float(process_from_bus[id]) > allowed + ABS_TOL: errors.append("Material conversion requires renewable-only AC provenance")
	var mixed_aux_buses: Dictionary = phase_from_bus.duplicate()
	for id in chemical_from_bus: mixed_aux_buses[id] = true
	for id in mixed_aux_buses:
		var allowed: float = (float(renewable_at_bus.get(id,0.0))+float(storage_at_bus.get(id,0.0)))*(1.0-float(prepared.nodes[id].params.loss_fraction))
		if float(phase_from_bus.get(id,0.0))+float(chemical_from_bus.get(id,0.0))+float(process_from_bus.get(id,0.0)) > allowed+ABS_TOL: errors.append("Phase hydrogen auxiliaries require external renewable/finite storage AC")
	for id in fuel_cell_at_bus:
		var injected: float = float(fuel_cell_at_bus[id]) * (1.0-float(prepared.nodes[id].params.loss_fraction))
		if injected > float(loads_from_bus.get(id,0.0)) + ABS_TOL: errors.append("Fuel cell output may only serve actual electric loads")
	var c: Dictionary = MC.coefficients()
	for id in scratch.report.devices:
		var n: Dictionary = prepared.nodes[id]
		var d: Dictionary = scratch.report.devices[id]
		var p: Dictionary = n.params
		var actual: Dictionary = original.devices.get(id,{})
		if not actual.get("model_profile") is String or actual.model_profile != MC.model_profile(n.kind) or not _number(actual.get("model_profile_version")) or actual.model_profile_version != MC.model_profile_version(n.kind): errors.append("Material process profile changed")
		match n.kind:
			"water_supply_boundary":
				if d.water_out_kg_s > float(resources["material_water:"+id]) + 1.0e-9: errors.append("Finite water source/rate violated")
				_near(errors,d.input_mw+d.output_mw,0.0,"water boundary has no AC")
			"electrolyzer_station":
				_near(errors,d.water_in_kg_s,d.hydrogen_out_kg_s*c.water_per_h2,"electrolysis stoichiometry")
				_near(errors,d.input_mw,d.hydrogen_out_kg_s*3.6*p.electricity_kwh_per_kg,"electrolysis actual AC")
				_near(errors,d.output_mw,0.0,"electrolysis cannot return AC")
				if d.hydrogen_out_kg_s > float(resources["material_prod:"+id]) + 1.0e-9: errors.append("Electrolyzer aggregate capacity violated")
				d.mode = "produce" if d.hydrogen_out_kg_s > EPS else "idle"
			"hydrogen_gas_store":
				_near(errors,d.input_mw,d.hydrogen_in_kg_s*3.6*p.compression_kwh_per_kg,"compression actual AC")
				_near(errors,d.output_mw,0.0,"gas store has no direct AC output")
				if d.hydrogen_in_kg_s > float(resources["material_charge:"+id]) + 1.0e-9 or d.hydrogen_out_kg_s > float(resources["material_discharge:"+id]) + 1.0e-9: errors.append("Gas store finite inventory/aggregate rate violated")
				if d.hydrogen_in_kg_s > EPS and d.hydrogen_out_kg_s > EPS: errors.append("Gas store simultaneous charge/discharge")
				d.mode = "charge" if d.hydrogen_in_kg_s > EPS else "discharge" if d.hydrogen_out_kg_s > EPS else "idle"
			"hydrogen_liquid_store", "hydrogen_metal_hydride_store":
				var pc: Dictionary = MC.phase_coefficients(n.kind)
				_near(errors,d.input_mw,3.6*(d.hydrogen_in_kg_s*pc.charge_kwh_per_kg+d.hydrogen_out_kg_s*pc.discharge_kwh_per_kg),"phase store actual AC")
				_near(errors,d.output_mw,0.0,"phase store cannot output AC")
				if d.hydrogen_in_kg_s > float(resources["material_charge:"+id])+1e-9 or d.hydrogen_out_kg_s > float(resources["material_discharge:"+id])+1e-9: errors.append("Phase store finite stock/power/heat/rate violated")
				if d.hydrogen_in_kg_s>EPS and d.hydrogen_out_kg_s>EPS: errors.append("Phase store simultaneous charge/discharge")
				d.mode = "charge" if d.hydrogen_in_kg_s>EPS else "discharge" if d.hydrogen_out_kg_s>EPS else "idle"
				if not actual.get("reference_id") is String or actual.reference_id != MC.reference_id(n.kind): errors.append("Phase reference identity changed")
				for field in ["energy_mwh","soc","charge_mw","discharge_mw","useful_heat_output_mwth"]:
					if actual.has(field): errors.append("Phase store cannot claim additional electric/usable heat inventory: "+field)
				if n.kind == "hydrogen_metal_hydride_store": _near(errors,actual.get("host_dry_mass_kg"),p.dry_host_mass_kg,"immutable LaNi5 host")
			"nitrogen_supply_boundary", "co2_supply_boundary":
				var field: String = "nitrogen" if n.kind == "nitrogen_supply_boundary" else "co2"
				if d[field+"_out_kg_s"] > float(resources["material_feed:"+id])+1e-9: errors.append("Finite prepared feed source/rate violated")
				_near(errors,d.input_mw+d.output_mw,0.0,"prepared feed has no free electricity")
				d.mode = "supply" if d[field+"_out_kg_s"]>EPS else "idle"
			"ammonia_synthesis_station", "methanol_synthesis_station":
				var cc: Dictionary = MC.chemical_coefficients(n.kind)
				var q: float = d.hydrogen_in_kg_s/cc.hydrogen_per_product
				var field: String = "nitrogen" if n.kind == "ammonia_synthesis_station" else "co2"
				_near(errors,d[field+"_in_kg_s"],q*cc.feed_per_product,"synthesis feed stoichiometry")
				_near(errors,d.input_mw,q*3.6*cc.electric_kwh_per_kg,"synthesis actual electrical heat and auxiliary")
				_near(errors,d.output_mw,0.0,"synthesis cannot export electricity")
				if q>float(resources["material_product:"+id])+1e-9: errors.append("Synthesis product space/rate/AC/heater/cooler violated")
				d.mode = "produce" if q>EPS else "idle"
			"fuel_cell_station":
				_near(errors,d.output_mw,d.hydrogen_in_kg_s*3.6*c.lhv_kwh_per_kg*p.net_efficiency_lhv,"fuel cell actual AC")
				_near(errors,d.input_mw,0.0,"fuel cell has no AC input")
				if d.hydrogen_in_kg_s > float(resources["material_fc:"+id]) + 1.0e-9: errors.append("Fuel cell aggregate capacity violated")
				d.mode = "produce" if d.hydrogen_in_kg_s > EPS else "idle"
	finish(scratch)
	for id in scratch.report.devices:
		var d: Dictionary = scratch.report.devices[id]
		var actual: Dictionary = original.devices.get(id,{})
		for field in DETAIL_FIELDS: _near(errors,actual.get(field),float(d[field]),id+" "+field)
		if prepared.nodes[id].kind in MC.CHEMICAL_KINDS:
			for field in CHEMICAL_DETAIL_FIELDS: _near(errors,actual.get(field),float(d[field]),id+" "+field)
		if prepared.nodes[id].kind in MC.PHASE_KINDS:
			for field in PHASE_DETAIL_FIELDS: _near(errors,actual.get(field),float(d[field]),id+" "+field)
		for field in ["input_mw", "received_mw"]: _near(errors,actual.get(field),float(d.input_mw),id+" AC input "+field)
		for field in ["output_mw", "sent_mw"]: _near(errors,actual.get(field),float(d.output_mw),id+" AC output "+field)
		if not actual.get("mode") is String or actual.mode != d.mode: errors.append("Material operating mode disagrees with flows")
		if scratch.report.next_states.has(id):
			var state: Variant = original.next_states.get(id)
			var n: Dictionary = prepared.nodes[id]
			var state_errors: Array = MC.validate_state(n.kind,n.params,state)
			errors.append_array(state_errors)
			if state_errors.is_empty(): _near(errors,state.material_inventory_kg[MC.species(n.kind)],d.next_inventory_kg,"material next stock")
	for field in FIELDS: _near(errors,original.material.get(field),float(scratch.report.material[field]),"aggregate "+field)
	var phase_enabled: bool = false
	for n in prepared.nodes.values(): phase_enabled = phase_enabled or n.kind in MC.PHASE_KINDS
	if prepared.nodes.values().any(func(n): return n.kind in MC.CHEMICAL_KINDS):
		for field in CHEMICAL_FIELDS: _near(errors,original.material.get(field),float(scratch.report.material[field]),"aggregate "+field)
		for field in ["carbon_element_error_kg","nitrogen_element_error_kg"]: _near(errors,scratch.report.material[field],0.0,field)
		phase_enabled = true
	if phase_enabled:
		for field in PHASE_FIELDS: _near(errors,original.material.get(field),float(scratch.report.material[field]),"aggregate "+field)
		for field in ["inventory_by_reference_kg","dry_host_by_device_kg"]:
			if not original.material.get(field) is Dictionary or original.material[field].size()!=scratch.report.material[field].size(): errors.append("Incomplete reference inventory: "+field)
			else:
				for key in scratch.report.material[field]: _near(errors,original.material[field].get(key),scratch.report.material[field][key],field+":"+key)
	for field in ["mass_balance_error_kg","hydrogen_element_error_kg","oxygen_element_error_kg","enthalpy_balance_error_mw"]: _near(errors,scratch.report.material[field],0.0,field)
	return scratch.report.material

## Independent reference recurrence for horizon audit. Never advances with the
## candidate's claimed next stock; opposite forgeries at two stores cannot cancel.
static func reconstruct_next_states(devices: Array, links: Array, report: Dictionary) -> Dictionary:
	var next: Dictionary = {}
	var incoming: Dictionary = {}
	var outgoing: Dictionary = {}
	var dt: float = report.dt_s
	for d in devices:
		if not d.kind in MC.INVENTORY_KINDS: continue
		var id: String = str(int(d.id))
		incoming[id] = 0.0
		outgoing[id] = 0.0
	for i in links.size():
		var line: Dictionary = links[i]
		if not line.get("carrier", "") in MC.CARRIERS: continue
		var a: String = str(int(line.from))
		var b: String = str(int(line.to))
		var q: float = float(report.lines[i].sent_kg_s)
		if outgoing.has(a): outgoing[a] += q
		if incoming.has(b): incoming[b] += q
	for d in devices:
		if not d.kind in MC.INVENTORY_KINDS: continue
		var id: String = str(int(d.id))
		var sp: String = MC.species(d.kind)
		var decay: float = float(MC.phase_coefficients(d.kind).leak_per_h) if d.kind in MC.PHASE_KINDS else float(d.params.leak_per_h) if d.kind == "hydrogen_gas_store" else 0.0
		var delta: float = float(incoming[id])-float(outgoing[id])
		if d.kind in MC.SYNTHESIS_KINDS:
			var h2_in: float = 0.0
			for i in links.size():
				if links[i].get("species_id") == "H2" and int(links[i].to)==int(d.id): h2_in += float(report.lines[i].sent_kg_s)
			delta = h2_in/MC.chemical_coefficients(d.kind).hydrogen_per_product
		var stock: float = float(d.state.material_inventory_kg[sp])*exp(-decay*dt/3600.0)+delta*dt
		var cap: float = MC.inventory_capacity(d.kind,d.params)
		# Only the independent floating-point reference is rounded at an exact
		# exhausted/full boundary; no reported or live inventory is modified.
		if stock < 0.0 and stock > -1e-12: stock = 0.0
		if stock > cap and stock < cap+1e-12: stock = cap
		next[id] = {"material_inventory_kg":{sp:stock}}
		if d.kind == "hydrogen_metal_hydride_store": next[id].host_dry_mass_kg = d.state.host_dry_mass_kg
	return next

static func _chemical_balance(prepared: Dictionary, m: Dictionary) -> void:
	var before: Dictionary = Ledger.empty_inventory()
	for n in prepared.nodes.values():
		if n.valid and n.kind in MC.INVENTORY_KINDS: before[MC.reference_id(n.kind)] += float(n.state.material_inventory_kg[MC.species(n.kind)])
	var boundary_in: Dictionary = Ledger.empty_inventory()
	var boundary_out: Dictionary = Ledger.empty_inventory()
	var dt: float = prepared.report.dt_s
	boundary_in.O2_gas_25c = m.oxygen_from_air_kg_s*dt
	boundary_out.O2_gas_25c = m.oxygen_vented_kg_s*dt
	boundary_out.H2O_liquid_25c = m.water_released_kg_s*dt
	boundary_out.H2_gas_25c = m.hydrogen_leaked_kg
	var ba: Dictionary = Ledger.atoms_for_inventory(before)
	var ia: Dictionary = Ledger.atoms_for_inventory(boundary_in)
	var oa: Dictionary = Ledger.atoms_for_inventory(boundary_out)
	var aa: Dictionary = Ledger.atoms_for_inventory(m.inventory_by_reference_kg)
	if ba.is_empty() or ia.is_empty() or oa.is_empty() or aa.is_empty():
		# Invalid inventory must remain an explicit failed audit, not zero atoms.
		for field in ["mass_balance_error_kg", "hydrogen_element_error_kg", "carbon_element_error_kg", "nitrogen_element_error_kg", "oxygen_element_error_kg", "enthalpy_balance_error_mw"]: m[field] = NAN
		return
	for e in {"H":"hydrogen","C":"carbon","N":"nitrogen","O":"oxygen"}: m[{"H":"hydrogen","C":"carbon","N":"nitrogen","O":"oxygen"}[e]+"_element_error_kg"] = ba[e]+ia[e]-oa[e]-aa[e]
	m.mass_balance_error_kg = m.hydrogen_element_error_kg+m.carbon_element_error_kg+m.nitrogen_element_error_kg+m.oxygen_element_error_kg
	# Rate-form reference enthalpy avoids catastrophic cancellation when a GUI
	# frame is tiny relative to large stored inventories. Inventory/atom maps and
	# the cumulative reference ledger remain separately checked, not replaced.
	var enthalpy_terms: Array = []
	if dt > 0.0:
		for id in prepared.nodes:
			var n: Dictionary = prepared.nodes[id]
			if not n.valid or not n.kind in MC.INVENTORY_KINDS: continue
			var d: Dictionary = prepared.report.devices[id]
			var rate: float = 0.0
			if n.kind == "water_supply_boundary": rate = -d.water_out_kg_s
			elif n.kind in MC.HYDROGEN_STORE_KINDS: rate = d.hydrogen_in_kg_s-d.hydrogen_out_kg_s-d.leaked_kg/dt
			elif n.kind in MC.FEED_KINDS: rate = -d["nitrogen_out_kg_s" if n.kind == "nitrogen_supply_boundary" else "co2_out_kg_s"]
			elif n.kind in MC.SYNTHESIS_KINDS: rate = d.product_produced_kg_s
			enthalpy_terms.append(rate*float(Ledger.H_MWH_PER_KG[MC.reference_id(n.kind)])*3600.0)
		enthalpy_terms.append(m.water_released_kg_s*float(Ledger.H_MWH_PER_KG.H2O_liquid_25c)*3600.0)
		# O2 and leaked H2 cross the boundary at zero formation enthalpy.
	m.enthalpy_balance_error_mw = m.electrolyzer_electric_mw+m.compression_electric_mw+m.phase_store_electric_mw+m.chemical_electric_mw+m.environment_heat_in_mwth-m.fuel_cell_output_mw-m.heat_rejected_mwth-Ledger._sum(enthalpy_terms)

## Runtime is demand-first, then deterministic-ID surplus-renewable production.
## The optimizer may use finite electrical stores for an explicit product target.
static func synthesize_surplus(prepared: Dictionary, allocate: Callable) -> void:
	if not prepared.report.has("material"): return
	var ids: Array = prepared.nodes.keys()
	ids.sort_custom(func(a,b):return int(a)<int(b))
	for sid in ids:
		var n: Dictionary = prepared.nodes[sid]
		if not n.valid or not n.kind in MC.SYNTHESIS_KINDS: continue
		var cc: Dictionary = MC.chemical_coefficients(n.kind)
		for hi in prepared.material_lines:
			var hl: Dictionary = prepared.report.lines[hi]
			if str(hl.to)!=sid or hl.species_id!="H2": continue
			var hid: String = str(hl.from)
			if prepared.report.devices[hid].mode=="charge": continue
			for fi in prepared.material_lines:
				var fl: Dictionary = prepared.report.lines[fi]
				if str(fl.to)!=sid or fl.species_id!=cc.feed: continue
				var fid: String = str(fl.from)
				for ep in prepared.paths:
					if ep.sink_id!=sid or not ep.source_kind in ["wind","pv"]: continue
					var aps: Array = []
					if prepared.nodes[hid].kind in MC.PHASE_KINDS:
						for ap in prepared.paths:
							if ap.sink_id==hid and (ap.source_kind in ["wind","pv"] or Catalog.is_electric_storage(ap.source_kind)): aps.append(ap)
					else: aps.append({})
					for ap in aps:
						var mass: Dictionary = {"material_product:"+sid:1.0,"material_feed:"+fid:cc.feed_per_product,"material_discharge:"+hid:cc.hydrogen_per_product,"material_line:"+str(fi):cc.feed_per_product,"material_line:"+str(hi):cc.hydrogen_per_product}
						var all: Dictionary = mass.duplicate()
						var ef: float = 3.6*cc.electric_kwh_per_kg/ep.received
						var electric: Array = [{"path":ep,"factor":ef}]
						for key in ep.coefficients: _add(all,key,ef*float(ep.coefficients[key]))
						if not ap.is_empty():
							var af: float = 3.6*MC.phase_coefficients(prepared.nodes[hid].kind).discharge_kwh_per_kg*cc.hydrogen_per_product/ap.received
							for key in ap.coefficients: _add(all,key,af*float(ap.coefficients[key]))
							electric.append({"path":ap,"factor":af})
						var q: float = _representable_rate(prepared, mass, _limit(all,prepared.resources))
						if not _reserve(prepared,electric,mass,q,allocate): continue
						_record_line(prepared,hi,q*cc.hydrogen_per_product)
						_record_line(prepared,fi,q*cc.feed_per_product)
						prepared.report.devices[hid].hydrogen_out_kg_s += q*cc.hydrogen_per_product
						prepared.report.devices[hid].mode = "discharge"
						var feed_field: String = "nitrogen" if cc.feed=="N2" else "co2"
						prepared.report.devices[fid][feed_field+"_out_kg_s"] += q*cc.feed_per_product
						prepared.report.devices[fid].mode = "supply"
						prepared.report.devices[sid][feed_field+"_in_kg_s"] += q*cc.feed_per_product
						prepared.report.devices[sid].hydrogen_in_kg_s += q*cc.hydrogen_per_product
						prepared.report.devices[sid].mode = "produce"
