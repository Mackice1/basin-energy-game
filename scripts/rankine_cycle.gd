extends RefCounted
## Fixed-state closed teaching Rankine loop, with isolated oil or molten-salt SG.
## The salt SG reuses 1 MPa / 280 C states, not a high-temperature optimized cycle.
## No transient startup, inventory,
## pressure solve, minimum load or same-interval self-powered auxiliaries.
const KINDS := ["salt_steam_generator", "steam_generator", "steam_turbine", "steam_condenser", "feedwater_pump"]
const H1: float = 191.81
const H2: float = 193.238810
const H3: float = 3008.6
const H4: float = 2426.78753
const PROFILE: String = "rankine_stage1_v1"
const EPS: float = 1.0e-9
const POWER_FIELDS := ["oil_input_mwth", "steam_heat_mwth", "gross_electric_mw", "condenser_rejection_mwth", "generator_loss_mw", "pump_hydraulic_mw", "pump_motor_loss_mw", "steam_generator_loss_mwth", "sg_auxiliary_electric_mw", "cooling_auxiliary_electric_mw", "pump_electric_mw", "auxiliary_electric_mw", "net_electric_mw"]
const AUX_KINDS := ["electric_boiler", "fuel_boiler", "solar_thermal", "parabolic_trough", "oil_water_exchanger", "steam_generator", "steam_condenser", "feedwater_pump", "solar_tower_receiver", "molten_salt_store", "salt_steam_generator"]

static func empty() -> Dictionary:
	var r := {"mass_flow_kg_s": 0.0, "balance_error_mw": 0.0}
	for key in POWER_FIELDS: r[key] = 0.0
	return r

static func initial_energy(include_salt: bool = false) -> Dictionary:
	var r := {"circulated_mass_kg": 0.0}
	if include_salt: r.salt_input_mwhth = 0.0
	for key in POWER_FIELDS: r[key.replace("_mw", "_mwh")] = 0.0
	return r

static func _number(v: Variant) -> bool:
	return (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and is_finite(float(v))

static func validate_energy(v: Variant) -> String:
	if not v is Dictionary: return "rankine_energy must be an object"
	var expected := initial_energy(v.has("salt_input_mwhth"))
	if v.size() != expected.size(): return "rankine_energy has unexpected fields"
	for key in expected:
		if not _number(v.get(key)) or (key != "net_electric_mwh" and float(v[key]) < 0.0): return "Invalid Rankine energy: " + key
	var tol: float = 2e-6 + 2e-7 * maxf(1.0, (float(v.oil_input_mwhth) + float(v.get("salt_input_mwhth", 0.0))))
	var mass_mwh: float = float(v.circulated_mass_kg) / 3.6e6
	var fixed := {"steam_heat_mwhth": (H3-H2)*mass_mwh, "gross_electric_mwh": (H3-H4)*0.95*mass_mwh, "condenser_rejection_mwhth": (H4-H1)*mass_mwh, "pump_hydraulic_mwh": (H2-H1)*mass_mwh, "generator_loss_mwh": (H3-H4)*0.05*mass_mwh, "pump_electric_mwh": (H2-H1)/0.90*mass_mwh, "pump_motor_loss_mwh": (H2-H1)*(1.0/0.90-1.0)*mass_mwh, "oil_input_mwhth": (H3-H2)/0.97*mass_mwh, "steam_generator_loss_mwhth": (H3-H2)*(1.0/0.97-1.0)*mass_mwh}
	for key in fixed:
		if absf((float(v[key]) + (float(v.get("salt_input_mwhth", 0.0)) if key == "oil_input_mwhth" else 0.0))-float(fixed[key])) > tol: return "Rankine cumulative fixed-enthalpy mismatch: " + key
	for item in [["sg_auxiliary_electric_mwh", "oil_input_mwhth"], ["cooling_auxiliary_electric_mwh", "condenser_rejection_mwhth"]]:
		if float(v[item[0]]) < (float(v[item[1]]) + (float(v.get("salt_input_mwhth", 0.0)) if item[1] == "oil_input_mwhth" else 0.0))*0.001-tol or float(v[item[0]]) > (float(v[item[1]]) + (float(v.get("salt_input_mwhth", 0.0)) if item[1] == "oil_input_mwhth" else 0.0))*0.2+tol: return "Rankine cumulative auxiliary ratio mismatch"
	if absf(float(v.net_electric_mwh) - float(v.gross_electric_mwh) + float(v.auxiliary_electric_mwh)) > tol: return "Rankine cumulative net electricity mismatch"
	if absf(float(v.auxiliary_electric_mwh) - float(v.sg_auxiliary_electric_mwh) - float(v.cooling_auxiliary_electric_mwh) - float(v.pump_electric_mwh)) > tol: return "Rankine cumulative auxiliary mismatch"
	if absf((float(v.oil_input_mwhth) + float(v.get("salt_input_mwhth", 0.0))) + float(v.pump_electric_mwh) - float(v.gross_electric_mwh) - float(v.condenser_rejection_mwhth) - float(v.generator_loss_mwh) - float(v.steam_generator_loss_mwhth) - float(v.pump_motor_loss_mwh)) > tol: return "Rankine cumulative first law mismatch"
	return ""

static func enthalpy(grade: String) -> float:
	return float({"rankine_live_v1": H3, "rankine_exhaust_v1": H4, "rankine_condensate_v1": H1, "rankine_feedwater_v1": H2}.get(grade, 0.0))

static func condenser_available(p: Dictionary, weather: Dictionary) -> float:
	if not _number(weather.get("air_temp_c")): return 0.0
	var air: float = float(weather.air_temp_c)
	if air >= float(p.condensing_temp_c) - float(p.min_approach_k): return 0.0
	return float(p.capacity_mwth) * clampf((float(p.condensing_temp_c) - air) / (float(p.condensing_temp_c) - float(p.design_ambient_c)), 0.0, 1.0)

static func initialize_node(id: String, kind: String, p: Dictionary, d: Dictionary, resources: Dictionary) -> void:
	d.merge({"model_profile": "tower_stage1_v1" if kind == "salt_steam_generator" else PROFILE, "model_profile_version": 1, "mass_flow_kg_s": 0.0, "input_mwth": 0.0, "output_mwth": 0.0, "loss_mwth": 0.0, "heat_connected": false, "electric_connected": false, "cycle_complete": false, "status_reason": "闭式水汽回路未接完整"}, true)
	match kind:
		"steam_generator", "salt_steam_generator":
			d.merge({("salt_input_mwth" if kind == "salt_steam_generator" else "oil_input_mwth"): 0.0, "steam_heat_mwth": 0.0, "auxiliary_electric_mw": 0.0, "auxiliary_electric_loss_mw": 0.0})
			resources["rankine_sg:" + id] = float(p.capacity_mwth)
			resources["rankine_aux:" + id] = float(p.capacity_mwth) * float(p.auxiliary_electric_ratio)
		"steam_turbine":
			d.merge({"gross_electric_mw": 0.0, "generator_loss_mw": 0.0})
			resources["rankine_mass:" + id] = float(p.mass_flow_capacity_kg_s)
			resources["source:" + id] = float(p.mass_flow_capacity_kg_s) * (H3-H4) * float(p.generator_efficiency) / 1000.0
		"steam_condenser":
			d.merge({"condenser_rejection_mwth": 0.0, "available_rejection_mwth": 0.0, "auxiliary_electric_mw": 0.0, "auxiliary_electric_loss_mw": 0.0})
			resources["rankine_cond:" + id] = 0.0
			resources["rankine_aux:" + id] = float(p.capacity_mwth) * float(p.auxiliary_electric_ratio)
		"feedwater_pump":
			d.merge({"pump_electric_mw": 0.0, "pump_hydraulic_mw": 0.0, "pump_motor_loss_mw": 0.0, "auxiliary_electric_mw": 0.0, "auxiliary_electric_loss_mw": 0.0})
			resources["rankine_mass:" + id] = float(p.mass_flow_capacity_kg_s)
			resources["rankine_aux:" + id] = float(p.mass_flow_capacity_kg_s) * (H2-H1) / 1000.0 / float(p.motor_efficiency)

static func _outgoing(lines: Array, id: int, port: String) -> Dictionary:
	for line in lines:
		if line.valid and line.carrier == "water_steam" and line.from == id and line.from_port == port: return line
	return {}

static func prepare(prepared: Dictionary) -> void:
	var r: Dictionary = prepared.report
	var nodes: Dictionary = prepared.nodes
	var present: bool = false
	for id in nodes:
		if nodes[id].kind in KINDS: present = true
	if not present: return
	r.rankine = empty()
	r.rankine_dispatch_policy = "stable-ID external auxiliary split; bounded 40-step mass feasibility search; not forecast optimal"
	var has_oil_sg: bool = false
	for node in nodes.values():
		if node.kind == "steam_generator": has_oil_sg = true
	if has_oil_sg and not r.has("high_temp"): r.high_temp = preload("res://scripts/high_temp_thermal.gd").empty()
	if r.has("high_temp"): r.high_temp.rankine_oil_input_mwth = 0.0
	if r.has("tower"): r.rankine.salt_input_mwth = 0.0
	prepared.rankine_cycles = []
	prepared.rankine_routes = []
	prepared.rankine_aux_paths = {}
	for battery in [false,true]:
		for ep in prepared.paths:
			if not ep.source_kind in ["wind","pv","battery"] or (ep.source_kind == "battery") != battery or not ep.sink_kind in AUX_KINDS: continue
			if not prepared.rankine_aux_paths.has(ep.sink_id): prepared.rankine_aux_paths[ep.sink_id] = []
			prepared.rankine_aux_paths[ep.sink_id].append(ep)
	var ids: Array = nodes.keys()
	ids.sort_custom(func(a, b): return int(a) < int(b))
	for id in ids:
		if not nodes[id].valid: continue
		if nodes[id].kind == "steam_condenser":
			if not _number(prepared.weather.get("air_temp_c")) or absf(float(prepared.weather.get("air_temp_c", 0.0))) > 100.0:
				r.errors.append("Rankine dry cooling requires explicit finite air_temp_c in [-100,100]")
			var cap: float = condenser_available(nodes[id].params, prepared.weather)
			r.devices[id].available_rejection_mwth = cap
			prepared.resources["rankine_cond:" + id] = cap
		if not nodes[id].kind in ["steam_generator", "salt_steam_generator"]: continue
		var e0 := _outgoing(r.lines, int(id), "steam_out")
		if e0.is_empty(): continue
		var e1 := _outgoing(r.lines, int(e0.to), "exhaust_out")
		if e1.is_empty(): continue
		var e2 := _outgoing(r.lines, int(e1.to), "condensate_out")
		if e2.is_empty(): continue
		var e3 := _outgoing(r.lines, int(e2.to), "feed_out")
		if e3.is_empty() or int(e3.to) != int(id): continue
		var cycle := {"sg": id, "turbine": str(e0.to), "condenser": str(e1.to), "pump": str(e2.to), "edges": [int(e0.index), int(e1.index), int(e2.index), int(e3.index)]}
		prepared.rankine_cycles.append(cycle)
		for key in ["sg", "turbine", "condenser", "pump"]:
			r.devices[cycle[key]].cycle_complete = true
			r.devices[cycle[key]].status_reason = "待热源、外部辅机电力和发电受端"
		for line in r.lines:
			if not line.valid or line.carrier != ("heat_salt" if nodes[id].kind == "salt_steam_generator" else "heat_oil") or str(line.to) != id: continue
			var source: String = str(line.from)
			if not nodes[source].kind in (["solar_tower_receiver", "molten_salt_store"] if nodes[id].kind == "salt_steam_generator" else ["parabolic_trough", "high_temp_store"]): continue
			var route: Dictionary = cycle.duplicate(true)
			route.source = source
			route.oil_edge = int(line.index)
			prepared.rankine_routes.append(route)
	for line in r.lines:
		if line.valid and line.carrier == "water_steam":
			r.devices[str(line.from)].heat_connected = true
			r.devices[str(line.to)].heat_connected = true

static func _coefficients(route: Dictionary, prepared: Dictionary) -> Dictionary:
	var nodes: Dictionary = prepared.nodes
	var oil: float = (H3-H2) / 1000.0 / float(nodes[route.sg].params.transfer_efficiency)
	var c := {"heat_line:" + str(route.oil_edge): oil, "rankine_sg:" + route.sg: oil, "rankine_mass:" + route.turbine: 1.0, "rankine_mass:" + route.pump: 1.0, "rankine_cond:" + route.condenser: (H4-H1)/1000.0}
	c[("solar:" if nodes[route.source].kind in ["parabolic_trough", "solar_tower_receiver"] else "heat_discharge:") + route.source] = oil
	for i in route.edges: c["mass_line:" + str(i)] = 1.0
	return c

## All auxiliary and output AC paths are included in the same reservation.
## A turbine can never be selected as an auxiliary source, including another loop.
static func serve_sink(prepared: Dictionary, sink_id: String, allocate: Callable) -> void:
	if not prepared.has("rankine_routes") or float(prepared.report.dt_h) <= 0.0: return
	var r: Dictionary = prepared.report
	if sink_id != "-1" and prepared.nodes[sink_id].kind == "battery" and r.devices[sink_id].mode == "discharge": return
	for route in prepared.rankine_routes:
		if prepared.nodes[route.source].kind in ["high_temp_store", "molten_salt_store"] and r.devices[route.source].mode == "charge": continue
		var oil: float = (H3-H2)/1000.0/float(prepared.nodes[route.sg].params.transfer_efficiency)
		var gross: float = (H3-H4)/1000.0*float(prepared.nodes[route.turbine].params.generator_efficiency)
		var consumers := [{"id": route.sg, "factor": oil*float(prepared.nodes[route.sg].params.auxiliary_electric_ratio)}, {"id": route.condenser, "factor": (H4-H1)/1000.0*float(prepared.nodes[route.condenser].params.auxiliary_electric_ratio)}, {"id": route.pump, "factor": (H2-H1)/1000.0/float(prepared.nodes[route.pump].params.motor_efficiency)}]
		if prepared.nodes[route.source].kind in ["parabolic_trough", "solar_tower_receiver", "molten_salt_store"]: consumers.push_front({"id": route.source, "factor": oil*float(prepared.nodes[route.source].params.auxiliary_electric_ratio)})
		for output in prepared.paths:
			if output.source_id != route.turbine or output.sink_id != sink_id: continue
			var base := _coefficients(route, prepared)
			var combined: Dictionary = base.duplicate()
			for key in output.coefficients: combined[key] = float(combined.get(key, 0.0)) + gross*float(output.coefficients[key])
			var limit: float = INF
			for key in combined:
				if float(combined[key]) > 0.0: limit = minf(limit, maxf(0.0,float(prepared.resources[key]))/float(combined[key]))
			if not is_finite(limit) or limit <= EPS: continue
			var flow: float = limit
			var plan := _auxiliary_plan(prepared, sink_id, combined, consumers, flow)
			if not plan.ok:
				var low: float = 0.0
				var high: float = limit
				# Fixed work bound, independent of the product of source choices.
				# This is a stable-ID greedy feasibility search, not a joint optimum.
				for iteration in 40:
					var middle: float = (low+high)*0.5
					var trial := _auxiliary_plan(prepared, sink_id, combined, consumers, middle)
					if trial.ok: low = middle
					else: high = middle
				flow = low
				plan = _auxiliary_plan(prepared, sink_id, combined, consumers, flow)
			if not plan.ok or flow <= EPS: continue
			for allocation in plan.allocations: allocate.call(allocation.path, prepared.resources, r, float(allocation.sent))
			for key in base: prepared.resources[key] = maxf(0.0,float(prepared.resources[key])-flow*float(base[key]))
			_record(route, flow, prepared)
			allocate.call(output, prepared.resources, r, flow*gross)

## Plan on copied shared rows. The same auxiliary may use multiple external
## sources. No partial electricity or heat is committed on a failed reservation.
static func _auxiliary_plan(prepared: Dictionary, sink_id: String, combined: Dictionary, consumers: Array, flow: float) -> Dictionary:
	var resources: Dictionary = prepared.resources.duplicate()
	for key in combined:
		resources[key] = float(resources[key])-flow*float(combined[key])
		if float(resources[key]) < -1e-12: return {"ok":false,"allocations":[]}
	var allocations: Array = []
	for consumer in consumers:
		var remaining: float = flow*float(consumer.factor)
		for ep in prepared.rankine_aux_paths.get(consumer.id, []):
			if remaining <= 1e-14: break
			if ep.source_kind == "battery" and (prepared.report.devices[ep.source_id].mode == "charge" or ep.source_id == sink_id): continue
			var sent: float = remaining/float(ep.received)
			for key in ep.coefficients:
				if float(ep.coefficients[key]) > 0.0: sent = minf(sent,maxf(0.0,float(resources[key]))/float(ep.coefficients[key]))
			if sent <= 0.0: continue
			for key in ep.coefficients: resources[key] = maxf(0.0,float(resources[key])-sent*float(ep.coefficients[key]))
			allocations.append({"path":ep,"sent":sent})
			remaining -= sent*float(ep.received)

		if remaining > 1e-14: return {"ok":false,"allocations":[]}
	return {"ok":true,"allocations":allocations}

static func _record(route: Dictionary, m: float, prepared: Dictionary) -> void:
	var r: Dictionary = prepared.report
	var nodes: Dictionary = prepared.nodes
	var q: float = m*(H3-H2)/1000.0/float(nodes[route.sg].params.transfer_efficiency)
	var source: Dictionary = r.devices[route.source]
	source.output_mwth += q
	if nodes[route.source].kind in ["high_temp_store", "molten_salt_store"]:
		source.discharge_mwth += q
		source.mode = "discharge"
	else: source.heat_output_mwth += q
	var line: Dictionary = r.lines[route.oil_edge]
	line.sent_mwth += q
	line.received_mwth += q
	line.signed_mwth = line.sent_mwth
	line.direction = 1
	for id in [route.sg, route.turbine, route.condenser, route.pump]: r.devices[id].mass_flow_kg_s += m
	for i in route.edges:
		var pipe: Dictionary = r.lines[i]
		pipe.sent_kg_s += m
		pipe.received_kg_s += m
		pipe.signed_kg_s = pipe.sent_kg_s
		pipe.direction = 1
		pipe.enthalpy_flow_mw = pipe.sent_kg_s * enthalpy(pipe.grade_id) / 1000.0
	var sg: Dictionary = r.devices[route.sg]
	sg["salt_input_mwth" if nodes[route.sg].kind == "salt_steam_generator" else "oil_input_mwth"] += q
	sg.input_mwth += q
	sg.steam_heat_mwth += m*(H3-H2)/1000.0
	sg.loss_mwth += q-m*(H3-H2)/1000.0
	var tg: Dictionary = r.devices[route.turbine]
	var gross: float = m*(H3-H4)/1000.0*float(nodes[route.turbine].params.generator_efficiency)
	tg.mw += gross
	tg.generated_mw += gross
	tg.gross_electric_mw += gross
	tg.generator_loss_mw += m*(H3-H4)/1000.0-gross
	r.generated_mw += gross
	r.devices[route.condenser].condenser_rejection_mwth += m*(H4-H1)/1000.0
	var pump: Dictionary = r.devices[route.pump]
	pump.pump_hydraulic_mw += m*(H2-H1)/1000.0
	pump.pump_electric_mw += m*(H2-H1)/1000.0/float(nodes[route.pump].params.motor_efficiency)
	pump.pump_motor_loss_mw = pump.pump_electric_mw-pump.pump_hydraulic_mw

static func finish(prepared: Dictionary) -> void:
	if not prepared.report.has("rankine"): return
	var r: Dictionary = prepared.report
	var total: Dictionary = empty()
	if r.has("tower"): total.salt_input_mwth = 0.0
	for id in prepared.nodes:
		var n: Dictionary = prepared.nodes[id]
		if not n.valid or not n.kind in KINDS: continue
		var d: Dictionary = r.devices[id]
		if d.mass_flow_kg_s > EPS: d.status_reason = "闭式朗肯循环运行"
		if n.kind == "steam_condenser" and d.available_rejection_mwth <= EPS: d.status_reason = "环境温度过高，干冷能力为零"
		if n.kind != "steam_turbine": d.auxiliary_electric_loss_mw = d.pump_motor_loss_mw if n.kind == "feedwater_pump" else d.auxiliary_electric_mw
		match n.kind:
			"steam_generator", "salt_steam_generator":
				total["salt_input_mwth" if n.kind == "salt_steam_generator" else "oil_input_mwth"] += d["salt_input_mwth" if n.kind == "salt_steam_generator" else "oil_input_mwth"]
				total.steam_heat_mwth += d.steam_heat_mwth
				total.steam_generator_loss_mwth += d.loss_mwth
				total.sg_auxiliary_electric_mw += d.auxiliary_electric_mw
				d.utilization = d.input_mwth / float(n.params.capacity_mwth)
			"steam_turbine":
				total.mass_flow_kg_s += d.mass_flow_kg_s
				total.gross_electric_mw += d.gross_electric_mw
				total.generator_loss_mw += d.generator_loss_mw
				d.utilization = d.mass_flow_kg_s / float(n.params.mass_flow_capacity_kg_s)
			"steam_condenser":
				total.condenser_rejection_mwth += d.condenser_rejection_mwth
				total.cooling_auxiliary_electric_mw += d.auxiliary_electric_mw
				d.utilization = d.condenser_rejection_mwth / d.available_rejection_mwth if d.available_rejection_mwth > EPS else 0.0
			"feedwater_pump":
				for key in ["pump_electric_mw", "pump_hydraulic_mw", "pump_motor_loss_mw"]: total[key] += d[key]
				d.utilization = d.mass_flow_kg_s / float(n.params.mass_flow_capacity_kg_s)
	total.auxiliary_electric_mw = total.sg_auxiliary_electric_mw + total.cooling_auxiliary_electric_mw + total.pump_electric_mw
	total.net_electric_mw = total.gross_electric_mw - total.auxiliary_electric_mw
	total.balance_error_mw = total.oil_input_mwth + float(total.get("salt_input_mwth", 0.0)) + total.pump_electric_mw - total.gross_electric_mw - total.condenser_rejection_mwth - total.generator_loss_mw - total.steam_generator_loss_mwth - total.pump_motor_loss_mw
	r.rankine = total
	if r.has("high_temp"): r.high_temp.rankine_oil_input_mwth = total.oil_input_mwth
	for line in r.lines:
		if line.valid and line.carrier == "water_steam":
			line.active = line.sent_kg_s > EPS
			line.utilization = line.sent_kg_s / line.mass_flow_capacity_kg_s if line.mass_flow_capacity_kg_s > EPS else 0.0

static func _near(errors: Array[String], value: Variant, expected: float, label: String) -> void:
	if not _number(value) or absf(float(value)-expected) > 2e-6+2e-7*absf(expected): errors.append("Independent audit: Rankine " + label)

## Reconstruct from raw topology, flows and original fixed physical parameters.
static func audit(prepared: Dictionary, errors: Array[String]) -> Dictionary:
	var r: Dictionary = prepared.report
	if not r.has("rankine"): return empty()
	var totals := empty()
	if r.has("tower"): totals.salt_input_mwth = 0.0
	var ins := {}
	var outs := {}
	var electrical := {}
	var electric_out := {}
	var oil := {}
	var salt := {}
	var external_station := {}
	var auxiliary_station := {}
	for id in prepared.nodes:
		ins[id] = 0.0
		outs[id] = 0.0
		electrical[id] = 0.0
		electric_out[id] = 0.0
		oil[id] = 0.0
		salt[id] = 0.0
	for line in r.lines:
		if not line.valid: continue
		var a: String = str(line.flow_from)
		var b: String = str(line.flow_to)
		if line.carrier == "water_steam":
			var raw: Dictionary = prepared.raw_links[int(line.index)]
			for key in ["from", "to", "from_port", "to_port", "carrier", "unit", "grade_id"]:
				if line.get(key) != raw.get(key): errors.append("Independent audit: Rankine changed mass edge metadata " + key)
			if line.flow_from != raw.from or line.flow_to != raw.to:
				errors.append("Independent audit: Rankine reversed mass edge")
				continue
			_near(errors, line.get("mass_flow_capacity_kg_s"), float(raw.mass_flow_capacity_kg_s), "mass edge capacity metadata")
			_near(errors, line.get("loss_fraction"), 0.0, "mass edge loss metadata")
			if not _number(line.get("sent_kg_s")) or not _number(line.get("received_kg_s")): errors.append("Independent audit: Rankine nonfinite mass flow"); continue
			var m: float = float(line.sent_kg_s)
			if m < -2e-6 or m > float(raw.mass_flow_capacity_kg_s)+2e-6: errors.append("Independent audit: Rankine mass pipe limit")
			_near(errors, line.received_kg_s, m, "mass continuity")
			_near(errors, line.get("loss_kg_s"), 0.0, "mass loss")
			_near(errors, line.get("enthalpy_kj_kg"), enthalpy(raw.grade_id), "fixed stream enthalpy")
			_near(errors, line.get("enthalpy_flow_mw"), m*enthalpy(raw.grade_id)/1000.0, "stream enthalpy transport")
			outs[a] += m
			ins[b] += float(line.received_kg_s)
		elif line.carrier == "heat_oil": oil[b] += float(line.received_mwth)
		elif line.carrier == "heat_salt": salt[b] += float(line.received_mwth)
		elif line.carrier == "electricity_ac":
			var raw: Dictionary = prepared.raw_links[int(line.index)]
			var forward: bool = int(line.flow_from) == int(raw.from) and int(line.flow_to) == int(raw.to)
			var battery_edge: bool = prepared.nodes[str(int(raw.from))].kind == "battery" or (int(raw.to) != -1 and prepared.nodes[str(int(raw.to))].kind == "battery")
			var reverse: bool = battery_edge and int(line.flow_from) == int(raw.to) and int(line.flow_to) == int(raw.from)
			if not forward and not reverse: errors.append("Independent audit: Rankine changed AC route provenance")
			if electric_out.has(a): electric_out[a] += float(line.sent_mw)
			if electrical.has(b): electrical[b] += float(line.received_mw)
			if prepared.nodes.has(a) and prepared.nodes[a].kind in ["wind", "pv", "battery"] and prepared.nodes.has(b) and prepared.nodes[b].kind == "station": external_station[b] = float(external_station.get(b, 0.0)) + float(line.received_mw)
			if prepared.nodes.has(a) and prepared.nodes[a].kind == "station" and prepared.nodes.has(b) and prepared.nodes[b].kind in AUX_KINDS: auxiliary_station[a] = float(auxiliary_station.get(a, 0.0)) + float(line.sent_mw)
	for station in auxiliary_station:
		if float(auxiliary_station[station]) > float(external_station.get(station, 0.0))*(1.0-float(prepared.nodes[station].params.loss_fraction))+2e-6: errors.append("Independent audit: Rankine external-only auxiliary provenance")
	var complete := {}
	for cycle in prepared.get("rankine_cycles", []):
		for key in ["sg", "turbine", "condenser", "pump"]: complete[cycle[key]] = true
	for id in prepared.nodes:
		var n: Dictionary = prepared.nodes[id]
		if not n.valid or not n.kind in KINDS: continue
		var d: Dictionary = r.devices[id]
		var m: float = float(outs[id])
		var e: float = float(electrical[id])
		_near(errors, ins[id], m, id + " closed mass balance")
		_near(errors, d.get("mass_flow_kg_s"), m, id + " reported mass")
		if (not complete.has(id) or float(r.dt_h) == 0.0) and m > EPS: errors.append("Independent audit: Rankine incomplete/paused loop activity")
		match n.kind:
			"steam_generator", "salt_steam_generator":
				if n.kind == "salt_steam_generator" and d.has("oil_input_mwth"): errors.append("Independent audit: salt SG must not expose an oil input ledger")
				var q: float = m*(H3-H2)/1000.0/float(n.params.transfer_efficiency)
				var steam: float = m*(H3-H2)/1000.0
				_near(errors, salt[id] if n.kind == "salt_steam_generator" else oil[id], q, id + " heat draw")
				_near(errors, oil[id] if n.kind == "salt_steam_generator" else salt[id], 0.0, id + " isolated heat carrier")
				_near(errors, d.get("salt_input_mwth" if n.kind == "salt_steam_generator" else "oil_input_mwth"), q, id + " heat ledger")
				_near(errors, d.get("input_mwth"), q, id + " oil port")
				_near(errors, d.get("steam_heat_mwth"), steam, id + " steam heat")
				_near(errors, d.get("loss_mwth"), q-steam, id + " SG loss")
				_near(errors, e, q*float(n.params.auxiliary_electric_ratio), id + " SG auxiliary")
				if q > float(n.params.capacity_mwth)+2e-6: errors.append("Independent audit: Rankine steam generator capacity")
				totals["salt_input_mwth" if n.kind == "salt_steam_generator" else "oil_input_mwth"] += q
				totals.steam_heat_mwth += steam
				totals.steam_generator_loss_mwth += q-steam
				totals.sg_auxiliary_electric_mw += e
			"steam_turbine":
				var shaft: float = m*(H3-H4)/1000.0
				var gross: float = shaft*float(n.params.generator_efficiency)
				_near(errors, electric_out[id], gross, id + " measured AC terminal output")
				for key in ["mw", "generated_mw", "gross_electric_mw", "output_mw", "sent_mw"]: _near(errors, d.get(key), gross, id + " " + key)
				_near(errors, d.get("generator_loss_mw"), shaft-gross, id + " generator loss")
				if m > float(n.params.mass_flow_capacity_kg_s)+2e-6: errors.append("Independent audit: Rankine turbine mass capacity")
				totals.mass_flow_kg_s += m
				totals.gross_electric_mw += gross
				totals.generator_loss_mw += shaft-gross
			"steam_condenser":
				var q: float = m*(H4-H1)/1000.0
				var cap: float = condenser_available(n.params, prepared.weather)
				_near(errors, d.get("condenser_rejection_mwth"), q, id + " heat rejection")
				_near(errors, d.get("available_rejection_mwth"), cap, id + " dry cooling weather cap")
				_near(errors, e, q*float(n.params.auxiliary_electric_ratio), id + " fan input")
				if q > cap+2e-6: errors.append("Independent audit: Rankine dry cooling capacity")
				totals.condenser_rejection_mwth += q
				totals.cooling_auxiliary_electric_mw += e
			"feedwater_pump":
				var hydraulic: float = m*(H2-H1)/1000.0
				var power: float = hydraulic/float(n.params.motor_efficiency)
				_near(errors, e, power, id + " feedwater pump input")
				_near(errors, d.get("pump_electric_mw"), power, id + " pump electric ledger")
				_near(errors, d.get("pump_hydraulic_mw"), hydraulic, id + " pump enthalpy lift")
				_near(errors, d.get("pump_motor_loss_mw"), power-hydraulic, id + " pump motor loss")
				if m > float(n.params.mass_flow_capacity_kg_s)+2e-6: errors.append("Independent audit: Rankine pump mass capacity")
				totals.pump_electric_mw += power
				totals.pump_hydraulic_mw += hydraulic
				totals.pump_motor_loss_mw += power-hydraulic
		if n.kind != "steam_turbine":
			_near(errors, d.get("auxiliary_electric_mw"), e, id + " auxiliary ledger")
			_near(errors, d.get("auxiliary_electric_loss_mw"), e-float(d.pump_hydraulic_mw) if n.kind == "feedwater_pump" else e, id + " auxiliary dissipation")
	totals.auxiliary_electric_mw = totals.sg_auxiliary_electric_mw+totals.cooling_auxiliary_electric_mw+totals.pump_electric_mw
	totals.net_electric_mw = totals.gross_electric_mw-totals.auxiliary_electric_mw
	totals.balance_error_mw = totals.oil_input_mwth+float(totals.get("salt_input_mwth", 0.0))+totals.pump_electric_mw-totals.gross_electric_mw-totals.condenser_rejection_mwth-totals.generator_loss_mw-totals.steam_generator_loss_mwth-totals.pump_motor_loss_mw
	for key in totals: _near(errors, r.rankine.get(key), float(totals[key]), "aggregate " + key)
	_near(errors, totals.balance_error_mw, 0.0, "first law")
	return totals
