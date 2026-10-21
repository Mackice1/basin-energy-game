extends RefCounted
## Steady north-south horizontal one-axis aperture model, teaching proxy coefficients.
## Oil inventory is useful 200->300 C enthalpy only; no startup or cold-tank model.
const Catalog = preload("res://scripts/device_catalog.gd")
const Solar = preload("res://scripts/solar_thermal.gd")
const FIELDS = Solar.FIELDS
const LEDGER_FIELDS = ["collector_auxiliary_electric_mw", "oil_auxiliary_electric_mw", "oil_water_output_mwth", "exchanger_loss_mwth", "charge_mwth", "discharge_mwth", "storage_conversion_loss_mwth", "storage_loss_mwth", "self_discharge_mwhth", "energy_mwhth", "soc", "balance_error_mwth", "energy_balance_error_mwhth"]
static func empty() -> Dictionary:
	var r: Dictionary = Solar.empty()
	for key in LEDGER_FIELDS: r[key] = 0.0
	return r
static func evaluate(params: Dictionary, weather: Dictionary) -> Dictionary:
	var p: Dictionary = Catalog.defaults("parabolic_trough")
	p.merge(params, true)
	var r: Dictionary = Solar.empty()
	var errors: Array[String] = Catalog.validate_thermal("parabolic_trough", p)
	for key in ["dni_wm2", "solar_altitude_deg", "solar_azimuth_deg", "air_temp_c"]:
		var v: Variant = weather.get(key)
		if not (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) or not is_finite(float(v)):
			errors.append("Trough requires explicit finite weather: " + key)
	if errors.is_empty():
		if float(weather.dni_wm2) < 0.0 or float(weather.dni_wm2) > 2000.0: errors.append("DNI outside [0,2000]")
		if absf(float(weather.solar_altitude_deg)) > 90.0: errors.append("Solar altitude outside [-90,90]")
		if float(weather.solar_azimuth_deg) < 0.0 or float(weather.solar_azimuth_deg) > 360.0: errors.append("Solar azimuth outside [0,360]")
		if absf(float(weather.air_temp_c)) > 100.0: errors.append("Air temperature outside [-100,100]")
	if weather.has("is_day") and not weather.is_day is bool: errors.append("is_day must be boolean")
	r.merge({"valid": errors.is_empty(), "errors": errors, "dni_wm2": 0.0, "cos_incidence": 0.0, "mean_fluid_temp_c": 250.0, "area_basis": "aperture", "irradiance_kind": "dni", "tracking_axis": "north_south_horizontal", "fluid": "Therminol66"})
	if not errors.is_empty(): return r
	var cosine: float = sqrt(maxf(0.0, 1.0 - pow(cos(deg_to_rad(float(weather.solar_altitude_deg))) * cos(deg_to_rad(float(weather.solar_azimuth_deg))), 2.0)))
	var dni: float = float(weather.dni_wm2) if weather.get("is_day", true) and float(weather.solar_altitude_deg) > 0.0 else 0.0
	var delta: float = maxf(0.0, 250.0 - float(weather.air_temp_c))
	r.dni_wm2 = dni
	r.cos_incidence = cosine
	r.incident_mw = float(p.aperture_area_m2) * dni * cosine / 1.0e6
	var absorbed: float = r.incident_mw * float(p.optical_efficiency)
	r.optical_rejection_mw = r.incident_mw - absorbed
	r.potential_thermal_loss_mw = float(p.aperture_area_m2) * (float(p.heat_loss_w_m2k) * delta + float(p.heat_loss_quadratic_w_m2k2) * delta * delta) / 1.0e6
	r.thermal_loss_mw = minf(absorbed, r.potential_thermal_loss_mw)
	r.available_mwth = maxf(0.0, absorbed - r.potential_thermal_loss_mw)
	r.curtailed_mwth = r.available_mwth
	return r
static func initial_energy() -> Dictionary:
	var r: Dictionary = Solar.initial_energy()
	for key in ["oil_auxiliary_mwh", "oil_water_output_mwhth", "exchanger_loss_mwhth", "charge_mwhth", "discharge_mwhth", "storage_conversion_loss_mwhth", "self_discharge_mwhth"]: r[key] = 0.0
	return r
static func validate_energy(value: Variant) -> String:
	if not value is Dictionary: return "high_temp_energy must be an object"
	var base: Dictionary = {}
	for key in Solar.initial_energy(): base[key] = value.get(key)
	var err: String = Solar.validate_energy(base)
	if not err.is_empty(): return "High temperature: " + err
	for key in value:
		if key == "rankine_oil_input_mwhth":
			if not (typeof(value[key]) == TYPE_FLOAT or typeof(value[key]) == TYPE_INT) or not is_finite(float(value[key])) or float(value[key]) < 0.0: return "Invalid Rankine oil cumulative draw"
			continue
		if not initial_energy().has(key): return "Unknown high temperature energy field: " + str(key)
	for key in initial_energy():
		var v: Variant = value.get(key)
		if not (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) or not is_finite(float(v)) or float(v) < 0.0: return "Invalid high temperature energy: " + key
	var tol: float = 1.0e-6 + 1.0e-7 * float(value.useful_mwhth)
	if absf(float(value.useful_mwhth) + float(value.discharge_mwhth) - float(value.charge_mwhth) - float(value.oil_water_output_mwhth) - float(value.exchanger_loss_mwhth) - float(value.get("rankine_oil_input_mwhth", 0.0))) > tol: return "Oil circuit cumulative balance mismatch"
	var hot_input: float = float(value.oil_water_output_mwhth) + float(value.exchanger_loss_mwhth)
	if float(value.oil_auxiliary_mwh) < hot_input * .001 - tol or float(value.oil_auxiliary_mwh) > hot_input * .2 + tol: return "Oil auxiliary cumulative ratio mismatch"
	return ""

static func add_paths(prepared: Dictionary, paths: Array) -> void:
	var r: Dictionary = prepared.report
	var nodes: Dictionary = prepared.nodes
	for line in r.lines:
		if not line.valid or line.carrier != "heat_oil": continue
		r.devices[str(line.from)].heat_connected = true
		r.devices[str(line.to)].heat_connected = true
		var sid: String = str(line.from)
		var tid: String = str(line.to)
		if not nodes[sid].kind in ["parabolic_trough", "high_temp_store"]: continue
		var base: Dictionary = {"high_temp": true, "source_id": sid, "source_kind": nodes[sid].kind, "sink_id": tid, "sink_kind": nodes[tid].kind, "first": line.index, "second": -1, "hx_id": "", "efficiency": 1.0, "edges": [line.index], "exchangers": []}
		if nodes[tid].kind == "high_temp_store": paths.append(base)
		if nodes[tid].kind != "oil_water_exchanger": continue
		for middle in r.lines:
			if not middle.valid or middle.from != line.to or middle.carrier != "heat_water": continue
			var hid: String = str(middle.to)
			if nodes[hid].kind != "heat_exchanger": continue
			for last in r.lines:
				if not last.valid or last.from != middle.to or last.carrier != "heat_water" or nodes[str(last.to)].kind != "heat_demand": continue
				var path: Dictionary = base.duplicate(true)
				path.sink_id = str(last.to)
				path.sink_kind = "heat_demand"
				path.hx_id = tid
				path.edges = [line.index, middle.index, last.index]
				path.exchangers = [tid, hid]
				path.efficiency = float(nodes[tid].params.transfer_efficiency) * float(nodes[hid].params.transfer_efficiency)
				path.coefficients = {"heat_line:" + str(line.index): 1.0, "hx:" + tid: 1.0, "heat_line:" + str(middle.index): float(nodes[tid].params.transfer_efficiency), "hx:" + hid: float(nodes[tid].params.transfer_efficiency), "heat_line:" + str(last.index): path.efficiency, "heat_demand:" + path.sink_id: path.efficiency}
				path.coefficients[("solar:" if nodes[sid].kind == "parabolic_trough" else "heat_discharge:") + sid] = 1.0
				paths.append(path)
	for path in paths:
		if path.get("high_temp", false) and not path.has("coefficients"):
			path.coefficients = {"heat_line:" + str(path.first): 1.0, "solar:" + path.source_id: 1.0, "heat_charge:" + path.sink_id: 1.0}

## Reserve heat and every required AC path together before recording anything.
## The second AC path is selected after accounting for the first on shared rows.
static func supply(path: Dictionary, prepared: Dictionary, allocate: Callable, record_heat: Callable, allow_battery: bool) -> void:
	var consumers: Array = []
	if path.source_kind == "parabolic_trough": consumers.append({"id": path.source_id, "ratio": prepared.nodes[path.source_id].params.auxiliary_electric_ratio})
	if not path.exchangers.is_empty(): consumers.append({"id": path.exchangers[0], "ratio": prepared.nodes[path.exchangers[0]].params.auxiliary_electric_ratio})
	var options: Array = [[]]
	for consumer in consumers:
		var expanded: Array = []
		for choice in options:
			for battery in [false, true]:
				if battery and not allow_battery: continue
				for ep in prepared.paths:
					if ep.sink_id != consumer.id or (ep.source_kind == "battery") != battery: continue
					var next: Array = choice.duplicate()
					next.append({"path": ep, "factor": float(consumer.ratio) / float(ep.received)})
					expanded.append(next)
		options = expanded
	for choice in options:
		if path.source_kind == "high_temp_store" and prepared.report.devices[path.source_id].mode == "charge": return
		if path.sink_kind == "high_temp_store" and prepared.report.devices[path.sink_id].mode == "discharge": return
		var coeffs: Dictionary = path.coefficients.duplicate()
		for c in choice:
			for key in c.path.coefficients: coeffs[key] = float(coeffs.get(key, 0.0)) + float(c.path.coefficients[key]) * float(c.factor)
		var q: float = INF
		for key in coeffs:
			if float(coeffs[key]) > 0.0: q = minf(q, maxf(0.0, float(prepared.resources[key])) / float(coeffs[key]))
		if not is_finite(q) or q <= 1.0e-9: continue
		for c in choice: allocate.call(c.path, prepared.resources, prepared.report, q * float(c.factor))
		record_heat.call(path, q, prepared)

static func _near(errors: Array[String], actual: Variant, expected: float, label: String) -> void:
	if not (typeof(actual) == TYPE_FLOAT or typeof(actual) == TYPE_INT) or not is_finite(float(actual)) or absf(float(actual) - expected) > 2.0e-6 + 2.0e-7 * absf(expected): errors.append("Independent audit: high temperature " + label)

static func audit(prepared: Dictionary, errors: Array[String]) -> Dictionary:
	var totals: Dictionary = empty()
	var r: Dictionary = prepared.report
	if r.has("rankine"): totals.rankine_oil_input_mwth = 0.0
	var inputs: Dictionary = {}
	var outputs: Dictionary = {}
	var before_total: float = 0.0
	var capacity: float = 0.0
	for id in prepared.nodes:
		inputs[id] = {"electricity_ac": 0.0, "heat_oil": 0.0, "heat_water": 0.0}
		outputs[id] = inputs[id].duplicate()
	for line in r.lines:
		if not line.valid: continue
		if line.carrier == "water_steam": continue
		var heat: bool = line.carrier in ["heat_oil", "heat_water"]
		if heat and r.has("high_temp") and (line.flow_from != line.from or line.flow_to != line.to): errors.append("Independent audit: reversed thermal flow endpoints")
		var sent: Variant = line.get("sent_mwth" if heat else "sent_mw")
		var received: Variant = line.get("received_mwth" if heat else "received_mw")
		if not (typeof(sent) == TYPE_FLOAT or typeof(sent) == TYPE_INT) or not (typeof(received) == TYPE_FLOAT or typeof(received) == TYPE_INT): continue
		if outputs.has(str(line.flow_from)) and outputs[str(line.flow_from)].has(line.carrier): outputs[str(line.flow_from)][line.carrier] += float(sent)
		if inputs.has(str(line.flow_to)) and inputs[str(line.flow_to)].has(line.carrier): inputs[str(line.flow_to)][line.carrier] += float(received)
	if r.has("rankine"):
		for id in prepared.nodes:
			if prepared.nodes[id].kind == "steam_generator": totals.rankine_oil_input_mwth += float(inputs[id].heat_oil)
	for id in prepared.nodes:
		var n: Dictionary = prepared.nodes[id]
		if not n.valid or not n.kind in ["parabolic_trough", "oil_water_exchanger", "high_temp_store"]: continue
		var d: Dictionary = r.devices[id]
		var p: Dictionary = n.params
		var ei: float = inputs[id].electricity_ac
		var hi: float = inputs[id].heat_oil
		var ho: float = outputs[id].heat_oil
		if n.kind == "parabolic_trough":
			var physics: Dictionary = evaluate(p, prepared.weather)
			if not physics.valid: errors.append("Independent audit: invalid trough physics")
			for key in ["incident_mw", "optical_rejection_mw", "potential_thermal_loss_mw", "thermal_loss_mw", "available_mwth", "dni_wm2", "cos_incidence", "mean_fluid_temp_c"]:
				_near(errors, d.get(key), float(physics[key]), id + " source " + key)
				if totals.has(key): totals[key] += float(physics[key])
			for key in ["area_basis", "irradiance_kind", "tracking_axis", "fluid"]:
				if d.get(key) != physics[key]: errors.append("Independent audit: trough convention " + key)
			_near(errors, ei, ho * float(p.auxiliary_electric_ratio), id + " collector auxiliary")
			for key in ["output_mwth", "heat_output_mwth", "useful_mwth"]: _near(errors, d.get(key), ho, id + " " + key)
			_near(errors, d.get("curtailed_mwth"), float(physics.available_mwth) - ho, id + " curtailment")
			if ho < -2e-6 or ho > float(physics.available_mwth) + 2e-6: errors.append("Independent audit: trough availability exceeded")
			totals.useful_mwth += ho
			totals.curtailed_mwth += float(physics.available_mwth) - ho
			totals.collector_auxiliary_electric_mw += ei
		elif n.kind == "oil_water_exchanger":
			var water: float = outputs[id].heat_water
			_near(errors, water, hi * float(p.transfer_efficiency), id + " oil-water conversion")
			_near(errors, ei, hi * float(p.auxiliary_electric_ratio), id + " oil circulation auxiliary")
			for key in ["input_mwth", "hot_input_mwth"]: _near(errors, d.get(key), hi, id + " " + key)
			for key in ["output_mwth", "warm_output_mwth"]: _near(errors, d.get(key), water, id + " " + key)
			_near(errors, d.get("loss_mwth"), hi - water, id + " exchanger loss")
			if hi > float(p.capacity_mwth) + 2e-6: errors.append("Independent audit: oil exchanger rating")
			if not Catalog.validate_thermal(n.kind, p).is_empty(): errors.append("Independent audit: oil exchanger grades")
			totals.oil_water_output_mwth += water
			totals.exchanger_loss_mwth += hi - water
			totals.oil_auxiliary_electric_mw += ei
		else:
			var before: float = n.state.energy_mwhth
			var decayed: float = before * exp(-float(p.self_discharge_per_h) * float(r.dt_h))
			var after: float = decayed + (float(p.charge_efficiency) * hi - ho / float(p.discharge_efficiency)) * float(r.dt_h)
			var conversion: float = hi * (1.0 - float(p.charge_efficiency)) + ho * (1.0 / float(p.discharge_efficiency) - 1.0)
			_near(errors, d.get("charge_mwth"), hi, id + " charge")
			_near(errors, d.get("discharge_mwth"), ho, id + " discharge")
			_near(errors, d.get("input_mwth"), hi, id + " store input")
			_near(errors, d.get("output_mwth"), ho, id + " store output")
			_near(errors, d.get("self_discharge_mwhth"), before - decayed, id + " standing loss")
			_near(errors, d.get("storage_conversion_loss_mwth"), conversion, id + " storage conversion loss")
			_near(errors, d.get("next_energy_mwhth"), after, id + " inventory")
			_near(errors, r.next_states.get(id, {}).get("energy_mwhth"), after, id + " next inventory")
			_near(errors, d.get("soc"), after / float(p.capacity_mwhth), id + " soc")
			if hi > float(p.charge_mwth) + 2e-6 or ho > float(p.discharge_mwth) + 2e-6 or after < -2e-6 or after > float(p.capacity_mwhth) + 2e-6 or (hi > 1e-9 and ho > 1e-9) or (r.dt_h == 0.0 and (hi > 1e-9 or ho > 1e-9)): errors.append("Independent audit: oil inventory/rate/mode")
			var mode: String = "charge" if hi > 1e-9 else ("discharge" if ho > 1e-9 else "idle")
			if d.get("mode") != mode: errors.append("Independent audit: oil mode label")
			totals.charge_mwth += hi
			totals.discharge_mwth += ho
			totals.self_discharge_mwhth += before - decayed
			totals.storage_conversion_loss_mwth += conversion
			totals.energy_mwhth += after
			before_total += before
			capacity += float(p.capacity_mwhth)
		if n.kind != "high_temp_store":
			_near(errors, d.get("auxiliary_electric_mw"), ei, id + " auxiliary input")
			_near(errors, d.get("auxiliary_electric_loss_mw"), ei, id + " auxiliary loss")
			totals.auxiliary_electric_mw += ei
	totals.storage_loss_mwth = totals.storage_conversion_loss_mwth + (totals.self_discharge_mwhth / float(r.dt_h) if float(r.dt_h) > 0.0 else 0.0)
	totals.soc = totals.energy_mwhth / capacity if capacity > 0.0 else 0.0
	totals.balance_error_mwth = totals.useful_mwth + totals.discharge_mwth - totals.charge_mwth - totals.oil_water_output_mwth - totals.exchanger_loss_mwth - float(totals.get("rankine_oil_input_mwth", 0.0))
	totals.energy_balance_error_mwhth = before_total - totals.energy_mwhth - totals.self_discharge_mwhth + (totals.useful_mwth - totals.oil_water_output_mwth - totals.exchanger_loss_mwth - totals.storage_conversion_loss_mwth - float(totals.get("rankine_oil_input_mwth", 0.0))) * float(r.dt_h)
	_near(errors, totals.balance_error_mwth, 0.0, "oil power conservation")
	_near(errors, totals.energy_balance_error_mwhth, 0.0, "oil energy conservation")
	if r.has("high_temp"):
		_near(errors, r.get("cross_carrier_balance_error_mw"), 0.0, "reported cross-carrier residual")
		for key in totals: _near(errors, r.high_temp.get(key), float(totals[key]), "aggregate " + key)
	return totals
