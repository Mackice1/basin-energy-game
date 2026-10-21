extends RefCounted
## Pure one-step active-power transport dispatch. Actual radial paths retain every
## line and station bottleneck. Priority policy is deterministic, not an optimum.
## Malformed devices/edges are excluded for feasible-subgraph diagnostics. Such
## reports have valid=false and MUST NOT be committed by the simulation caller.
## step_valid is only the finite/nonnegative-duration guard, not an apply gate.
const Catalog = preload("res://scripts/device_catalog.gd")
const Materials = preload("res://scripts/material_dispatch.gd")
const Thermal = preload("res://scripts/thermal_dispatch.gd")
const FuelSupply = preload("res://scripts/fuel_supply.gd")
const HighTemp = preload("res://scripts/high_temp_thermal.gd")
const Solar = preload("res://scripts/solar_thermal.gd")
const Rankine = preload("res://scripts/rankine_cycle.gd")
const Tower = preload("res://scripts/solar_tower_thermal.gd")
const EPS: float = 1.0e-9

static func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))

static func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floor(float(value))

static func _sorted_ids(nodes: Dictionary) -> Array:
	var ids: Array = nodes.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	return ids

static func _prepare(devices: Array, links: Array, weather: Dictionary, direct: Dictionary, dt_s: float, generation: Callable, validate: Callable) -> Dictionary:
	var valid_dt: bool = is_finite(dt_s) and dt_s >= 0.0
	var step_s: float = dt_s if valid_dt else 0.0
	var report: Dictionary = {"devices": {}, "lines": [], "errors": [], "warnings": [],
		"generated_mw": 0.0, "available_mw": 0.0, "produced_mw": 0.0,
		"delivered_mw": 0.0, "curtailed_mw": 0.0, "demand_mw": 0.0,
		"served_mw": 0.0, "unserved_mw": 0.0, "charge_mw": 0.0, "discharge_mw": 0.0,
		"loss_mw": 0.0, "line_loss_mw": 0.0, "station_loss_mw": 0.0,
		"storage_loss_mw": 0.0, "storage_conversion_loss_mw": 0.0, "self_discharge_mwh": 0.0,
		"nameplate_clipped_mw": 0.0, "balance_error_mw": 0.0, "storage_balance_error_mwh": 0.0,
		"energy_balance_error_mwh": 0.0, "boiler_electric_mw": 0.0, "boiler_conversion_loss_mw": 0.0, "next_states": {}, "grid_capacity_mw": Catalog.GRID_CAPACITY_MW,
		"dt_s": step_s, "dt_h": step_s / 3600.0, "step_valid": valid_dt,
		"optimal": false, "dispatch_policy": "priority_then_stable_id", "status": "feasible",
		"model": "radial active-power capacity transport; not AC power flow"}
	if not valid_dt:
		report.errors.append("dt_s must be finite and nonnegative; step rejected and storage frozen")
		report.status = "error"
	var nodes: Dictionary = {}
	var valid_devices: Array = []
	var has_fuel: bool = false
	var has_solar: bool = false
	var has_high_temp: bool = false
	var has_tower: bool = false
	var resources: Dictionary = {"grid": Catalog.GRID_CAPACITY_MW}
	for raw in devices:
		if not raw is Dictionary or not _integer(raw.get("id")) or float(raw.get("id", -1)) < 0.0:
			report.errors.append("Device requires a nonnegative integer stable id")
			continue
		var id: String = str(int(raw.id))
		if nodes.has(id):
			report.errors.append("Duplicate device id %s ignored" % id)
			continue
		var kind: String = str(raw.get("kind", ""))
		has_fuel = has_fuel or kind == "fuel_boiler"
		has_solar = has_solar or kind == "solar_thermal"
		has_tower = has_tower or kind in Tower.KINDS
		has_high_temp = has_high_temp or kind in ["parabolic_trough", "high_temp_store", "oil_water_exchanger"]
		var params: Dictionary = raw.get("params", {}) if raw.get("params", {}) is Dictionary else {}
		var p: Dictionary = Catalog.defaults(kind)
		p.merge(params, true)
		var errors: Array = validate.call(kind, params)
		if not raw.get("params", {}) is Dictionary:
			errors.append("params must be a dictionary")
		var state: Dictionary = {}
		if errors.is_empty():
			var raw_state: Variant = raw.get("state", Catalog.initial_state(kind, params))
			errors.append_array(Catalog.validate_state(kind, p, raw_state))
			if errors.is_empty():
				state = raw_state.duplicate(true)
		if Catalog.is_thermal(kind) or Catalog.is_material(kind) or kind in [Catalog.CO2_STORAGE_KIND,Catalog.COLLECTOR_KIND]:
			if raw.has("model_profile") and (not raw.model_profile is String or raw.model_profile != Catalog.model_profile(kind)):
				errors.append("Unknown thermal model_profile")
			if raw.has("model_profile_version") and (not _integer(raw.model_profile_version) or int(raw.model_profile_version) != Catalog.model_profile_version(kind)):
				errors.append("Unknown thermal model_profile_version")
		var detail: Dictionary = {"mw": 0.0, "generated_mw": 0.0, "errors": errors,
			"valid": errors.is_empty(), "source": "device", "nameplate_clipped_mw": 0.0}
		if kind in ["wind", "pv"] and errors.is_empty():
			if direct.has(id):
				var sample: Variant = direct[id]
				var ok: bool = sample is Dictionary and _number(sample.get("mw")) and float(sample.get("mw", -1.0)) >= 0.0
				var rating: float = float(p.get("rated_mw", p.get("inverter_capacity_mw", 0.0)))
				var raw_mw: float = float(sample.mw) if ok else 0.0
				detail = {"mw": minf(raw_mw, rating), "generated_mw": minf(raw_mw, rating),
					"source": str(sample.get("source", "direct")) if sample is Dictionary else "direct",
					"valid": ok, "errors": [] if ok else ["Direct power must be finite and nonnegative"],
					"requested_mw": raw_mw, "nameplate_clipped_mw": maxf(0.0, raw_mw - rating),
					"model": "direct AC terminal power", "rated_mw": rating}
			else:
				detail = generation.call(kind, params, weather)
		if kind == "solar_thermal" and errors.is_empty():
			detail.merge(Solar.evaluate(p, weather), true)
		if kind == "solar_tower_receiver" and errors.is_empty():
			detail.merge(Tower.evaluate(p, weather), true)
		if kind == "parabolic_trough" and errors.is_empty():
			detail.merge(HighTemp.evaluate(p, weather), true)
		detail.merge({"id": int(raw.id), "kind": kind, "sent_mw": 0.0,
			"received_mw": 0.0, "delivered_mw": 0.0, "curtailed_mw": 0.0, "loss_mw": 0.0,
			"input_mw": 0.0, "output_mw": 0.0, "connected": false, "utilization": 0.0}, true)
		if Catalog.is_electric_station(kind) and detail.valid:
			if kind == Catalog.COLLECTOR_KIND: detail.merge({"model_profile":Catalog.COLLECTOR_PROFILE,"model_profile_version":1})
			detail.capacity_mw = p.capacity_mw
			detail.loss_fraction = p.loss_fraction
			resources["station:" + id] = float(p.capacity_mw)
		elif kind == "load" and detail.valid:
			detail.merge({"demand_mw": p.demand_mw, "served_mw": 0.0, "unserved_mw": p.demand_mw, "priority": int(p.priority)})
			report.demand_mw += p.demand_mw
			resources["load:" + id] = float(p.demand_mw)
		elif Catalog.is_electric_storage(kind) and detail.valid:
			var limits: Dictionary = Catalog.storage_limits(p, state.energy_mwh, step_s)
			detail.merge(limits)
			detail.storage_technology = Catalog.storage_technology(kind)
			detail.merge(Catalog.storage_stage_metrics(kind, p, 0.0, 0.0, limits.energy_after_self_discharge_mwh))
			detail.merge({"mode": "idle", "soc": state.energy_mwh / p.capacity_mwh,
				"soc_before": state.energy_mwh / p.capacity_mwh, "energy_mwh": state.energy_mwh,
				"next_energy_mwh": limits.energy_after_self_discharge_mwh, "capacity_mwh": p.capacity_mwh,
				"charge_mw": 0.0, "discharge_mw": 0.0, "storage_loss_mw": 0.0,
				"storage_conversion_loss_mw": 0.0, "storage_balance_error_mwh": 0.0})
			resources["charge:" + id] = limits.charge_limit_mw
			resources["discharge:" + id] = limits.discharge_limit_mw
		elif kind in ["wind", "pv"] and detail.valid:
			resources["source:" + id] = float(detail.mw)
		if Catalog.is_material(kind) and detail.valid:
			Materials.initialize_node(id, kind, p, state, step_s, detail, resources)
		elif kind in Rankine.KINDS and detail.valid:
			Rankine.initialize_node(id, kind, p, detail, resources)
		elif kind in Tower.KINDS and detail.valid:
			Tower.initialize_node(id, kind, p, state, step_s, detail, resources)
		elif Catalog.is_thermal(kind) and detail.valid:
			Thermal.initialize_node(id, kind, p, state, step_s, detail, resources)
		nodes[id] = {"id": int(raw.id), "kind": kind, "params": p, "state": state, "valid": detail.valid}
		report.devices[id] = detail
		report.generated_mw += float(detail.mw)
		report.nameplate_clipped_mw += float(detail.get("nameplate_clipped_mw", 0.0))
		if detail.valid:
			valid_devices.append(raw)
		else:
			report.errors.append("Device %s: %s" % [id, "; ".join(detail.errors)])
	# The fleet resource is independent of device instances and reset each interval.
	# Missing or disabled supply never creates fuel, and malformed input rejects commit.
	if has_fuel:
		var supplied: Variant = direct.get("_fuel_supply", {})
		var supply: Dictionary = FuelSupply.defaults()
		if supplied is Dictionary:
			supply.merge(supplied, true)
		var supply_error: String = FuelSupply.validate(supply) if supplied is Dictionary else "fuel_supply must be a dictionary"
		if not supply_error.is_empty():
			report.errors.append("Fuel supply: " + supply_error)
			supply = FuelSupply.defaults()
		report.fuel_supply = supply.duplicate(true)
		report.fuel = {"input_mw": 0.0, "volume_nm3_per_h": 0.0, "cost_per_h": 0.0,
			"heat_output_mwth": 0.0, "conversion_loss_mw": 0.0,
			"auxiliary_electric_mw": 0.0, "auxiliary_electric_loss_mw": 0.0}
		resources["fuel:supply"] = float(supply.max_input_mw) if supply.enabled else 0.0
	if has_solar:
		report.solar = Solar.empty()
	if has_tower:
		report.tower = Tower.empty()
	if has_high_temp:
		report.high_temp = HighTemp.empty()
	var accepted: Array = []
	var attachments: Dictionary = {}
	var outputs: Dictionary = {}
	for index in links.size():
		var line: Dictionary = {"index": index, "from": -2, "to": -2,
			"flow_from": -2, "flow_to": -2, "direction": 0, "signed_mw": 0.0,
			"valid": false, "reason": "Malformed link", "sent_mw": 0.0, "received_mw": 0.0,
			"loss_mw": 0.0, "capacity_mw": 0.0, "loss_fraction": 0.0,
			"carrier": Catalog.CARRIER, "utilization": 0.0, "active": false}
		report.lines.append(line)
		var raw: Variant = links[index]
		if not raw is Dictionary:
			report.warnings.append("Line %d: malformed link" % index)
			continue
		var reason: String = Catalog.validate_link(valid_devices, accepted, raw)
		if _integer(raw.get("from")):
			line.from = int(raw.from)
		if _integer(raw.get("to")):
			line.to = int(raw.to)
		if not reason.is_empty():
			line.reason = reason
			report.warnings.append("Line %d: %s" % [index, reason])
			continue
		line.merge(Catalog.connection_ports(valid_devices, raw), true)
		line.valid = true
		line.reason = ""
		if line.carrier in Catalog.Materials.CARRIERS:
			for key in ["capacity_mw", "sent_mw", "received_mw", "signed_mw", "loss_mw"]: line.erase(key)
			line.merge({"mass_flow_capacity_kg_s":float(raw.mass_flow_capacity_kg_s),"sent_kg_s":0.0,"received_kg_s":0.0,"signed_kg_s":0.0,"loss_kg_s":0.0,"flow_from":line.from,"flow_to":line.to}, true)
			line.loss_fraction = 0.0
			resources["material_line:"+str(index)] = line.mass_flow_capacity_kg_s if step_s > 0.0 else 0.0
			accepted.append(raw)
			report.devices[str(line.from)].connected = true
			report.devices[str(line.to)].connected = true
			continue
		if line.carrier == "water_steam":
			line.erase("capacity_mw")
			line.merge({"mass_flow_capacity_kg_s": float(raw.mass_flow_capacity_kg_s), "sent_kg_s": 0.0, "received_kg_s": 0.0, "signed_kg_s": 0.0, "loss_kg_s": 0.0, "enthalpy_kj_kg": Rankine.enthalpy(line.grade_id), "enthalpy_flow_mw": 0.0, "flow_from": line.from, "flow_to": line.to}, true)
			line.loss_fraction = 0.0
			resources["mass_line:" + str(index)] = line.mass_flow_capacity_kg_s
			accepted.append(raw)
			report.devices[str(line.from)].connected = true
			report.devices[str(line.to)].connected = true
			continue
		if line.carrier in [Catalog.THERMAL_CARRIER, "heat_oil", "heat_salt"]:
			line.erase("capacity_mw")
			line.merge({"capacity_mwth": float(raw.capacity_mwth), "sent_mwth": 0.0, "received_mwth": 0.0,
				"loss_mwth": 0.0, "signed_mwth": 0.0, "flow_from": line.from, "flow_to": line.to}, true)
			line.loss_fraction = 0.0
			resources["heat_line:" + str(index)] = line.capacity_mwth
			accepted.append(raw)
			report.devices[str(line.from)].connected = true
			report.devices[str(line.to)].connected = true
			continue
		line.capacity_mw = float(raw.get("capacity_mw", 4.0))
		line.loss_fraction = float(raw.get("loss_fraction", 0.01))
		line.flow_from = line.from
		line.flow_to = line.to
		resources["line:" + str(index)] = line.capacity_mw
		accepted.append(raw)
		var a: String = str(line.from)
		var b: String = str(line.to)
		report.devices[a].connected = true
		if nodes.has(b):
			report.devices[b].connected = true
		var station_id: String = a if Catalog.is_electric_station(nodes[a].kind) else b
		var leaf_id: String = b if Catalog.is_electric_station(nodes[a].kind) else a
		if not outputs.has(station_id):
			outputs[station_id] = []
		if leaf_id == "-1" or nodes[leaf_id].kind in ["electrolyzer_station", "hydrogen_gas_store", "hydrogen_liquid_store", "hydrogen_metal_hydride_store", "ammonia_synthesis_station", "methanol_synthesis_station", "load", "battery", "battery_sodium", "battery_flow", "caes_aboveground", "liquid_air_store", "hydrogen_storage_system", "co2_liquid_cycle_store", "electric_boiler", "fuel_boiler", "solar_thermal", "parabolic_trough", "oil_water_exchanger", "steam_generator", "steam_condenser", "feedwater_pump", "salt_steam_generator", "solar_tower_receiver", "molten_salt_store"]:
			outputs[station_id].append({"id": leaf_id, "line": index})
		if leaf_id != "-1" and nodes[leaf_id].kind in ["fuel_cell_station", "wind", "pv", "battery", "battery_sodium", "battery_flow", "caes_aboveground", "liquid_air_store", "hydrogen_storage_system", "co2_liquid_cycle_store", "steam_turbine"]:
			attachments[leaf_id] = {"station": station_id, "line": index}
	var paths: Array = []
	for source_id in _sorted_ids(attachments):
		var source: Dictionary = nodes[source_id]
		var attach: Dictionary = attachments[source_id]
		var station_id: String = attach.station
		var incoming: Dictionary = report.lines[attach.line]
		var targets: Array = outputs.get(station_id, []).duplicate()
		targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.id) < int(b.id))
		for target in targets:
			var sink_id: String = target.id
			var sink_kind: String = "grid" if sink_id == "-1" else str(nodes[sink_id].kind)
			if source.kind == "fuel_cell_station" and sink_kind != "load": continue
			if sink_kind in ["electrolyzer_station", "hydrogen_gas_store"] and not source.kind in ["wind", "pv"]: continue
			if Catalog.is_electric_storage(source.kind) and not sink_kind in ["hydrogen_liquid_store", "hydrogen_metal_hydride_store", "ammonia_synthesis_station", "methanol_synthesis_station", "load", "electric_boiler", "fuel_boiler", "solar_thermal", "parabolic_trough", "oil_water_exchanger", "steam_generator", "steam_condenser", "feedwater_pump", "salt_steam_generator", "solar_tower_receiver", "molten_salt_store"]:
				continue # No battery-to-battery cycling or discharge for export.
			if source.kind == "steam_turbine" and not sink_kind in ["load", "battery", "battery_sodium", "battery_flow", "caes_aboveground", "liquid_air_store", "hydrogen_storage_system", "co2_liquid_cycle_store", "grid"]:
				continue
			var outgoing: Dictionary = report.lines[target.line]
			var arriving: float = 1.0 - incoming.loss_fraction
			var after_station: float = arriving * (1.0 - float(nodes[station_id].params.loss_fraction))
			var received: float = after_station * (1.0 - outgoing.loss_fraction)
			var coeffs: Dictionary = {}
			coeffs[("discharge:" if Catalog.is_electric_storage(source.kind) else "source:") + source_id] = 1.0
			coeffs["line:" + str(attach.line)] = 1.0
			coeffs["station:" + station_id] = arriving
			coeffs["line:" + str(target.line)] = after_station
			coeffs[("material_aux:"+sink_id) if Catalog.is_material(sink_kind) else ("grid" if sink_id == "-1" else ("charge:" if Catalog.is_electric_storage(sink_kind) else ("boiler:" if sink_kind == "electric_boiler" else ("fuel_aux:" if sink_kind == "fuel_boiler" else ("rankine_aux:" if sink_kind in ["steam_generator", "steam_condenser", "feedwater_pump", "salt_steam_generator"] else ("solar_aux:" if sink_kind in ["solar_thermal", "parabolic_trough", "oil_water_exchanger", "solar_tower_receiver", "molten_salt_store"] else "load:"))))) + sink_id)] = received
			paths.append({"source_id": source_id, "source_kind": source.kind,
				"station_id": station_id, "sink_id": sink_id, "sink_kind": sink_kind,
				"incoming": int(attach.line), "outgoing": int(target.line),
				"arriving": arriving, "after_station": after_station, "received": received,
				"coefficients": coeffs})
	return {"report": report, "nodes": nodes, "resources": resources, "paths": paths, "raw_links": links.duplicate(true), "weather": weather.duplicate(true)}

static func _record_line(line: Dictionary, from_id: int, to_id: int, sent: float, received: float) -> void:
	line.flow_from = from_id
	line.flow_to = to_id
	line.direction = 1 if line.from == from_id else -1
	line.sent_mw += sent
	line.received_mw += received
	line.loss_mw += sent - received
	line.signed_mw = line.direction * line.sent_mw

static func _allocate(path: Dictionary, resources: Dictionary, report: Dictionary, maximum: float = INF) -> float:
	var sent: float = maximum
	for key in path.coefficients:
		var coefficient: float = path.coefficients[key]
		if coefficient > 0.0:
			sent = minf(sent, maxf(0.0, float(resources[key])) / coefficient)
	if not is_finite(sent) or sent <= EPS:
		return 0.0
	for key in path.coefficients:
		resources[key] = maxf(0.0, resources[key] - sent * path.coefficients[key])
	var arriving: float = sent * path.arriving
	var after_station: float = sent * path.after_station
	var received: float = sent * path.received
	var source: Dictionary = report.devices[path.source_id]
	var station: Dictionary = report.devices[path.station_id]
	source.sent_mw += sent
	source.output_mw += sent
	source.loss_mw += sent - received
	if Catalog.is_electric_storage(path.source_kind):
		source.discharge_mw += sent
		source.mode = "discharge"
	station.input_mw += arriving
	station.received_mw += arriving
	station.output_mw += after_station
	station.sent_mw += after_station
	station.loss_mw += arriving - after_station
	if path.sink_kind == "grid":
		report.delivered_mw += received
		source.delivered_mw += received
		station.delivered_mw += received
	else:
		var sink: Dictionary = report.devices[path.sink_id]
		sink.input_mw += received
		sink.received_mw += received
		if path.sink_kind == "load":
			sink.served_mw += received
		elif Catalog.is_material(path.sink_kind):
			sink.electric_input_mw += received
		elif path.sink_kind == "electric_boiler":
			sink.electric_input_mw += received
		elif path.sink_kind in ["fuel_boiler", "solar_thermal", "parabolic_trough", "oil_water_exchanger", "steam_generator", "steam_condenser", "feedwater_pump", "salt_steam_generator", "solar_tower_receiver", "molten_salt_store"]:
			sink.auxiliary_electric_mw += received
		else:
			sink.charge_mw += received
			sink.mode = "charge"
	_record_line(report.lines[path.incoming], int(path.source_id), int(path.station_id), sent, arriving)
	_record_line(report.lines[path.outgoing], int(path.station_id), int(path.sink_id), after_station, received)
	return sent

static func _external_can_fill(prepared: Dictionary, sink_id: String) -> bool:
	var trial_resources: Dictionary = prepared.resources.duplicate(true)
	var trial_report: Dictionary = prepared.report.duplicate(true)
	for path in prepared.paths:
		if path.sink_id == sink_id and path.source_kind in ["wind", "pv"]:
			_allocate(path, trial_resources, trial_report)
	var key: String = "grid" if sink_id == "-1" else ("charge:" if Catalog.is_electric_storage(prepared.nodes[sink_id].kind) else "load:") + sink_id
	return float(trial_resources.get(key, 0.0)) <= EPS

static func run(devices: Array, links: Array, weather: Dictionary, direct: Dictionary, dt_s: float, generation: Callable, validate: Callable) -> Dictionary:
	var prepared: Dictionary = _prepare(devices, links, weather, direct, dt_s, generation, validate)
	var report: Dictionary = prepared.report
	var nodes: Dictionary = prepared.nodes
	var paths: Array = prepared.paths
	var resources: Dictionary = prepared.resources
	Thermal.prepare(prepared)
	Tower.prepare(prepared)
	Rankine.prepare(prepared)
	Materials.prepare(prepared)
	var loads: Array = []
	for id in _sorted_ids(nodes):
		if nodes[id].valid and nodes[id].kind in ["load", "heat_demand"]:
			loads.append(id)
	loads.sort_custom(func(a: String, b: String) -> bool:
		var pa: int = int(nodes[a].params.priority)
		var pb: int = int(nodes[b].params.priority)
		return pa < pb if pa != pb else int(a) < int(b))
	if report.step_valid:
		# Each service shares electric resources by priority/id. Heat uses renewable
		# boiler output before stored heat, then gas backup and battery boiler power,
		# to avoid pointless
		# successive-step heat-storage cycling during constant renewable surplus.
		for load_id in loads:
			if nodes[load_id].kind == "heat_demand":
				Thermal.serve_solar_heat(prepared, load_id, _allocate)
				Thermal.serve_boiler_heat(prepared, load_id, _allocate, false)
				Thermal.serve_stored_heat(prepared, load_id)
				Thermal.serve_fuel_heat(prepared, load_id, _allocate)
				Thermal.serve_boiler_heat(prepared, load_id, _allocate, true)
			else:
				if report.has("rankine") and not _external_can_fill(prepared, load_id): Rankine.serve_sink(prepared, load_id, _allocate)
				var phase_enabled: bool = false
				for n in nodes.values(): phase_enabled = phase_enabled or n.kind in Catalog.Materials.PHASE_KINDS
				for storage in [false, true]:
					if storage and phase_enabled: Materials.serve_load(prepared,load_id,_allocate)
					for path in paths:
						if path.sink_id == load_id and not path.source_kind in ["steam_turbine", "fuel_cell_station"] and (Catalog.is_electric_storage(path.source_kind)) == storage:
							_allocate(path, resources, report)
				Materials.serve_load(prepared, load_id, _allocate)
		Materials.synthesize_surplus(prepared,_allocate)
		# Boiler demand was reserved/served before either kind of surplus storage.
		Thermal.charge_solar_storage(prepared, _allocate)
		Tower.charge_surplus(prepared, _allocate)
		Thermal.charge_surplus(prepared, _allocate)
		Thermal.charge_fuel_storage(prepared, _allocate)
		# Only renewable surplus may charge, with one mode per battery per step.
		for battery_id in _sorted_ids(nodes):
			if not Catalog.is_electric_storage(nodes[battery_id].kind) or not nodes[battery_id].valid or report.devices[battery_id].mode == "discharge":
				continue
			if report.has("rankine") and not _external_can_fill(prepared, battery_id): Rankine.serve_sink(prepared, battery_id, _allocate)
			for path in paths:
				if path.sink_id == battery_id and path.source_kind != "steam_turbine":
					_allocate(path, resources, report)
		Materials.charge_surplus(prepared, _allocate)
		# The grid is an explicitly cabled, finite export sink, never a fallback.
		if report.has("rankine") and not _external_can_fill(prepared, "-1"): Rankine.serve_sink(prepared, "-1", _allocate)
		for path in paths:
			if path.sink_kind == "grid" and path.source_kind != "steam_turbine":
				_allocate(path, resources, report)
	var energy_before: float = 0.0
	var energy_after: float = 0.0
	for id in _sorted_ids(nodes):
		var node: Dictionary = nodes[id]
		var d: Dictionary = report.devices[id]
		if not d.valid:
			continue
		match Catalog.dispatch_role(node.kind):
			"wind", "pv":
				d.curtailed_mw = maxf(0.0, d.mw - d.sent_mw)
				report.curtailed_mw += d.curtailed_mw
				d.utilization = d.mw / maxf(EPS, d.get("rated_mw", 1.0))
			"station":
				report.station_loss_mw += d.loss_mw
				d.utilization = d.input_mw / d.capacity_mw
			"load":
				d.unserved_mw = maxf(0.0, d.demand_mw - d.served_mw)
				d.utilization = d.served_mw / d.demand_mw if d.demand_mw > 0.0 else 1.0
				report.served_mw += d.served_mw
				report.unserved_mw += d.unserved_mw
			"battery", "battery_sodium", "battery_flow", "caes_aboveground", "liquid_air_store", "hydrogen_storage_system", "co2_liquid_cycle_store":
				var p: Dictionary = node.params
				var e: float = d.energy_after_self_discharge_mwh + (p.charge_efficiency * d.charge_mw - d.discharge_mw / p.discharge_efficiency) * report.dt_h
				d.next_energy_mwh = clampf(e, 0.0, p.capacity_mwh)
				d.soc = d.next_energy_mwh / p.capacity_mwh
				d.merge(Catalog.storage_stage_metrics(node.kind, p, d.charge_mw, d.discharge_mw, d.next_energy_mwh), true)
				d.storage_conversion_loss_mw = d.charge_mw * (1.0 - p.charge_efficiency) + d.discharge_mw * (1.0 / p.discharge_efficiency - 1.0)
				d.storage_loss_mw = d.storage_conversion_loss_mw + (d.self_discharge_mwh / report.dt_h if report.dt_h > 0.0 else 0.0)
				d.storage_balance_error_mwh = e - d.next_energy_mwh
				d.utilization = d.charge_mw / p.charge_mw if d.mode == "charge" and p.charge_mw > 0.0 else (d.discharge_mw / p.discharge_mw if p.discharge_mw > 0.0 else 0.0)
				report.next_states[id] = {"energy_mwh": d.next_energy_mwh}
				report.charge_mw += d.charge_mw
				report.discharge_mw += d.discharge_mw
				report.storage_loss_mw += d.storage_loss_mw
				report.storage_conversion_loss_mw += d.storage_conversion_loss_mw
				report.self_discharge_mwh += d.self_discharge_mwh
				report.storage_balance_error_mwh += d.storage_balance_error_mwh
				energy_before += d.energy_before_mwh
				energy_after += d.next_energy_mwh
	Rankine.finish(prepared)
	Thermal.finish(prepared)
	Tower.finish(prepared)
	Materials.finish(prepared)
	for line in report.lines:
		if line.carrier in [Catalog.THERMAL_CARRIER, "heat_oil", "heat_salt", "water_steam"] or line.carrier in Catalog.Materials.CARRIERS:
			continue
		line.active = line.sent_mw > EPS
		line.utilization = line.sent_mw / line.capacity_mw if line.capacity_mw > 0.0 else 0.0
		report.line_loss_mw += line.loss_mw
	report.loss_mw = report.line_loss_mw + report.station_loss_mw
	report.network_loss_mw = report.loss_mw
	report.total_loss_mw = report.loss_mw + report.storage_loss_mw
	report.available_mw = report.generated_mw - float(report.get("rankine", {}).get("gross_electric_mw", 0.0)) - float(report.get("material", {}).get("fuel_cell_output_mw", 0.0))
	report.produced_mw = report.generated_mw - report.curtailed_mw
	var fuel_aux: float = float(report.get("fuel", {}).get("auxiliary_electric_mw", 0.0)) + float(report.get("solar", {}).get("auxiliary_electric_mw", 0.0)) + float(report.get("high_temp", {}).get("auxiliary_electric_mw", 0.0)) + float(report.get("rankine", {}).get("auxiliary_electric_mw", 0.0)) + float(report.get("tower", {}).get("auxiliary_electric_mw", 0.0))
	fuel_aux += float(report.get("material", {}).get("electrolyzer_electric_mw", 0.0)) + float(report.get("material", {}).get("compression_electric_mw", 0.0)) + float(report.get("material", {}).get("phase_store_electric_mw",0.0)) + float(report.get("material", {}).get("chemical_electric_mw",0.0))
	report.balance_error_mw = report.generated_mw + report.discharge_mw - report.curtailed_mw - report.served_mw - report.charge_mw - report.boiler_electric_mw - fuel_aux - report.delivered_mw - report.loss_mw
	report.energy_balance_error_mwh = (report.generated_mw - report.curtailed_mw - report.served_mw - report.boiler_electric_mw - fuel_aux - report.delivered_mw - report.total_loss_mw) * report.dt_h + energy_before - energy_after
	if report.has("fuel"):
		var t: Dictionary = report.thermal
		var f: Dictionary = report.fuel
		report.cross_carrier_balance_error_mw = report.generated_mw - report.curtailed_mw + report.discharge_mw + t.discharge_mwth + f.input_mw - report.served_mw - report.charge_mw - report.delivered_mw - report.loss_mw - t.served_mwth - t.charge_mwth - t.exchanger_loss_mwth - t.network_loss_mwth - report.boiler_conversion_loss_mw - f.conversion_loss_mw - f.auxiliary_electric_loss_mw
	if report.has("solar") and report.has("cross_carrier_balance_error_mw"):
		report.cross_carrier_balance_error_mw += report.solar.useful_mwth - report.solar.auxiliary_electric_mw
	elif report.has("solar"):
		var t: Dictionary = report.thermal
		var s: Dictionary = report.solar
		report.cross_carrier_balance_error_mw = report.generated_mw - report.curtailed_mw + report.discharge_mw + t.discharge_mwth + s.incident_mw - report.served_mw - report.charge_mw - report.delivered_mw - report.loss_mw - t.served_mwth - t.charge_mwth - t.exchanger_loss_mwth - t.network_loss_mwth - report.boiler_conversion_loss_mw - s.optical_rejection_mw - s.thermal_loss_mw - s.curtailed_mwth - s.auxiliary_electric_mw
	if report.has("high_temp"):
		var h: Dictionary = report.high_temp
		if report.has("cross_carrier_balance_error_mw"):
			report.cross_carrier_balance_error_mw += h.oil_water_output_mwth - h.auxiliary_electric_mw
		else:
			report.cross_carrier_balance_error_mw = report.balance_error_mw + report.thermal.balance_error_mwth + h.balance_error_mwth
	if report.has("rankine"):
		report.cross_carrier_balance_error_mw = report.balance_error_mw + report.thermal.balance_error_mwth + float(report.get("high_temp", {}).get("balance_error_mwth", 0.0)) + report.rankine.balance_error_mw
	if report.has("tower"):
		report.cross_carrier_balance_error_mw = report.balance_error_mw + report.thermal.balance_error_mwth + float(report.get("high_temp", {}).get("balance_error_mwth", 0.0)) + float(report.get("rankine", {}).get("balance_error_mw", 0.0)) + report.tower.balance_error_mwth
	if report.has("material"):
		report.cross_carrier_balance_error_mw = report.balance_error_mw + report.thermal.balance_error_mwth + float(report.get("high_temp", {}).get("balance_error_mwth", 0.0)) + float(report.get("rankine", {}).get("balance_error_mw", 0.0)) + float(report.get("tower", {}).get("balance_error_mwth", 0.0)) + report.material.enthalpy_balance_error_mw
	report.audit_errors = Thermal.audit(prepared)
	report.errors.append_array(report.audit_errors)
	report.valid = report.errors.is_empty() and report.warnings.is_empty()
	report.commit_allowed = report.valid and report.step_valid
	for key in ["generated", "delivered", "curtailed", "loss", "balance_error", "served", "unserved", "charge", "discharge"]:
		report[key] = report[key + "_mw"]
	report.net_mw = report.delivered_mw
	return report

## The same device limits, explicit edges and path coefficient rows used by run().
## A backend must enforce storage mode exclusivity and independently validate any
## result before applying it. This API only exports data; it invokes no solver.
static func optimization_snapshot(devices: Array, links: Array, weather: Dictionary, direct: Dictionary, dt_s: float, generation: Callable, validate: Callable, context: Dictionary = {}) -> Dictionary:
	var prepared: Dictionary = _prepare(devices, links, weather, direct, dt_s, generation, validate)
	Thermal.prepare(prepared)
	Tower.prepare(prepared)
	Rankine.prepare(prepared)
	Materials.prepare(prepared)
	var report: Dictionary = prepared.report
	var has_heat: bool = bool(report.get("thermal_enabled", false))
	var entries: Array = []
	var all_ports: Array = []
	var initial_states: Dictionary = {}
	for id in _sorted_ids(prepared.nodes):
		var node: Dictionary = prepared.nodes[id]
		if not node.valid:
			continue
		var entry: Dictionary = node.duplicate(true)
		entry.ports = Catalog.ports(node.kind)
		if Catalog.is_storage(node.kind): entry.storage_technology = Catalog.storage_technology(node.kind)
		if node.kind == Catalog.COLLECTOR_KIND:
			entry.model_profile = Catalog.COLLECTOR_PROFILE
			entry.model_profile_version = 1
		if node.kind == Catalog.CO2_STORAGE_KIND:
			entry.model_profile = Catalog.CO2_STORAGE_PROFILE
			entry.model_profile_version = 1
		if Catalog.is_material(node.kind):
			entry.model_profile = Catalog.Materials.model_profile(node.kind)
			entry.model_profile_version = Catalog.Materials.model_profile_version(node.kind)
		if Catalog.is_thermal(node.kind):
			entry.model_profile = Catalog.model_profile(node.kind)
			entry.model_profile_version = Catalog.THERMAL_PROFILE_VERSION
		entry.available_mw = report.devices[id].mw
		if node.kind == "solar_tower_receiver":
			entry.available_mwth = report.devices[id].available_mwth
			entry.tower_physics = Tower.evaluate(node.params, weather)
		if node.kind == "parabolic_trough":
			entry.available_mwth = report.devices[id].available_mwth
			entry.high_temp_physics = HighTemp.evaluate(node.params, weather)
		if node.kind == "solar_thermal":
			entry.available_mwth = report.devices[id].available_mwth
			entry.solar_physics = Solar.evaluate(node.params, weather)
		for p in entry.ports:
			var typed_port: Dictionary = p.duplicate(true)
			typed_port.device_id = node.id
			all_ports.append(typed_port)
		if Catalog.is_material_inventory(node.kind):
			initial_states[id] = node.state.duplicate(true)
			entry.mode_options = ["idle", "charge", "discharge"] if node.kind in Catalog.Materials.HYDROGEN_STORE_KINDS else ["idle", "supply"]
		if Catalog.is_electric_storage(node.kind):
			initial_states[id] = node.state.duplicate(true)
			entry.storage_limits = Catalog.storage_limits(node.params, node.state.energy_mwh, report.dt_s)
			entry.mode_options = ["idle", "charge", "discharge"]
		elif node.kind in ["thermal_store", "solid_thermal_store", "high_temp_store", "molten_salt_store"]:
			initial_states[id] = node.state.duplicate(true)
			entry.storage_limits = Catalog.thermal_storage_limits(node.params, node.state.energy_mwhth, report.dt_s)
			entry.mode_options = ["idle", "charge", "discharge"]
		entries.append(entry)
	var edges: Array = []
	for line in report.lines:
		if line.valid:
			if line.carrier in Catalog.Materials.CARRIERS:
				edges.append({"id": "line:" + str(line.index), "from": line.from, "to": line.to, "from_port": line.from_port, "to_port": line.to_port, "carrier": line.carrier, "unit": "kg/s", "species_id": line.species_id, "phase_id": line.phase_id, "grade_id": line.grade_id, "mass_flow_capacity_kg_s": line.mass_flow_capacity_kg_s, "loss_fraction": 0.0, "bidirectional": false})
				continue
			if line.carrier == "water_steam":
				edges.append({"id": "line:" + str(line.index), "from": line.from, "to": line.to, "from_port": line.from_port, "to_port": line.to_port, "carrier": line.carrier, "unit": "kg/s", "grade_id": line.grade_id, "mass_flow_capacity_kg_s": line.mass_flow_capacity_kg_s, "loss_fraction": 0.0, "bidirectional": false})
				continue
			if line.carrier in [Catalog.THERMAL_CARRIER, "heat_oil", "heat_salt"]:
				edges.append({"id": "line:" + str(line.index), "from": line.from, "to": line.to,
					"from_port": line.from_port, "to_port": line.to_port, "carrier": line.carrier,
					"unit": "MWth", "grade_id": line.grade_id, "capacity_mwth": line.capacity_mwth,
					"loss_fraction": 0.0, "bidirectional": false})
				continue
			edges.append({"id": "line:" + str(line.index), "from": line.from, "to": line.to,
				"from_port": line.from_port, "to_port": line.to_port, "carrier": line.carrier,
				"unit": "MW", "voltage_level": Catalog.VOLTAGE_LEVEL,
				"capacity_mw": line.capacity_mw, "loss_fraction": line.loss_fraction,
				"bidirectional": Catalog.is_electric_storage(prepared.nodes[str(line.from)].kind) or (line.to != -1 and Catalog.is_electric_storage(prepared.nodes[str(line.to)].kind))})
	var snapshot: Dictionary = {"schema_version": 2, "device_catalog_version": Catalog.SCHEMA_VERSION if report.has("fuel_supply") else 2,
		"request_id": str(context.get("request_id", "")), "scene_revision": context.get("scene_revision", 0),
		"simulation_time": context.get("simulation_time", 0.0), "dt_s": report.dt_s, "dt_h": report.dt_h,
		"horizon": 1, "status": "snapshot_only", "solver_invoked": false,
		"valid": report.errors.is_empty() and report.warnings.is_empty(), "errors": report.errors, "warnings": report.warnings,
		"model": report.model, "units": {"power": "MW", "storage_energy": "MWh", "heat_power": "MWth", "thermal_storage_energy": "MWhth", "time": "seconds"},
		"devices": entries, "ports": all_ports, "edges": edges,
		"grid_boundary": {"id": -1, "ports": Catalog.ports("grid"), "import_limit_mw": 0.0,
			"export_limit_mw": Catalog.GRID_CAPACITY_MW, "requires_explicit_edge": true},
		"initial_states": initial_states, "forecasts": {"weather": weather.duplicate(true), "direct_ac_power": direct.duplicate(true)},
		"objective": {"policy": report.dispatch_policy, "load_priority": "lower_first",
			"order": ["serve_electric_and_heat_by_priority_then_stable_id", "heat_uses_renewable_boilers_then_stored_heat_then_battery_boilers", "charge_heat_with_renewable_surplus", "charge_battery_with_renewable_surplus", "export_renewable_surplus", "curtail"] if has_heat else ["serve_load_by_priority", "charge_with_renewable_surplus", "export_renewable_surplus", "curtail"],
			"economic_optimality_claimed": false, "forecast_optimality_claimed": false},
		"constraints": {"resource_limits": prepared.resources.duplicate(true), "paths": prepared.paths.duplicate(true),
			"thermal_paths": prepared.heat_paths.duplicate(true),
			"thermal_carrier_balance": "boiler_heat + thermal_discharge = heat_served + thermal_charge + exchanger_loss + thermal_network_loss",
			"thermal_fixed_grade_dag": has_heat, "thermal_storage_modes_mutually_exclusive": true,
			"carrier_balance": "available + discharge = curtailment + served + charge + boiler_electric + export + network_loss",
			"storage_update": "E_next = E * exp(-self_discharge_per_h * dt_h) + (charge_efficiency * charge - discharge / discharge_efficiency) * dt_h",
			"storage_modes_mutually_exclusive": true, "battery_discharge_to_grid": false,
			"battery_to_battery": false, "grid_import_mw": 0.0, "grid_export_limit_mw": Catalog.GRID_CAPACITY_MW,
			"terminal_policy": context.get("terminal_policy", "restore_initial"),
			"application_requires_current_revision_and_independent_validation": true},
		"notes": ["Teaching defaults are assumptions, not product specifications.",
			"Explicit capacity-flow network; no voltage, phase-angle or AC power-flow claim.",
			"Snapshot export only. No external solver is invoked."]}

	if report.has("fuel_supply"):
		snapshot.fuel_supply = report.fuel_supply.duplicate(true)
		snapshot.constraints.carrier_balance = "available + discharge = curtailment + served + charge + boiler_electric + fuel_auxiliary + export + network_loss"
		snapshot.constraints.thermal_carrier_balance = "electric_boiler_heat + fuel_boiler_heat + thermal_discharge = heat_served + thermal_charge + exchanger_loss + thermal_network_loss"
		snapshot.constraints.fuel_balance = "sum(fuel_input) <= enabled * max_input_mw; Q = thermal_efficiency * F; P_aux = auxiliary_electric_ratio * F"
		snapshot.constraints.fuel_inventory = false
		snapshot.objective.order = ["serve_electric_and_heat_by_priority_then_stable_id", "heat_uses_renewable_electric_boilers_then_stored_heat_then_fuel_then_battery_electric_boilers", "charge_heat_with_renewable_surplus", "charge_heat_with_remaining_fuel_and_renewable_auxiliary", "charge_battery_with_renewable_surplus", "export_renewable_surplus", "curtail"]
		snapshot.notes.append("Natural gas LHV resource shared across the fleet per interval; mandatory AC auxiliary is dissipated separately. No fuel inventory or steam model.")
	if report.has("solar"):
		snapshot.device_catalog_version = Catalog.SCHEMA_VERSION
		snapshot.constraints.solar_heat = "0 <= Q <= absorber-area POA curve; auxiliary AC = auxiliary_electric_ratio * Q"
		snapshot.objective.order.insert(1, "solar_heat_before_electric_boilers_with_renewable_then_battery_auxiliary; storage_renewable_auxiliary_only")
	if report.has("high_temp"):
		snapshot.schema_version = 4
		snapshot.device_catalog_version = Catalog.SCHEMA_VERSION
		snapshot.constraints.high_temp_balance = "trough_useful + oil_discharge = oil_charge + oil_water_output + oil_exchanger_loss"
		snapshot.constraints.trough_heat = "explicit DNI and solar geometry; aperture N-S horizontal one-axis; mandatory auxiliary AC"
	if report.has("rankine"):
		snapshot.schema_version = 5
		if report.has("fuel"):
			for i in snapshot.notes.size():
				if "No fuel inventory or steam model" in str(snapshot.notes[i]): snapshot.notes[i] = "Natural gas LHV shared per interval. Gas boilers provide hot water only; the separate Rankine loop uses fixed steam states with no dynamic steam inventory."
		snapshot.constraints.rankine = "fixed-state closed mass loop; external-only auxiliaries; turbine output to load/battery/export; shared oil draw once"
	if report.has("tower"):
		snapshot.schema_version = 6
		snapshot.device_catalog_version = Catalog.SCHEMA_VERSION
		snapshot.tower_profile = "tower_stage1_v1"
		snapshot.constraints.tower_charge_paths = prepared.get("tower_charge_paths", []).duplicate(true)
		snapshot.constraints.tower_balance = "receiver_useful + salt_discharge = salt_charge + rankine_salt_input; independent 565/290 C preheated molten-salt inventory"
		snapshot.notes.append("Tower salt uses an isolated salt-to-steam generator feeding the unchanged 1 MPa/280 C teaching Rankine cycle; this low-pressure cycle does not exploit the full efficiency potential of 565 C salt. No freeze protection or cold-start model.")
	if entries.any(func(d): return d.kind in Catalog.NEW_STORAGE_KINDS):
		snapshot.schema_version = 7
		snapshot.constraints.storage_discharge_to_grid = false
		snapshot.constraints.storage_to_storage = false
		snapshot.notes.append("Expanded storage uses finite net-efficiency inventories, not pressure/temperature/electrochemical transients. Hydrogen is an integrated electrolyzer-storage-fuel-cell facility on LHV basis; all input and output stage losses are counted.")
	if entries.any(func(d): return Catalog.is_material(d.kind)):
		snapshot.schema_version = 8
		snapshot.device_catalog_version = Catalog.SCHEMA_VERSION
		snapshot.units.material_flow = "kg/s"
		snapshot.units.material_inventory = "kg"
		snapshot.material_profile = Catalog.Materials.PROFILE_ID
		snapshot.material_profile_version = Catalog.Materials.PROFILE_VERSION
		snapshot.constraints.material_inventory = "finite kg; typed kg/s; start-step leakage; mutually exclusive gas charge/discharge; no same-step hydrogen pass-through"
	if entries.any(func(d): return d.kind == Catalog.CO2_STORAGE_KIND):
		snapshot.schema_version = 9
		snapshot.co2_storage_profile = Catalog.CO2_STORAGE_PROFILE
		snapshot.notes.append(Catalog.storage_technology(Catalog.CO2_STORAGE_KIND).assumptions)
	if entries.any(func(d): return d.kind == Catalog.COLLECTOR_KIND):
		snapshot.schema_version = 10
		snapshot.collector_profile = Catalog.COLLECTOR_PROFILE
		snapshot.notes.append("Collector is a 200 MW bounded active-power star hub; no station cascade, voltage/power-flow or transformer transient model. Default 1% loss is a teaching assumption.")
	if entries.any(func(d): return d.kind in Catalog.Materials.PHASE_KINDS):
		snapshot.schema_version = 11
		snapshot.material_profile = Catalog.Materials.PHASE_PROFILE_ID
		snapshot.material_profile_version = Catalog.Materials.PHASE_PROFILE_VERSION
		snapshot.constraints.phase_hydrogen = "Fixed phase/binding enthalpy, finite external AC/ambient heat, start-step boiloff, exclusive charge/discharge; no store-to-store transfer"
	if entries.any(func(d): return d.kind in Catalog.Materials.CHEMICAL_KINDS):
		snapshot.schema_version = 12
		snapshot.material_profile = Catalog.Materials.CHEMICAL_PROFILE_ID
		snapshot.material_profile_version = Catalog.Materials.CHEMICAL_PROFILE_VERSION
		snapshot.constraints.chemical_products = "Finite prepared N2/CO2 gas, actual H2/AC/electric heat/cooling, finite NH3gas/CH3OHliquid buffers, explicit terminal product floor; no sales or power"
	return snapshot

## Independent replay audit, usable for tests and transaction-application gates.
static func audit_result(devices: Array, links: Array, report: Dictionary, generation: Callable, validate: Callable, fuel_supply: Dictionary = {}, weather: Dictionary = {}, original_direct: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	for key in ["dt_s", "dt_h", "generated_mw", "discharge_mw", "curtailed_mw", "served_mw", "charge_mw", "delivered_mw", "loss_mw", "boiler_electric_mw", "boiler_conversion_loss_mw"]:
		if not _number(report.get(key)):
			errors.append("Independent audit: missing/nonfinite " + key)
	if not errors.is_empty(): return errors
	var audit_direct: Dictionary = original_direct.duplicate(true)
	if report.has("fuel_supply") or not fuel_supply.is_empty():
		audit_direct["_fuel_supply"] = fuel_supply if not fuel_supply.is_empty() else report.get("fuel_supply")
	for device in devices:
		if device.get("kind") in ["solar_thermal", "parabolic_trough", "solar_tower_receiver"] and weather.is_empty():
			return ["Independent audit: original solar weather required"]
	var prepared: Dictionary = _prepare(devices, links, weather, audit_direct, float(report.dt_s), generation, validate)
	Rankine.prepare(prepared)
	Materials.prepare(prepared)
	for e in prepared.report.errors: errors.append(str(e))
	for e in prepared.report.warnings: errors.append(str(e))
	if not errors.is_empty(): return errors
	if not report.get("devices") is Dictionary or not report.get("lines") is Array or not report.get("thermal") is Dictionary or not report.get("next_states") is Dictionary:
		errors.append("Independent audit: incomplete report")
		return errors
	if report.lines.size() != links.size() or report.devices.size() != prepared.nodes.size():
		errors.append("Independent audit: changed device or edge set")
		return errors
	var storage_count: int = 0
	for id in prepared.nodes:
		var n: Dictionary = prepared.nodes[id]
		if not report.devices.get(id) is Dictionary:
			errors.append("Independent audit: missing device " + id)
			continue
		for field in prepared.report.devices[id]:
			if n.kind in ["wind", "pv"] and not field in ["mw", "generated_mw", "curtailed_mw", "input_mw", "output_mw", "sent_mw", "received_mw"]:
				continue
			if _number(prepared.report.devices[id][field]) and not _number(report.devices[id].get(field)):
				errors.append("Independent audit: missing/nonfinite device field " + id + ":" + field)
		if Catalog.is_storage(n.kind) or Catalog.is_material_inventory(n.kind):
			storage_count += 1
			errors.append_array(Catalog.validate_state(n.kind, n.params, report.next_states.get(id)))
	if storage_count != report.next_states.size(): errors.append("Independent audit: unexpected storage state set")
	for i in report.lines.size():
		var line: Variant = report.lines[i]
		if not line is Dictionary:
			errors.append("Independent audit: malformed line")
			continue
		for field in prepared.report.lines[i]:
			if not line.has(field):
				errors.append("Independent audit: missing line field " + field)
			elif _number(prepared.report.lines[i][field]) and not _number(line[field]):
				errors.append("Independent audit: nonfinite line field " + field)
		if line.get("index") != i or line.get("valid") != true:
			errors.append("Independent audit: changed edge index/validity")
		if prepared.report.has("material") or prepared.report.has("high_temp") or prepared.report.has("tower"):
			for field in ["from", "to", "carrier", "from_port", "to_port", "unit", "grade_id"]:
				if line.get(field) != prepared.report.lines[i].get(field): errors.append("Independent audit: changed original edge metadata " + field)
		if prepared.report.lines[i].carrier in Catalog.Materials.CARRIERS:
			for field in ["species_id", "phase_id"]:
				if line.get(field) != prepared.report.lines[i].get(field): errors.append("Independent audit: changed material " + field)
		for field in ["carrier", "from_port", "to_port", "unit", "grade_id"]:
			if not line.get(field) is String:
				errors.append("Independent audit: malformed line type metadata")
	for key in ["boiler_heat_mwth", "served_mwth", "charge_mwth", "discharge_mwth", "energy_mwhth", "demand_mwth", "unserved_mwth", "exchanger_loss_mwth", "network_loss_mwth", "self_discharge_mwhth", "storage_conversion_loss_mwth"]:
		if not _number(report.thermal.get(key)): errors.append("Independent audit: malformed thermal aggregate " + key)
	if not errors.is_empty(): return errors
	if prepared.report.has("fuel"):
		if not report.get("fuel") is Dictionary or not report.get("fuel_supply") is Dictionary:
			errors.append("Independent audit: missing fuel report or supply")
		else:
			for key in prepared.report.fuel:
				if not _number(report.fuel.get(key)): errors.append("Independent audit: missing/nonfinite fuel aggregate " + key)
			if report.fuel_supply != prepared.report.fuel_supply: errors.append("Independent audit: fuel supply differs from original resource")
		if not errors.is_empty(): return errors
	elif report.has("fuel") or report.has("fuel_supply"):
		return ["Independent audit: unexpected fuel metadata without fuel devices"]
	if prepared.report.has("solar"):
		if not report.get("solar") is Dictionary: return ["Independent audit: missing solar aggregate"]
		for key in Solar.FIELDS:
			if not _number(report.solar.get(key)): errors.append("Independent audit: missing/nonfinite solar aggregate " + key)
	elif report.has("solar"):
		errors.append("Independent audit: unexpected solar metadata")
	if not errors.is_empty(): return errors
	if prepared.report.has("high_temp"):
		if not report.get("high_temp") is Dictionary: return ["Independent audit: missing high temperature aggregate"]
		for key in HighTemp.empty():
			if not _number(report.high_temp.get(key)): errors.append("Independent audit: missing/nonfinite high temperature " + key)
	elif report.has("high_temp"):
		errors.append("Independent audit: unexpected high temperature aggregate")
	if not errors.is_empty(): return errors
	if prepared.report.has("rankine"):
		if not report.get("rankine") is Dictionary: return ["Independent audit: missing Rankine aggregate"]
		for key in Rankine.empty():
			if not _number(report.rankine.get(key)): errors.append("Independent audit: missing/nonfinite Rankine " + key)
	elif report.has("rankine"):
		errors.append("Independent audit: unexpected Rankine aggregate")
	if not errors.is_empty(): return errors
	if prepared.report.has("tower"):
		if not report.get("tower") is Dictionary: return ["Independent audit: missing tower aggregate"]
		for key in Tower.empty():
			if not _number(report.tower.get(key)): errors.append("Independent audit: missing/nonfinite tower " + key)
		if prepared.report.has("rankine") and not _number(report.rankine.get("salt_input_mwth")): errors.append("Independent audit: missing Rankine salt input")
	elif report.has("tower"):
		errors.append("Independent audit: unexpected tower aggregate")
	if not errors.is_empty(): return errors
	if prepared.report.has("material"):
		if not report.get("material") is Dictionary: return ["Independent audit: missing material aggregate"]
		for key in Materials.FIELDS:
			if not _number(report.material.get(key)): errors.append("Independent audit: missing/nonfinite material " + key)
	elif report.has("material"):
		errors.append("Independent audit: unexpected material aggregate")
	if not errors.is_empty(): return errors
	prepared.report = report
	return Thermal.audit(prepared)

## Whole-horizon, read-only second audit, before displaying a solver result.
## Replay original inputs and original coefficients; no solver-authored residual
## or Python "validation.valid" flag can replace this check.
static func audit_optimization_result(request: Dictionary, result: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not _integer(request.get("schema_version")) or not _integer(result.get("schema_version")) or result.get("schema_version") != request.get("schema_version"): return ["Optimization schema differs from frozen request"]
	if not request.get("devices") is Array or not request.get("links") is Array or not request.get("steps") is Array or not result.get("steps") is Array: return ["Incomplete optimization request/result"]
	if result.steps.size() != request.steps.size() or request.steps.is_empty(): return ["Optimization step count differs from frozen request"]
	if not result.get("initial_states") is Dictionary or not result.get("final_states") is Dictionary: return ["Optimization initial/final inventories missing"]
	var model: GDScript = load("res://scripts/energy_model.gd")
	var fleet: Array = request.devices.duplicate(true)
	var initial: Dictionary = {}
	var material_totals: Dictionary = Materials.initial_energy_v1()
	var material_bounds: Dictionary = {"initial_hydrogen_kg":0.0,"final_hydrogen_kg":0.0,"initial_water_kg":0.0,"final_water_kg":0.0}
	var has_material: bool = false
	var has_co2: bool = false
	var has_collector: bool = false
	var has_phase: bool = false
	var has_chemical: bool = false
	var ids: Dictionary = {}
	for d in fleet:
		if not d is Dictionary or not _integer(d.get("id")) or not d.get("kind") is String or not d.get("params",{}) is Dictionary: return ["Malformed frozen device"]
		var id: String = str(int(d.id))
		if ids.has(id): return ["Duplicate frozen device"]
		ids[id] = true
		if d.kind == Catalog.CO2_STORAGE_KIND:
			has_co2 = true
			if not int(request.schema_version) in [9,10,11,12]: return ["CO2 storage requires optimization schema9 or schema10"]
			if d.get("model_profile",Catalog.CO2_STORAGE_PROFILE) != Catalog.CO2_STORAGE_PROFILE or d.get("model_profile_version",1) != 1: return ["Unsupported original CO2 storage profile"]
		if d.kind == Catalog.COLLECTOR_KIND:
			has_collector = true
			if not int(request.schema_version) in [10,11,12]: return ["Collector requires optimization schema10 or11"]
			if d.get("model_profile",Catalog.COLLECTOR_PROFILE) != Catalog.COLLECTOR_PROFILE or d.get("model_profile_version",1) != 1: return ["Unsupported original collector profile"]
		var parameters: Dictionary = Catalog.defaults(d.kind)
		parameters.merge(d.get("params",{}),true)
		d.params = parameters
		var validation: Array = model.validate(d.kind,d.get("params",{}))
		if not validation.is_empty(): errors.append_array(validation)
		var state: Variant = d.get("state",Catalog.initial_state(d.kind,d.get("params",{})))
		errors.append_array(Catalog.validate_state(d.kind,d.get("params",{}),state))
		if not errors.is_empty(): return errors
		if d.kind in Catalog.Materials.PHASE_KINDS:
			has_phase = true
			if not int(request.schema_version) in [11,12]: return ["Phase hydrogen requires optimization schema11 or12"]
		if d.kind in Catalog.Materials.CHEMICAL_KINDS:
			has_chemical = true
			if request.schema_version != 12: return ["Chemical facilities require optimization schema12"]
		if Catalog.is_material(d.kind) and (not d.get("model_profile",Catalog.model_profile(d.kind)) is String or d.get("model_profile",Catalog.model_profile(d.kind)) != Catalog.model_profile(d.kind) or not _number(d.get("model_profile_version",Catalog.model_profile_version(d.kind))) or d.get("model_profile_version",Catalog.model_profile_version(d.kind)) != Catalog.model_profile_version(d.kind)): return ["Unsupported original material process profile"]
		has_material = has_material or Catalog.is_material(d.kind)
		if d.kind == "water_supply_boundary" or d.kind in Catalog.Materials.HYDROGEN_STORE_KINDS:
			material_bounds["initial_water_kg" if d.kind == "water_supply_boundary" else "initial_hydrogen_kg"] += float(state.material_inventory_kg[Catalog.Materials.species(d.kind)])
		if Catalog.is_storage(d.kind) or Catalog.is_material_inventory(d.kind):
			initial[id] = state.duplicate(true)
			d.state = state.duplicate(true)
	if not errors.is_empty(): return errors
	if has_material and float(request.get("schema_version",0))<8: return ["Material facilities require optimization schema8 or later"]
	if request.get("schema_version")==8 and not has_material: return ["Optimization schema8 requires material facilities"]
	if request.get("schema_version")==9 and not has_co2: return ["Optimization schema9 requires CO2 storage"]
	if request.get("schema_version")==10 and not has_collector: return ["Optimization schema10 requires collector"]
	if request.get("schema_version")==11 and not has_phase: return ["Optimization schema11 requires phase hydrogen stores"]
	if request.get("schema_version")==12 and not has_chemical: return ["Optimization schema12 requires chemical facilities"]
	if has_phase or has_chemical:
		var profile: String = Catalog.Materials.CHEMICAL_PROFILE_ID if has_chemical else Catalog.Materials.PHASE_PROFILE_ID
		var version: int = 3 if has_chemical else 2
		for envelope in [request,result]:
			if not envelope.get("material_profile") is String or envelope.material_profile != profile or not _number(envelope.get("material_profile_version")) or envelope.material_profile_version != version: return ["Material top-level profile changed"]
		material_totals = Materials.initial_energy(fleet) if has_chemical else Materials.initial_energy_v2(fleet)
		if material_totals.is_empty(): return ["Cannot anchor reference-state material ledger"]
	if initial != result.initial_states: return ["Optimization initial inventories differ from original request"]
	var options: Variant = request.get("options",{})
	if not options is Dictionary or not options.get("strict_supply",false) is bool: return ["Malformed original optimization options"]
	for t in request.steps.size():
		var step: Variant = request.steps[t]
		var report: Variant = result.steps[t]
		if not step is Dictionary or not report is Dictionary or not _number(step.get("dt_h")) or float(step.dt_h)<0.0 or not _number(step.get("time_s")): return ["Malformed original/result optimization step"]
		if not _number(report.get("time_s")) or absf(float(report.time_s)-float(step.time_s))>1.0e-7: return ["Optimization interval start changed"]
		if not _number(report.get("dt_s")) or absf(float(report.dt_s)-float(step.dt_h)*3600.0)>1.0e-7: return ["Optimization interval duration changed"]
		if not step.get("available_mw") is Dictionary or not step.get("demand_mw") is Dictionary: return ["Missing original forecast maps"]
		var direct: Dictionary = {}
		for d in fleet:
			var id: String = str(int(d.id))
			if d.kind in ["wind","pv"]:
				if not _number(step.available_mw.get(id)) or float(step.available_mw[id])<0.0: return ["Invalid original renewable forecast"]
				direct[id] = {"mw":step.available_mw[id],"source":"frozen forecast"}
				if not report.get("devices") is Dictionary or not report.devices.get(id) is Dictionary or not _number(report.devices[id].get("mw")) or absf(float(report.devices[id].mw)-float(step.available_mw[id]))>2.0e-6: return ["Optimization renewable availability changed"]
			elif d.kind == "load":
				if not _number(step.demand_mw.get(id)): return ["Missing original demand forecast"]
				d.params.demand_mw = step.demand_mw[id]
			elif d.kind == "heat_demand":
				if not step.get("heat_demand_mwth") is Dictionary or not _number(step.heat_demand_mwth.get(id)): return ["Missing original heat forecast"]
				d.params.demand_mwth = step.heat_demand_mwth[id]
		var seed: Dictionary = _prepare(fleet,request.links,step.get("weather",{}),direct,float(report.dt_s),Callable(model,"generation"),Callable(model,"validate"))
		var audit_report: Dictionary = _optimization_report_aliases(seed,report,errors)
		if not errors.is_empty(): return errors
		var step_errors: Array[String] = audit_result(fleet,request.links,audit_report,Callable(model,"generation"),Callable(model,"validate"),request.get("fuel_supply",{}),step.get("weather",{}),direct)
		for message in step_errors: errors.append("Step %d: %s" % [t,message])
		if not errors.is_empty(): return errors
		if options.get("strict_supply",false):
			if not _number(report.get("unserved_mw")) or float(report.unserved_mw)>2e-6 or float(report.thermal.unserved_mwth)>2e-6: return ["Original strict-supply requirement violated"]
		if has_material:
			material_totals = Materials.accumulate_energy(material_totals,report,float(report.dt_s))
			if material_totals.is_empty(): return ["Optimization material cumulative ledger failed"]
		var reconstructed: Dictionary = Materials.reconstruct_next_states(fleet,request.links,audit_report) if has_material else {}
		for d in fleet:
			var id: String = str(int(d.id))
			if reconstructed.has(id): d.state = reconstructed[id].duplicate(true)
			elif initial.has(id): d.state = report.next_states[id].duplicate(true)
	if has_material:
		for d in fleet:
			if d.kind == "water_supply_boundary" or d.kind in Catalog.Materials.HYDROGEN_STORE_KINDS: material_bounds["final_water_kg" if d.kind == "water_supply_boundary" else "final_hydrogen_kg"] += float(d.state.material_inventory_kg[Catalog.Materials.species(d.kind)])
		if has_phase or has_chemical:
			var numeric_totals: Dictionary = Materials.initial_energy_v1()
			numeric_totals.phase_store_electric_mwh = 0.0
			numeric_totals.environment_heat_in_mwhth = 0.0
			if has_chemical:
				for key in ["chemical_electric_mwh","ammonia_produced_kg","methanol_produced_kg","nitrogen_withdrawn_kg","co2_withdrawn_kg","chemical_hydrogen_consumed_kg","chemical_water_released_kg"]: numeric_totals[key] = 0.0
			for key in numeric_totals: numeric_totals[key] = material_totals[key]
			material_totals = numeric_totals
		material_totals.merge(material_bounds,true)
		if not result.get("totals") is Dictionary or not result.totals.get("material") is Dictionary or result.totals.material.size() != material_totals.size(): return ["Optimization material totals incomplete"]
		for key in material_totals:
			var actual: Variant = result.totals.material.get(key)
			if not _number(actual) or absf(float(actual)-float(material_totals[key]))>2e-6+2e-12*absf(float(material_totals[key])): errors.append("Optimization material total changed: "+key)
	if result.final_states != result.steps[-1].next_states: errors.append("Optimization final inventories differ from audited final step")
	for d in fleet:
		if not Catalog.is_storage(d.kind): continue
		var heat: bool = Catalog.is_thermal_storage(d.kind)
		var floor_value: Variant = options.get("terminal_heat_soc_fraction" if heat else "terminal_soc_fraction")
		if floor_value == null: continue
		if not _number(floor_value) or float(floor_value)<0 or float(floor_value)>1: return ["Malformed original terminal SOC target"]
		var field: String = "energy_mwhth" if heat else "energy_mwh"
		var capacity: String = "capacity_mwhth" if heat else "capacity_mwh"
		if float(d.state[field])+2e-6 < float(floor_value)*float(d.params[capacity]): errors.append("Original terminal SOC requirement violated")
	var targets: Variant = request.get("options",{}).get("terminal_hydrogen_kg",{})
	if not targets is Dictionary: return ["Malformed original terminal hydrogen target"]
	for id in targets:
		if not id is String: return ["Terminal hydrogen target ID must be canonical string"]
		var h2_node: Dictionary = {}
		for d in fleet:
			if str(int(d.id))==id: h2_node=d
		if h2_node.is_empty() or not h2_node.kind in Catalog.Materials.HYDROGEN_STORE_KINDS or not _number(targets[id]) or float(targets[id])<0.0 or float(targets[id])>Catalog.inventory_capacity(h2_node.kind,h2_node.params): return ["Invalid terminal hydrogen inventory target"]
		if not _number(targets[id]) or not result.final_states.get(id) is Dictionary or not result.final_states[id].get("material_inventory_kg") is Dictionary or not _number(result.final_states[id].material_inventory_kg.get("H2")):
			errors.append("Terminal hydrogen target references missing gas inventory")
		elif float(result.final_states[id].material_inventory_kg.H2) + 2.0e-6 < float(targets[id]): errors.append("Terminal hydrogen inventory target not met")
	var product_targets: Variant = request.get("options",{}).get("terminal_product_kg",{})
	if not product_targets is Dictionary: return ["Malformed terminal product targets"]
	if request.schema_version < 12 and not product_targets.is_empty(): return ["Product targets require schema12"]
	for id in product_targets:
		if not id is String: return ["Terminal product target ID must be canonical string"]
		var target_node: Dictionary = {}
		for d in fleet:
			if str(int(d.id))==id: target_node = d
		if not id is String or target_node.is_empty() or not target_node.kind in Catalog.Materials.SYNTHESIS_KINDS or not _number(product_targets[id]) or float(product_targets[id])<0.0 or float(product_targets[id])>Catalog.inventory_capacity(target_node.kind,target_node.params):
			errors.append("Invalid terminal chemical product target")
			continue
		if float(target_node.state.material_inventory_kg[Catalog.Materials.species(target_node.kind)])+2e-6<float(product_targets[id]): errors.append("Terminal product inventory target not met")
	return errors

## Compatibility adapter for the existing solver report's presentation aliases.
## Missing chemistry, flows, inventories and losses are NEVER supplied here.
static func _optimization_report_aliases(seed: Dictionary, candidate: Dictionary, errors: Array[String]) -> Dictionary:
	var r: Dictionary = candidate.duplicate(true)
	if not r.get("devices") is Dictionary or not r.get("lines") is Array: errors.append("Missing solver device/line report"); return {}
	for id in seed.nodes:
		if not r.devices.get(id) is Dictionary: errors.append("Missing solver device " + id); continue
		var n: Dictionary = seed.nodes[id]
		var d: Dictionary = r.devices[id]
		var base: Dictionary = seed.report.devices[id]
		if d.get("kind") != n.kind or not _integer(d.get("id")) or int(d.id) != int(n.id) or d.get("valid") != true: errors.append("Solver device identity/validity changed")
		for field in ["nameplate_clipped_mw","utilization"]:
			if not d.has(field): d[field] = base.get(field,0.0)
		if not n.kind in ["wind","pv"]:
			for field in ["mw","generated_mw","curtailed_mw"]:
				if not d.has(field): d[field] = base.get(field,0.0)
		if Catalog.is_electric_station(n.kind) and not d.has("loss_fraction"): d.loss_fraction = n.params.loss_fraction
		if Catalog.is_storage(n.kind):
			for key in ["charge_limit_mw","discharge_limit_mw","charge_limit_mwth","discharge_limit_mwth"]:
				if not d.has(key) and base.has(key): d[key] = base[key]
			var unit: String = "mwhth" if Catalog.is_thermal_storage(n.kind) else "mwh"
			var field: String = "energy_"+unit
			if not _number(d.get(field)) or not _number(d.get("next_"+field)) or absf(float(d.get(field,0))-float(d.get("next_"+field,0)))>2e-6: errors.append("Solver storage post-step alias differs")
			d[field] = n.state[field]
			if not d.has("storage_balance_error_"+unit): d["storage_balance_error_"+unit] = 0.0
		if n.kind == "electric_boiler":
			if not d.has("rated_electric_mw"): d.rated_electric_mw = n.params.rated_electric_mw
			for pair in [["electric_input_mw","boiler_electric_mw"],["heat_output_mwth","boiler_heat_mwth"],["conversion_loss_mw","boiler_conversion_loss_mw"]]:
				if not d.has(pair[0]) and d.has(pair[1]): d[pair[0]] = d[pair[1]]
	for line in r.lines:
		if not line is Dictionary: errors.append("Malformed solver line"); continue
		for field in ["index","from","to","flow_from","flow_to","direction"]:
			if not _integer(line.get(field)): errors.append("Malformed solver line integer: "+field)
			else: line[field] = int(line[field])
		if line.get("carrier") in [Catalog.THERMAL_CARRIER,"heat_oil","heat_salt"]:
			# Legacy Python heat reports omit inactive electric-unit placeholders.
			for field in ["signed_mw","sent_mw","received_mw","loss_mw"]:
				if not line.has(field): line[field] = 0.0
		if not line.has("reason"): line.reason = ""
		if line.get("carrier") == Catalog.CARRIER and not line.has("grade_id"): line.grade_id = ""
	if not seed.nodes.values().any(func(n): return n.kind == "fuel_boiler") and r.has("fuel"):
		if not r.fuel is Dictionary: errors.append("Malformed absent-fuel placeholder")
		else:
			for value in r.fuel.values():
				if not _number(value) or absf(float(value))>1e-9: errors.append("Unexpected fuel without fuel facilities")
			r.erase("fuel")
	return r
