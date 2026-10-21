extends RefCounted
## Absorber-area evacuated tube efficiency curve, fixed primary 90/60 C.
## Existing climate irradiance_wm2 is teaching equivalent POA, not DNI/GHI.
## No tracking, concentration, thermal inertia, or second transposition is implied.
const Catalog = preload("res://scripts/device_catalog.gd")
const FIELDS = ["incident_mw", "optical_rejection_mw", "potential_thermal_loss_mw", "thermal_loss_mw", "available_mwth", "useful_mwth", "curtailed_mwth", "auxiliary_electric_mw"]

static func empty() -> Dictionary:
	var result: Dictionary = {}
	for key in FIELDS: result[key] = 0.0
	return result

static func evaluate(params: Dictionary, weather: Dictionary) -> Dictionary:
	var p: Dictionary = Catalog.defaults("solar_thermal")
	p.merge(params, true)
	var result: Dictionary = empty()
	var errors: Array[String] = Catalog.validate_thermal("solar_thermal", p)
	for key in ["irradiance_wm2", "air_temp_c"]:
		var value: Variant = weather.get(key, 0.0 if key == "irradiance_wm2" else 25.0)
		if not (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) or not is_finite(float(value)):
			errors.append("Solar weather must be finite: " + key)
	if errors.is_empty():
		if float(weather.get("irradiance_wm2", 0.0)) < 0.0 or float(weather.get("irradiance_wm2", 0.0)) > 2000.0:
			errors.append("Solar POA irradiance must be in [0,2000] W/m2")
		if float(weather.get("air_temp_c", 25.0)) < -100.0 or float(weather.get("air_temp_c", 25.0)) > 100.0:
			errors.append("Solar ambient temperature must be in [-100,100] C")
	if weather.has("is_day") and not weather.is_day is bool:
		errors.append("Solar is_day must be boolean")
	var irradiance_kind: String = str(weather.get("irradiance_kind", "teaching_equivalent_poa"))
	if not irradiance_kind in ["teaching_equivalent_poa", "poa", "plane_of_array"]:
		errors.append("Solar requires POA irradiance; GHI/DNI are not silently reinterpreted")
	result.merge({"valid": errors.is_empty(), "errors": errors, "poa_wm2": 0.0, "mean_fluid_temp_c": 75.0,
		"irradiance_kind": irradiance_kind, "area_basis": "absorber"})
	if not errors.is_empty(): return result
	var poa: float = float(weather.get("irradiance_wm2", 0.0))
	# A supplied solar-geometry night flag also closes any inconsistent imported irradiance.
	if weather.get("is_day", true) == false: poa = 0.0
	var mean_temp: float = (float(p.supply_temp_c) + float(p.return_temp_c)) * 0.5
	var delta: float = maxf(0.0, mean_temp - float(weather.get("air_temp_c", 25.0)))
	var area: float = float(p.absorber_area_m2)
	result.poa_wm2 = poa
	result.mean_fluid_temp_c = mean_temp
	result.incident_mw = area * poa / 1.0e6
	var absorbed: float = result.incident_mw * float(p.optical_efficiency)
	result.optical_rejection_mw = result.incident_mw - absorbed
	result.potential_thermal_loss_mw = area * (float(p.heat_loss_w_m2k) * delta + float(p.heat_loss_quadratic_w_m2k2) * delta * delta) / 1.0e6
	result.thermal_loss_mw = minf(absorbed, result.potential_thermal_loss_mw)
	result.available_mwth = maxf(0.0, absorbed - result.potential_thermal_loss_mw)
	result.curtailed_mwth = result.available_mwth
	return result

static func initial_energy() -> Dictionary:
	return {"incident_mwh": 0.0, "optical_rejection_mwh": 0.0, "thermal_loss_mwh": 0.0,
		"available_mwhth": 0.0, "useful_mwhth": 0.0, "curtailed_mwhth": 0.0, "auxiliary_mwh": 0.0}

static func validate_energy(value: Variant) -> String:
	if not value is Dictionary: return "solar_energy must be an object"
	var fields: Dictionary = initial_energy()
	for key in value:
		if not fields.has(key): return "Unknown solar energy field: " + str(key)
	for key in fields:
		var v: Variant = value.get(key)
		if not (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) or not is_finite(float(v)) or float(v) < 0.0:
			return "Solar energy must be finite and nonnegative: " + key
	var tol: float = 1.0e-6 + 1.0e-7 * float(value.incident_mwh)
	if absf(float(value.incident_mwh) - float(value.optical_rejection_mwh) - float(value.thermal_loss_mwh) - float(value.available_mwhth)) > tol:
		return "Solar incident energy balance mismatch"
	if absf(float(value.available_mwhth) - float(value.useful_mwhth) - float(value.curtailed_mwhth)) > tol:
		return "Solar useful energy balance mismatch"
	if float(value.auxiliary_mwh) < float(value.useful_mwhth) * 0.001 - tol or float(value.auxiliary_mwh) > float(value.useful_mwhth) * 0.2 + tol:
		return "Solar auxiliary energy ratio mismatch"
	return ""
