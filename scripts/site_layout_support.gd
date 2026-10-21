extends RefCounted
## Versioned, pure site-support contract. This is not an engineering certificate.
## Read/restore never mutates a legacy device or clamps a stored physical rating.
## World must separately verify as-built geometry and collisions before assigning
## SITE_GEOMETRY_PROFILE. Core energy/material equations intentionally unchanged.
const SPEC_ID := "site_layout_support_v1"
const SPEC_VERSION := 1
const SITE_GEOMETRY_PROFILE := "reference_size_v1"
const SPEC_PATH := "res://data/site_layout_support_v1.json"
static var _cache: Dictionary = {}

static func _data() -> Dictionary:
	if _cache.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SPEC_PATH))
		if parsed is Dictionary and parsed.get("spec_id") == SPEC_ID and parsed.get("spec_version") == SPEC_VERSION and parsed.get("site_geometry_profile") == SITE_GEOMETRY_PROFILE and parsed.get("kinds") is Dictionary:
			_cache = parsed
	return _cache

static func spec() -> Dictionary:
	return _data().duplicate(true)

static func shared_spec_version() -> int:
	return SPEC_VERSION

static func supported_kinds() -> Array:
	return _data().get("kinds", {}).keys()

static func parameter_limits(kind: String) -> Dictionary:
	return _data().get("kinds", {}).get(kind, {}).get("bounds", {}).duplicate(true)

static func geometry(kind: String) -> Dictionary:
	return _data().get("kinds", {}).get(kind, {}).get("geometry", {}).duplicate(true)

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _issue(code: String, parameter: String, message: String) -> Dictionary:
	return {"code":code,"parameter":parameter,"message":message}

static func _base() -> Dictionary:
	return {"spec_id":SPEC_ID,"spec_version":SPEC_VERSION,"profile_id":SITE_GEOMETRY_PROFILE,
		"id":null,"kind":"","applicable":true,"supported":true,"needs_migration":false,
		"operable":true,"issues":[],"supported_bounds":{},"required_geometry":{}}

static func _invalid(result: Dictionary, issue: Dictionary) -> Dictionary:
	result.supported = false
	result.needs_migration = true
	result.operable = false
	result.issues.append(issue)
	return result

## params must contain the normal Catalog-resolved parameters. This module does
## not merge dynamic defaults, so a future Catalog change cannot rewrite v1.
static func assess_device(device: Variant) -> Dictionary:
	var out := _base()
	var data := _data()
	if data.is_empty(): return _invalid(out,_issue("invalid_spec","","Site layout specification could not be loaded."))
	if not device is Dictionary: return _invalid(out,_issue("invalid_device","","Device must be a dictionary."))
	out.id = device.get("id")
	if not device.get("kind") is String or str(device.kind).is_empty():
		return _invalid(out,_issue("invalid_device_kind","kind","Device kind must be a nonempty string."))
	out.kind = device.kind
	if not data.kinds.has(out.kind):
		out.applicable = false
		return out
	out.supported_bounds = parameter_limits(out.kind)
	if not device.get("params") is Dictionary:
		return _invalid(out,_issue("invalid_parameters","params","Device params must be a dictionary."))
	var params: Dictionary = device.params
	for key in out.supported_bounds:
		var bound: Dictionary = out.supported_bounds[key]
		if not params.has(key):
			out.issues.append(_issue("missing_parameter",key,"Layout parameter is missing."))
		elif not _number(params[key]):
			out.issues.append(_issue("invalid_parameter",key,"Layout parameter must be a finite number."))
		elif float(params[key]) < float(bound.min) or float(params[key]) > float(bound.max) or (bool(bound.get("min_exclusive",false)) and float(params[key]) == float(bound.min)):
			var problem := _issue("outside_supported_range",key,"Layout parameter is outside the supported site envelope.")
			problem.actual = params[key]
			problem.maximum = bound.max
			out.issues.append(problem)
	if out.kind == "battery_flow" and device.get("site_geometry_profile") == SITE_GEOMETRY_PROFILE and device.has("geometry_profile") and (not device.geometry_profile is String or str(device.geometry_profile) != "flow_process_v2"):
		out.issues.append(_issue("incompatible_geometry_profile","geometry_profile","Reference-size flow storage requires flow_process_v2; old icon geometry must remain in legacy compatibility until migrated."))
	out.supported = out.issues.is_empty()
	if out.supported:
		out.required_geometry = required_geometry(out.kind,params)
		if out.required_geometry.has("energy_screen_pass") and not out.required_geometry.energy_screen_pass:
			out.supported = false
			var problem := _issue("energy_screen_exceeded","discharge_efficiency","Capacity times discharge efficiency exceeds the finite net-electric geometry screen.")
			problem.actual = out.required_geometry.requested_net_electric_mwh
			problem.maximum = out.required_geometry.net_electric_screen_mwh
			out.issues.append(problem)
		if out.required_geometry.has("hardware_capacity_sufficient") and not out.required_geometry.hardware_capacity_sufficient:
			out.supported = false
			out.issues.append(_issue("insufficient_spec_geometry","","Reference hardware does not meet its own minimum volume."))
	if device.get("site_geometry_profile") != SITE_GEOMETRY_PROFILE:
		var problem := _issue("profile_migration_required","site_geometry_profile","Explicit site geometry migration is required; stored ratings and inventory must remain unchanged.")
		if device.get("site_geometry_profile") is String: problem.actual = device.site_geometry_profile
		out.issues.append(problem)
		out.needs_migration = true
	out.needs_migration = out.needs_migration or not out.supported
	out.operable = out.supported and not out.needs_migration
	return out

static func assess_world(devices: Variant) -> Dictionary:
	var out := {"spec_id":SPEC_ID,"spec_version":SPEC_VERSION,"profile_id":SITE_GEOMETRY_PROFILE,
		"supported":true,"needs_migration":false,"operable":true,"devices":[],"issues":[]}
	if not devices is Array:
		out.supported=false;out.needs_migration=true;out.operable=false
		out.issues.append(_issue("invalid_devices","devices","Devices must be an array."))
		return out
	for device in devices:
		var item := assess_device(device)
		out.devices.append(item)
		out.supported = out.supported and item.supported
		out.needs_migration = out.needs_migration or item.needs_migration
		out.operable = out.operable and item.operable
		for problem in item.issues:
			var copy: Dictionary = problem.duplicate(true)
			copy.device_id = item.id
			out.issues.append(copy)
	return out

## Geometry requirements use full supported hardware even when operational
## capacity is reduced. All lengths are internal NET dimensions in metres.
## An internal capsule is a cylinder plus two hemispheres, not a full cylinder
## whose stated length already includes its heads.
static func required_geometry(kind: String, params: Dictionary) -> Dictionary:
	var g := geometry(kind)
	if g.is_empty(): return {}
	g.as_built_verified = false
	if g.method == "bounded_existing_layout": return g
	if g.method in ["compressed_air_static_screen","liquid_air_static_screen"]: return _air_energy_screen(g,params)
	var key: String = g.capacity_key
	if not _number(params.get(key)): return {}
	var requested := float(params[key])
	var installed := float(g.installed_capacity)
	g.requested_capacity = requested
	var mass_per_capacity: float
	var density: float
	if g.method == "gas":
		mass_per_capacity = float(g.capacity_to_mass_kg)
		density = float(g.sizing_density_kg_m3)
	else:
		var specific_energy := float(g.get("specific_enthalpy_difference_j_kg",0.0))
		if g.method == "sensible": specific_energy = float(g.specific_heat_j_kg_k) * (float(g.hot_temperature_c)-float(g.cold_temperature_c))
		mass_per_capacity = 3600000000.0 / specific_energy
		density = float(g.density_kg_m3)
	g.required_material_mass_kg = requested * mass_per_capacity
	g.minimum_installed_material_mass_kg = installed * mass_per_capacity
	g.required_effective_volume_m3 = g.required_material_mass_kg / density
	g.minimum_installed_effective_volume_m3 = g.minimum_installed_material_mass_kg / density
	var copies := float(g.get("inventory_volume_copies",1.0))
	var fraction := float(g.get("material_volume_fraction",1.0))
	g.minimum_container_volume_m3 = g.minimum_installed_effective_volume_m3 * copies / fraction
	var hw: Dictionary = g.hardware
	var n := float(hw.count)
	var hardware_volume := 0.0
	match str(hw.shape):
		"capsule_bank":
			var r := float(hw.internal_radius_m)
			hardware_volume = n * (PI*r*r*float(hw.straight_length_m) + 4.0/3.0*PI*r*r*r)
		"parallel_cylinders":
			var r := float(hw.internal_radius_m)
			hardware_volume = n * PI*r*r*float(hw.straight_length_m)
		"solid_blocks":
			var d: Array = hw.net_block_dimensions_m
			hardware_volume = n * float(d[0])*float(d[1])*float(d[2])
		"ellipsoid":
			var d: Array = hw.internal_diameters_m
			hardware_volume = n * PI/6.0*float(d[0])*float(d[1])*float(d[2])
			fraction = float(hw.usable_volume_fraction)
			g.minimum_container_volume_m3 = g.minimum_installed_effective_volume_m3 / fraction
		"two_tanks_derived":
			var each := float(g.minimum_container_volume_m3)/n
			var ratio := float(hw.height_to_diameter)
			var diameter := pow(4.0*each/(PI*ratio),1.0/3.0)
			hw.internal_radius_m = diameter*.5
			hw.straight_length_m = diameter*ratio
			hardware_volume = n*PI*diameter*diameter*.25*diameter*ratio
	g.hardware_internal_volume_m3 = hardware_volume
	g.hardware_effective_volume_m3 = hardware_volume * fraction
	g.hardware_capacity_sufficient = g.hardware_effective_volume_m3 + 1e-9 >= g.minimum_installed_effective_volume_m3 * copies
	return g

## Static necessary screen only, not a pressure/liquid-level state or process solver.
## Internal SOC is compared with AC output only AFTER the existing discharge loss.
static func _air_energy_screen(g: Dictionary, params: Dictionary) -> Dictionary:
	if not _number(params.get("capacity_mwh")) or not _number(params.get("discharge_efficiency")): return {}
	var hw: Dictionary = g.hardware
	var volume: float = float(hw.count)*PI*pow(float(hw.internal_radius_m),2.0)*float(hw.straight_length_m)
	var fraction: float = float(g.material_volume_fraction)
	g.hardware_internal_volume_m3 = volume
	g.hardware_effective_volume_m3 = volume*fraction
	g.requested_capacity = float(params.capacity_mwh)
	g.requested_net_electric_mwh = float(params.capacity_mwh)*float(params.discharge_efficiency)
	var output_density: float
	if g.method == "compressed_air_static_screen":
		var pressure: float = float(g.reference_pressure_bar_abs)*100000.0
		var ambient: float = float(g.ambient_pressure_bar_abs)*100000.0
		var ratio: float = ambient/pressure
		var gamma: float = float(g.air_heat_capacity_ratio)
		# Integrate cp*(T_tank-T_expander_out) dm over ideal adiabatic blowdown.
		output_density = pressure/(gamma-1.0)*(1.0+(gamma-1.0)*ratio-gamma*pow(ratio,(gamma-1.0)/gamma))/3600000000.0
		g.ideal_isothermal_availability_mwh = volume*(pressure*log(pressure/ambient)-pressure+ambient)/3600000000.0
		g.ideal_adiabatic_no_reheat_mwh = volume*output_density
		g.reference_full_pressure_gas_mass_kg = pressure*volume/(float(g.ideal_air_gas_constant_j_kg_k)*float(g.reference_temperature_k))
	else:
		g.reference_maximum_liquid_mass_kg = volume*fraction*float(g.density_kg_m3)
		output_density = float(g.density_kg_m3)*float(g.net_specific_output_screen_kj_kg)/3600000.0
		g.required_liquid_mass_kg = float(g.requested_net_electric_mwh)*3600000.0/float(g.net_specific_output_screen_kj_kg)
	g.net_electric_screen_mwh = volume*fraction*output_density
	g.required_effective_volume_m3 = float(g.requested_net_electric_mwh)/output_density
	g.required_container_volume_m3 = float(g.required_effective_volume_m3)/fraction
	g.energy_screen_pass = float(g.requested_net_electric_mwh) <= float(g.net_electric_screen_mwh)
	g.screen_is_performance_guarantee = false
	g.pressure_vessel_certified = false
	return g

## Explicit opt-in preserves historical solver/runtime contracts. Any marker,
## including malformed/null, opts the whole world into strict reference layout;
## a partially migrated world cannot silently run as legacy compatibility.
static func validate_for_model(devices: Variant, require_reference: bool = false) -> Dictionary:
	var enabled := require_reference or not devices is Array
	if devices is Array:
		for device in devices:
			if device is Dictionary and device.has("site_geometry_profile"): enabled = true
	if enabled:
		var result := assess_world(devices)
		result.mode = "reference_layout"
		result.applied = true
		return result
	return {"spec_id":SPEC_ID,"spec_version":SPEC_VERSION,"profile_id":SITE_GEOMETRY_PROFILE,
		"supported":true,"needs_migration":false,"operable":true,"devices":[],"issues":[],
		"mode":"legacy_compatibility","applied":false}
