extends RefCounted
## Fixed, dimensioned chemistry contracts. Chemical mass is the only inventory
## truth; LHV indicators and reference-state reaction heat are distinct ledgers.
const PROFILE_ID := "material_hydrogen_2a_v1"
const PROFILE_VERSION := 1
const LEGACY_KINDS := ["water_supply_boundary", "electrolyzer_station", "hydrogen_gas_store", "fuel_cell_station"]
const PHASE_KINDS := ["hydrogen_liquid_store", "hydrogen_metal_hydride_store"]
const CHEMICAL_KINDS := ["nitrogen_supply_boundary", "co2_supply_boundary", "ammonia_synthesis_station", "methanol_synthesis_station"]
const SYNTHESIS_KINDS := ["ammonia_synthesis_station", "methanol_synthesis_station"]
const FEED_KINDS := ["nitrogen_supply_boundary", "co2_supply_boundary"]
const CHEMICAL_PROFILE_ID := "material_chemical_2c_v3"
const CHEMICAL_PROFILE_VERSION := 3
const KINDS := ["water_supply_boundary", "electrolyzer_station", "hydrogen_gas_store", "fuel_cell_station", "hydrogen_liquid_store", "hydrogen_metal_hydride_store", "nitrogen_supply_boundary", "co2_supply_boundary", "ammonia_synthesis_station", "methanol_synthesis_station"]
const HYDROGEN_STORE_KINDS := ["hydrogen_gas_store", "hydrogen_liquid_store", "hydrogen_metal_hydride_store"]
const INVENTORY_KINDS := ["water_supply_boundary", "hydrogen_gas_store", "hydrogen_liquid_store", "hydrogen_metal_hydride_store", "nitrogen_supply_boundary", "co2_supply_boundary", "ammonia_synthesis_station", "methanol_synthesis_station"]
const PHASE_PROFILE_ID := "material_hydrogen_2b_v2"
const PHASE_PROFILE_VERSION := 2
const CARRIERS := ["material_water", "material_h2_gas", "material_n2_gas", "material_co2_gas"]
static var _chemical_profile: Dictionary = {}
static var _profile: Dictionary = {}
static var _phase_profile: Dictionary = {}

static func profile() -> Dictionary:
	if _profile.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/material_process_profiles_v1.json"))
		if parsed is Dictionary and parsed.get("profile_id") == PROFILE_ID and parsed.get("profile_version") == PROFILE_VERSION:
			_profile = parsed
	return _profile.duplicate(true)

static func coefficients() -> Dictionary:
	var data: Dictionary = profile()
	var atoms: Dictionary = data.atomic_mass_kg_per_kmol
	var h2: float = 2.0 * float(atoms.H)
	var oxygen: float = float(atoms.O)
	var water: Dictionary = data.species.H2O
	return {"water_per_h2": (h2 + oxygen) / h2, "oxygen_per_h2": oxygen / h2,
		"lhv_kwh_per_kg": -float(water.vapor_formation_enthalpy_kj_per_kmol) / h2 / 3600.0,
		"hhv_kwh_per_kg": -float(water.formation_enthalpy_kj_per_kmol) / h2 / 3600.0,
		"hydrogen_fraction_water": h2 / (h2 + oxygen)}

static func phase_profile() -> Dictionary:
	if _phase_profile.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/material_process_profiles_v2.json"))
		if parsed is Dictionary and parsed.get("profile_id") == PHASE_PROFILE_ID and parsed.get("profile_version") == PHASE_PROFILE_VERSION: _phase_profile = parsed
	return _phase_profile.duplicate(true)

static func model_profile(kind: String) -> String:
	return CHEMICAL_PROFILE_ID if kind in CHEMICAL_KINDS else PHASE_PROFILE_ID if kind in PHASE_KINDS else PROFILE_ID

static func model_profile_version(kind: String) -> int:
	return CHEMICAL_PROFILE_VERSION if kind in CHEMICAL_KINDS else PHASE_PROFILE_VERSION if kind in PHASE_KINDS else PROFILE_VERSION

static func defaults(kind: String) -> Dictionary:
	return (chemical_profile() if kind in CHEMICAL_KINDS else phase_profile() if kind in PHASE_KINDS else profile()).get("defaults", {}).get(kind, {}).duplicate(true)

static func inventory_capacity(kind: String, params: Dictionary = {}) -> float:
	var p: Dictionary = defaults(kind)
	p.merge(params, true)
	return float(p.get("dry_host_mass_kg",0.0)) * float(phase_profile().constants.dry_host_hydrogen_fraction) if kind == "hydrogen_metal_hydride_store" else float(p.get("capacity_kg",0.0))

static func reference_id(kind: String) -> String:
	return {"water_supply_boundary":"H2O_liquid_25c","hydrogen_gas_store":"H2_gas_25c","hydrogen_liquid_store":"H2_liquid_20k","hydrogen_metal_hydride_store":"H2_bound_lani5","nitrogen_supply_boundary":"N2_gas_25c","co2_supply_boundary":"CO2_gas_25c","ammonia_synthesis_station":"NH3_gas_25c","methanol_synthesis_station":"CH3OH_liquid_25c"}.get(kind, "")

static func phase_coefficients(kind: String) -> Dictionary:
	var c: Dictionary = phase_profile().constants
	if kind == "hydrogen_liquid_store":
		return {"enthalpy_kwh_per_kg":c.liquid_phase_enthalpy_kwh_per_kg,"charge_kwh_per_kg":c.liquefaction_kwh_per_kg,"discharge_kwh_per_kg":c.vaporizer_aux_kwh_per_kg,"ambient_kwh_per_kg":-c.liquid_phase_enthalpy_kwh_per_kg,"leak_per_h":c.boiloff_per_h}
	if kind == "hydrogen_metal_hydride_store":
		return {"enthalpy_kwh_per_kg":c.metal_binding_enthalpy_kwh_per_kg,"charge_kwh_per_kg":c.adsorption_aux_kwh_per_kg,"discharge_kwh_per_kg":c.desorption_aux_kwh_per_kg+(-c.metal_binding_enthalpy_kwh_per_kg+c.desorption_process_heat_kwh_per_kg)/c.heater_efficiency,"ambient_kwh_per_kg":0.0,"leak_per_h":0.0}
	return {}


static func _number(x: Variant) -> bool:
	return (x is int or x is float) and is_finite(float(x))

static func validate(kind: String, params: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var p: Dictionary = defaults(kind)
	if p.is_empty(): return ["Unknown material kind: " + kind]
	for key in params:
		if not p.has(key): errors.append("Unknown material parameter: " + str(key))
	p.merge(params, true)
	for key in p:
		if not _number(p[key]) or float(p[key]) < 0.0:
			errors.append(str(key) + " must be finite and nonnegative")
	if not errors.is_empty(): return errors
	if kind in PHASE_KINDS or kind in CHEMICAL_KINDS:
		var maxima: Dictionary = (chemical_profile() if kind in CHEMICAL_KINDS else phase_profile()).maximums[kind]
		for key in p:
			if float(p[key]) > float(maxima[key]): errors.append(key + " exceeds fixed facility maximum")
		if inventory_capacity(kind,p) <= 0.0: errors.append("Finite hydrogen capacity must be positive")
		if float(p.initial_inventory_kg) > inventory_capacity(kind,p): errors.append("Initial hydrogen exceeds phase capacity")
		return errors
	for key in ["capacity_kg", "rated_electric_mw", "compressor_electric_mw"]:
		if p.has(key) and (float(p[key]) <= 0.0 or float(p[key]) > (1.0e9 if key == "capacity_kg" else 10000.0)):
			errors.append(key + " is outside positive bounded capacity range")
	for key in ["max_outflow_kg_s", "max_hydrogen_kg_s", "charge_kg_s", "discharge_kg_s"]:
		if p.has(key) and float(p[key]) > 1000.0: errors.append(key + " must not exceed 1000 kg/s")
	if p.has("initial_inventory_kg") and float(p.initial_inventory_kg) > float(p.capacity_kg): errors.append("Initial inventory exceeds capacity")
	if kind == "electrolyzer_station" and (float(p.electricity_kwh_per_kg) < coefficients().hhv_kwh_per_kg or float(p.electricity_kwh_per_kg) > 1000.0):
		errors.append("Electrolysis net electricity must cover liquid-water reaction enthalpy; no external free heat")
	if kind == "hydrogen_gas_store":
		if float(p.compression_kwh_per_kg) <= 0.0 or float(p.compression_kwh_per_kg) > 1000.0: errors.append("Compression electricity must be positive and bounded")
		if float(p.leak_per_h) > 1.0: errors.append("Leak rate must be within [0,1] per hour")
	if kind == "fuel_cell_station" and (float(p.net_efficiency_lhv) <= 0.0 or float(p.net_efficiency_lhv) > 1.0): errors.append("Net LHV efficiency must be within (0,1]")
	return errors

static func species(kind: String) -> String:
	return {"water_supply_boundary":"H2O","nitrogen_supply_boundary":"N2","co2_supply_boundary":"CO2","ammonia_synthesis_station":"NH3","methanol_synthesis_station":"CH3OH"}.get(kind,"H2" if kind in HYDROGEN_STORE_KINDS else "")

static func initial_state(kind: String, params: Dictionary = {}) -> Dictionary:
	if not kind in INVENTORY_KINDS: return {}
	var p: Dictionary = defaults(kind)
	p.merge(params, true)
	var state: Dictionary = {"material_inventory_kg": {species(kind): p.initial_inventory_kg}}
	if kind == "hydrogen_metal_hydride_store": state.host_dry_mass_kg = p.dry_host_mass_kg
	return state

static func validate_state(kind: String, params: Dictionary, state: Variant) -> Array[String]:
	if not state is Dictionary: return ["Material state must be a dictionary"]
	if not kind in INVENTORY_KINDS:
		if not state.is_empty(): return ["Material converter cannot hold implicit inventory"]
		return []
	if state.size() != (2 if kind == "hydrogen_metal_hydride_store" else 1) or not state.get("material_inventory_kg") is Dictionary: return ["Material state requires only material_inventory_kg"]
	var stock: Dictionary = state.material_inventory_kg
	var sp: String = species(kind)
	if stock.size() != 1 or not stock.has(sp): return ["Material inventory species does not match facility"]
	var p: Dictionary = defaults(kind)
	p.merge(params, true)
	if kind == "hydrogen_metal_hydride_store" and (not _number(state.get("host_dry_mass_kg")) or state.host_dry_mass_kg != p.dry_host_mass_kg): return ["LaNi5 dry host is immutable and must match configuration"]
	if not _number(stock[sp]) or float(stock[sp]) < 0.0 or float(stock[sp]) > inventory_capacity(kind,p): return ["Material inventory must be finite and within capacity"]
	return []

static func _ac(id: String, direction: String) -> Dictionary:
	return {"id":id,"direction":direction,"carrier":"electricity_ac","unit":"MW","voltage_level":"AC_BUS"}

static func _mass(id: String, direction: String, carrier: String, sp: String, phase: String, grade: String) -> Dictionary:
	return {"id":id,"direction":direction,"carrier":carrier,"unit":"kg/s","species_id":sp,"phase_id":phase,"grade_id":grade}

static func ports(kind: String) -> Array:
	match kind:
		"nitrogen_supply_boundary": return [_mass("n2_out","output","material_n2_gas","N2","gas","n2_gas_25c")]
		"co2_supply_boundary": return [_mass("co2_out","output","material_co2_gas","CO2","gas","co2_gas_25c")]
		"ammonia_synthesis_station": return [_ac("ac_in","input"),_mass("h2_in","input","material_h2_gas","H2","gas","h2_gas_delivery"),_mass("n2_in","input","material_n2_gas","N2","gas","n2_gas_25c")]
		"methanol_synthesis_station": return [_ac("ac_in","input"),_mass("h2_in","input","material_h2_gas","H2","gas","h2_gas_delivery"),_mass("co2_in","input","material_co2_gas","CO2","gas","co2_gas_25c")]
		"water_supply_boundary": return [_mass("water_out","output","material_water","H2O","liquid","water_liquid_25c")]
		"electrolyzer_station": return [_ac("ac_in","input"),_mass("water_in","input","material_water","H2O","liquid","water_liquid_25c"),_mass("h2_out","output","material_h2_gas","H2","gas","h2_gas_supply")]
		"hydrogen_gas_store", "hydrogen_liquid_store", "hydrogen_metal_hydride_store": return [_ac("ac_in","input"),_mass("h2_in","input","material_h2_gas","H2","gas","h2_gas_supply"),_mass("h2_out","output","material_h2_gas","H2","gas","h2_gas_delivery")]
		"fuel_cell_station": return [_ac("ac_out","output"),_mass("h2_in","input","material_h2_gas","H2","gas","h2_gas_delivery")]
	return []

static func validate_link(ak: String, bk: String, candidate: Dictionary, ap: Dictionary, bp: Dictionary) -> String:
	for key in ["from_port","to_port","carrier","unit","species_id","phase_id","grade_id","mass_flow_capacity_kg_s","loss_fraction"]:
		if not candidate.has(key): return "Material line missing " + key
	for key in ["capacity_mw","capacity_mwth","voltage_level"]:
		if candidate.has(key): return "Material line cannot mix energy capacity units"
	for key in ["carrier","unit","species_id","phase_id","grade_id"]:
		if not candidate[key] is String or candidate[key] != ap.get(key) or candidate[key] != bp.get(key): return "Material port mismatch: " + key
	var allowed: bool = (ak == "water_supply_boundary" and bk == "electrolyzer_station") or (ak == "electrolyzer_station" and bk in HYDROGEN_STORE_KINDS) or (ak in HYDROGEN_STORE_KINDS and (bk == "fuel_cell_station" or bk in SYNTHESIS_KINDS)) or (ak == "nitrogen_supply_boundary" and bk == "ammonia_synthesis_station") or (ak == "co2_supply_boundary" and bk == "methanol_synthesis_station")
	if not allowed: return "物料仅支持有限水→电解→独立储氢站→燃料电池；不支持储库间倒氢"
	if not _number(candidate.mass_flow_capacity_kg_s) or float(candidate.mass_flow_capacity_kg_s) < 0.0 or float(candidate.mass_flow_capacity_kg_s) > 1000.0: return "Material line capacity must be within [0,1000] kg/s"
	if not _number(candidate.loss_fraction) or float(candidate.loss_fraction) != 0.0: return "Stage 2A material pipes have zero line loss; storage leakage is explicit"
	return ""

static func chemical_profile() -> Dictionary:
	if _chemical_profile.is_empty():
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/material_process_profiles_v3.json"))
		if data is Dictionary and data.get("profile_id") == CHEMICAL_PROFILE_ID and data.get("profile_version") == CHEMICAL_PROFILE_VERSION: _chemical_profile = data
	return _chemical_profile.duplicate(true)

static func chemical_coefficients(kind: String) -> Dictionary:
	if not kind in SYNTHESIS_KINDS: return {}
	var data: Dictionary = chemical_profile()
	var mm: Dictionary = data.molar_mass_kg_per_kmol
	var hf: Dictionary = data.formation_enthalpy_kj_per_kmol
	var pc: Dictionary = data.process_constants[kind]
	var ammonia: bool = kind == "ammonia_synthesis_station"
	var product: String = "NH3" if ammonia else "CH3OH"
	var feed: String = "N2" if ammonia else "CO2"
	var denom: float = (2.0 if ammonia else 1.0)*mm[product]
	var reaction: float = (2.0*hf.NH3 if ammonia else hf.CH3OH+hf.H2O-hf.CO2)/denom/3600.0
	var heater: float = pc.process_heat_kwh_per_kg/pc.heater_efficiency
	return {"product":product,"feed":feed,"feed_kind":"nitrogen_supply_boundary" if ammonia else "co2_supply_boundary","feed_per_product":mm[feed]/denom,"hydrogen_per_product":3.0*mm.H2/denom,"water_per_product":0.0 if ammonia else mm.H2O/denom,"reaction_enthalpy_kwh_per_kg":reaction,"heater_kwh_per_kg":heater,"electric_kwh_per_kg":pc.auxiliary_kwh_per_kg+heater,"heat_rejected_kwh_per_kg":pc.auxiliary_kwh_per_kg+heater-reaction}
