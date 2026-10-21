extends RefCounted
## Implemented teaching devices only. AC terminals include built-in PV/battery PCS.
## Fixed-grade hot-water service devices; no steam, hydraulics or pressure model.
const SCHEMA_VERSION: int = 3
const THERMAL_PROFILE_VERSION: int = 1
const THERMAL_CARRIER: String = "heat_water"
const OIL_CARRIER: String = "heat_oil"
const OIL_GRADE: String = "oil_300_200"
const SALT_CARRIER: String = "heat_salt"
const SALT_GRADE: String = "salt_565_290"
const TOWER_KINDS := ["solar_tower_receiver", "molten_salt_store", "salt_steam_generator"]
const RANKINE_KINDS := ["steam_generator", "steam_turbine", "steam_condenser", "feedwater_pump"]
const MASS_CARRIER := "water_steam"
const HIGH_TEMP_KINDS := ["parabolic_trough", "high_temp_store", "oil_water_exchanger"]
const PRIMARY_GRADE: String = "hw_primary_90_60"
const SECONDARY_GRADE: String = "hw_secondary_70_40"
const CARRIER: String = "electricity_ac"
const VOLTAGE_LEVEL: String = "AC_BUS"
const GRID_CAPACITY_MW: float = 4.0

static func implemented_kinds() -> Array[String]:
	return ["wind", "pv", "station", "load", "battery", "electric_boiler", "thermal_store", "heat_exchanger", "heat_demand", "fuel_boiler", "solar_thermal", "parabolic_trough", "high_temp_store", "oil_water_exchanger", "steam_generator", "steam_turbine", "steam_condenser", "feedwater_pump", "solar_tower_receiver", "molten_salt_store", "salt_steam_generator"]

static func is_thermal(kind: String) -> bool:
	return kind in TOWER_KINDS or kind in RANKINE_KINDS or kind in ["electric_boiler", "thermal_store", "heat_exchanger", "heat_demand", "fuel_boiler", "solar_thermal", "parabolic_trough", "high_temp_store", "oil_water_exchanger"]

static func is_tower(kind: String) -> bool:
	return kind in TOWER_KINDS

static func is_rankine(kind: String) -> bool:
	return kind in RANKINE_KINDS or kind == "salt_steam_generator"

static func is_high_temp(kind: String) -> bool:
	return kind in HIGH_TEMP_KINDS

static func model_profile(kind: String) -> String:
	return "tower_stage1_v1" if is_tower(kind) else "rankine_stage1_v1" if is_rankine(kind) else "high_temp_stage1_v1" if is_high_temp(kind) else ("thermal_stage1_v1" if is_thermal(kind) else "")

static func temperature_grade(grade_id: String) -> Dictionary:
	match grade_id:
		"rankine_live_v1": return {"temperature_c":280.0,"pressure_kpa":1000.0,"enthalpy_kj_kg":3008.6,"medium":"water_steam"}
		"rankine_exhaust_v1": return {"temperature_c":45.806,"pressure_kpa":10.0,"enthalpy_kj_kg":2426.78753,"medium":"water_steam"}
		"rankine_condensate_v1": return {"temperature_c":45.806,"pressure_kpa":10.0,"enthalpy_kj_kg":191.81,"medium":"water_steam"}
		"rankine_feedwater_v1": return {"temperature_c":45.806,"pressure_kpa":1000.0,"enthalpy_kj_kg":193.238810,"medium":"water_steam","temperature_note":"incompressible fixed-point approximation"}
		SALT_GRADE: return {"supply_c":565.0, "return_c":290.0, "medium":"solar_salt"}
		OIL_GRADE: return {"supply_c":300.0, "return_c":200.0, "medium":"Therminol66"}
		PRIMARY_GRADE: return {"supply_c": 90.0, "return_c": 60.0, "medium": "water_equivalent"}
		SECONDARY_GRADE: return {"supply_c": 70.0, "return_c": 40.0, "medium": "water_equivalent"}
	return {}

static func defaults(kind: String) -> Dictionary:
	match kind:
		"solar_tower_receiver": return {"mirror_area_m2":1600.0,"optical_efficiency":0.6,"receiver_efficiency":0.9,"auxiliary_electric_ratio":0.02,"supply_temp_c":565.0,"return_temp_c":290.0}
		"molten_salt_store": return {"capacity_mwhth":0.5,"charge_mwth":0.8,"discharge_mwth":0.1,"charge_efficiency":0.98,"discharge_efficiency":0.98,"self_discharge_per_h":0.005,"initial_soc":0.0,"auxiliary_electric_ratio":0.01}
		"steam_generator", "salt_steam_generator": return {"capacity_mwth":0.1,"transfer_efficiency":0.97,"auxiliary_electric_ratio":0.005}
		"steam_turbine": return {"mass_flow_capacity_kg_s":0.05,"generator_efficiency":0.95}
		"steam_condenser": return {"capacity_mwth":0.08,"auxiliary_electric_ratio":0.02,"condensing_temp_c":45.806,"design_ambient_c":25.0,"min_approach_k":10.0}
		"feedwater_pump": return {"mass_flow_capacity_kg_s":0.05,"motor_efficiency":0.90}
		"wind":
			return {"rated_mw": 5.0, "rotor_diameter_m": 126.0, "hub_height_m": 90.0,
				"cut_in_mps": 3.0, "rated_speed_mps": 11.4, "cut_out_mps": 25.0,
				"drivetrain_efficiency": 0.944, "cp_max": 0.49, "shear_exponent": 0.14,
				"reference_air_density_kgm3": 1.225, "power_curve_kw": []}
		"pv":
			return {"dc_capacity_mw": 1.2, "inverter_capacity_mw": 1.0,
				"inverter_efficiency": 0.96, "temp_coefficient_per_c": -0.004,
				"faiman_u0": 25.0, "faiman_u1": 6.84,
				"dc_loss_fraction": 0.02, "cell_delta_c_at_1000": 3.0}
		"station":
			return {"capacity_mw": 4.0, "loss_fraction": 0.01}
		"load":
			return {"demand_mw": 2.0, "priority": 10}
		"battery":
			return {"capacity_mwh": 10.0, "charge_mw": 3.0, "discharge_mw": 3.0,
				"charge_efficiency": 0.9, "discharge_efficiency": 0.9,
				"self_discharge_per_h": 0.0, "initial_soc": 0.5}
		"electric_boiler":
			return {"rated_electric_mw": 2.0, "thermal_efficiency": 0.98}
		"parabolic_trough":
			return {"aperture_area_m2":69.24,"optical_efficiency":0.75,"heat_loss_w_m2k":0.1,
				"heat_loss_quadratic_w_m2k2":0.0002,"auxiliary_electric_ratio":0.02,"supply_temp_c":300.0,"return_temp_c":200.0}
		"high_temp_store":
			return {"capacity_mwhth":0.2,"charge_mwth":0.1,"discharge_mwth":0.1,"charge_efficiency":0.98,
				"discharge_efficiency":0.98,"self_discharge_per_h":0.005,"initial_soc":0.0}
		"oil_water_exchanger":
			return {"capacity_mwth":0.1,"transfer_efficiency":0.98,"min_approach_k":10.0,"auxiliary_electric_ratio":0.01}
		"solar_thermal":
			# Absorber-area coefficients; fixed primary-grade steady-state collector.
			return {"absorber_area_m2":30.3, "optical_efficiency":0.785, "heat_loss_w_m2k":1.42,
				"heat_loss_quadratic_w_m2k2":0.005, "auxiliary_electric_ratio":0.02,
				"supply_temp_c":90.0, "return_temp_c":60.0}
		"fuel_boiler":
			# LHV fuel input, independent auxiliary AC demand, primary hot water only.
			return {"rated_fuel_mw": 2.0, "thermal_efficiency": 0.90, "auxiliary_electric_ratio": 0.01}
		"thermal_store":
			return {"capacity_mwhth": 4.0, "charge_mwth": 2.0, "discharge_mwth": 2.0,
				"charge_efficiency": 0.98, "discharge_efficiency": 0.98,
				"self_discharge_per_h": 0.002, "initial_soc": 0.0}
		"heat_exchanger":
			return {"capacity_mwth": 2.0, "transfer_efficiency": 0.98, "min_approach_k": 5.0}
		"heat_demand":
			return {"demand_mwth": 1.0, "priority": 10}
	return {}

static func _port(id: String, direction: String) -> Dictionary:
	return {"id": id, "direction": direction, "carrier": CARRIER,
		"unit": "MW", "voltage_level": VOLTAGE_LEVEL}

static func _heat_port(id: String, direction: String, grade: String) -> Dictionary:
	return {"id": id, "direction": direction, "carrier": THERMAL_CARRIER, "unit": "MWth", "grade_id": grade}

static func _oil_port(id: String, direction: String) -> Dictionary:
	return {"id":id,"direction":direction,"carrier":OIL_CARRIER,"unit":"MWth","grade_id":OIL_GRADE}

static func _salt_port(id: String, direction: String) -> Dictionary:
	return {"id":id,"direction":direction,"carrier":SALT_CARRIER,"unit":"MWth","grade_id":SALT_GRADE}

static func _mass_port(id: String, direction: String, grade: String) -> Dictionary:
	return {"id":id,"direction":direction,"carrier":MASS_CARRIER,"unit":"kg/s","grade_id":grade}

static func ports(kind: String) -> Array:
	match kind:
		"solar_tower_receiver": return [_salt_port("heat_out","output"),_port("ac_in","input")]
		"molten_salt_store": return [_salt_port("heat_in","input"),_salt_port("heat_out","output"),_port("ac_in","input")]
		"salt_steam_generator": return [_salt_port("salt_in","input"),_port("ac_in","input"),_mass_port("feed_in","input","rankine_feedwater_v1"),_mass_port("steam_out","output","rankine_live_v1")]
		"steam_generator": return [_oil_port("oil_in","input"),_port("ac_in","input"),_mass_port("feed_in","input","rankine_feedwater_v1"),_mass_port("steam_out","output","rankine_live_v1")]
		"steam_turbine": return [_mass_port("steam_in","input","rankine_live_v1"),_mass_port("exhaust_out","output","rankine_exhaust_v1"),_port("ac_out","output")]
		"steam_condenser": return [_mass_port("exhaust_in","input","rankine_exhaust_v1"),_mass_port("condensate_out","output","rankine_condensate_v1"),_port("ac_in","input")]
		"feedwater_pump": return [_mass_port("condensate_in","input","rankine_condensate_v1"),_mass_port("feed_out","output","rankine_feedwater_v1"),_port("ac_in","input")]
		"parabolic_trough": return [_port("ac_in", "input"), _oil_port("heat_out","output")]
		"high_temp_store": return [_oil_port("heat_in","input"), _oil_port("heat_out","output")]
		"oil_water_exchanger": return [_port("ac_in","input"), _oil_port("hot_in","input"), _heat_port("warm_out","output",PRIMARY_GRADE)]
		"wind", "pv": return [_port("out", "output")]
		"station": return [_port("in", "input"), _port("out", "output")]
		"load", "grid": return [_port("in", "input")]
		"battery": return [_port("ac", "bidirectional")]
		"electric_boiler", "fuel_boiler", "solar_thermal": return [_port("ac_in", "input"), _heat_port("heat_out", "output", PRIMARY_GRADE)]
		"thermal_store": return [_heat_port("heat_in", "input", PRIMARY_GRADE), _heat_port("heat_out", "output", PRIMARY_GRADE)]
		"heat_exchanger": return [_heat_port("hot_in", "input", PRIMARY_GRADE), _heat_port("warm_out", "output", SECONDARY_GRADE)]
		"heat_demand": return [_heat_port("heat_in", "input", SECONDARY_GRADE)]
	return []

static func port(kind: String, id: String) -> Dictionary:
	for entry in ports(kind):
		if entry.id == id:
			return entry
	return {}

static func _number(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value))

static func _integer(value: Variant) -> bool:
	return _number(value) and float(value) == floor(float(value))

static func _range(errors: Array[String], p: Dictionary, key: String, low: float, high: float, exclusive_low: bool = false) -> void:
	if not _number(p.get(key)):
		errors.append(key + " must be a finite number")
	elif float(p[key]) < low or float(p[key]) > high or (exclusive_low and float(p[key]) == low):
		errors.append("%s must be %s %s and <= %s" % [key, ">" if exclusive_low else ">=", low, high])

static func validate_storage_load(kind: String, params: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not kind in ["load", "battery"]:
		errors.append("Not a load/storage kind: " + kind)
		return errors
	var p: Dictionary = defaults(kind)
	for key in params:
		if not p.has(key):
			errors.append("Unknown %s parameter: %s" % [kind, key])
	p.merge(params, true)
	if kind == "load":
		_range(errors, p, "demand_mw", 0.0, 10000.0)
		_range(errors, p, "priority", 0.0, 1000.0)
		if _number(p.priority) and not _integer(p.priority):
			errors.append("priority must be an integer; lower values are served first")
	else:
		_range(errors, p, "capacity_mwh", 0.0, 100000.0, true)
		_range(errors, p, "charge_mw", 0.0, 10000.0)
		_range(errors, p, "discharge_mw", 0.0, 10000.0)
		_range(errors, p, "charge_efficiency", 0.0, 1.0, true)
		_range(errors, p, "discharge_efficiency", 0.0, 1.0, true)
		_range(errors, p, "self_discharge_per_h", 0.0, 1.0)
		_range(errors, p, "initial_soc", 0.0, 1.0)
	return errors

static func validate_thermal(kind: String, params: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not is_thermal(kind):
		return ["Unknown thermal device kind: " + kind]
	var p: Dictionary = defaults(kind)
	for key in params:
		if not p.has(key):
			errors.append("Unknown %s parameter: %s" % [kind, key])
	p.merge(params, true)
	match kind:
		"solar_tower_receiver":
			_range(errors,p,"mirror_area_m2",1600.0,1600.0)
			_range(errors,p,"optical_efficiency",0.0,1.0,true)
			_range(errors,p,"receiver_efficiency",0.0,1.0,true)
			_range(errors,p,"auxiliary_electric_ratio",0.001,0.2)
			_range(errors,p,"supply_temp_c",565.0,565.0)
			_range(errors,p,"return_temp_c",290.0,290.0)
		"steam_generator", "salt_steam_generator":
			_range(errors,p,"capacity_mwth",0.0,10000.0,true)
			_range(errors,p,"transfer_efficiency",0.97,0.97)
			_range(errors,p,"auxiliary_electric_ratio",0.001,0.2)
		"steam_turbine":
			_range(errors,p,"mass_flow_capacity_kg_s",0.0,1000.0,true)
			_range(errors,p,"generator_efficiency",0.95,0.95)
		"steam_condenser":
			_range(errors,p,"capacity_mwth",0.0,10000.0,true)
			_range(errors,p,"auxiliary_electric_ratio",0.001,0.2)
			_range(errors,p,"condensing_temp_c",45.806,45.806)
			_range(errors,p,"design_ambient_c",25.0,25.0)
			_range(errors,p,"min_approach_k",10.0,10.0)
		"feedwater_pump":
			_range(errors,p,"mass_flow_capacity_kg_s",0.0,1000.0,true)
			_range(errors,p,"motor_efficiency",0.90,0.90)
		"electric_boiler":
			_range(errors, p, "rated_electric_mw", 0.0, 10000.0, true)
			_range(errors, p, "thermal_efficiency", 0.0, 1.0, true)
		"parabolic_trough":
			_range(errors,p,"aperture_area_m2",0.0,6924.0,true)
			_range(errors,p,"optical_efficiency",0.0,1.0,true)
			_range(errors,p,"heat_loss_w_m2k",0.0,20.0)
			_range(errors,p,"heat_loss_quadratic_w_m2k2",0.0,0.2)
			_range(errors,p,"auxiliary_electric_ratio",0.001,0.2)
			_range(errors,p,"supply_temp_c",300.0,300.0)
			_range(errors,p,"return_temp_c",200.0,200.0)
		"oil_water_exchanger":
			_range(errors,p,"capacity_mwth",0.0,10000.0,true)
			_range(errors,p,"transfer_efficiency",0.0,1.0,true)
			_range(errors,p,"auxiliary_electric_ratio",0.001,0.2)
			_range(errors,p,"min_approach_k",0.0,140.0)
			if _number(p.min_approach_k):
				var hot: Dictionary = temperature_grade(OIL_GRADE)
				var cold: Dictionary = temperature_grade(PRIMARY_GRADE)
				if hot.supply_c-cold.supply_c<p.min_approach_k or hot.return_c-cold.return_c<p.min_approach_k:
					errors.append("300/200°C油与90/60°C水两端温差均须满足最小换热温差")
		"solar_thermal":
			_range(errors, p, "absorber_area_m2", 0.0, 3030.0, true)
			_range(errors, p, "optical_efficiency", 0.0, 1.0, true)
			_range(errors, p, "heat_loss_w_m2k", 0.0, 20.0)
			_range(errors, p, "heat_loss_quadratic_w_m2k2", 0.0, 0.2)
			_range(errors, p, "auxiliary_electric_ratio", 0.001, 0.2)
			_range(errors, p, "supply_temp_c", 90.0, 90.0)
			_range(errors, p, "return_temp_c", 60.0, 60.0)
		"fuel_boiler":
			_range(errors, p, "rated_fuel_mw", 0.0, 10000.0, true)
			_range(errors, p, "thermal_efficiency", 0.0, 1.0, true)
			# Positive auxiliary demand preserves no-electricity/no-boiler behavior.
			_range(errors, p, "auxiliary_electric_ratio", 0.001, 0.2)
		"thermal_store", "high_temp_store", "molten_salt_store":
			_range(errors, p, "capacity_mwhth", 0.0, 100000.0, true)
			_range(errors, p, "charge_mwth", 0.0, 10000.0)
			_range(errors, p, "discharge_mwth", 0.0, 10000.0)
			_range(errors, p, "charge_efficiency", 0.0, 1.0, true)
			_range(errors, p, "discharge_efficiency", 0.0, 1.0, true)
			_range(errors, p, "self_discharge_per_h", 0.0, 1.0)
			_range(errors, p, "initial_soc", 0.0, 1.0)
			if kind == "molten_salt_store": _range(errors,p,"auxiliary_electric_ratio",0.001,0.2)
		"heat_exchanger":
			_range(errors, p, "capacity_mwth", 0.0, 10000.0, true)
			_range(errors, p, "transfer_efficiency", 0.0, 1.0, true)
			_range(errors, p, "min_approach_k", 0.0, 20.0)
			# Both endpoint approaches, not just the hot supply, must be valid.
			if _number(p.min_approach_k):
				var hot: Dictionary = temperature_grade(PRIMARY_GRADE)
				var cold: Dictionary = temperature_grade(SECONDARY_GRADE)
				if hot.supply_c - cold.supply_c < p.min_approach_k or hot.return_c - cold.return_c < p.min_approach_k:
					errors.append("固定温区的供/回水端温差均须满足最小换热温差")
		"heat_demand":
			_range(errors, p, "demand_mwth", 0.0, 10000.0)
			_range(errors, p, "priority", 0.0, 1000.0)
			if _number(p.priority) and not _integer(p.priority):
				errors.append("priority must be an integer; lower values are served first")
	return errors

static func validate_state(kind: String, params: Dictionary, state: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not state is Dictionary:
		return ["state must be a dictionary"]
	if not kind in ["battery", "thermal_store", "high_temp_store", "molten_salt_store"]:
		if not state.is_empty():
			errors.append("Only storage devices may have runtime state")
		return errors
	var field: String = "energy_mwhth" if kind in ["thermal_store","high_temp_store","molten_salt_store"] else "energy_mwh"
	var capacity: String = "capacity_mwhth" if kind in ["thermal_store","high_temp_store","molten_salt_store"] else "capacity_mwh"
	var p: Dictionary = defaults(kind)
	p.merge(params, true)
	for key in state:
		if key != field:
			errors.append("Unknown %s state field: %s" % [kind, key])
	if not _number(state.get(field)):
		errors.append(field + " must be finite")
	elif not _number(p.get(capacity)) or float(state[field]) < 0.0 or float(state[field]) > float(p[capacity]):
		errors.append(field + " must be between 0 and " + capacity)
	return errors

static func initial_state(kind: String, params: Dictionary = {}) -> Dictionary:
	if kind == "battery" and validate_storage_load(kind, params).is_empty():
		var p: Dictionary = defaults(kind)
		p.merge(params, true)
		return {"energy_mwh": p.capacity_mwh * p.initial_soc}
	if kind in ["thermal_store","high_temp_store","molten_salt_store"] and validate_thermal(kind, params).is_empty():
		var p: Dictionary = defaults(kind)
		p.merge(params, true)
		return {"energy_mwhth": p.capacity_mwhth * p.initial_soc}
	return {}

static func thermal_storage_limits(params: Dictionary, energy_mwhth: float, dt_s: float) -> Dictionary:
	var p: Dictionary = defaults("thermal_store")
	p.merge(params, true)
	var dt_h: float = dt_s / 3600.0 if is_finite(dt_s) and dt_s > 0.0 else 0.0
	var e0: float = energy_mwhth * exp(-float(p.self_discharge_per_h) * dt_h)
	var result: Dictionary = {"energy_before_mwhth": energy_mwhth, "energy_after_self_discharge_mwhth": e0,
		"self_discharge_mwhth": energy_mwhth - e0, "charge_limit_mwth": 0.0, "discharge_limit_mwth": 0.0}
	if dt_h > 0.0:
		result.charge_limit_mwth = minf(p.charge_mwth, maxf(0.0, p.capacity_mwhth - e0) / (p.charge_efficiency * dt_h))
		result.discharge_limit_mwth = minf(p.discharge_mwth, e0 * p.discharge_efficiency / dt_h)
	return result

## AC-terminal limits after self discharge. Both modes are feasible alternatives,
## never an instruction to activate both. Zero duration freezes all storage flows.
static func storage_limits(params: Dictionary, energy_mwh: float, dt_s: float) -> Dictionary:
	var p: Dictionary = defaults("battery")
	p.merge(params, true)
	var dt_h: float = dt_s / 3600.0
	var e0: float = energy_mwh * exp(-float(p.self_discharge_per_h) * dt_h)
	var result: Dictionary = {"energy_before_mwh": energy_mwh, "energy_after_self_discharge_mwh": e0,
		"self_discharge_mwh": energy_mwh - e0, "charge_limit_mw": 0.0, "discharge_limit_mw": 0.0}
	if dt_h > 0.0:
		result.charge_limit_mw = minf(p.charge_mw, maxf(0.0, p.capacity_mwh - e0) / (p.charge_efficiency * dt_h))
		result.discharge_limit_mw = minf(p.discharge_mw, e0 * p.discharge_efficiency / dt_h)
	return result

static func connection_ports(devices: Array, candidate: Dictionary) -> Dictionary:
	var kinds: Dictionary = {"-1": "grid"}
	for d in devices:
		if d is Dictionary and _integer(d.get("id")):
			kinds[str(int(d.id))] = str(d.get("kind", ""))
	var a: String = str(int(candidate.get("from", -2)))
	var b: String = str(int(candidate.get("to", -2)))
	return {"from_port": str(candidate.get("from_port", "ac" if kinds.get(a) == "battery" else ("ac_out" if kinds.get(a)=="steam_turbine" else "out"))),
		"to_port": str(candidate.get("to_port", "ac" if kinds.get(b) == "battery" else ("ac_in" if kinds.get(b) in ["electric_boiler", "fuel_boiler", "solar_thermal", "parabolic_trough", "oil_water_exchanger", "steam_generator", "steam_condenser", "feedwater_pump", "solar_tower_receiver", "molten_salt_store", "salt_steam_generator"] else "in"))),
		"carrier": str(candidate.get("carrier", CARRIER)),
		"unit": str(candidate.get("unit", "MW")), "grade_id": str(candidate.get("grade_id", ""))}

## Shared UI, save and simulation topology check. Existing links excludes candidate.
## Leaves have one station attachment, stations fan out; no station-station/rings.
static func validate_link(devices: Array, links: Array, candidate: Dictionary) -> String:
	for field in ["from_port", "to_port", "carrier", "unit", "grade_id", "voltage_level"]:
		if candidate.has(field) and not candidate[field] is String:
			return "连接类型字段必须为字符串：" + field
	if not _integer(candidate.get("from")) or not _integer(candidate.get("to")):
		return "线路端点必须是整数设备ID"
	var a: int = int(candidate.from)
	var b: int = int(candidate.to)
	if a == b:
		return "不支持设备自连接"
	var nodes: Dictionary = {}
	for d in devices:
		if d is Dictionary and _integer(d.get("id")) and int(d.id) >= 0:
			nodes[int(d.id)] = str(d.get("kind", ""))
	if not nodes.has(a) or (b != -1 and not nodes.has(b)):
		return "连接端点设备不存在"
	var ak: String = nodes[a]
	var bk: String = "grid" if b == -1 else str(nodes[b])
	var names: Dictionary = connection_ports(devices, candidate)
	var ap: Dictionary = port(ak, names.from_port)
	var bp: Dictionary = port(bk, names.to_port)
	if ap.is_empty() or bp.is_empty():
		return "未知设备端口；热连接必须显式指定端口"
	if not ap.direction in ["output", "bidirectional"] or not bp.direction in ["input", "bidirectional"]:
		return "端口方向必须为输出到输入"
	if ap.carrier != bp.carrier or names.carrier != ap.carrier:
		return "电口与热口不可互连，载体必须一致"
	var thermal: bool = names.carrier in [THERMAL_CARRIER,OIL_CARRIER,SALT_CARRIER]
	var mass: bool = names.carrier == MASS_CARRIER
	if mass:
		for field in ["from_port","to_port","carrier","unit","grade_id","mass_flow_capacity_kg_s","loss_fraction"]:
			if not candidate.has(field): return "循环质量连接缺少字段："+field
		for field in ["capacity_mw","capacity_mwth","voltage_level"]:
			if candidate.has(field): return "循环质量连接仅使用kg/s容量"
		if names.unit!="kg/s" or ap.grade_id!=bp.grade_id or names.grade_id!=ap.grade_id: return "蒸汽/凝结水/给水状态品位或单位不匹配"
		var expected: Dictionary={"steam_generator":"steam_turbine","steam_turbine":"steam_condenser","steam_condenser":"feedwater_pump","feedwater_pump":"steam_generator"}
		if expected.get("steam_generator" if ak == "salt_steam_generator" else ak,"")!=("steam_generator" if bk == "salt_steam_generator" else bk): return "质量连接必须沿蒸汽发生器→汽轮机→凝汽器→给水泵→蒸汽发生器"
		if not _number(candidate.mass_flow_capacity_kg_s) or float(candidate.mass_flow_capacity_kg_s)<0.0 or float(candidate.mass_flow_capacity_kg_s)>1000.0: return "质量流量容量必须为0至1000kg/s"
		if not _number(candidate.loss_fraction) or float(candidate.loss_fraction)!=0.0: return "闭合循环不允许质量泄漏"
	elif thermal:
		for field in ["from_port", "to_port", "carrier", "unit", "grade_id", "capacity_mwth", "loss_fraction"]:
			if not candidate.has(field):
				return "热连接缺少显式字段：" + field
		if candidate.has("capacity_mw") or candidate.has("voltage_level"):
			return "热连接只允许MWth热容量，不允许电容量或电压"
		if names.unit != "MWth":
			return "热连接单位必须为MWth"
		if ap.grade_id != bp.grade_id or names.grade_id != ap.grade_id:
			return "温区不匹配：主温区90/60°C须经换热器降至70/40°C"
		var legal: bool = (ak in ["electric_boiler", "fuel_boiler", "solar_thermal"] and bk in ["heat_exchanger", "thermal_store"]) or (ak == "thermal_store" and bk == "heat_exchanger") or (ak == "heat_exchanger" and bk == "heat_demand") or (ak == "parabolic_trough" and bk in ["high_temp_store","oil_water_exchanger","steam_generator"]) or (ak == "high_temp_store" and bk in ["oil_water_exchanger","steam_generator"]) or (ak == "oil_water_exchanger" and bk == "heat_exchanger") or (ak == "solar_tower_receiver" and bk in ["molten_salt_store","salt_steam_generator"]) or (ak == "molten_salt_store" and bk == "salt_steam_generator")
		if not legal:
			return "热连接仅支持锅炉→储热/换热器、储热→换热器、换热器→热需求"
		if not _number(candidate.capacity_mwth) or float(candidate.capacity_mwth) < 0.0 or float(candidate.capacity_mwth) > 10000.0:
			return "热线路容量必须为0至10000的有限MWth数值"
		if not _number(candidate.loss_fraction) or float(candidate.loss_fraction) != 0.0:
			return "首版固定温区热线路loss_fraction必须为0"
	else:
		if bk in ["electric_boiler", "fuel_boiler", "solar_thermal", "parabolic_trough", "oil_water_exchanger", "steam_generator", "steam_condenser", "feedwater_pump", "solar_tower_receiver", "molten_salt_store", "salt_steam_generator"]:
			for field in ["from_port", "to_port", "carrier", "unit"]:
				if not candidate.has(field):
					return "锅炉电输入必须显式指定字段：" + field
		var legal: bool = (ak in ["wind", "pv", "battery", "steam_turbine"] and bk == "station") or (ak == "station" and bk in ["load", "battery", "grid", "electric_boiler", "fuel_boiler", "solar_thermal", "parabolic_trough", "oil_water_exchanger", "steam_generator", "steam_condenser", "feedwater_pump", "solar_tower_receiver", "molten_salt_store", "salt_steam_generator"])
		if not legal:
			return "电连接仅支持电源/电池→站→负荷/电池/锅炉电输入/电网"
		if candidate.has("capacity_mwth") or (candidate.has("grade_id") and not str(candidate.grade_id).is_empty()):
			return "电线路不允许热容量或热温区"
		if names.unit != "MW":
			return "电线路单位必须为MW"
		if candidate.has("voltage_level") and candidate.voltage_level != VOLTAGE_LEVEL:
			return "电口电压等级必须为AC_BUS"
		if not _number(candidate.get("capacity_mw", 4.0)) or float(candidate.get("capacity_mw", 4.0)) < 0.0:
			return "电线路容量必须为有限非负数"
		if not _number(candidate.get("loss_fraction", 0.01)) or float(candidate.get("loss_fraction", 0.01)) < 0.0 or float(candidate.get("loss_fraction", 0.01)) >= 1.0:
			return "电线路损耗率必须为[0,1)内有限数"
	var leaf: int = a if ak != "station" else b
	for old in links:
		if not old is Dictionary or not _integer(old.get("from")) or not _integer(old.get("to")):
			continue
		var old_names: Dictionary = connection_ports(devices, old)
		if old_names.carrier != names.carrier:
			continue
		var x: int = int(old.from)
		var y: int = int(old.to)
		if mass:
			if (a==x and names.from_port==old_names.from_port) or (b==y and names.to_port==old_names.to_port): return "每个循环质量端口仅允许一条连接"
		elif thermal:
			if a == x and b == y and old_names.from_port == names.from_port and old_names.to_port == names.to_port:
				return "同一对热端口不可重复连接"
		else:
			if (a == x and b == y) or (a == y and b == x):
				return "重复电连接；电池使用同一条双向电缆"
			if leaf >= 0 and (leaf == x or leaf == y):
				return "每个电源、负荷、锅炉电输入或电池仅可接入一座电站"
	return ""

static func validate_topology(devices: Array, links: Array) -> Array[String]:
	var errors: Array[String] = []
	var accepted: Array = []
	for i in links.size():
		if not links[i] is Dictionary:
			errors.append("Line %d: malformed link" % i)
			continue
		var reason: String = validate_link(devices, accepted, links[i])
		if reason.is_empty():
			accepted.append(links[i])
		else:
			errors.append("Line %d: %s" % [i, reason])
	return errors
