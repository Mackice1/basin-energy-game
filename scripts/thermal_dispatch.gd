extends RefCounted
## Pure fixed-grade DAG heat routing sharing the electric dispatch resource rows.
## Services share electricity by priority/id. Heat uses renewable electric boilers,
## stored heat, optional rate-limited natural gas, then battery electric boilers.
## Heat charging uses renewable electric surplus, then remaining gas with renewable
## auxiliary AC, before electric batteries/export. Auxiliary energy is dissipated.
## Deterministic teaching greedy policy, not GLPK or forecast-optimal dispatch.
const Materials = preload("res://scripts/material_dispatch.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
const FuelSupply = preload("res://scripts/fuel_supply.gd")
const HighTemp = preload("res://scripts/high_temp_thermal.gd")
const Solar = preload("res://scripts/solar_thermal.gd")
const Rankine = preload("res://scripts/rankine_cycle.gd")
const Tower = preload("res://scripts/solar_tower_thermal.gd")
const EPS: float = 1.0e-9
const ABS_TOL: float = 2.0e-6
const REL_TOL: float = 2.0e-7

static func initialize_node(id: String, kind: String, p: Dictionary, state: Dictionary, dt_s: float, d: Dictionary, resources: Dictionary) -> void:
	d.merge({"model_profile": Catalog.model_profile(kind), "model_profile_version": Catalog.THERMAL_PROFILE_VERSION,
		"input_mwth": 0.0, "output_mwth": 0.0, "loss_mwth": 0.0,
		"heat_connected": false, "electric_connected": false})
	match kind:
		"solar_thermal", "parabolic_trough":
			d.merge({"heat_output_mwth": 0.0, "auxiliary_electric_mw": 0.0, "auxiliary_electric_loss_mw": 0.0})
			resources["solar:" + id] = d.available_mwth
			resources["solar_aux:" + id] = d.available_mwth * p.auxiliary_electric_ratio
		"electric_boiler":
			d.merge({"electric_input_mw": 0.0, "heat_output_mwth": 0.0, "conversion_loss_mw": 0.0,
				"rated_electric_mw": p.rated_electric_mw})
			resources["boiler:" + id] = p.rated_electric_mw
		"fuel_boiler":
			d.merge({"fuel_input_mw": 0.0, "fuel_volume_nm3_per_h": 0.0, "fuel_cost_per_h": 0.0,
				"heat_output_mwth": 0.0, "conversion_loss_mw": 0.0, "auxiliary_electric_mw": 0.0,
				"auxiliary_electric_loss_mw": 0.0, "rated_fuel_mw": p.rated_fuel_mw})
			resources["fuel_boiler:" + id] = p.rated_fuel_mw
			resources["fuel_aux:" + id] = p.rated_fuel_mw * p.auxiliary_electric_ratio
		"heat_exchanger", "oil_water_exchanger":
			d.merge({"capacity_mwth": p.capacity_mwth, "hot_input_mwth": 0.0, "warm_output_mwth": 0.0})
			resources["hx:" + id] = p.capacity_mwth
			if kind == "oil_water_exchanger":
				d.merge({"auxiliary_electric_mw": 0.0, "auxiliary_electric_loss_mw": 0.0})
				resources["solar_aux:" + id] = p.capacity_mwth * p.auxiliary_electric_ratio
		"heat_demand":
			d.merge({"demand_mwth": p.demand_mwth, "served_mwth": 0.0, "unserved_mwth": p.demand_mwth, "priority": p.priority})
			resources["heat_demand:" + id] = p.demand_mwth
		"thermal_store", "solid_thermal_store", "high_temp_store":
			var limits: Dictionary = Catalog.thermal_storage_limits(p, state.energy_mwhth, dt_s)
			d.merge(limits)
			d.merge({"mode": "idle", "soc": state.energy_mwhth / p.capacity_mwhth,
				"soc_before": state.energy_mwhth / p.capacity_mwhth, "energy_mwhth": state.energy_mwhth,
				"next_energy_mwhth": limits.energy_after_self_discharge_mwhth, "capacity_mwhth": p.capacity_mwhth,
				"charge_mwth": 0.0, "discharge_mwth": 0.0, "storage_conversion_loss_mwth": 0.0,
				"storage_balance_error_mwhth": 0.0})
			resources["heat_charge:" + id] = limits.charge_limit_mwth
			resources["heat_discharge:" + id] = limits.discharge_limit_mwth

static func prepare(prepared: Dictionary) -> void:
	var r: Dictionary = prepared.report
	var nodes: Dictionary = prepared.nodes
	r.thermal = {"demand_mwth": 0.0, "served_mwth": 0.0, "unserved_mwth": 0.0,
		"boiler_heat_mwth": 0.0, "charge_mwth": 0.0, "discharge_mwth": 0.0,
		"energy_mwhth": 0.0, "soc": 0.0, "network_loss_mwth": 0.0, "exchanger_loss_mwth": 0.0,
		"storage_conversion_loss_mwth": 0.0, "self_discharge_mwhth": 0.0,
		"balance_error_mwth": 0.0, "energy_balance_error_mwhth": 0.0}
	var paths: Array = []
	for line in r.lines:
		if not line.valid:
			continue
		if line.carrier in ["heat_oil", "heat_salt", "water_steam"]: continue
		if line.carrier != Catalog.THERMAL_CARRIER:
			if line.to != -1 and nodes[str(line.to)].kind in ["electric_boiler", "fuel_boiler", "solar_thermal", "parabolic_trough", "oil_water_exchanger", "steam_generator", "steam_condenser", "feedwater_pump", "salt_steam_generator", "solar_tower_receiver", "molten_salt_store"]:
				r.devices[str(line.to)].electric_connected = true
			continue
		r.devices[str(line.from)].heat_connected = true
		r.devices[str(line.to)].heat_connected = true
		var source_id: String = str(line.from)
		var sink_id: String = str(line.to)
		var source_kind: String = nodes[source_id].kind
		if not source_kind in ["electric_boiler", "fuel_boiler", "solar_thermal", "thermal_store", "solid_thermal_store"]:
			continue
		if Catalog.is_primary_thermal_storage(nodes[sink_id].kind):
			paths.append({"source_id": source_id, "source_kind": source_kind, "sink_id": sink_id,
				"sink_kind": nodes[sink_id].kind, "first": line.index, "second": -1, "hx_id": "", "efficiency": 1.0})
		else:
			for outgoing in r.lines:
				if outgoing.valid and outgoing.carrier == Catalog.THERMAL_CARRIER and outgoing.from == line.to:
					paths.append({"source_id": source_id, "source_kind": source_kind, "sink_id": str(outgoing.to),
						"sink_kind": "heat_demand", "first": line.index, "second": outgoing.index,
						"hx_id": sink_id, "efficiency": nodes[sink_id].params.transfer_efficiency})
	HighTemp.add_paths(prepared, paths)
	paths.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.sink_id) != int(b.sink_id): return int(a.sink_id) < int(b.sink_id)
		if int(a.source_id) != int(b.source_id): return int(a.source_id) < int(b.source_id)
		return a.hx_id.to_int() < b.hx_id.to_int())
	prepared.heat_paths = paths
	for id in nodes:
		if nodes[id].valid and Catalog.is_thermal(nodes[id].kind):
			r.thermal_enabled = true
			r.dispatch_policy = "shared_service_priority_renewable_heat_then_storage_then_surplus"
			r.model = "radial electric transport + fixed-grade thermal DAG; not AC or hydraulic flow"
			r.policy_notes = "Services by lower priority then ID; heat uses renewable boiler supply, then stored heat, then battery boiler supply. Renewable surplus charges heat before electric batteries/export. Greedy, not forecast optimal."

	if r.has("fuel"):
		r.dispatch_policy = "shared_service_priority_max_min_fuel_backup_then_storage_charge"
		r.policy_notes = "Services by lower priority then ID. Heat uses renewable electric boilers, stored heat, gas boilers (renewable then battery auxiliary), then battery electric boilers. Within each auxiliary-source phase and service, feasible gas boilers share fuel by max-min equal input, redistributing blocked shares, stable IDs for route ties. Surplus heat charging uses renewable electric boilers, then remaining gas with renewable-only auxiliary, before battery charging/export. Greedy, not cost or forecast optimal."

static func _heat_coefficients(path: Dictionary) -> Dictionary:
	if path.get("high_temp", false): return path.coefficients
	var c: Dictionary = {"heat_line:" + str(path.first): 1.0}
	if path.source_kind == "solar_thermal":
		c["solar:" + path.source_id] = 1.0
	if Catalog.is_primary_thermal_storage(path.source_kind):
		c["heat_discharge:" + path.source_id] = 1.0
	if Catalog.is_primary_thermal_storage(path.sink_kind):
		c["heat_charge:" + path.sink_id] = 1.0
	else:
		c["hx:" + path.hx_id] = 1.0
		c["heat_line:" + str(path.second)] = path.efficiency
		c["heat_demand:" + path.sink_id] = path.efficiency
	return c

static func _heat_limit(path: Dictionary, resources: Dictionary, report: Dictionary) -> float:
	if path.sink_kind in ["thermal_store", "solid_thermal_store", "high_temp_store"] and report.devices[path.sink_id].mode == "discharge":
		return 0.0
	if path.source_kind in ["thermal_store", "solid_thermal_store", "high_temp_store"] and report.devices[path.source_id].mode == "charge":
		return 0.0
	var q: float = INF
	var c: Dictionary = _heat_coefficients(path)
	for key in c:
		q = minf(q, maxf(0.0, float(resources[key])) / float(c[key]))
	return q

static func _record_heat(path: Dictionary, q: float, prepared: Dictionary) -> void:
	if q <= EPS:
		return
	var r: Dictionary = prepared.report
	var c: Dictionary = _heat_coefficients(path)
	for key in c:
		prepared.resources[key] = maxf(0.0, float(prepared.resources[key]) - q * float(c[key]))
	var source: Dictionary = r.devices[path.source_id]
	source.output_mwth += q
	if path.source_kind in ["thermal_store", "solid_thermal_store", "high_temp_store"]:
		source.discharge_mwth += q
		source.mode = "discharge"
	else:
		source.heat_output_mwth += q
	if path.get("high_temp", false):
		_record_high_heat(path, q, prepared)
		return
	_record_heat_line(r.lines[path.first], q)
	var sink: Dictionary = r.devices[path.sink_id]
	var delivered: float = q * float(path.efficiency)
	sink.input_mwth += delivered
	if Catalog.is_primary_thermal_storage(path.sink_kind):
		sink.charge_mwth += delivered
		sink.mode = "charge"
	else:
		var hx: Dictionary = r.devices[path.hx_id]
		hx.input_mwth += q
		hx.output_mwth += delivered
		hx.hot_input_mwth += q
		hx.warm_output_mwth += delivered
		hx.loss_mwth += q - delivered
		sink.served_mwth += delivered
		_record_heat_line(r.lines[path.second], delivered)

static func _record_high_heat(path: Dictionary, q: float, prepared: Dictionary) -> void:
	var r: Dictionary = prepared.report
	var flow: float = q
	for i in path.edges.size():
		_record_heat_line(r.lines[path.edges[i]], flow)
		if i < path.exchangers.size():
			var id: String = path.exchangers[i]
			var hx: Dictionary = r.devices[id]
			var out: float = flow * float(prepared.nodes[id].params.transfer_efficiency)
			hx.input_mwth += flow
			hx.hot_input_mwth += flow
			hx.output_mwth += out
			hx.warm_output_mwth += out
			hx.loss_mwth += flow - out
			flow = out
	var sink: Dictionary = r.devices[path.sink_id]
	sink.input_mwth += flow
	if path.sink_kind == "high_temp_store":
		sink.charge_mwth += flow
		sink.mode = "charge"
	else:
		sink.served_mwth += flow

static func _record_heat_line(line: Dictionary, q: float) -> void:
	line.sent_mwth += q
	line.received_mwth += q # Stage one explicitly enforces loss_fraction=0.
	line.signed_mwth = line.sent_mwth
	line.direction = 1

static func serve_stored_heat(prepared: Dictionary, demand_id: String) -> void:
	for path in prepared.heat_paths:
		if path.sink_id == demand_id and Catalog.is_primary_thermal_storage(path.source_kind):
			_record_heat(path, _heat_limit(path, prepared.resources, prepared.report), prepared)

static func _supply_boiler(path: Dictionary, prepared: Dictionary, electric_allocate: Callable, allow_battery: bool, battery_only: bool = false) -> void:
	for battery in [false, true]:
		if battery_only and not battery:
			continue
		if battery and not allow_battery:
			continue
		for ep in prepared.paths:
			if ep.sink_id != path.source_id or (Catalog.is_electric_storage(ep.source_kind)) != battery:
				continue
			var q: float = _heat_limit(path, prepared.resources, prepared.report)
			if q <= EPS:
				return
			var factor: float = float(ep.received) * float(prepared.nodes[path.source_id].params.thermal_efficiency)
			var sent: float = electric_allocate.call(ep, prepared.resources, prepared.report, q / factor)
			_record_heat(path, sent * factor, prepared)

static func serve_boiler_heat(prepared: Dictionary, demand_id: String, electric_allocate: Callable, battery_only: bool = false) -> void:
	for path in prepared.heat_paths:
		if path.sink_id == demand_id and path.source_kind == "electric_boiler":
			_supply_boiler(path, prepared, electric_allocate, battery_only, battery_only)

## Collect only accepted useful heat. Pump energy is proportional to actual
## collection; curtailment is uncaptured potential, not a stagnation safety model.
static func _supply_solar(path: Dictionary, prepared: Dictionary, electric_allocate: Callable, allow_battery: bool) -> void:
	for battery in [false, true]:
		if battery and not allow_battery: continue
		for ep in prepared.paths:
			if ep.sink_id != path.source_id or (Catalog.is_electric_storage(ep.source_kind)) != battery: continue
			var q: float = _heat_limit(path, prepared.resources, prepared.report)
			if q <= EPS: return
			var ratio: float = float(prepared.nodes[path.source_id].params.auxiliary_electric_ratio)
			var sent: float = electric_allocate.call(ep, prepared.resources, prepared.report, q * ratio / float(ep.received))
			_record_heat(path, sent * float(ep.received) / ratio, prepared)

static func serve_solar_heat(prepared: Dictionary, demand_id: String, electric_allocate: Callable) -> void:
	for path in prepared.heat_paths:
		if path.sink_id == demand_id and path.get("high_temp", false):
			HighTemp.supply(path, prepared, electric_allocate, _record_heat, true)
	for path in prepared.heat_paths:
		if path.sink_id == demand_id and path.source_kind == "solar_thermal":
			_supply_solar(path, prepared, electric_allocate, true)

static func charge_solar_storage(prepared: Dictionary, electric_allocate: Callable) -> void:
	for path in prepared.heat_paths:
		if path.sink_kind == "high_temp_store":
			HighTemp.supply(path, prepared, electric_allocate, _record_heat, false)
	for path in prepared.heat_paths:
		if path.sink_kind in ["thermal_store", "solid_thermal_store", "high_temp_store"] and path.source_kind == "solar_thermal":
			_supply_solar(path, prepared, electric_allocate, false)

static func charge_surplus(prepared: Dictionary, electric_allocate: Callable) -> void:
	for path in prepared.heat_paths:
		if path.sink_kind in ["thermal_store", "solid_thermal_store", "high_temp_store"] and path.source_kind == "electric_boiler":
			_supply_boiler(path, prepared, electric_allocate, false)

## Progressive filling shares *fuel input* equally among feasible boilers for
## this service. A combined row includes fuel, auxiliary AC and both heat paths,
## so a scarce shared line, station, HX, or sink is shared without over-allocation.
## Each pass saturates a row; blocked routes are replaced on the next pass.
static func _fuel_candidates(prepared: Dictionary, sink_id: String, storage: bool, battery: bool) -> Array:
	var candidates: Array = []
	var ids: Array = prepared.nodes.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for id in ids:
		var n: Dictionary = prepared.nodes[id]
		if not n.valid or n.kind != "fuel_boiler" or float(prepared.resources["fuel_boiler:" + id]) <= EPS:
			continue
		var selected: bool = false
		for hp in prepared.heat_paths:
			if hp.source_id != id or (Catalog.is_primary_thermal_storage(hp.sink_kind)) != storage or (not storage and hp.sink_id != sink_id):
				continue
			if _heat_limit(hp, prepared.resources, prepared.report) <= EPS:
				continue
			for ep in prepared.paths:
				if ep.sink_id != id or (Catalog.is_electric_storage(ep.source_kind)) != battery:
					continue
				var c: Dictionary = {"fuel:supply": 1.0, "fuel_boiler:" + id: 1.0}
				var heat_c: Dictionary = _heat_coefficients(hp)
				for key in heat_c:
					c[key] = float(heat_c[key]) * float(n.params.thermal_efficiency)
				var electric_factor: float = float(n.params.auxiliary_electric_ratio) / float(ep.received)
				for key in ep.coefficients:
					c[key] = float(c.get(key, 0.0)) + float(ep.coefficients[key]) * electric_factor
				var limit: float = INF
				for key in c:
					limit = minf(limit, maxf(0.0, float(prepared.resources[key])) / float(c[key]))
				if limit <= EPS:
					continue
				candidates.append({"id": id, "heat_path": hp, "electric_path": ep, "coefficients": c, "electric_factor": electric_factor})
				selected = true
				break
			if selected:
				break
	return candidates

static func _share_fuel(prepared: Dictionary, sink_id: String, storage: bool, battery: bool, electric_allocate: Callable) -> void:
	if not prepared.report.has("fuel") or float(prepared.resources.get("fuel:supply", 0.0)) <= EPS:
		return
	while true:
		var candidates: Array = _fuel_candidates(prepared, sink_id, storage, battery)
		if candidates.is_empty():
			return
		var totals: Dictionary = {}
		for candidate in candidates:
			for key in candidate.coefficients:
				totals[key] = float(totals.get(key, 0.0)) + float(candidate.coefficients[key])
		var delta: float = INF
		for key in totals:
			delta = minf(delta, maxf(0.0, float(prepared.resources[key])) / float(totals[key]))
		if not is_finite(delta) or delta <= EPS:
			return
		var progress: float = 0.0
		for candidate in candidates:
			var ep: Dictionary = candidate.electric_path
			var sent: float = electric_allocate.call(ep, prepared.resources, prepared.report, delta * float(candidate.electric_factor))
			var f: float = sent / float(candidate.electric_factor)
			progress += f
			prepared.resources["fuel:supply"] = maxf(0.0, float(prepared.resources["fuel:supply"]) - f)
			prepared.resources["fuel_boiler:" + candidate.id] = maxf(0.0, float(prepared.resources["fuel_boiler:" + candidate.id]) - f)
			prepared.report.devices[candidate.id].fuel_input_mw += f
			_record_heat(candidate.heat_path, f * float(prepared.nodes[candidate.id].params.thermal_efficiency), prepared)
		if progress <= EPS:
			return

static func serve_fuel_heat(prepared: Dictionary, demand_id: String, electric_allocate: Callable) -> void:
	_share_fuel(prepared, demand_id, false, false, electric_allocate)
	_share_fuel(prepared, demand_id, false, true, electric_allocate)

static func charge_fuel_storage(prepared: Dictionary, electric_allocate: Callable) -> void:
	# Gas may charge a real, non-full heat store, but never discharge an electric
	# battery merely to provide auxiliary power for speculative heat charging.
	_share_fuel(prepared, "", true, false, electric_allocate)

static func finish(prepared: Dictionary) -> void:
	var r: Dictionary = prepared.report
	var t: Dictionary = r.thermal
	var energy_before: float = 0.0
	var total_capacity: float = 0.0
	var oil_before: float = 0.0
	var oil_capacity: float = 0.0
	for id in prepared.nodes:
		var n: Dictionary = prepared.nodes[id]
		var d: Dictionary = r.devices[id]
		if not n.valid:
			continue
		var p: Dictionary = n.params
		match Catalog.dispatch_role(n.kind):
			"parabolic_trough":
				d.useful_mwth = d.heat_output_mwth
				d.curtailed_mwth = maxf(0.0, d.available_mwth - d.useful_mwth)
				d.auxiliary_electric_loss_mw = d.auxiliary_electric_mw
				d.utilization = d.useful_mwth / d.available_mwth if d.available_mwth > EPS else 0.0
				d.status_reason = "槽式集热供热" if d.useful_mwth > EPS else "未采集：DNI、受热端或辅助电力不足"
				for key in Solar.FIELDS: r.high_temp[key] += d[key]
				r.high_temp.collector_auxiliary_electric_mw += d.auxiliary_electric_mw
			"oil_water_exchanger":
				d.utilization = d.input_mwth / p.capacity_mwth
				d.auxiliary_electric_loss_mw = d.auxiliary_electric_mw
				d.status_reason = "油水换热" if d.input_mwth > EPS else "无热源、受热端或辅助电力"
				r.high_temp.exchanger_loss_mwth += d.loss_mwth
				r.high_temp.oil_water_output_mwth += d.output_mwth
				r.high_temp.auxiliary_electric_mw += d.auxiliary_electric_mw
				r.high_temp.oil_auxiliary_electric_mw += d.auxiliary_electric_mw
			"solar_thermal":
				d.useful_mwth = d.heat_output_mwth
				d.curtailed_mwth = maxf(0.0, d.available_mwth - d.useful_mwth)
				d.auxiliary_electric_loss_mw = d.auxiliary_electric_mw
				d.utilization = d.useful_mwth / d.available_mwth if d.available_mwth > EPS else 0.0
				d.status_reason = "太阳能供热" if d.useful_mwth > EPS else ("无可用太阳热" if d.available_mwth <= EPS else "未采集：无受热端或辅助电力")
				for key in Solar.FIELDS: r.solar[key] += d[key]
			"electric_boiler":
				d.conversion_loss_mw = d.electric_input_mw - d.heat_output_mwth
				d.utilization = d.electric_input_mw / p.rated_electric_mw
				d.status_reason = "未接电" if not d.electric_connected else ("热出口未连接" if not d.heat_connected else ("下游能力不足或电力不足" if d.electric_input_mw <= EPS else "供热"))
				r.boiler_electric_mw += d.electric_input_mw
				r.boiler_conversion_loss_mw += d.conversion_loss_mw
				t.boiler_heat_mwth += d.heat_output_mwth
			"fuel_boiler":
				d.conversion_loss_mw = d.fuel_input_mw - d.heat_output_mwth
				d.auxiliary_electric_loss_mw = d.auxiliary_electric_mw
				d.fuel_volume_nm3_per_h = FuelSupply.volume_nm3(d.fuel_input_mw, r.fuel_supply)
				d.fuel_cost_per_h = FuelSupply.cost(d.fuel_input_mw, r.fuel_supply)
				d.utilization = d.fuel_input_mw / p.rated_fuel_mw
				d.status_reason = "未接辅助电源" if not d.electric_connected else ("热出口未连接" if not d.heat_connected else ("燃料供应关闭或受限" if not r.fuel_supply.enabled or float(r.fuel_supply.max_input_mw) <= EPS else ("下游能力不足或辅助电力不足" if d.fuel_input_mw <= EPS else "燃气供热")))
				r.fuel.input_mw += d.fuel_input_mw
				r.fuel.volume_nm3_per_h += d.fuel_volume_nm3_per_h
				r.fuel.cost_per_h += d.fuel_cost_per_h
				r.fuel.heat_output_mwth += d.heat_output_mwth
				r.fuel.conversion_loss_mw += d.conversion_loss_mw
				r.fuel.auxiliary_electric_mw += d.auxiliary_electric_mw
				r.fuel.auxiliary_electric_loss_mw += d.auxiliary_electric_loss_mw
			"heat_exchanger":
				d.utilization = d.input_mwth / p.capacity_mwth
				d.status_reason = "换热供热" if d.input_mwth > EPS else "上游无热或下游能力不足"
				t.exchanger_loss_mwth += d.loss_mwth
			"heat_demand":
				d.unserved_mwth = maxf(0.0, d.demand_mwth - d.served_mwth)
				d.utilization = d.served_mwth / d.demand_mwth if d.demand_mwth > 0.0 else 1.0
				t.demand_mwth += d.demand_mwth
				t.served_mwth += d.served_mwth
				t.unserved_mwth += d.unserved_mwth
			"thermal_store", "solid_thermal_store", "high_temp_store":
				var ledger: Dictionary = r.high_temp if n.kind == "high_temp_store" else t
				var e: float = d.energy_after_self_discharge_mwhth + (p.charge_efficiency * d.charge_mwth - d.discharge_mwth / p.discharge_efficiency) * r.dt_h
				d.next_energy_mwhth = clampf(e, 0.0, p.capacity_mwhth)
				d.soc = d.next_energy_mwhth / p.capacity_mwhth
				d.storage_conversion_loss_mwth = d.charge_mwth * (1.0 - p.charge_efficiency) + d.discharge_mwth * (1.0 / p.discharge_efficiency - 1.0)
				d.storage_balance_error_mwhth = e - d.next_energy_mwhth
				d.status_reason = "热储已空" if d.next_energy_mwhth <= EPS else ("热储已满" if d.next_energy_mwhth >= p.capacity_mwhth - EPS else d.mode)
				d.utilization = d.charge_mwth / p.charge_mwth if d.mode == "charge" and p.charge_mwth > 0.0 else (d.discharge_mwth / p.discharge_mwth if p.discharge_mwth > 0.0 else 0.0)
				r.next_states[id] = {"energy_mwhth": d.next_energy_mwhth}
				ledger.charge_mwth += d.charge_mwth
				ledger.discharge_mwth += d.discharge_mwth
				ledger.energy_mwhth += d.next_energy_mwhth
				ledger.storage_conversion_loss_mwth += d.storage_conversion_loss_mwth
				ledger.self_discharge_mwhth += d.self_discharge_mwhth
				if n.kind == "high_temp_store":
					oil_before += d.energy_before_mwhth
					oil_capacity += p.capacity_mwhth
				else:
					energy_before += d.energy_before_mwhth
					total_capacity += p.capacity_mwhth
	for line in r.lines:
		if line.valid and line.carrier in [Catalog.THERMAL_CARRIER, "heat_oil"]:
			line.active = line.sent_mwth > EPS
			line.utilization = line.sent_mwth / line.capacity_mwth if line.capacity_mwth > 0.0 else 0.0
			t.network_loss_mwth += line.loss_mwth
	if r.has("high_temp"):
		var h: Dictionary = r.high_temp
		h.storage_loss_mwth = h.storage_conversion_loss_mwth + (h.self_discharge_mwhth / r.dt_h if r.dt_h > 0.0 else 0.0)
		h.soc = h.energy_mwhth / oil_capacity if oil_capacity > 0.0 else 0.0
		h.balance_error_mwth = h.useful_mwth + h.discharge_mwth - h.charge_mwth - h.oil_water_output_mwth - h.exchanger_loss_mwth - float(h.get("rankine_oil_input_mwth", 0.0))
		h.energy_balance_error_mwhth = oil_before - h.energy_mwhth - h.self_discharge_mwhth + (h.useful_mwth - h.oil_water_output_mwth - h.exchanger_loss_mwth - h.storage_conversion_loss_mwth - float(h.get("rankine_oil_input_mwth", 0.0))) * r.dt_h
	t.soc = t.energy_mwhth / total_capacity if total_capacity > 0.0 else 0.0
	var fuel_heat: float = float(r.get("fuel", {}).get("heat_output_mwth", 0.0)) + float(r.get("solar", {}).get("useful_mwth", 0.0)) + float(r.get("high_temp", {}).get("oil_water_output_mwth", 0.0))
	t.balance_error_mwth = t.boiler_heat_mwth + fuel_heat + t.discharge_mwth - t.served_mwth - t.charge_mwth - t.exchanger_loss_mwth - t.network_loss_mwth
	t.energy_balance_error_mwhth = energy_before - t.energy_mwhth - t.self_discharge_mwhth + (t.boiler_heat_mwth + fuel_heat - t.served_mwth - t.exchanger_loss_mwth - t.network_loss_mwth - t.storage_conversion_loss_mwth) * r.dt_h

static func _number(v: Variant) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))

static func _near(errors: Array[String], actual: Variant, expected: float, label: String) -> void:
	if not _number(actual) or absf(float(actual) - expected) > ABS_TOL + REL_TOL * maxf(absf(expected), absf(float(actual))):
		errors.append("Independent audit: " + label)

## Rebuild node equations from line flows and original parameter/state dictionaries.
## Do not accept the reported balance residual as proof of conservation.
static func audit(prepared: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var r: Dictionary = prepared.report
	var nodes: Dictionary = prepared.nodes
	var inputs: Dictionary = {}
	var raw_links: Array = prepared.get("raw_links", [])
	if r.lines.size() != raw_links.size():
		errors.append("Independent audit: changed edge set")
		return errors
	if not _number(r.get("dt_h")) or float(r.dt_h) < 0.0:
		errors.append("Independent audit: invalid duration")
		return errors
	_near(errors, r.dt_h, float(r.dt_s) / 3600.0, "duration units")
	var outputs: Dictionary = {}
	var nonstorage_station_input: Dictionary = {}
	var restricted_station_output: Dictionary = {}
	for id in nodes:
		inputs[id] = {"electricity_ac": 0.0, "heat_water": 0.0, "heat_oil": 0.0, "heat_salt": 0.0}
		outputs[id] = {"electricity_ac": 0.0, "heat_water": 0.0, "heat_oil": 0.0, "heat_salt": 0.0}
	for line in r.lines:
		if not line.valid:
			continue
		if line.carrier == "water_steam" or line.carrier in Catalog.Materials.CARRIERS: continue
		var heat: bool = line.carrier in [Catalog.THERMAL_CARRIER, "heat_oil", "heat_salt"]
		var sent: Variant = line.get("sent_mwth" if heat else "sent_mw")
		var received: Variant = line.get("received_mwth" if heat else "received_mw")
		var raw: Dictionary = raw_links[int(line.index)]
		var cap: float = float(raw.get("capacity_mwth" if heat else "capacity_mw", 4.0))
		if int(raw.from) != int(line.from) or int(raw.to) != int(line.to) or str(raw.get("carrier", Catalog.CARRIER)) != str(line.carrier):
			errors.append("Independent audit: changed line endpoints/carrier")
			continue
		_near(errors, line.get("capacity_mwth" if heat else "capacity_mw"), cap, "line capacity metadata")
		_near(errors, line.loss_fraction, float(raw.get("loss_fraction", 0.0 if heat else 0.01)), "line loss metadata")
		if not _number(sent) or not _number(received) or float(sent) < -ABS_TOL or float(received) < -ABS_TOL or float(sent) > cap + ABS_TOL + REL_TOL * cap:
			errors.append("Independent audit: invalid line flow/capacity")
			continue
		_near(errors, received, float(sent) * (1.0 - float(line.loss_fraction)), "line efficiency")
		var a: String = str(line.flow_from)
		var b: String = str(line.flow_to)
		var forward: bool = int(line.flow_from) == int(raw.from) and int(line.flow_to) == int(raw.to)
		var storage_edge: bool = Catalog.is_electric_storage(nodes[str(int(raw.from))].kind) or (int(raw.to) != -1 and Catalog.is_electric_storage(nodes[str(int(raw.to))].kind))
		var reverse: bool = not heat and storage_edge and int(line.flow_from) == int(raw.to) and int(line.flow_to) == int(raw.from)
		if not forward and not reverse:
			errors.append("Independent audit: changed port flow direction/endpoints")
			continue
		if not heat:
			if nodes.has(b) and Catalog.is_electric_station(nodes[b].kind) and nodes[a].kind in ["wind", "pv", "steam_turbine"]:
				nonstorage_station_input[b] = float(nonstorage_station_input.get(b,0.0)) + float(received)
			if Catalog.is_electric_station(nodes[a].kind) and (b == "-1" or Catalog.is_electric_storage(nodes[b].kind) or nodes[b].kind in ["electrolyzer_station", "hydrogen_gas_store"]):
				restricted_station_output[a] = float(restricted_station_output.get(a,0.0)) + float(sent)
		if outputs.has(a): outputs[a][line.carrier] += float(sent)
		if inputs.has(b): inputs[b][line.carrier] += float(received)
		if heat:
			var ap: Dictionary = Catalog.port(nodes[str(line.from)].kind, line.from_port)
			var bp: Dictionary = Catalog.port(nodes[str(line.to)].kind, line.to_port)
			if ap.get("grade_id", "") != line.grade_id or bp.get("grade_id", "") != line.grade_id or float(line.loss_fraction) != 0.0:
				errors.append("Independent audit: thermal grade/loss contract")
	# Charging stores/export may only be supplied by generation, not by another
	# store. Reconstruct a feasible source partition at each original AC bus.
	for station in restricted_station_output:
		var allowed: float = float(nonstorage_station_input.get(station,0.0)) * (1.0 - float(nodes[station].params.loss_fraction))
		if float(restricted_station_output[station]) > allowed + ABS_TOL + REL_TOL * absf(allowed):
			errors.append("Independent audit: storage cannot supply other storage or grid export")
	var rankine: Dictionary = Rankine.audit(prepared, errors)
	var tower: Dictionary = Tower.audit(prepared, errors)
	var oil: Dictionary = HighTemp.audit(prepared, errors) if r.has("high_temp") else HighTemp.empty()
	var boiler_electric: float = 0.0
	var boiler_heat: float = 0.0
	var solar_totals: Dictionary = Solar.empty()
	var fuel_input: float = 0.0
	var fuel_heat: float = 0.0
	var fuel_auxiliary: float = 0.0
	var heat_served: float = 0.0
	var heat_charge: float = 0.0
	var heat_discharge: float = 0.0
	var exchanger_loss: float = 0.0
	var heat_energy: float = 0.0
	var heat_demand: float = 0.0
	var heat_before: float = 0.0
	var heat_self_loss: float = 0.0
	var heat_conversion_loss: float = 0.0
	var electric_generated: float = 0.0
	var electric_curtailed: float = 0.0
	var electric_served: float = 0.0
	var electric_charge: float = 0.0
	var electric_discharge: float = 0.0
	var electric_network_loss: float = 0.0
	var electric_before: float = 0.0
	var electric_after: float = 0.0
	var electric_self_loss: float = 0.0
	var electric_conversion_loss: float = 0.0
	var exported: float = 0.0
	for line in r.lines:
		if line.valid and line.carrier == Catalog.CARRIER:
			electric_network_loss += float(line.sent_mw) - float(line.received_mw)
			if line.flow_to == -1: exported += line.received_mw
	for id in nodes:
		var n: Dictionary = nodes[id]
		if not n.valid:
			continue
		var d: Dictionary = r.devices[id]
		var p: Dictionary = n.params
		var ei: float = inputs[id].electricity_ac
		var eo: float = outputs[id].electricity_ac
		var hi: float = inputs[id].heat_water
		var ho: float = outputs[id].heat_water
		match Catalog.dispatch_role(n.kind):
			"solar_thermal":
				var physics: Dictionary = Solar.evaluate(p, prepared.get("weather", {}))
				if not physics.valid: errors.append("Independent audit: invalid solar weather or parameters")
				for key in ["incident_mw", "optical_rejection_mw", "potential_thermal_loss_mw", "thermal_loss_mw", "available_mwth"]:
					_near(errors, d.get(key), float(physics[key]), id + " solar " + key)
					solar_totals[key] += physics[key]
				for key in ["poa_wm2", "mean_fluid_temp_c"]:
					_near(errors, d.get(key), float(physics[key]), id + " solar metadata " + key)
				if d.get("area_basis") != "absorber" or d.get("irradiance_kind") != physics.irradiance_kind:
					errors.append("Independent audit: solar area/irradiance convention")
				_near(errors, ei, ho * float(p.auxiliary_electric_ratio), id + " solar auxiliary per useful heat")
				_near(errors, d.get("heat_output_mwth"), ho, id + " solar heat output")
				_near(errors, d.get("output_mwth"), ho, id + " solar port output")
				_near(errors, d.get("useful_mwth"), ho, id + " solar useful heat")
				_near(errors, d.get("curtailed_mwth"), float(physics.available_mwth) - ho, id + " solar curtailed potential")
				_near(errors, d.get("auxiliary_electric_mw"), ei, id + " solar auxiliary input")
				_near(errors, d.get("auxiliary_electric_loss_mw"), ei, id + " solar auxiliary dissipation")
				if ho > float(physics.available_mwth) + ABS_TOL: errors.append("Independent audit: solar availability exceeded")
				solar_totals.useful_mwth += ho
				solar_totals.curtailed_mwth += float(physics.available_mwth) - ho
				solar_totals.auxiliary_electric_mw += ei
			"electric_boiler":
				_near(errors, ho, ei * p.thermal_efficiency, id + " boiler conversion")
				_near(errors, d.electric_input_mw, ei, id + " boiler input")
				_near(errors, d.heat_output_mwth, ho, id + " boiler output")
				_near(errors, d.conversion_loss_mw, ei - ho, id + " boiler loss")
				if ei > p.rated_electric_mw + ABS_TOL: errors.append("Independent audit: boiler rating")
				boiler_electric += ei
				boiler_heat += ho
			"fuel_boiler":
				# Reconstruct fuel from measured auxiliary AC, then check heat.
				var f: float = ei / float(p.auxiliary_electric_ratio)
				_near(errors, d.fuel_input_mw, f, id + " fuel input from auxiliary AC")
				_near(errors, ho, f * float(p.thermal_efficiency), id + " gas boiler heat conversion")
				_near(errors, d.heat_output_mwth, ho, id + " gas boiler output")
				_near(errors, d.auxiliary_electric_mw, ei, id + " gas auxiliary input")
				_near(errors, d.auxiliary_electric_loss_mw, ei, id + " gas auxiliary dissipation")
				_near(errors, d.conversion_loss_mw, f - ho, id + " gas conversion loss")
				_near(errors, d.fuel_volume_nm3_per_h, FuelSupply.volume_nm3(f, r.fuel_supply), id + " gas volume")
				_near(errors, d.fuel_cost_per_h, FuelSupply.cost(f, r.fuel_supply), id + " gas cost")
				_near(errors, f + ei, ho + float(d.conversion_loss_mw) + float(d.auxiliary_electric_loss_mw), id + " cross-carrier conversion")
				if f > float(p.rated_fuel_mw) + ABS_TOL: errors.append("Independent audit: gas boiler fuel rating")
				if f > EPS and (ei <= 0.0 or ho <= 0.0): errors.append("Independent audit: fuel without auxiliary AC or useful heat path")
				fuel_input += f
				fuel_heat += ho
				fuel_auxiliary += ei
			"heat_exchanger":
				_near(errors, ho, hi * p.transfer_efficiency, id + " exchanger conversion")
				_near(errors, d.input_mwth, hi, id + " exchanger input")
				_near(errors, d.output_mwth, ho, id + " exchanger output")
				if hi > p.capacity_mwth + ABS_TOL: errors.append("Independent audit: exchanger rating")
				if not Catalog.validate_thermal(n.kind, p).is_empty(): errors.append("Independent audit: exchanger temperatures")
				exchanger_loss += hi - ho
			"heat_demand":
				_near(errors, d.served_mwth, hi, id + " heat demand delivery")
				_near(errors, d.unserved_mwth, p.demand_mwth - hi, id + " heat demand balance")
				if hi > p.demand_mwth + ABS_TOL: errors.append("Independent audit: excess heat service")
				heat_served += hi
				heat_demand += p.demand_mwth
			"thermal_store", "solid_thermal_store":
				var before: float = n.state.energy_mwhth
				var decayed: float = before * exp(-p.self_discharge_per_h * r.dt_h)
				var after: float = decayed + (p.charge_efficiency * hi - ho / p.discharge_efficiency) * r.dt_h
				_near(errors, d.charge_mwth, hi, id + " heat charge")
				_near(errors, d.discharge_mwth, ho, id + " heat discharge")
				_near(errors, d.self_discharge_mwhth, before - decayed, id + " self discharge")
				_near(errors, d.next_energy_mwhth, after, id + " heat inventory")
				_near(errors, r.next_states.get(id, {}).get("energy_mwhth"), after, id + " next heat state")
				if after < -ABS_TOL or after > p.capacity_mwhth + ABS_TOL or hi > p.charge_mwth + ABS_TOL or ho > p.discharge_mwth + ABS_TOL or (hi > EPS and ho > EPS):
					errors.append("Independent audit: thermal inventory/capacity/mode")
				if r.dt_h == 0.0 and (hi > EPS or ho > EPS): errors.append("Independent audit: paused thermal storage exchange")
				heat_charge += hi
				heat_discharge += ho
				heat_energy += after
				heat_before += before
				heat_self_loss += before - decayed
				var conversion: float = hi * (1.0 - p.charge_efficiency) + ho * (1.0 / p.discharge_efficiency - 1.0)
				heat_conversion_loss += conversion
				_near(errors, d.storage_conversion_loss_mwth, conversion, id + " thermal conversion loss")
				var mode: String = "charge" if hi > EPS else ("discharge" if ho > EPS else "idle")
				if not d.get("mode") is String or d.mode != mode: errors.append("Independent audit: thermal mode label")
			"station":
				if n.kind == Catalog.COLLECTOR_KIND:
					for field in ["energy_mwh","energy_mwhth","material_inventory_kg","soc"]:
						if d.has(field): errors.append("Independent audit: collector has no inventory")
					if d.get("model_profile") != Catalog.COLLECTOR_PROFILE or d.get("model_profile_version") != 1: errors.append("Independent audit: collector profile")
					_near(errors,d.get("capacity_mw"),p.capacity_mw,id+" collector capacity metadata")
					_near(errors,d.get("loss_fraction"),p.loss_fraction,id+" collector loss metadata")
					for field in ["input_mw","received_mw"]:_near(errors,d.get(field),ei,id+" collector actual AC input")
					for field in ["output_mw","sent_mw"]:_near(errors,d.get(field),eo,id+" collector actual AC output")
					_near(errors,d.get("loss_mw"),ei-eo,id+" collector actual loss")
				_near(errors, eo, ei * (1.0 - p.loss_fraction), id + " station conservation")
				if ei > p.capacity_mw + ABS_TOL: errors.append("Independent audit: station capacity")
				electric_network_loss += ei - eo
			"load":
				_near(errors, d.served_mw, ei, id + " electric load delivery")
				if ei > p.demand_mw + ABS_TOL: errors.append("Independent audit: electric demand limit")
				electric_served += ei
			"wind", "pv":
				_near(errors, d.mw, eo + d.curtailed_mw, id + " renewable balance")
				var rating: float = p.get("rated_mw", p.get("inverter_capacity_mw", 0.0))
				if d.mw < -ABS_TOL or d.mw > rating + ABS_TOL: errors.append("Independent audit: generation rating")
				electric_generated += d.mw
				electric_curtailed += d.curtailed_mw
			"battery", "battery_sodium", "battery_flow", "caes_aboveground", "liquid_air_store", "hydrogen_storage_system", "co2_liquid_cycle_store":
				_near(errors, d.charge_mw, ei, id + " battery charge")
				_near(errors, d.discharge_mw, eo, id + " battery discharge")
				if ei > EPS and eo > EPS: errors.append("Independent audit: electric battery mode")
				var expected: float = n.state.energy_mwh * exp(-p.self_discharge_per_h * r.dt_h) + (p.charge_efficiency * ei - eo / p.discharge_efficiency) * r.dt_h
				_near(errors, d.next_energy_mwh, expected, id + " electric inventory")
				if n.kind == Catalog.CO2_STORAGE_KIND:
					var expected_mode: String = "charge" if ei>EPS else "discharge" if eo>EPS else "idle"
					if d.get("mode") != expected_mode: errors.append("Independent audit: CO2 mode differs from actual AC")
					_near(errors,d.get("capacity_mwh"),p.capacity_mwh,id+" CO2 capacity metadata")
					_near(errors,d.get("energy_before_mwh"),n.state.energy_mwh,id+" CO2 original energy")
					_near(errors,d.get("energy_after_self_discharge_mwh"),n.state.energy_mwh*exp(-p.self_discharge_per_h*r.dt_h),id+" CO2 post-decay energy")
					for field in ["input_mw","received_mw"]:_near(errors,d.get(field),ei,id+" CO2 actual AC input")
					for field in ["output_mw","sent_mw"]:_near(errors,d.get(field),eo,id+" CO2 actual AC output")
					for field in d:
						if str(field).ends_with("_kg") or str(field).ends_with("_kg_s") or str(field).ends_with("_mwth") or str(field).ends_with("_mwhth") or "lhv" in str(field) or field == "material_inventory_kg": errors.append("Independent audit: CO2 aggregate cannot claim material or useful heat inventory")
				var stage: Dictionary = Catalog.storage_stage_metrics(n.kind, p, ei, eo, expected)
				for field in stage:
					if stage[field] is String or stage[field] is bool:
						if d.get(field) != stage[field]: errors.append("Independent audit: " + id + " " + field)
					else:
						_near(errors, d.get(field), stage[field], id + " " + field)
				_near(errors, d.storage_conversion_loss_mw, stage.charge_conversion_loss_mw + stage.discharge_conversion_loss_mw, id + " electric storage conversion loss")
				_near(errors, d.self_discharge_mwh, n.state.energy_mwh * (1.0 - exp(-p.self_discharge_per_h * r.dt_h)), id + " electric self loss")
				if r.dt_h == 0.0 and (ei > EPS or eo > EPS): errors.append("Independent audit: paused electric storage exchange")

				_near(errors, r.next_states.get(id, {}).get("energy_mwh"), expected, id + " next electric state")
				if expected < -ABS_TOL or expected > p.capacity_mwh + ABS_TOL or ei > p.charge_mw + ABS_TOL or eo > p.discharge_mw + ABS_TOL:
					errors.append("Independent audit: electric inventory/limits")
				electric_charge += ei
				electric_discharge += eo
				electric_before += n.state.energy_mwh
				electric_after += expected
				electric_self_loss += n.state.energy_mwh * (1.0 - exp(-p.self_discharge_per_h * r.dt_h))
				electric_conversion_loss += stage.charge_conversion_loss_mw + stage.discharge_conversion_loss_mw
				_near(errors, d.storage_loss_mw, stage.charge_conversion_loss_mw + stage.discharge_conversion_loss_mw + (d.self_discharge_mwh / r.dt_h if r.dt_h > 0.0 else 0.0), id + " total storage loss")
				_near(errors, d.soc, expected / p.capacity_mwh, id + " electric SOC")
	var material: Dictionary = Materials.audit(prepared, errors)
	var material_aux: float = float(material.electrolyzer_electric_mw) + float(material.compression_electric_mw) + float(material.get("phase_store_electric_mw",0.0)) + float(material.get("chemical_electric_mw",0.0))
	electric_generated += float(rankine.gross_electric_mw) + float(material.fuel_cell_output_mw)
	_near(errors, r.generated_mw, electric_generated, "aggregate generated electricity")
	_near(errors, r.curtailed_mw, electric_curtailed, "aggregate curtailed electricity")
	_near(errors, r.served_mw, electric_served, "aggregate electric service")
	_near(errors, r.charge_mw, electric_charge, "aggregate battery charge")
	_near(errors, r.discharge_mw, electric_discharge, "aggregate battery discharge")
	_near(errors, r.get("self_discharge_mwh"), electric_self_loss, "aggregate electric self loss")
	_near(errors, r.get("storage_conversion_loss_mw"), electric_conversion_loss, "aggregate electric storage conversion loss")
	_near(errors, r.get("storage_loss_mw"), electric_conversion_loss + (electric_self_loss / r.dt_h if r.dt_h > 0.0 else 0.0), "aggregate electric storage loss")
	_near(errors, electric_before + electric_charge * r.dt_h, electric_after + electric_discharge * r.dt_h + electric_self_loss + electric_conversion_loss * r.dt_h, "electric inventory energy equation")

	_near(errors, r.delivered_mw, exported, "aggregate grid export")
	_near(errors, r.loss_mw, electric_network_loss, "aggregate electric network loss")
	_near(errors, r.boiler_conversion_loss_mw, boiler_electric - boiler_heat, "aggregate boiler loss")
	_near(errors, r.thermal.demand_mwth, heat_demand, "aggregate heat demand")
	_near(errors, r.thermal.unserved_mwth, heat_demand - heat_served, "aggregate heat shortfall")
	_near(errors, r.thermal.exchanger_loss_mwth, exchanger_loss, "aggregate exchanger loss")
	_near(errors, r.thermal.network_loss_mwth, 0.0, "stage-one zero thermal line loss")
	_near(errors, r.thermal.self_discharge_mwhth, heat_self_loss, "aggregate thermal self discharge")
	_near(errors, r.thermal.storage_conversion_loss_mwth, heat_conversion_loss, "aggregate thermal storage conversion loss")
	_near(errors, heat_before + heat_charge * r.dt_h, heat_energy + heat_discharge * r.dt_h + heat_self_loss + heat_conversion_loss * r.dt_h, "thermal storage energy equation")
	_near(errors, r.generated_mw + r.discharge_mw - r.curtailed_mw, r.served_mw + r.charge_mw + boiler_electric + fuel_auxiliary + solar_totals.auxiliary_electric_mw + oil.auxiliary_electric_mw + rankine.auxiliary_electric_mw + tower.auxiliary_electric_mw + material_aux + r.delivered_mw + r.loss_mw, "electric network conservation")
	_near(errors, r.boiler_electric_mw, boiler_electric, "aggregate boiler electric")
	_near(errors, r.thermal.boiler_heat_mwth, boiler_heat, "aggregate boiler heat")
	_near(errors, r.thermal.served_mwth, heat_served, "aggregate heat service")
	_near(errors, r.thermal.charge_mwth, heat_charge, "aggregate heat charge")
	_near(errors, r.thermal.discharge_mwth, heat_discharge, "aggregate heat discharge")
	_near(errors, r.thermal.energy_mwhth, heat_energy, "aggregate heat inventory")
	_near(errors, boiler_heat + fuel_heat + solar_totals.useful_mwth + oil.oil_water_output_mwth + heat_discharge, heat_served + heat_charge + exchanger_loss, "thermal network conservation")
	if r.has("fuel"):
		var supply_error: String = FuelSupply.validate(r.fuel_supply)
		if not supply_error.is_empty(): errors.append("Independent audit: " + supply_error)
		var cap: float = float(r.fuel_supply.max_input_mw) if r.fuel_supply.enabled else 0.0
		if fuel_input > cap + ABS_TOL + REL_TOL * cap: errors.append("Independent audit: shared fleet fuel cap")
		_near(errors, r.fuel.input_mw, fuel_input, "aggregate fuel input")
		_near(errors, r.fuel.heat_output_mwth, fuel_heat, "aggregate fuel heat")
		_near(errors, r.fuel.conversion_loss_mw, fuel_input - fuel_heat, "aggregate fuel conversion loss")
		_near(errors, r.fuel.auxiliary_electric_mw, fuel_auxiliary, "aggregate fuel auxiliary AC")
		_near(errors, r.fuel.auxiliary_electric_loss_mw, fuel_auxiliary, "aggregate auxiliary dissipation")
		_near(errors, r.fuel.volume_nm3_per_h, FuelSupply.volume_nm3(fuel_input, r.fuel_supply), "aggregate gas volume")
		_near(errors, r.fuel.cost_per_h, FuelSupply.cost(fuel_input, r.fuel_supply), "aggregate gas cost")
		if r.has("cross_carrier_balance_error_mw"):
			_near(errors, r.cross_carrier_balance_error_mw, 0.0, "reported cross-carrier residual")
		_near(errors, electric_generated - electric_curtailed + electric_discharge + heat_discharge + fuel_input + solar_totals.useful_mwth + oil.oil_water_output_mwth, electric_served + electric_charge + exported + electric_network_loss + heat_served + heat_charge + exchanger_loss + (boiler_electric - boiler_heat) + (fuel_input - fuel_heat) + fuel_auxiliary + solar_totals.auxiliary_electric_mw + oil.auxiliary_electric_mw + rankine.auxiliary_electric_mw + tower.auxiliary_electric_mw + material_aux, "whole-system cross-carrier conservation")
	if r.has("solar"):
		_near(errors, r.get("cross_carrier_balance_error_mw"), 0.0, "solar cross-carrier residual")
		if not r.solar is Dictionary: errors.append("Independent audit: malformed solar aggregate")
		else:
			for key in Solar.FIELDS: _near(errors, r.solar.get(key), float(solar_totals[key]), "aggregate solar " + key)
	elif solar_totals.incident_mw > EPS or solar_totals.useful_mwth > EPS:
		errors.append("Independent audit: missing solar aggregate")
	return errors
