extends RefCounted
## Pure terminal generation, legacy steady-state solve and storage-aware dispatch.
## AC power is MW; battery state is MWh; explicit simulation duration is seconds.
## Scientific provenance, unit definitions and deliberate approximations:
## res://config/ENERGY_MODEL_SOURCES.md

const Catalog = preload("res://scripts/device_catalog.gd")
const Dispatch = preload("res://scripts/network_dispatch.gd")
const HighTemp = preload("res://scripts/high_temp_thermal.gd")
const Solar = preload("res://scripts/solar_thermal.gd")

const GRID_CAPACITY_MW: float = 4.0
const BETZ_LIMIT: float = 16.0 / 27.0
const REFERENCE_DENSITY: float = 1.225
const EPS: float = 1.0e-9

static func defaults(kind: String) -> Dictionary:
	return Catalog.defaults(kind)

static func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))

static func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floor(float(value))

static func _params(kind: String, params: Dictionary) -> Dictionary:
	var result: Dictionary = defaults(kind)
	result.merge(params, true)
	return result

static func _range_error(errors: Array[String], p: Dictionary, key: String, low: float, high: float, exclusive_low: bool = false) -> void:
	if not p.has(key) or not _number(p[key]):
		errors.append("%s must be a finite number" % key)
	elif float(p[key]) < low or float(p[key]) > high or (exclusive_low and float(p[key]) == low):
		errors.append("%s must be %s %s and <= %s" % [key, ">" if exclusive_low else ">=", low, high])

static func validate(kind: String, params: Dictionary) -> Array[String]:
	if Catalog.is_material(kind): return Catalog.Materials.validate(kind, params)
	if Catalog.is_thermal(kind):
		return Catalog.validate_thermal(kind, params)
	if kind == "load" or Catalog.is_electric_storage(kind):
		return Catalog.validate_storage_load(kind, params)
	var errors: Array[String] = []
	var p: Dictionary = _params(kind, params)
	if defaults(kind).is_empty():
		errors.append("Unknown device kind: " + kind)
		return errors
	for key in params:
		if not defaults(kind).has(key):
			errors.append("Unknown %s parameter: %s" % [kind, key])
	match Catalog.dispatch_role(kind):
		"wind":
			_range_error(errors, p, "rated_mw", 0.0, 1000.0, true)
			_range_error(errors, p, "rotor_diameter_m", 0.0, 1000.0, true)
			_range_error(errors, p, "hub_height_m", 0.0, 2000.0, true)
			_range_error(errors, p, "cut_in_mps", 0.0, 99.0)
			_range_error(errors, p, "rated_speed_mps", 0.0, 100.0, true)
			_range_error(errors, p, "cut_out_mps", 0.0, 150.0, true)
			_range_error(errors, p, "drivetrain_efficiency", 0.0, 1.0, true)
			_range_error(errors, p, "cp_max", 0.0, BETZ_LIMIT, true)
			_range_error(errors, p, "shear_exponent", 0.0, 1.0)
			_range_error(errors, p, "reference_air_density_kgm3", 0.5, 2.0)
			_validate_wind_curve_shape(errors, p)
			if errors.is_empty():
				if p.power_curve_kw.is_empty():
					if p.cut_in_mps >= p.rated_speed_mps or p.rated_speed_mps >= p.cut_out_mps:
						errors.append("Wind speeds must satisfy cut-in < rated < cut-out")
				elif p.cut_in_mps >= p.cut_out_mps:
					errors.append("Wind speeds must satisfy cut-in < cut-out for power_curve_kw")
				if p.hub_height_m <= p.rotor_diameter_m / 2.0:
					errors.append("Hub height must exceed rotor radius")
				if errors.is_empty() and not p.power_curve_kw.is_empty():
					_validate_wind_curve_cp(errors, p)
				elif errors.is_empty():
					# Shifted cubic electrical curve: Cp rises monotonically to rated,
					# then falls as v^-3 on the plateau. This checks its entire interior,
					# not just a sampled set of endpoints or a linear chord.
					var available: float = _wind_kinetic_mw(p.rotor_diameter_m, p.rated_speed_mps, p.reference_air_density_kgm3)
					var required_cp: float = p.rated_mw / (available * p.drivetrain_efficiency)
					if required_cp > minf(p.cp_max, BETZ_LIMIT) + EPS:
						errors.append("Rated power requires Cp=%.4f; rotor, rated speed and drivetrain permit at most Cp=%.4f (Betz %.4f)" % [required_cp, p.cp_max, BETZ_LIMIT])
		"pv":
			_range_error(errors, p, "dc_capacity_mw", 0.0, 10000.0, true)
			_range_error(errors, p, "inverter_capacity_mw", 0.0, 10000.0, true)
			_range_error(errors, p, "inverter_efficiency", 0.0, 1.0, true)
			_range_error(errors, p, "temp_coefficient_per_c", -0.02, 0.0)
			_range_error(errors, p, "faiman_u0", 0.0, 500.0, true)
			_range_error(errors, p, "faiman_u1", 0.0, 100.0)
			_range_error(errors, p, "dc_loss_fraction", 0.0, 1.0)
			_range_error(errors, p, "cell_delta_c_at_1000", 0.0, 30.0)
		"station":
			_range_error(errors, p, "capacity_mw", 0.0, 200.0 if kind == Catalog.COLLECTOR_KIND else 10000.0, true)
			_range_error(errors, p, "loss_fraction", 0.0, 0.999999)
	return errors

## The supplied curve is electrical terminal kW at reference density. It is
## validated, never silently edited or clipped to a different Cp envelope.
static func _validate_wind_curve_shape(errors: Array[String], p: Dictionary) -> void:
	if not p.power_curve_kw is Array:
		errors.append("power_curve_kw must be an array of {wind_mps, power_kw} points (or [] for the cubic model)")
		return
	var curve: Array = p.power_curve_kw
	if curve.is_empty():
		return
	if curve.size() < 2 or curve.size() > 256:
		errors.append("power_curve_kw must contain 2 to 256 points, or be empty")
		return
	var previous_speed: float = -1.0
	for index in curve.size():
		var point: Variant = curve[index]
		var prefix: String = "power_curve_kw point %d" % (index + 1)
		if not point is Dictionary:
			errors.append(prefix + " must be an object with wind_mps and power_kw")
			continue
		for key in point:
			if not key in ["wind_mps", "power_kw"]:
				errors.append(prefix + " has unknown field: " + str(key))
		if not _number(point.get("wind_mps")):
			errors.append(prefix + " wind_mps must be a finite number")
		elif float(point.wind_mps) < 0.0 or float(point.wind_mps) > 100.0:
			errors.append(prefix + " wind_mps must be between 0 and 100 m/s")
		else:
			if float(point.wind_mps) <= previous_speed:
				errors.append(prefix + " wind_mps must be strictly increasing")
			previous_speed = float(point.wind_mps)
		if not _number(point.get("power_kw")):
			errors.append(prefix + " power_kw must be a finite number")
		elif float(point.power_kw) < 0.0:
			errors.append(prefix + " power_kw must be nonnegative")
		elif _number(p.rated_mw) and float(point.power_kw) > float(p.rated_mw) * 1000.0:
			errors.append(prefix + " power_kw must not exceed rated_mw * 1000")

static func _curve_required_cp(p: Dictionary, speed: float, power_kw: float) -> float:
	if power_kw <= 0.0:
		return 0.0
	var available: float = _wind_kinetic_mw(p.rotor_diameter_m, speed, p.reference_air_density_kgm3) * p.drivetrain_efficiency
	return power_kw / available / 1000.0 if available > 0.0 else INF

static func _validate_wind_curve_cp(errors: Array[String], p: Dictionary) -> void:
	var curve: Array = p.power_curve_kw
	var limit: float = minf(p.cp_max, BETZ_LIMIT)
	for index in curve.size():
		var point: Dictionary = curve[index]
		var required: float = _curve_required_cp(p, point.wind_mps, point.power_kw)
		if required > limit + EPS:
			errors.append("power_curve_kw point %d requires Cp=%.6f at %.6f m/s; maximum is %.6f (Betz %.6f)" % [index + 1, required, point.wind_mps, limit, BETZ_LIMIT])
	for index in range(1, curve.size()):
		var left: Dictionary = curve[index - 1]
		var right: Dictionary = curve[index]
		# On each segment P(v)=a*v+b, Cp is proportional to P(v)/v^3.
		# Its derivative is (-2*a*v-3*b)/v^4: endpoints and the sole
		# stationary point v=-3*b/(2*a) exhaust all finite extrema.
		# A positive linear rise from v=0 has unbounded Cp as v -> 0+.
		if float(left.wind_mps) == 0.0 and float(right.power_kw) > 0.0:
			errors.append("power_curve_kw segment %d has unbounded Cp near 0 m/s; add a zero-power interval before positive power" % index)
			continue
		var delta_power: float = float(right.power_kw) - float(left.power_kw)
		if delta_power == 0.0:
			continue
		var delta_speed: float = float(right.wind_mps) - float(left.wind_mps)
		# Equivalent stationary-point form avoids forming a huge slope for
		# narrowly spaced points. Values outside the segment are irrelevant.
		var critical_speed: float = 1.5 * (float(left.wind_mps) - float(left.power_kw) * delta_speed / delta_power)
		if critical_speed <= float(left.wind_mps) or critical_speed >= float(right.wind_mps):
			continue
		var power_kw: float = lerpf(left.power_kw, right.power_kw, (critical_speed - float(left.wind_mps)) / delta_speed)
		var required: float = _curve_required_cp(p, critical_speed, power_kw)
		if required > limit + EPS:
			errors.append("power_curve_kw segment %d requires interior Cp=%.6f at %.6f m/s; maximum is %.6f (Betz %.6f), even if its endpoints pass" % [index, required, critical_speed, limit, BETZ_LIMIT])

static func _curve_power_mw(curve: Array, speed: float) -> float:
	# No extrapolation, including below the first and above the last point.
	if speed < float(curve[0].wind_mps) or speed > float(curve[-1].wind_mps):
		return 0.0
	for index in range(1, curve.size()):
		var right: Dictionary = curve[index]
		if speed <= float(right.wind_mps):
			var left: Dictionary = curve[index - 1]
			return lerpf(left.power_kw, right.power_kw, (speed - float(left.wind_mps)) / (float(right.wind_mps) - float(left.wind_mps))) / 1000.0
	return 0.0

static func _wind_kinetic_mw(diameter: float, speed: float, density: float) -> float:
	return 0.5 * density * PI * pow(diameter * 0.5, 2.0) * pow(speed, 3.0) / 1.0e6

static func _weather_errors(kind: String, weather: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var w: Dictionary = {"wind_speed_mps": 0.0, "irradiance_wm2": 0.0, "air_temp_c": 25.0,
		"air_density_kgm3": REFERENCE_DENSITY}
	w.merge(weather, true)
	if kind == "wind":
		_range_error(errors, w, "wind_speed_mps", 0.0, 150.0)
		_range_error(errors, w, "air_density_kgm3", 0.1, 2.0)
		if w.has("wind_height_m"):
			_range_error(errors, w, "wind_height_m", 0.0, 5000.0, true)
	elif kind == "pv":
		_range_error(errors, w, "irradiance_wm2", 0.0, 2000.0)
		_range_error(errors, w, "air_temp_c", -100.0, 100.0)
		if w.has("pv_wind_speed_mps"):
			_range_error(errors, w, "pv_wind_speed_mps", 0.0, 150.0)
		else:
			_range_error(errors, w, "wind_speed_mps", 0.0, 150.0)
	return errors

static func generation(kind: String, params: Dictionary, weather: Dictionary) -> Dictionary:
	if kind == "parabolic_trough":
		var trough: Dictionary = HighTemp.evaluate(params, weather)
		trough.merge({"mw": 0.0, "generated_mw": 0.0, "source": "solar_dni", "nameplate_clipped_mw": 0.0})
		return trough
	if kind == "solar_thermal":
		var solar: Dictionary = Solar.evaluate(params, weather)
		solar.merge({"mw": 0.0, "generated_mw": 0.0, "source": "solar_poa", "nameplate_clipped_mw": 0.0})
		return solar
	var errors: Array[String] = validate(kind, params)
	errors.append_array(_weather_errors(kind, weather))
	var result: Dictionary = {"mw": 0.0, "generated_mw": 0.0, "source": str(weather.get("source", "weather")),
		"valid": errors.is_empty(), "errors": errors, "clipping_mw": 0.0, "nameplate_clipped_mw": 0.0}
	if not errors.is_empty():
		return result
	var p: Dictionary = _params(kind, params)
	if kind == "wind":
		var speed: float = float(weather.get("wind_speed_mps", 0.0))
		if weather.has("wind_height_m"):
			speed *= pow(p.hub_height_m / float(weather.wind_height_m), p.shear_exponent)
		var density: float = float(weather.get("air_density_kgm3", REFERENCE_DENSITY))
		var kinetic: float = _wind_kinetic_mw(p.rotor_diameter_m, speed, density)
		var kinetic_after_efficiency: float = kinetic * p.drivetrain_efficiency
		var output: float = 0.0
		var operating: bool = speed >= p.cut_in_mps and speed < p.cut_out_mps
		var custom_curve: bool = not p.power_curve_kw.is_empty()
		var reference_curve_mw: float = 0.0
		var density_adjusted_mw: float = 0.0
		if operating:
			if custom_curve:
				reference_curve_mw = _curve_power_mw(p.power_curve_kw, speed)
				density_adjusted_mw = reference_curve_mw * density / p.reference_air_density_kgm3
				# Input already represents electrical power. Efficiency participates
				# in physical validation, not a second conversion. Density scaling
				# preserves the validated Cp; rated clipping can only lower it.
				output = minf(p.rated_mw, density_adjusted_mw)
				result.nameplate_clipped_mw = maxf(0.0, density_adjusted_mw - output)
			else:
				# Preserve the original cubic model exactly for old/default params.
				var fraction: float = maxf(0.0, (pow(speed, 3.0) - pow(p.cut_in_mps, 3.0)) / (pow(p.rated_speed_mps, 3.0) - pow(p.cut_in_mps, 3.0)))
				output = minf(p.rated_mw, p.rated_mw * fraction * density / p.reference_air_density_kgm3)
				output = minf(output, kinetic * p.cp_max * p.drivetrain_efficiency)
		result.merge({"mw": output, "generated_mw": output, "rated_mw": p.rated_mw,
			"wind_speed_mps": speed, "air_density_kgm3": density, "kinetic_mw": kinetic,
			"reference_air_density_kgm3": p.reference_air_density_kgm3,
			"cp_aero": output / kinetic_after_efficiency if kinetic_after_efficiency > 0.0 else 0.0,
			"operating": operating, "curve_mode": "custom" if custom_curve else "cubic",
			"model": "Custom electrical power curve: linear interpolation, density correction, rated cap" if custom_curve else "NREL-5MW-sized constrained cubic approximation"}, true)
		if custom_curve:
			result.merge({"reference_curve_mw": reference_curve_mw, "density_adjusted_mw": density_adjusted_mw,
				"curve_in_range": speed >= float(p.power_curve_kw[0].wind_mps) and speed <= float(p.power_curve_kw[-1].wind_mps)}, true)
	elif kind == "pv":
		var poa: float = float(weather.get("irradiance_wm2", 0.0))
		var ambient: float = float(weather.get("air_temp_c", 25.0))
		var speed: float = float(weather.get("pv_wind_speed_mps", weather.get("wind_speed_mps", 0.0)))
		var module_temp: float = ambient + poa / (p.faiman_u0 + p.faiman_u1 * speed)
		var cell_temp: float = module_temp + p.cell_delta_c_at_1000 * poa / 1000.0
		var temp_factor: float = maxf(0.0, 1.0 + p.temp_coefficient_per_c * (cell_temp - 25.0))
		var gross_dc: float = p.dc_capacity_mw * poa / 1000.0 * temp_factor
		var dc: float = gross_dc * (1.0 - p.dc_loss_fraction)
		var conversion_loss: float = dc * (1.0 - p.inverter_efficiency)
		var unclipped_ac: float = dc - conversion_loss
		var ac: float = minf(p.inverter_capacity_mw, unclipped_ac)
		result.merge({"mw": ac, "generated_mw": ac, "rated_mw": p.inverter_capacity_mw,
			"irradiance_wm2": poa, "module_temp_c": module_temp, "cell_temp_c": cell_temp,
			"gross_dc_mw": gross_dc, "dc_loss_mw": gross_dc - dc, "dc_mw": dc,
			"inverter_loss_mw": conversion_loss, "clipping_mw": unclipped_ac - ac,
			"ac_mw": ac, "model": "Faiman temperature + linear DC temperature model + constant-efficiency inverter"}, true)
	return result

## Max-delivered-power LP over generator -> station -> grid paths.
## Every capacity is imposed at its sending/input side, before that element's loss.
## This is an active-power transport model, not an AC load-flow solver.
static func solve(devices: Array, links: Array, weather: Dictionary, direct: Dictionary = {}) -> Dictionary:
	# The legacy duration-less entry point previews heat scenes at dt=0 rather
	# than silently discarding their carrier. Advance storage only via dispatch.
	for device in devices:
		if device is Dictionary and Catalog.is_thermal(str(device.get("kind", ""))):
			return dispatch(devices, links, weather, direct, 0.0)
	var report: Dictionary = {"devices": {}, "lines": [], "errors": [], "warnings": [],
		"generated_mw": 0.0, "delivered_mw": 0.0, "curtailed_mw": 0.0,
		"loss_mw": 0.0, "line_loss_mw": 0.0, "station_loss_mw": 0.0,
		"nameplate_clipped_mw": 0.0, "balance_error_mw": 0.0,
		"grid_capacity_mw": GRID_CAPACITY_MW, "optimal": true}
	var nodes: Dictionary = {}
	for raw in devices:
		if not raw is Dictionary or not _integer(raw.get("id")) or float(raw.get("id", -1)) < 0:
			report.errors.append("Device requires a nonnegative integer stable id")
			continue
		var id: String = str(int(raw.id))
		if nodes.has(id):
			report.errors.append("Duplicate device id %s ignored" % id)
			continue
		var kind: String = str(raw.get("kind", ""))
		var p: Dictionary = raw.get("params", {}) if raw.get("params", {}) is Dictionary else {}
		var detail: Dictionary
		var param_errors: Array[String] = validate(kind, p)
		if not raw.get("params", {}) is Dictionary:
			param_errors.append("params must be a dictionary")
		if direct.has(id) and kind in ["wind", "pv"] and param_errors.is_empty():
			var sample: Variant = direct[id]
			var ok: bool = sample is Dictionary and _number(sample.get("mw")) and float(sample.get("mw", -1.0)) >= 0.0
			var rating: float = float(_params(kind, p).get("rated_mw", _params(kind, p).get("inverter_capacity_mw", 0.0)))
			var raw_mw: float = float(sample.mw) if ok else 0.0
			detail = {"mw": minf(raw_mw, rating), "generated_mw": minf(raw_mw, rating),
				"source": str(sample.get("source", "direct")) if sample is Dictionary else "direct",
				"valid": ok, "errors": [] if ok else ["Direct power must be finite and nonnegative"],
				"requested_mw": raw_mw, "nameplate_clipped_mw": maxf(0.0, raw_mw - rating),
				"model": "direct AC terminal power", "rated_mw": rating}
		else:
			detail = generation(kind, p, weather)
		if not param_errors.is_empty():
			detail.valid = false
			detail.errors = param_errors
			detail.mw = 0.0
			detail.generated_mw = 0.0
		detail.merge({"id": int(raw.id), "kind": kind, "sent_mw": 0.0,
			"received_mw": 0.0, "delivered_mw": 0.0, "curtailed_mw": 0.0, "loss_mw": 0.0,
			"input_mw": 0.0, "output_mw": 0.0, "connected": false, "utilization": 0.0}, true)
		if Catalog.is_electric_station(kind) and detail.valid:
			if kind == Catalog.COLLECTOR_KIND: detail.merge({"model_profile":Catalog.COLLECTOR_PROFILE,"model_profile_version":1})
			detail.capacity_mw = _params(kind, p).capacity_mw
			detail.loss_fraction = _params(kind, p).loss_fraction
		nodes[id] = {"kind": kind, "params": _params(kind, p), "valid": detail.valid}
		report.devices[id] = detail
		report.generated_mw += detail.mw
		report.nameplate_clipped_mw += detail.get("nameplate_clipped_mw", 0.0)
		if not detail.valid:
			report.errors.append("Device %s: %s" % [id, "; ".join(detail.errors)])

	var seen: Dictionary = {}
	for index in links.size():
		var raw: Variant = links[index]
		var line: Dictionary = {"index": index, "from": -2, "to": -2, "valid": false,
			"reason": "Malformed link", "sent_mw": 0.0, "received_mw": 0.0,
			"loss_mw": 0.0, "capacity_mw": 0.0, "loss_fraction": 0.0,
			"utilization": 0.0, "active": false}
		report.lines.append(line)
		if not raw is Dictionary or not _integer(raw.get("from")) or not _integer(raw.get("to")):
			continue
		line.from = int(raw.from)
		line.to = int(raw.to)
		var a: String = str(line.from)
		var b: String = str(line.to)
		var cap: Variant = raw.get("capacity_mw", 4.0)
		var loss: Variant = raw.get("loss_fraction", 0.01)
		if not _number(cap) or float(cap) < 0.0 or not _number(loss) or float(loss) < 0.0 or float(loss) >= 1.0:
			line.reason = "Link capacity must be finite and >=0; loss fraction must be finite in [0,1)"
			continue
		line.capacity_mw = float(cap)
		line.loss_fraction = float(loss)
		if not nodes.has(a) or not nodes[a].valid:
			line.reason = "Missing or invalid source device"
			continue
		var route_ok: bool = (nodes[a].kind in ["wind", "pv"] and nodes.has(b) and Catalog.is_electric_station(nodes[b].kind) and nodes[b].valid) or (Catalog.is_electric_station(nodes[a].kind) and line.to == -1)
		if not route_ok:
			line.reason = "Only wind/PV -> station -> grid connections are allowed"
			continue
		var signature: String = a + ":" + b
		if seen.has(signature):
			line.reason = "Duplicate connection ignored; first valid connection is authoritative"
			continue
		seen[signature] = true
		line.valid = true
		line.reason = ""
		report.devices[a].connected = true
		if nodes.has(b):
			report.devices[b].connected = true
	for line in report.lines:
		if not line.valid:
			report.warnings.append("Line %s: %s" % [line.index, line.reason])

	var resources: Array = []
	var resource_index: Dictionary = {}
	var ids: Array = nodes.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for id in ids:
		if not nodes[id].valid:
			continue
		var cap: float = report.devices[id].mw if not Catalog.is_electric_station(nodes[id].kind) else nodes[id].params.capacity_mw
		resource_index["device:" + id] = resources.size()
		resources.append(cap)
	for line in report.lines:
		if line.valid:
			resource_index["line:" + str(line.index)] = resources.size()
			resources.append(line.capacity_mw)
	var grid_resource: int = resources.size()
	resources.append(GRID_CAPACITY_MW)
	var paths: Array = []
	for incoming in report.lines:
		if not incoming.valid or incoming.to == -1 or incoming.capacity_mw <= EPS:
			continue
		var gen_id: String = str(incoming.from)
		var station_id: String = str(incoming.to)
		if report.devices[gen_id].mw <= EPS:
			continue
		for outgoing in report.lines:
			if not outgoing.valid or outgoing.from != incoming.to or outgoing.to != -1 or outgoing.capacity_mw <= EPS:
				continue
			var arriving: float = 1.0 - incoming.loss_fraction
			var after_station: float = arriving * (1.0 - nodes[station_id].params.loss_fraction)
			var at_grid: float = after_station * (1.0 - outgoing.loss_fraction)
			var coefficients: Dictionary = {}
			coefficients[resource_index["device:" + gen_id]] = 1.0
			coefficients[resource_index["line:" + str(incoming.index)]] = 1.0
			coefficients[resource_index["device:" + station_id]] = arriving
			coefficients[resource_index["line:" + str(outgoing.index)]] = after_station
			coefficients[grid_resource] = at_grid
			paths.append({"gen": gen_id, "station": station_id, "incoming": incoming.index,
				"outgoing": outgoing.index, "arriving": arriving, "after_station": after_station,
				"at_grid": at_grid, "coefficients": coefficients})
	var allocation: Dictionary = _maximize(paths, resources)
	report.optimal = allocation.optimal
	if not allocation.optimal:
		report.warnings.append("Dispatch iteration limit reached; reporting feasible partial allocation")
	for index in paths.size():
		var path: Dictionary = paths[index]
		var sent: float = maxf(0.0, allocation.values[index])
		var arriving: float = sent * path.arriving
		var station_out: float = sent * path.after_station
		var delivered: float = sent * path.at_grid
		var gen: Dictionary = report.devices[path.gen]
		var station: Dictionary = report.devices[path.station]
		gen.sent_mw += sent
		gen.output_mw += sent
		gen.delivered_mw += delivered
		gen.loss_mw += sent - delivered
		station.input_mw += arriving
		station.received_mw += arriving
		station.output_mw += station_out
		station.sent_mw += station_out
		station.delivered_mw += delivered
		station.loss_mw += arriving - station_out
		var first: Dictionary = report.lines[path.incoming]
		first.sent_mw += sent
		first.received_mw += arriving
		first.loss_mw += sent - arriving
		var last: Dictionary = report.lines[path.outgoing]
		last.sent_mw += station_out
		last.received_mw += delivered
		last.loss_mw += station_out - delivered
		report.delivered_mw += delivered
	for id in report.devices:
		var device: Dictionary = report.devices[id]
		if Catalog.is_electric_station(device.kind):
			report.station_loss_mw += device.loss_mw
			device.utilization = device.input_mw / device.get("capacity_mw", 1.0)
		else:
			device.curtailed_mw = maxf(0.0, device.mw - device.sent_mw)
			report.curtailed_mw += device.curtailed_mw
			device.utilization = device.mw / maxf(EPS, device.get("rated_mw", 1.0))
	for line in report.lines:
		line.active = line.sent_mw > EPS
		line.utilization = line.sent_mw / line.capacity_mw if line.capacity_mw > EPS else 0.0
		report.line_loss_mw += line.loss_mw
	report.loss_mw = report.line_loss_mw + report.station_loss_mw
	report.balance_error_mw = report.generated_mw - report.delivered_mw - report.curtailed_mw - report.loss_mw
	# Short aliases for clients that display the balance without unit suffixes.
	for key in ["generated", "delivered", "curtailed", "loss", "balance_error"]:
		report[key] = report[key + "_mw"]
	report.net_mw = report.delivered_mw
	return report

## Primal simplex: nonnegative path flows and <= capacity constraints. Zero is
## feasible. Bland's pivot rule makes degeneracy deterministic and avoids cycling.
static func _maximize(paths: Array, capacities: Array) -> Dictionary:
	var n: int = paths.size()
	var m: int = capacities.size()
	var values: PackedFloat64Array = PackedFloat64Array()
	values.resize(n)
	if n == 0:
		return {"values": values, "optimal": true}
	var width: int = n + m + 1
	var rows: Array = []
	var basis: Array[int] = []
	for i in m:
		var row: PackedFloat64Array = PackedFloat64Array()
		row.resize(width)
		for j in n:
			row[j] = float(paths[j].coefficients.get(i, 0.0))
		row[n + i] = 1.0
		row[width - 1] = maxf(0.0, capacities[i])
		rows.append(row)
		basis.append(n + i)
	var objective: PackedFloat64Array = PackedFloat64Array()
	objective.resize(width)
	for j in n:
		objective[j] = -paths[j].at_grid
	rows.append(objective)
	var optimal: bool = false
	for _iteration in maxi(1000, (n + m) * 100):
		var entering: int = -1
		for j in width - 1:
			if rows[m][j] < -EPS:
				entering = j
				break
		if entering == -1:
			optimal = true
			break
		var leaving: int = -1
		var ratio: float = INF
		for i in m:
			if rows[i][entering] > EPS:
				var candidate: float = rows[i][width - 1] / rows[i][entering]
				if candidate < ratio - EPS or (absf(candidate - ratio) <= EPS and (leaving == -1 or basis[i] < basis[leaving])):
					ratio = candidate
					leaving = i
		if leaving == -1:
			break # Defensive; bounded generator and grid rows make this unreachable.
		var pivot_row: PackedFloat64Array = rows[leaving]
		var pivot: float = pivot_row[entering]
		for j in width:
			pivot_row[j] /= pivot
		rows[leaving] = pivot_row
		for i in m + 1:
			if i == leaving:
				continue
			var row: PackedFloat64Array = rows[i]
			var factor: float = row[entering]
			if absf(factor) > 1.0e-14:
				for j in width:
					row[j] -= factor * pivot_row[j]
			rows[i] = row
		basis[leaving] = entering
	for i in m:
		if basis[i] < n:
			values[basis[i]] = maxf(0.0, rows[i][width - 1])
	return {"values": values, "optimal": optimal}

## Deterministic, connected-path teaching dispatch; no economic optimum is claimed.
## This call is pure. Apply next_states only when advancing simulated time AND
## report.valid is true. Optional natural gas is the explicit fleet configuration
## direct["_fuel_supply"], defaults disabled, with no per-device fuel inventory.
## Invalid edges are omitted for diagnostics but make valid
## false; step_valid checks only the duration. Storage conversion/self-discharge
## losses are separate from network loss_mw, because charge/discharge are AC MW.
static func dispatch(devices: Array, links: Array, weather: Dictionary, direct: Dictionary = {}, dt_s: float = 1.0) -> Dictionary:
	return Dispatch.run(devices, links, weather, direct, dt_s, generation, validate)

## Solver-neutral single-step snapshot. This exports constraints, it does not solve.
static func optimization_snapshot(devices: Array, links: Array, weather: Dictionary, direct: Dictionary = {}, dt_s: float = 1.0, context: Dictionary = {}) -> Dictionary:
	return Dispatch.optimization_snapshot(devices, links, weather, direct, dt_s, generation, validate, context)

## Audit a dispatch result against the original devices/edges before committing.
## Pass the original fleet fuel_supply when auditing fuel scenes so its cap/price
## cannot be changed by a report. Omitted supply replays the report's own metadata.
static func audit_dispatch(devices: Array, links: Array, report: Dictionary, fuel_supply: Dictionary = {}, weather: Dictionary = {}) -> Array[String]:
	return Dispatch.audit_result(devices, links, report, generation, validate, fuel_supply, weather)
