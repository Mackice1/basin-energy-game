extends RefCounted
## Pure reference-state material accounts. Mass is kg, energy is MWh/MWhth,
## and element amounts are kg of atoms (not molecular kg or kmol).
## Historical v1 process totals never become a fictitious stock/import.
const VERSION := 3
const MAX_DEVICE_ID := 2147483646
const PROFILE := "material_reference_ledger_v3"
const ABS_TOL := 2.0e-6
const REL_TOL := 2.0e-12
const ROUND_TOL := 3.552713678800501e-15 # 16 double-precision epsilons.
const MC = preload("res://scripts/material_catalog.gd")
# The released validator remains authoritative for every legacy ledger.
const V2 = preload("res://scripts/material_ledger_v2.gd")
const REFERENCES := ["H2O_liquid_25c", "H2_gas_25c", "H2_liquid_20k", "H2_bound_lani5", "O2_gas_25c", "N2_gas_25c", "CO2_gas_25c", "NH3_gas_25c", "CH3OH_liquid_25c"]
const ELEMENTS := ["H", "C", "N", "O"]
const CHEMICAL_KINDS := ["nitrogen_supply_boundary", "co2_supply_boundary", "ammonia_synthesis_station", "methanol_synthesis_station"]
const CHEMICAL_MAXIMUM_KG := {"nitrogen_supply_boundary":1000.0, "co2_supply_boundary":1000.0, "ammonia_synthesis_station":200.0, "methanol_synthesis_station":1000.0}
const PREFIXES := ["opening", "current", "imported", "exported"]
const KIND_REFERENCE := {"water_supply_boundary":"H2O_liquid_25c", "hydrogen_gas_store":"H2_gas_25c", "hydrogen_liquid_store":"H2_liquid_20k", "hydrogen_metal_hydride_store":"H2_bound_lani5", "nitrogen_supply_boundary":"N2_gas_25c", "co2_supply_boundary":"CO2_gas_25c", "ammonia_synthesis_station":"NH3_gas_25c", "methanol_synthesis_station":"CH3OH_liquid_25c"}
const KIND_SPECIES := {"water_supply_boundary":"H2O", "hydrogen_gas_store":"H2", "hydrogen_liquid_store":"H2", "hydrogen_metal_hydride_store":"H2", "nitrogen_supply_boundary":"N2", "co2_supply_boundary":"CO2", "ammonia_synthesis_station":"NH3", "methanol_synthesis_station":"CH3OH"}
const MOLAR_MASS := {"H2O_liquid_25c":18.015, "H2_gas_25c":2.016, "H2_liquid_20k":2.016, "H2_bound_lani5":2.016, "O2_gas_25c":31.998, "N2_gas_25c":28.014, "CO2_gas_25c":44.009, "NH3_gas_25c":17.031, "CH3OH_liquid_25c":32.042}
const ATOM_MASS := {"H":1.008, "C":12.011, "N":14.007, "O":15.999}
const ATOMS := {"H2O_liquid_25c":{"H":2, "O":1}, "H2_gas_25c":{"H":2}, "H2_liquid_20k":{"H":2}, "H2_bound_lani5":{"H":2}, "O2_gas_25c":{"O":2}, "N2_gas_25c":{"N":2}, "CO2_gas_25c":{"C":1, "O":2}, "NH3_gas_25c":{"N":1, "H":3}, "CH3OH_liquid_25c":{"C":1, "H":4, "O":1}}
# kJ/kmol divided by kg/kmol and 3.6e6 kJ/MWh; phase values kWh/kg / 1000.
const H_MWH_PER_KG := {"H2O_liquid_25c":-285830.0 / 18.015 / 3600000.0, "H2_gas_25c":0.0, "H2_liquid_20k":-0.00124, "H2_bound_lani5":-0.004275, "O2_gas_25c":0.0, "N2_gas_25c":0.0, "CO2_gas_25c":-393510.0 / 44.009 / 3600000.0, "NH3_gas_25c":-45940.0 / 17.031 / 3600000.0, "CH3OH_liquid_25c":-238400.0 / 32.042 / 3600000.0}
const WATER_PER_H2 := 18.015 / 2.016
const OXYGEN_PER_H2 := 15.999 / 2.016
const LHV_MWH_PER_KG := 241826.0 / 2.016 / 3600000.0
const HHV_MWH_PER_KG := 285830.0 / 2.016 / 3600000.0
const H2_PER_AMMONIA := 6.048 / 34.062
const N2_PER_AMMONIA := 28.014 / 34.062
const H2_PER_METHANOL := 6.048 / 32.042
const CO2_PER_METHANOL := 44.009 / 32.042
const WATER_PER_METHANOL := 18.015 / 32.042
const CHEMICAL_COUNTERS := ["chemical_electric_mwh", "ammonia_produced_kg", "methanol_produced_kg", "nitrogen_withdrawn_kg", "co2_withdrawn_kg", "chemical_hydrogen_consumed_kg", "chemical_water_released_kg"]
const RATE_LEDGER := {"water_withdrawn_kg":"water_withdrawn_kg_s", "hydrogen_produced_kg":"hydrogen_produced_kg_s", "hydrogen_consumed_kg":"hydrogen_consumed_kg_s", "hydrogen_charged_kg":"hydrogen_charged_kg_s", "hydrogen_discharged_kg":"hydrogen_discharged_kg_s", "oxygen_vented_kg":"oxygen_vented_kg_s", "oxygen_from_air_kg":"oxygen_from_air_kg_s", "water_released_kg":"water_released_kg_s", "ammonia_produced_kg":"ammonia_produced_kg_s", "methanol_produced_kg":"methanol_produced_kg_s", "nitrogen_withdrawn_kg":"nitrogen_withdrawn_kg_s", "co2_withdrawn_kg":"co2_withdrawn_kg_s", "chemical_hydrogen_consumed_kg":"chemical_hydrogen_consumed_kg_s", "chemical_water_released_kg":"chemical_water_released_kg_s"}
const POWER_LEDGER := {"electrolyzer_electric_mwh":"electrolyzer_electric_mw", "compression_electric_mwh":"compression_electric_mw", "fuel_cell_output_mwh":"fuel_cell_output_mw", "heat_rejected_mwhth":"heat_rejected_mwth"}
const EXTRA_POWER_LEDGER := {"phase_store_electric_mwh":"phase_store_electric_mw", "environment_heat_in_mwhth":"environment_heat_in_mwth", "chemical_electric_mwh":"chemical_electric_mw"}

static func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

## Match save identifiers after JSON turns integral numbers into floats.
## Persisted map keys are canonical strings; aliases such as "03"/"3.0" fail.
static func _canonical_id(value: Variant) -> String:
	if value is String:
		if not value.is_valid_int(): return ""
		var numeric: int = value.to_int()
		return value if numeric >= 0 and numeric <= MAX_DEVICE_ID and str(numeric) == value else ""
	if not _number(value) or float(value) < 0.0 or float(value) > MAX_DEVICE_ID or float(value) != floorf(float(value)): return ""
	return str(int(value))

static func empty_inventory() -> Dictionary:
	var result: Dictionary = {}
	for reference in REFERENCES: result[reference] = 0.0
	return result

static func _empty_atoms() -> Dictionary:
	return {"H":0.0, "C":0.0, "N":0.0, "O":0.0}

static func _sum(values: Array) -> float:
	# Neumaier summation keeps cancellation of large opening/import/export terms
	# from turning a valid small balance into a misleading large relative error.
	var total: float = 0.0
	var correction: float = 0.0
	for value in values:
		var x: float = float(value)
		var next: float = total + x
		correction += (total - next) + x if absf(total) >= absf(x) else (x - next) + total
		total = next
	return total + correction

static func _near(errors: Array[String], a: float, b: float, label: String) -> void:
	if not is_finite(a) or not is_finite(b) or absf(a - b) > ABS_TOL + REL_TOL * maxf(absf(a), absf(b)):
		errors.append("Material ledger mismatch: " + label)

static func _balanced(errors: Array[String], terms: Array, net_scale: float, label: String) -> void:
	var gross: float = 0.0
	for value in terms: gross += absf(float(value))
	var residual: float = _sum(terms)
	# Relative tolerance follows physical stock, not unlimited historical churn.
	# Cancellation allowance follows ULP scale of the gross accumulated terms.
	if not is_finite(residual) or not is_finite(gross) or absf(residual) > ABS_TOL + REL_TOL * absf(net_scale) + ROUND_TOL * gross:
		errors.append("Material ledger does not close: " + label)

static func _fixed_nonnegative_map(value: Variant, keys: Array) -> bool:
	if not value is Dictionary or value.size() != keys.size(): return false
	for key in keys:
		if not _number(value.get(key)) or float(value[key]) < 0.0: return false
	return true

static func _host_map(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in value:
		if not key is String or _canonical_id(key).is_empty() or not _number(value[key]) or float(value[key]) <= 0.0: return false
	return true

static func atoms_for_inventory(inventory: Variant) -> Dictionary:
	if not _fixed_nonnegative_map(inventory, REFERENCES): return {}
	var result: Dictionary = _empty_atoms()
	for element in ELEMENTS:
		var terms: Array = []
		for reference in REFERENCES:
			terms.append(float(inventory[reference]) * float(ATOMS[reference].get(element, 0)) * float(ATOM_MASS[element]) / float(MOLAR_MASS[reference]))
		result[element] = _sum(terms)
	return result

static func enthalpy_for_inventory(inventory: Variant) -> float:
	if not _fixed_nonnegative_map(inventory, REFERENCES): return NAN
	var terms: Array = []
	for reference in REFERENCES: terms.append(float(inventory[reference]) * float(H_MWH_PER_KG[reference]))
	return _sum(terms)

static func initial_energy_v1() -> Dictionary:
	return V2.initial_energy_v1()

static func _validate_counters(ledger: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key in initial_energy_v1().keys() + CHEMICAL_COUNTERS:
		if not _number(ledger.get(key)) or float(ledger[key]) < 0.0: errors.append("Invalid material process counter: " + key)
	if not errors.is_empty(): return errors
	_near(errors, ledger.hydrogen_produced_kg * WATER_PER_H2, ledger.water_withdrawn_kg, "electrolysis water")
	_near(errors, ledger.hydrogen_produced_kg * OXYGEN_PER_H2, ledger.oxygen_vented_kg, "electrolysis oxygen")
	_near(errors, ledger.hydrogen_consumed_kg * WATER_PER_H2 + ledger.chemical_water_released_kg, ledger.water_released_kg, "fuel-cell plus chemical water")
	_near(errors, ledger.hydrogen_consumed_kg * OXYGEN_PER_H2, ledger.oxygen_from_air_kg, "fuel-cell oxygen")
	_near(errors, ledger.hydrogen_charged_kg, ledger.hydrogen_produced_kg, "H2 charge")
	_near(errors, ledger.hydrogen_discharged_kg, ledger.hydrogen_consumed_kg + ledger.chemical_hydrogen_consumed_kg, "H2 discharge to fuel cells and chemistry")
	_near(errors, ledger.chemical_hydrogen_consumed_kg, ledger.ammonia_produced_kg * H2_PER_AMMONIA + ledger.methanol_produced_kg * H2_PER_METHANOL, "chemical H2 stoichiometry")
	_near(errors, ledger.nitrogen_withdrawn_kg, ledger.ammonia_produced_kg * N2_PER_AMMONIA, "ammonia nitrogen stoichiometry")
	_near(errors, ledger.co2_withdrawn_kg, ledger.methanol_produced_kg * CO2_PER_METHANOL, "methanol carbon dioxide stoichiometry")
	_near(errors, ledger.chemical_water_released_kg, ledger.methanol_produced_kg * WATER_PER_METHANOL, "methanol liquid water stoichiometry")
	_near(errors, ledger.hydrogen_leak_lhv_mwh, ledger.hydrogen_leaked_kg * LHV_MWH_PER_KG, "leak LHV (not reference-state heat)")
	return errors

static func validate_energy_v1(ledger: Variant) -> Array[String]:
	return V2.validate_energy_v1(ledger)

static func _blank() -> Dictionary:
	var result: Dictionary = initial_energy_v1()
	for key in CHEMICAL_COUNTERS: result[key] = 0.0
	result.ledger_version = VERSION
	result.ledger_profile = PROFILE
	for key in EXTRA_POWER_LEDGER: result[key] = 0.0
	for prefix in PREFIXES:
		result[prefix + "_inventory_kg"] = empty_inventory()
		result[prefix + "_atoms_kg"] = _empty_atoms()
		result[prefix + "_reference_enthalpy_mwh"] = 0.0
		result[prefix + "_dry_host_by_device_kg"] = {}
	result.current_inventory_by_device = {}
	result.legacy_v1_history = {}
	return result

static func _refresh_derived(ledger: Dictionary) -> void:
	for prefix in PREFIXES:
		ledger[prefix + "_atoms_kg"] = atoms_for_inventory(ledger[prefix + "_inventory_kg"])
		ledger[prefix + "_reference_enthalpy_mwh"] = enthalpy_for_inventory(ledger[prefix + "_inventory_kg"])

static func _device_entry(device: Variant) -> Dictionary:
	if not device is Dictionary or not device.get("kind") is String: return {}
	var kind: String = device.kind
	if not KIND_REFERENCE.has(kind): return {}
	if _canonical_id(device.get("id")).is_empty(): return {}
	if not device.get("params", {}) is Dictionary or not device.get("state") is Dictionary: return {}
	if not MC.validate(kind, device.get("params", {})).is_empty() or not MC.validate_state(kind, device.get("params", {}), device.state).is_empty(): return {}
	var p: Dictionary = MC.defaults(kind)
	p.merge(device.get("params", {}), true)
	var state: Dictionary = device.state
	var metal: bool = kind == "hydrogen_metal_hydride_store"
	if state.size() != (2 if metal else 1) or not state.get("material_inventory_kg") is Dictionary: return {}
	var stock: Dictionary = state.material_inventory_kg
	var species: String = KIND_SPECIES[kind]
	if stock.size() != 1 or not _number(stock.get(species)) or float(stock[species]) < 0.0: return {}
	if p.has("capacity_kg") and (not _number(p.capacity_kg) or float(stock[species]) > float(p.capacity_kg)): return {}
	if CHEMICAL_MAXIMUM_KG.has(kind) and float(stock[species]) > float(CHEMICAL_MAXIMUM_KG[kind]): return {}
	var host: float = 0.0
	if metal:
		if not _number(state.get("host_dry_mass_kg")) or not _number(p.get("dry_host_mass_kg")): return {}
		host = float(state.host_dry_mass_kg)
		if host <= 0.0 or host != float(p.dry_host_mass_kg) or float(stock[species]) > host * 0.012: return {}
	return {"kind":kind, "reference_id":KIND_REFERENCE[kind], "mass_kg":float(stock[species]), "host_dry_mass_kg":host}

static func snapshot_inventory(devices: Variant) -> Dictionary:
	if not devices is Array: return {"valid":false, "errors":["Material devices must be an array"]}
	var inventory: Dictionary = empty_inventory()
	var hosts: Dictionary = {}
	var by_device: Dictionary = {}
	var seen: Dictionary = {}
	for device in devices:
		if not device is Dictionary or not device.get("kind") is String: return {"valid":false, "errors":["Malformed material world device"]}
		if not KIND_REFERENCE.has(device.kind): continue
		var entry: Dictionary = _device_entry(device)
		if entry.is_empty(): return {"valid":false, "errors":["Invalid material inventory state or dry host"]}
		var id: String = _canonical_id(device.id)
		if seen.has(id): return {"valid":false, "errors":["Duplicate material device id: " + id]}
		seen[id] = true
		by_device[id] = entry
		inventory[entry.reference_id] += entry.mass_kg
		if entry.host_dry_mass_kg > 0.0: hosts[id] = entry.host_dry_mass_kg
	return {"valid":true, "errors":[], "inventory_by_reference_kg":inventory, "dry_host_by_device_kg":hosts, "inventory_by_device":by_device}

static func initial_energy(devices: Variant = []) -> Dictionary:
	var snapshot: Dictionary = snapshot_inventory(devices)
	if not snapshot.valid: return {}
	var result: Dictionary = _blank()
	result.opening_inventory_kg = snapshot.inventory_by_reference_kg.duplicate(true)
	result.current_inventory_kg = snapshot.inventory_by_reference_kg.duplicate(true)
	result.opening_dry_host_by_device_kg = snapshot.dry_host_by_device_kg.duplicate(true)
	result.current_dry_host_by_device_kg = snapshot.dry_host_by_device_kg.duplicate(true)
	result.current_inventory_by_device = snapshot.inventory_by_device.duplicate(true)
	_refresh_derived(result)
	return result if validate_energy(result).is_empty() else {}

static func _entries_snapshot(value: Variant) -> Dictionary:
	if not value is Dictionary: return {}
	var inventory: Dictionary = empty_inventory()
	var hosts: Dictionary = {}
	for id in value:
		if not id is String or _canonical_id(id).is_empty(): return {}
		var entry: Variant = value[id]
		if not entry is Dictionary or entry.size() != 4 or not entry.get("kind") is String or not KIND_REFERENCE.has(entry.kind): return {}
		if not entry.get("reference_id") is String or entry.reference_id != KIND_REFERENCE[entry.kind] or not _number(entry.get("mass_kg")) or float(entry.mass_kg) < 0.0 or not _number(entry.get("host_dry_mass_kg")): return {}
		if CHEMICAL_MAXIMUM_KG.has(entry.kind) and float(entry.mass_kg) > float(CHEMICAL_MAXIMUM_KG[entry.kind]): return {}
		var metal: bool = entry.kind == "hydrogen_metal_hydride_store"
		if (metal and entry.host_dry_mass_kg <= 0.0) or (not metal and entry.host_dry_mass_kg != 0.0): return {}
		inventory[entry.reference_id] += entry.mass_kg
		if metal: hosts[id] = entry.host_dry_mass_kg
	return {"inventory_by_reference_kg":inventory, "dry_host_by_device_kg":hosts}

static func _compare_fixed(errors: Array[String], actual: Dictionary, expected: Dictionary, label: String) -> void:
	for key in expected: _near(errors, float(actual[key]), float(expected[key]), label + "/" + key)

static func validate_energy(ledger: Variant, devices: Variant = null) -> Array[String]:
	if not ledger is Dictionary: return ["Material ledger must be a dictionary"]
	var shape: Dictionary = _blank()
	if ledger.size() != shape.size(): return ["Material ledger has incompatible fields"]
	for key in shape:
		if not ledger.has(key): return ["Material ledger missing " + key]
	if not _number(ledger.ledger_version) or ledger.ledger_version != VERSION or not ledger.ledger_profile is String or ledger.ledger_profile != PROFILE: return ["Material ledger profile/version mismatch"]
	var errors: Array[String] = _validate_counters(ledger)
	for key in EXTRA_POWER_LEDGER:
		if not _number(ledger[key]) or float(ledger[key]) < 0.0: errors.append("Invalid material power counter: " + key)
	for prefix in PREFIXES:
		if not _fixed_nonnegative_map(ledger[prefix + "_inventory_kg"], REFERENCES): errors.append("Invalid fixed reference inventory map: " + prefix)
		if not _fixed_nonnegative_map(ledger[prefix + "_atoms_kg"], ELEMENTS): errors.append("Invalid fixed element map: " + prefix)
		if not _number(ledger[prefix + "_reference_enthalpy_mwh"]): errors.append("Invalid signed reference enthalpy: " + prefix)
		if not _host_map(ledger[prefix + "_dry_host_by_device_kg"]): errors.append("Invalid dry-host map: " + prefix)
	if not ledger.legacy_v1_history is Dictionary: errors.append("Legacy material history must be a dictionary")
	elif not ledger.legacy_v1_history.is_empty(): errors.append_array(validate_energy_v1(ledger.legacy_v1_history))
	var entries: Dictionary = _entries_snapshot(ledger.current_inventory_by_device)
	if entries.is_empty(): errors.append("Invalid current per-device inventory")
	if not errors.is_empty(): return errors
	for prefix in PREFIXES:
		_compare_fixed(errors, ledger[prefix + "_atoms_kg"], atoms_for_inventory(ledger[prefix + "_inventory_kg"]), prefix + " atoms from species")
		_near(errors, ledger[prefix + "_reference_enthalpy_mwh"], enthalpy_for_inventory(ledger[prefix + "_inventory_kg"]), prefix + " reference enthalpy from species/phase")
	_near(errors, ledger.imported_inventory_kg.O2_gas_25c, ledger.oxygen_from_air_kg, "air oxygen import boundary")
	_near(errors, ledger.exported_inventory_kg.O2_gas_25c, ledger.oxygen_vented_kg, "vented oxygen export boundary")
	_near(errors, ledger.exported_inventory_kg.H2_gas_25c, ledger.hydrogen_leaked_kg, "warm gas leakage export boundary")
	_near(errors, ledger.exported_inventory_kg.H2O_liquid_25c, ledger.water_released_kg, "released water export boundary")
	for reference in ["H2_liquid_20k", "H2_bound_lani5", "N2_gas_25c", "CO2_gas_25c", "NH3_gas_25c", "CH3OH_liquid_25c"]:
		if ledger.exported_inventory_kg[reference] != 0.0: errors.append("Nonempty phase, feedstock or product inventory cannot leave by facility removal")
	if ledger.opening_inventory_kg.O2_gas_25c != 0.0: errors.append("No implemented oxygen inventory device")
	_compare_fixed(errors, ledger.current_inventory_kg, entries.inventory_by_reference_kg, "per-device/current inventory")
	if ledger.current_dry_host_by_device_kg != entries.dry_host_by_device_kg: errors.append("Current dry host does not match per-device inventory")
	for element in ELEMENTS:
		_balanced(errors, [ledger.opening_atoms_kg[element], ledger.imported_atoms_kg[element], -ledger.exported_atoms_kg[element], -ledger.current_atoms_kg[element]], maxf(ledger.opening_atoms_kg[element], ledger.current_atoms_kg[element]), element + " atoms")
	# Product formation and feed withdrawal are internal reactions, not imports.
	# Tying counters to their actual reference stocks prevents invented or erased
	# production history even when a forged pair of counters still balances atoms.
	for flow in [["N2_gas_25c", -float(ledger.nitrogen_withdrawn_kg)], ["CO2_gas_25c", -float(ledger.co2_withdrawn_kg)], ["NH3_gas_25c", float(ledger.ammonia_produced_kg)], ["CH3OH_liquid_25c", float(ledger.methanol_produced_kg)]]:
		var reference: String = flow[0]
		_balanced(errors, [ledger.opening_inventory_kg[reference], ledger.imported_inventory_kg[reference], -ledger.exported_inventory_kg[reference], -ledger.current_inventory_kg[reference], flow[1]], maxf(ledger.opening_inventory_kg[reference], ledger.current_inventory_kg[reference]), reference + " process inventory")
	var host_ids: Dictionary = {}
	for prefix in PREFIXES:
		for id in ledger[prefix + "_dry_host_by_device_kg"]: host_ids[id] = true
	for id in host_ids:
		_balanced(errors, [ledger.opening_dry_host_by_device_kg.get(id, 0.0), ledger.imported_dry_host_by_device_kg.get(id, 0.0), -float(ledger.exported_dry_host_by_device_kg.get(id, 0.0)), -float(ledger.current_dry_host_by_device_kg.get(id, 0.0))], float(ledger.current_dry_host_by_device_kg.get(id, 0.0)), "fixed LaNi5 dry host " + id)
	_balanced(errors, [ledger.current_reference_enthalpy_mwh, -ledger.opening_reference_enthalpy_mwh, -ledger.electrolyzer_electric_mwh, -ledger.compression_electric_mwh, -ledger.phase_store_electric_mwh, -ledger.chemical_electric_mwh, ledger.fuel_cell_output_mwh, -ledger.environment_heat_in_mwhth, ledger.heat_rejected_mwhth, -ledger.imported_reference_enthalpy_mwh, ledger.exported_reference_enthalpy_mwh], maxf(absf(ledger.opening_reference_enthalpy_mwh), absf(ledger.current_reference_enthalpy_mwh)), "reference-state enthalpy")
	if devices != null:
		var world: Dictionary = snapshot_inventory(devices)
		if not world.valid: errors.append_array(world.errors)
		else:
			_compare_fixed(errors, ledger.current_inventory_kg, world.inventory_by_reference_kg, "world/current inventory")
			if ledger.current_inventory_by_device != world.inventory_by_device: errors.append("World material devices differ from ledger inventory")
			if ledger.current_dry_host_by_device_kg != world.dry_host_by_device_kg: errors.append("World dry host differs from immutable ledger host")
	return errors

static func bootstrap_from_legacy(old: Variant, devices: Variant) -> Dictionary:
	var errors: Array[String] = validate_energy_v1(old)
	if not errors.is_empty(): return {"valid":false, "errors":errors, "ledger":{}}
	var ledger: Dictionary = initial_energy(devices)
	if ledger.is_empty(): return {"valid":false, "errors":["Cannot open v3 ledger from invalid actual inventory"], "ledger":{}}
	ledger.legacy_v1_history = old.duplicate(true)
	return {"valid":true, "errors":[], "ledger":ledger}

## Upgrade is not a new opening: all old anchors, boundaries and historical
## counters survive verbatim. Validate first using the frozen v2 contract.
static func upgrade_ledger_v2_to_v3(old: Variant, devices: Variant) -> Dictionary:
	if not devices is Array: return {"valid":false, "errors":["A v2 upgrade requires the actual device world"], "ledger":{}}
	var errors: Array[String] = V2.validate_energy(old, devices)
	if not errors.is_empty(): return {"valid":false, "errors":errors, "ledger":{}}
	var result: Dictionary = old.duplicate(true)
	result.ledger_version = VERSION
	result.ledger_profile = PROFILE
	for key in CHEMICAL_COUNTERS: result[key] = 0.0
	errors = validate_energy(result, devices)
	return {"valid":errors.is_empty(), "errors":errors, "ledger":result if errors.is_empty() else {}}

static func _event(ledger: Variant, device: Variant, removing: bool) -> Dictionary:
	var errors: Array[String] = validate_energy(ledger)
	if not errors.is_empty(): return {"valid":false, "errors":errors, "ledger":{}}
	if not device is Dictionary or not device.get("kind") is String: return {"valid":false, "errors":["Malformed inventory event device"], "ledger":{}}
	# Adding/removing converters has no material inventory boundary.
	if not KIND_REFERENCE.has(device.kind): return {"valid":true, "errors":[], "ledger":ledger.duplicate(true)}
	var entry: Dictionary = _device_entry(device)
	if entry.is_empty(): return {"valid":false, "errors":["Invalid inventory event state/host"], "ledger":{}}
	var id: String = _canonical_id(device.id)
	if removing:
		if not ledger.current_inventory_by_device.has(id) or ledger.current_inventory_by_device[id] != entry: return {"valid":false, "errors":["Removal must match exact current material device state"], "ledger":{}}
		if entry.mass_kg != 0.0: return {"valid":false, "errors":["Drain material inventory before removing its facility"], "ledger":{}}
	elif ledger.current_inventory_by_device.has(id): return {"valid":false, "errors":["Material device already exists in inventory ledger"], "ledger":{}}
	var result: Dictionary = ledger.duplicate(true)
	var prefix: String = "exported" if removing else "imported"
	result[prefix + "_inventory_kg"][entry.reference_id] += entry.mass_kg
	result.current_inventory_kg[entry.reference_id] += (-entry.mass_kg if removing else entry.mass_kg)
	if removing: result.current_inventory_by_device.erase(id)
	else: result.current_inventory_by_device[id] = entry.duplicate(true)
	if entry.host_dry_mass_kg > 0.0:
		result[prefix + "_dry_host_by_device_kg"][id] = float(result[prefix + "_dry_host_by_device_kg"].get(id, 0.0)) + entry.host_dry_mass_kg
		if removing: result.current_dry_host_by_device_kg.erase(id)
		else: result.current_dry_host_by_device_kg[id] = entry.host_dry_mass_kg
	_refresh_derived(result)
	errors = validate_energy(result)
	return {"valid":errors.is_empty(), "errors":errors, "ledger":result if errors.is_empty() else {}}

static func import_inventory_event(ledger: Variant, device: Variant) -> Dictionary:
	return _event(ledger, device, false)

static func remove_inventory_event(ledger: Variant, device: Variant) -> Dictionary:
	return _event(ledger, device, true)

static func _report_snapshot(ledger: Dictionary, report: Dictionary) -> Dictionary:
	if not report.get("devices") is Dictionary or not report.get("next_states") is Dictionary: return {}
	var entries: Dictionary = {}
	for id in report.devices:
		var detail: Variant = report.devices[id]
		if not id is String or _canonical_id(id).is_empty() or not detail is Dictionary or not detail.get("kind") is String: return {}
		if not KIND_REFERENCE.has(detail.kind): continue
		if not detail.get("valid") is bool or detail.valid != true or not ledger.current_inventory_by_device.has(id): return {}
		var previous: Dictionary = ledger.current_inventory_by_device[id]
		if detail.kind != previous.kind or not report.next_states.get(id) is Dictionary: return {}
		var state: Dictionary = report.next_states[id]
		var metal: bool = detail.kind == "hydrogen_metal_hydride_store"
		if state.size() != (2 if metal else 1) or not state.get("material_inventory_kg") is Dictionary: return {}
		var species: String = KIND_SPECIES[detail.kind]
		if state.material_inventory_kg.size() != 1 or not _number(state.material_inventory_kg.get(species)) or float(state.material_inventory_kg[species]) < 0.0: return {}
		if metal and (not _number(state.get("host_dry_mass_kg")) or state.host_dry_mass_kg != previous.host_dry_mass_kg): return {}
		var entry: Dictionary = previous.duplicate(true)
		entry.mass_kg = float(state.material_inventory_kg[species])
		entries[id] = entry
	if entries.size() != ledger.current_inventory_by_device.size(): return {}
	var result: Dictionary = _entries_snapshot(entries)
	if result.is_empty(): return {}
	result.inventory_by_device = entries
	return result

static func accumulate_energy(ledger: Variant, report: Variant, dt_s: Variant) -> Dictionary:
	if not validate_energy(ledger).is_empty() or not report is Dictionary or not _number(dt_s) or float(dt_s) < 0.0: return {}
	if not report.get("valid") is bool or report.valid != true or not _number(report.get("dt_s")) or float(report.dt_s) != float(dt_s) or not report.get("material") is Dictionary: return {}
	var m: Dictionary = report.material
	for fields in [RATE_LEDGER, POWER_LEDGER, EXTRA_POWER_LEDGER]:
		for field in fields.values():
			if not _number(m.get(field)) or float(m[field]) < 0.0 or (float(dt_s) == 0.0 and float(m[field]) != 0.0): return {}
	for field in ["hydrogen_leaked_kg", "hydrogen_leak_lhv_mwh"]:
		if not _number(m.get(field)) or float(m[field]) < 0.0 or (float(dt_s) == 0.0 and float(m[field]) != 0.0): return {}
	if not _fixed_nonnegative_map(m.get("inventory_by_reference_kg"), REFERENCES) or not _host_map(m.get("dry_host_by_device_kg")): return {}
	var snapshot: Dictionary = _report_snapshot(ledger, report)
	if snapshot.is_empty(): return {}
	var errors: Array[String] = []
	_compare_fixed(errors, m.inventory_by_reference_kg, snapshot.inventory_by_reference_kg, "report/current state")
	if m.dry_host_by_device_kg != snapshot.dry_host_by_device_kg: return {}
	if snapshot.dry_host_by_device_kg != ledger.current_dry_host_by_device_kg: return {}
	if float(dt_s) == 0.0 and snapshot.inventory_by_device != ledger.current_inventory_by_device: return {}
	if not errors.is_empty(): return {}
	# A fresh step ledger checks rates, boundaries, and phase energy independently
	# of large historical totals. Supplied zero residuals confer no trust.
	var step: Dictionary = _blank()
	step.opening_inventory_kg = ledger.current_inventory_kg.duplicate(true)
	step.opening_dry_host_by_device_kg = ledger.current_dry_host_by_device_kg.duplicate(true)
	step.current_inventory_kg = snapshot.inventory_by_reference_kg.duplicate(true)
	step.current_dry_host_by_device_kg = snapshot.dry_host_by_device_kg.duplicate(true)
	step.current_inventory_by_device = snapshot.inventory_by_device.duplicate(true)
	for key in RATE_LEDGER: step[key] = float(m[RATE_LEDGER[key]]) * float(dt_s)
	for fields in [POWER_LEDGER, EXTRA_POWER_LEDGER]:
		for key in fields: step[key] = float(m[fields[key]]) * float(dt_s) / 3600.0
	step.hydrogen_leaked_kg = float(m.hydrogen_leaked_kg)
	step.hydrogen_leak_lhv_mwh = float(m.hydrogen_leak_lhv_mwh)
	step.imported_inventory_kg.O2_gas_25c = step.oxygen_from_air_kg
	step.exported_inventory_kg.O2_gas_25c = step.oxygen_vented_kg
	step.exported_inventory_kg.H2O_liquid_25c = step.water_released_kg
	step.exported_inventory_kg.H2_gas_25c = step.hydrogen_leaked_kg
	_refresh_derived(step)
	if not validate_energy(step).is_empty(): return {}
	var result: Dictionary = ledger.duplicate(true)
	for key in initial_energy_v1(): result[key] += step[key]
	for key in CHEMICAL_COUNTERS:
		if key != "chemical_electric_mwh": result[key] += step[key]
	for key in EXTRA_POWER_LEDGER: result[key] += step[key]
	for prefix in ["imported", "exported"]:
		for reference in REFERENCES: result[prefix + "_inventory_kg"][reference] += step[prefix + "_inventory_kg"][reference]
	result.current_inventory_kg = step.current_inventory_kg.duplicate(true)
	result.current_inventory_by_device = step.current_inventory_by_device.duplicate(true)
	_refresh_derived(result)
	return result if validate_energy(result).is_empty() else {}

static func cumulative_electric_input_mwh(ledger: Variant) -> float:
	if not ledger is Dictionary: return NAN
	if ledger.has("ledger_version"):
		if not validate_energy(ledger).is_empty(): return NAN
		var historical: float = 0.0
		if not ledger.legacy_v1_history.is_empty(): historical = float(ledger.legacy_v1_history.electrolyzer_electric_mwh) + float(ledger.legacy_v1_history.compression_electric_mwh)
		return _sum([ledger.electrolyzer_electric_mwh, ledger.compression_electric_mwh, ledger.phase_store_electric_mwh, ledger.chemical_electric_mwh, historical])
	if not validate_energy_v1(ledger).is_empty(): return NAN
	return float(ledger.electrolyzer_electric_mwh) + float(ledger.compression_electric_mwh)
