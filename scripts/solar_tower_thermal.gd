extends RefCounted
## Preheated steady-state molten-salt teaching circuit, 565/290 C.
## Mirror optical efficiency includes field cosine/shading/intercept losses.
## No cold start, freeze protection, dynamic temperature or high-pressure cycle.
const Catalog = preload("res://scripts/device_catalog.gd")
const Solar = preload("res://scripts/solar_thermal.gd")
const KINDS := ["solar_tower_receiver", "molten_salt_store", "salt_steam_generator"]
const LEDGER_FIELDS := ["receiver_auxiliary_electric_mw", "store_auxiliary_electric_mw", "rankine_salt_input_mwth", "charge_mwth", "discharge_mwth", "storage_conversion_loss_mwth", "storage_loss_mwth", "self_discharge_mwhth", "energy_mwhth", "soc", "balance_error_mwth", "energy_balance_error_mwhth"]
const EPS: float = 1e-9

static func empty() -> Dictionary:
	var r: Dictionary = Solar.empty()
	for key in LEDGER_FIELDS: r[key] = 0.0
	return r

static func _number(v: Variant) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))

static func evaluate(params: Dictionary, weather: Dictionary) -> Dictionary:
	var p: Dictionary = Catalog.defaults("solar_tower_receiver")
	p.merge(params, true)
	var r: Dictionary = Solar.empty()
	var errors: Array[String] = Catalog.validate_thermal("solar_tower_receiver", p)
	for key in ["dni_wm2", "solar_altitude_deg", "solar_azimuth_deg", "air_temp_c"]:
		if not _number(weather.get(key)): errors.append("Tower requires explicit finite weather: " + key)
	if errors.is_empty():
		if float(weather.dni_wm2) < 0.0 or float(weather.dni_wm2) > 2000.0: errors.append("Tower DNI outside [0,2000]")
		if absf(float(weather.solar_altitude_deg)) > 90.0: errors.append("Tower solar altitude outside [-90,90]")
		if float(weather.solar_azimuth_deg) < 0.0 or float(weather.solar_azimuth_deg) > 360.0: errors.append("Tower solar azimuth outside [0,360]")
		if absf(float(weather.air_temp_c)) > 100.0: errors.append("Tower ambient temperature outside [-100,100]")
	if not weather.get("is_day") is bool: errors.append("Tower is_day must be boolean")
	r.merge({"valid": errors.is_empty(), "errors": errors, "dni_wm2": 0.0, "area_basis": "mirror_aperture", "irradiance_kind": "dni", "fluid": "molten_salt", "supply_temp_c": 565.0, "return_temp_c": 290.0})
	if not errors.is_empty(): return r
	r.dni_wm2 = float(weather.dni_wm2) if weather.get("is_day", true) and float(weather.solar_altitude_deg) > 0.0 else 0.0
	r.incident_mw = float(p.mirror_area_m2) * r.dni_wm2 / 1e6
	var absorbed: float = r.incident_mw * float(p.optical_efficiency)
	r.optical_rejection_mw = r.incident_mw - absorbed
	r.thermal_loss_mw = absorbed * (1.0 - float(p.receiver_efficiency))
	r.potential_thermal_loss_mw = r.thermal_loss_mw
	r.available_mwth = absorbed * float(p.receiver_efficiency)
	r.curtailed_mwth = r.available_mwth
	return r

static func initial_energy() -> Dictionary:
	var r: Dictionary = Solar.initial_energy()
	for key in ["receiver_auxiliary_mwh", "store_auxiliary_mwh", "rankine_salt_input_mwhth", "charge_mwhth", "discharge_mwhth", "storage_conversion_loss_mwhth", "self_discharge_mwhth"]: r[key] = 0.0
	return r

static func validate_energy(v: Variant) -> String:
	if not v is Dictionary: return "tower_energy must be an object"
	var expected: Dictionary = initial_energy()
	if v.size() != expected.size(): return "tower_energy has unexpected fields"
	for key in expected:
		if not _number(v.get(key)) or float(v[key]) < 0.0: return "Invalid tower energy: " + key
	var tol: float = 1e-6 + 1e-7 * float(v.incident_mwh)
	if absf(float(v.incident_mwh)-float(v.optical_rejection_mwh)-float(v.thermal_loss_mwh)-float(v.available_mwhth)) > tol: return "Tower incident energy mismatch"
	if absf(float(v.available_mwhth)-float(v.useful_mwhth)-float(v.curtailed_mwhth)) > tol: return "Tower useful energy mismatch"
	if absf(float(v.useful_mwhth)+float(v.discharge_mwhth)-float(v.charge_mwhth)-float(v.rankine_salt_input_mwhth)) > tol: return "Salt circuit cumulative balance mismatch"
	if absf(float(v.auxiliary_mwh)-float(v.receiver_auxiliary_mwh)-float(v.store_auxiliary_mwh)) > tol: return "Tower auxiliary total mismatch"
	for pair in [["receiver_auxiliary_mwh", float(v.useful_mwhth)], ["store_auxiliary_mwh", float(v.charge_mwhth)+float(v.discharge_mwhth)]]:
		if float(v[pair[0]]) < float(pair[1])*.001-tol or float(v[pair[0]]) > float(pair[1])*.2+tol: return "Tower auxiliary cumulative ratio mismatch"
	return ""

static func initialize_node(id: String, kind: String, p: Dictionary, state: Dictionary, dt_s: float, d: Dictionary, resources: Dictionary) -> void:
	d.merge({"model_profile": Catalog.model_profile(kind), "model_profile_version": 1, "input_mwth": 0.0, "output_mwth": 0.0, "loss_mwth": 0.0, "heat_connected": false, "electric_connected": false, "auxiliary_electric_mw": 0.0, "auxiliary_electric_loss_mw": 0.0})
	if kind == "solar_tower_receiver":
		d.heat_output_mwth = 0.0
		resources["solar:" + id] = d.available_mwth
		resources["solar_aux:" + id] = d.available_mwth * float(p.auxiliary_electric_ratio)
	elif kind == "molten_salt_store":
		var limits: Dictionary = Catalog.thermal_storage_limits(p, state.energy_mwhth, dt_s)
		d.merge(limits)
		d.merge({"mode": "idle", "soc": state.energy_mwhth / p.capacity_mwhth, "soc_before": state.energy_mwhth / p.capacity_mwhth, "energy_mwhth": state.energy_mwhth, "next_energy_mwhth": limits.energy_after_self_discharge_mwhth, "capacity_mwhth": p.capacity_mwhth, "charge_mwth": 0.0, "discharge_mwth": 0.0, "storage_conversion_loss_mwth": 0.0, "storage_balance_error_mwhth": 0.0})
		resources["heat_charge:" + id] = limits.charge_limit_mwth
		resources["heat_discharge:" + id] = limits.discharge_limit_mwth
		resources["solar_aux:" + id] = maxf(float(p.charge_mwth), float(p.discharge_mwth)) * float(p.auxiliary_electric_ratio)

static func prepare(prepared: Dictionary) -> void:
	if not prepared.report.has("tower"): return
	prepared.tower_charge_paths = []
	for line in prepared.report.lines:
		if not line.valid or line.carrier != "heat_salt": continue
		prepared.report.devices[str(line.from)].heat_connected = true
		prepared.report.devices[str(line.to)].heat_connected = true
		if prepared.nodes[str(line.from)].kind == "solar_tower_receiver" and prepared.nodes[str(line.to)].kind == "molten_salt_store":
			prepared.tower_charge_paths.append({"source_id": str(line.from), "sink_id": str(line.to), "edge": line.index, "coefficients": {"solar:"+str(line.from): 1.0, "heat_charge:"+str(line.to): 1.0, "heat_line:"+str(line.index): 1.0}})
	prepared.tower_charge_paths.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.sink_id) < int(b.sink_id) if a.sink_id != b.sink_id else int(a.source_id) < int(b.source_id))

static func _charge_plan(prepared: Dictionary, path: Dictionary, q: float) -> Dictionary:
	var resources: Dictionary = prepared.resources.duplicate()
	for key in path.coefficients:
		resources[key] -= q * float(path.coefficients[key])
		if float(resources[key]) < -1e-12: return {"ok": false}
	var allocations: Array = []
	for id in [path.source_id, path.sink_id]:
		var remaining: float = q * float(prepared.nodes[id].params.auxiliary_electric_ratio)
		for ep in prepared.paths:
			if ep.sink_id != id or not ep.source_kind in ["wind", "pv", "battery"]: continue
			if ep.source_kind == "battery" and prepared.report.devices[ep.source_id].mode == "charge": continue
			var sent: float = remaining / float(ep.received)
			for key in ep.coefficients:
				if float(ep.coefficients[key]) > 0.0: sent = minf(sent, maxf(0.0, float(resources[key]))/float(ep.coefficients[key]))
			if sent <= 0.0: continue
			for key in ep.coefficients: resources[key] = maxf(0.0, float(resources[key])-sent*float(ep.coefficients[key]))
			allocations.append({"path": ep, "sent": sent})
			remaining -= sent * float(ep.received)
			if remaining <= 1e-14: break
		if remaining > 1e-14: return {"ok": false}
	return {"ok": true, "allocations": allocations}

static func charge_surplus(prepared: Dictionary, allocate: Callable) -> void:
	if not prepared.report.has("tower") or float(prepared.report.dt_h) <= 0.0: return
	for path in prepared.get("tower_charge_paths", []):
		if prepared.report.devices[path.sink_id].mode == "discharge": continue
		var q: float = INF
		for key in path.coefficients: q = minf(q, maxf(0.0, float(prepared.resources[key]))/float(path.coefficients[key]))
		if not is_finite(q) or q <= EPS: continue
		var plan: Dictionary = _charge_plan(prepared, path, q)
		if not plan.ok:
			var low: float = 0.0
			var high: float = q
			for i in 40:
				var mid: float = (low+high)*.5
				if _charge_plan(prepared, path, mid).ok: low = mid
				else: high = mid
			q = low
			plan = _charge_plan(prepared, path, q)
		if not plan.ok or q <= EPS: continue
		for allocation in plan.allocations: allocate.call(allocation.path, prepared.resources, prepared.report, allocation.sent)
		for key in path.coefficients: prepared.resources[key] = maxf(0.0, float(prepared.resources[key])-q*float(path.coefficients[key]))
		var source: Dictionary = prepared.report.devices[path.source_id]
		var sink: Dictionary = prepared.report.devices[path.sink_id]
		source.output_mwth += q
		source.heat_output_mwth += q
		sink.input_mwth += q
		sink.charge_mwth += q
		sink.mode = "charge"
		var line: Dictionary = prepared.report.lines[path.edge]
		line.sent_mwth += q
		line.received_mwth += q
		line.signed_mwth = line.sent_mwth
		line.direction = 1

static func finish(prepared: Dictionary) -> void:
	var r: Dictionary = prepared.report
	if not r.has("tower"): return
	var t: Dictionary = empty()
	var before: float = 0.0
	var capacity: float = 0.0
	for id in prepared.nodes:
		var n: Dictionary = prepared.nodes[id]
		if not n.valid or not n.kind in ["solar_tower_receiver", "molten_salt_store"]: continue
		var d: Dictionary = r.devices[id]
		var p: Dictionary = n.params
		d.auxiliary_electric_loss_mw = d.auxiliary_electric_mw
		if n.kind == "solar_tower_receiver":
			d.useful_mwth = d.output_mwth
			d.curtailed_mwth = maxf(0.0, d.available_mwth-d.useful_mwth)
			d.utilization = d.useful_mwth/d.available_mwth if d.available_mwth > EPS else 0.0
			d.status_reason = "塔式熔盐集热" if d.useful_mwth > EPS else "未集热：DNI、受端或外部辅机电力不足"
			for key in Solar.FIELDS: t[key] += d[key]
			t.receiver_auxiliary_electric_mw += d.auxiliary_electric_mw
		else:
			var e: float = d.energy_after_self_discharge_mwhth+(float(p.charge_efficiency)*d.charge_mwth-d.discharge_mwth/float(p.discharge_efficiency))*float(r.dt_h)
			d.next_energy_mwhth = clampf(e, 0.0, float(p.capacity_mwhth))
			d.soc = d.next_energy_mwhth/float(p.capacity_mwhth)
			d.storage_conversion_loss_mwth = d.charge_mwth*(1.0-float(p.charge_efficiency))+d.discharge_mwth*(1.0/float(p.discharge_efficiency)-1.0)
			d.storage_balance_error_mwhth = e-d.next_energy_mwhth
			d.utilization = d.charge_mwth/float(p.charge_mwth) if d.mode == "charge" and float(p.charge_mwth)>0.0 else (d.discharge_mwth/float(p.discharge_mwth) if float(p.discharge_mwth)>0.0 else 0.0)
			d.status_reason = "盐储已空" if e<=EPS else ("盐储已满" if e>=float(p.capacity_mwhth)-EPS else d.mode)
			r.next_states[id] = {"energy_mwhth": d.next_energy_mwhth}
			for key in ["charge_mwth", "discharge_mwth", "self_discharge_mwhth", "storage_conversion_loss_mwth"]: t[key] += d[key]
			t.energy_mwhth += d.next_energy_mwhth
			t.store_auxiliary_electric_mw += d.auxiliary_electric_mw
			t.auxiliary_electric_mw += d.auxiliary_electric_mw
			before += float(n.state.energy_mwhth)
			capacity += float(p.capacity_mwhth)
	t.rankine_salt_input_mwth = float(r.get("rankine", {}).get("salt_input_mwth", 0.0))
	t.soc = t.energy_mwhth/capacity if capacity > 0.0 else 0.0
	t.storage_loss_mwth = t.storage_conversion_loss_mwth+(t.self_discharge_mwhth/float(r.dt_h) if float(r.dt_h)>0.0 else 0.0)
	t.balance_error_mwth = t.useful_mwth+t.discharge_mwth-t.charge_mwth-t.rankine_salt_input_mwth
	t.energy_balance_error_mwhth = before-t.energy_mwhth-t.self_discharge_mwhth+(t.useful_mwth-t.rankine_salt_input_mwth-t.storage_conversion_loss_mwth)*float(r.dt_h)
	r.tower = t
	for line in r.lines:
		if line.valid and line.carrier == "heat_salt":
			line.active = line.sent_mwth > EPS
			line.utilization = line.sent_mwth/line.capacity_mwth if line.capacity_mwth>0.0 else 0.0

static func _near(errors: Array[String], actual: Variant, expected: float, label: String) -> void:
	if not _number(actual) or absf(float(actual)-expected)>2e-6+2e-7*absf(expected): errors.append("Independent audit: tower "+label)

static func audit(prepared: Dictionary, errors: Array[String]) -> Dictionary:
	var r: Dictionary = prepared.report
	var total: Dictionary = empty()
	if not r.has("tower"): return total
	var ins: Dictionary = {}
	var outs: Dictionary = {}
	var ac: Dictionary = {}
	for id in prepared.nodes:
		ins[id] = 0.0
		outs[id] = 0.0
		ac[id] = 0.0
	for line in r.lines:
		if not line.valid: continue
		if line.carrier == "heat_salt":
			if line.flow_from != line.from or line.flow_to != line.to: errors.append("Independent audit: reversed salt flow")
			ins[str(line.to)] += float(line.received_mwth)
			outs[str(line.from)] += float(line.sent_mwth)
		elif line.carrier == "electricity_ac" and ac.has(str(line.flow_to)): ac[str(line.flow_to)] += float(line.received_mw)
	var before: float = 0.0
	var capacity: float = 0.0
	for id in prepared.nodes:
		var n: Dictionary = prepared.nodes[id]
		if not n.valid or not n.kind in KINDS: continue
		var d: Dictionary = r.devices[id]
		var p: Dictionary = n.params
		var hi: float = ins[id]
		var ho: float = outs[id]
		var ei: float = ac[id]
		if n.kind == "salt_steam_generator":
			total.rankine_salt_input_mwth += hi
			continue # SG steam and auxiliary equations belong to Rankine.audit.
		_near(errors, d.get("input_mwth"), hi, id+" input")
		_near(errors, d.get("output_mwth"), ho, id+" output")
		_near(errors, d.get("auxiliary_electric_mw"), ei, id+" auxiliary")
		_near(errors, d.get("auxiliary_electric_loss_mw"), ei, id+" auxiliary loss")
		total.auxiliary_electric_mw += ei
		if n.kind == "solar_tower_receiver":
			var physics: Dictionary = evaluate(p, prepared.weather)
			if not physics.valid: errors.append("Independent audit: invalid tower physics")
			for key in ["incident_mw", "optical_rejection_mw", "potential_thermal_loss_mw", "thermal_loss_mw", "available_mwth"]:
				_near(errors, d.get(key), float(physics[key]), id+" physics "+key)
				total[key] += physics[key]
			for key in ["dni_wm2", "supply_temp_c", "return_temp_c"]: _near(errors, d.get(key), float(physics[key]), id+" metadata "+key)
			for key in ["area_basis", "irradiance_kind", "fluid"]:
				if d.get(key) != physics[key]: errors.append("Independent audit: tower metadata "+key)
			_near(errors, ei, ho*float(p.auxiliary_electric_ratio), id+" receiver auxiliary ratio")
			_near(errors, d.get("useful_mwth"), ho, id+" useful heat")
			_near(errors, d.get("heat_output_mwth"), ho, id+" heat output")
			_near(errors, d.get("curtailed_mwth"), float(physics.available_mwth)-ho, id+" curtailment")
			if ho > float(physics.available_mwth)+2e-6: errors.append("Independent audit: tower availability exceeded")
			total.useful_mwth += ho
			total.curtailed_mwth += float(physics.available_mwth)-ho
			total.receiver_auxiliary_electric_mw += ei
		else:
			var initial: float = n.state.energy_mwhth
			var limits: Dictionary = Catalog.thermal_storage_limits(p, initial, float(r.dt_s))
			for key in limits: _near(errors, d.get(key), float(limits[key]), id+" physical limit "+key)
			_near(errors, d.get("energy_mwhth"), initial, id+" original inventory")
			_near(errors, d.get("soc_before"), initial/float(p.capacity_mwhth), id+" original soc")
			_near(errors, d.get("capacity_mwhth"), float(p.capacity_mwhth), id+" capacity metadata")
			_near(errors, d.get("storage_balance_error_mwhth"), 0.0, id+" storage residual")
			var decayed: float = initial*exp(-float(p.self_discharge_per_h)*float(r.dt_h))
			var after: float = decayed+(float(p.charge_efficiency)*hi-ho/float(p.discharge_efficiency))*float(r.dt_h)
			var conversion: float = hi*(1.0-float(p.charge_efficiency))+ho*(1.0/float(p.discharge_efficiency)-1.0)
			_near(errors, ei, (hi+ho)*float(p.auxiliary_electric_ratio), id+" store auxiliary ratio")
			for key in ["charge_mwth", "input_mwth"]: _near(errors, d.get(key), hi, id+" "+key)
			for key in ["discharge_mwth", "output_mwth"]: _near(errors, d.get(key), ho, id+" "+key)
			_near(errors, d.get("self_discharge_mwhth"), initial-decayed, id+" standing loss")
			_near(errors, d.get("storage_conversion_loss_mwth"), conversion, id+" conversion loss")
			_near(errors, d.get("next_energy_mwhth"), after, id+" inventory")
			_near(errors, r.next_states.get(id, {}).get("energy_mwhth"), after, id+" next inventory")
			_near(errors, d.get("soc"), after/float(p.capacity_mwhth), id+" soc")
			if after < -2e-6 or after > float(p.capacity_mwhth)+2e-6 or hi > float(p.charge_mwth)+2e-6 or ho > float(p.discharge_mwth)+2e-6 or (hi>EPS and ho>EPS) or (r.dt_h == 0.0 and (hi>EPS or ho>EPS)): errors.append("Independent audit: salt inventory/rate/mode")
			var mode: String = "charge" if hi>EPS else ("discharge" if ho>EPS else "idle")
			if d.get("mode") != mode: errors.append("Independent audit: salt mode label")
			total.charge_mwth += hi
			total.discharge_mwth += ho
			total.energy_mwhth += after
			total.self_discharge_mwhth += initial-decayed
			total.storage_conversion_loss_mwth += conversion
			total.store_auxiliary_electric_mw += ei
			before += initial
			capacity += float(p.capacity_mwhth)
	total.soc = total.energy_mwhth/capacity if capacity>0.0 else 0.0
	total.storage_loss_mwth = total.storage_conversion_loss_mwth+(total.self_discharge_mwhth/float(r.dt_h) if float(r.dt_h)>0.0 else 0.0)
	total.balance_error_mwth = total.useful_mwth+total.discharge_mwth-total.charge_mwth-total.rankine_salt_input_mwth
	total.energy_balance_error_mwhth = before-total.energy_mwhth-total.self_discharge_mwhth+(total.useful_mwth-total.rankine_salt_input_mwth-total.storage_conversion_loss_mwth)*float(r.dt_h)
	for key in total: _near(errors, r.tower.get(key), float(total[key]), "aggregate "+key)
	_near(errors, total.balance_error_mwth, 0.0, "salt power conservation")
	_near(errors, total.energy_balance_error_mwhth, 0.0, "salt energy conservation")
	_near(errors, r.get("cross_carrier_balance_error_mw"), 0.0, "cross-carrier residual")
	return total
