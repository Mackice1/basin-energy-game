extends RefCounted
## Pure, non-mutating validation before a scene replaces live state.
## Empty string means valid. Every rejected value produces a readable reason.
## Terrain exclusions/slope still require the controller's terrain-aware checks.
const Model = preload("res://scripts/energy_model.gd")
const Series = preload("res://scripts/series_import.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
const Spatial = preload("res://scripts/spatial_dimensions.gd")
const Rankine = preload("res://scripts/rankine_cycle.gd")
const HighTemp = preload("res://scripts/high_temp_thermal.gd")
const Tower = preload("res://scripts/solar_tower_thermal.gd")
const Solar = preload("res://scripts/solar_thermal.gd")
const FuelSupply = preload("res://scripts/fuel_supply.gd")
const LEGACY_KINDS := ["wind", "pv", "station"]
const ELECTRIC_KINDS := ["wind", "pv", "station", "load", "battery"]
const THERMAL_KINDS := ["solid_thermal_store", "electric_boiler", "thermal_store", "heat_exchanger", "heat_demand", "fuel_boiler", "solar_thermal", "parabolic_trough", "high_temp_store", "oil_water_exchanger" ,"steam_generator", "steam_turbine", "steam_condenser", "feedwater_pump", "solar_tower_receiver", "molten_salt_store", "salt_steam_generator"]
const STATION_INTERNAL_KINDS := ["solid_thermal_store", "electric_boiler", "thermal_store", "heat_exchanger", "fuel_boiler", "solar_thermal", "parabolic_trough", "high_temp_store", "oil_water_exchanger" ,"steam_generator", "steam_turbine", "steam_condenser", "feedwater_pump", "solar_tower_receiver", "molten_salt_store", "salt_steam_generator"]
const PRE_FUEL_KINDS := ["wind", "pv", "station", "load", "battery", "electric_boiler", "thermal_store", "heat_exchanger", "heat_demand"]
const CURRENT_KINDS := ["wind", "pv", "station", "load", "battery", "electric_boiler", "thermal_store", "heat_exchanger", "heat_demand", "fuel_boiler"]
const SOLAR_KINDS := ["wind", "pv", "station", "load", "battery", "electric_boiler", "thermal_store", "heat_exchanger", "heat_demand", "fuel_boiler", "solar_thermal"]
const HIGH_TEMP_KINDS := ["wind", "pv", "station", "load", "battery", "electric_boiler", "thermal_store", "heat_exchanger", "heat_demand", "fuel_boiler", "solar_thermal", "parabolic_trough", "high_temp_store", "oil_water_exchanger"]
const THERMAL_MODEL_PROFILE := "thermal_stage1_v1"
const LEGACY_ENERGY_KEYS := ["generated", "delivered", "curtailed", "loss"]
const ELECTRIC_ENERGY_KEYS := ["generated", "delivered", "curtailed", "loss", "served", "unserved", "charge", "discharge", "storage_loss"]
const CURRENT_ENERGY_KEYS := ["generated", "delivered", "curtailed", "loss", "served", "unserved", "charge", "discharge", "storage_loss", "boiler_electric", "boiler_conversion_loss"]
const THERMAL_ENERGY_KEYS := ["demand", "served", "unserved", "boiler_heat", "charge", "discharge", "network_loss", "exchanger_loss", "storage_loss"]
const MAX_ID := 2147483646
const MAX_DEVICES := 1024
const MAX_STATIONS := 128
const STATION_ID_MIN := 1000000
const STATION_RADIUS := 8.0
const INTERIOR_HALF_WIDTH := 24.0
const INTERIOR_HALF_DEPTH := 24.0
const MAX_IMPORTS := MAX_DEVICES * 4 + 6 # Four device fields; five global weather fields.
const FIELD_HALF_WIDTH := 95.0
const FIELD_HALF_DEPTH := 65.0
const EPS := 0.000001

static func finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func integer_number(value: Variant) -> bool:
	return finite_number(value) and float(value) == floor(float(value))

## JSON numbers parse as floats; integral numeric IDs are accepted without
## truncating fractions or treating strings and booleans as device IDs.
static func _identifier(value: Variant, allow_grid: bool = false) -> String:
	var minimum: int = -1 if allow_grid else 0
	if not integer_number(value) or float(value) < minimum or float(value) > MAX_ID:
		return ""
	return str(int(value))

static func radius(kind: String, params: Dictionary = {}, dimension_profile: String = "legacy_illustrative") -> float:
	if dimension_profile == Spatial.METRIC_PROFILE:
		var dimensions: Dictionary = Spatial.profile(kind, params, false)
		return float(dimensions.clearance_radius_world) if dimensions.valid else INF
	if kind == "wind":
		return maxf(7.0, float(params.get("rotor_diameter_m", Model.defaults("wind").rotor_diameter_m)) * 0.05 + 0.7)
	return 5.0 if kind in ["pv", "thermal_store", "solid_thermal_store"] else 4.0

static func validate(state: Variant) -> String:
	if not state is Dictionary:
		return "Save must be a JSON object."
	if not integer_number(state.get("schema")) or not int(state.schema) in [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]:
		return "Only rebuild save schemas 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 and 13 are supported."
	var legacy: bool = int(state.schema) == 3
	var hierarchy: bool = int(state.schema) >= 6
	var metric_schema: bool = int(state.schema) >= 7
	var storage_schema: bool = int(state.schema) >= 13
	var tower_schema: bool = int(state.schema) >= 12
	var rankine_schema: bool = int(state.schema) >= 11
	var high_temp_schema: bool = int(state.schema) >= 10
	var solar_schema: bool = int(state.schema) >= 9
	var fuel_schema: bool = int(state.schema) >= 8
	var dimension_profile: String = Spatial.LEGACY_PROFILE
	if metric_schema:
		if not state.get("dimension_profile") is String or not state.dimension_profile in [Spatial.METRIC_PROFILE, Spatial.LEGACY_PROFILE]:
			return "Save schema 7, 8 or 9 requires dimension_profile metric_v1 or legacy_illustrative."
		dimension_profile = state.dimension_profile
	elif state.has("dimension_profile"):
		return "Explicit dimension_profile requires save schema 7/model 16 or schema 8/model 17; old schemas retain legacy geometry."
	var interior_half_width: float = Spatial.STATION_INTERIOR_HALF_WORLD if dimension_profile == Spatial.METRIC_PROFILE else INTERIOR_HALF_WIDTH
	var interior_half_depth: float = Spatial.STATION_INTERIOR_HALF_WORLD if dimension_profile == Spatial.METRIC_PROFILE else INTERIOR_HALF_DEPTH
	var thermal: bool = int(state.schema) >= 5
	var expected_model: int = 22 if storage_schema else 21 if tower_schema else 20 if rankine_schema else 19 if high_temp_schema else 18 if solar_schema else 17 if fuel_schema else (16 if metric_schema else (15 if hierarchy else (14 if thermal else (11 if legacy else 12))))
	if not integer_number(state.get("model_version")) or float(state.model_version) != expected_model:
		return "Save schema %d requires energy-model version %d." % [int(state.schema), expected_model]
	var kinds: Array = Catalog.implemented_kinds() if storage_schema else Catalog.implemented_kinds().filter(func(k): return not k in Catalog.NEW_STORAGE_KINDS) if tower_schema else HIGH_TEMP_KINDS + Catalog.RANKINE_KINDS if rankine_schema else HIGH_TEMP_KINDS if high_temp_schema else SOLAR_KINDS if solar_schema else CURRENT_KINDS if fuel_schema else (PRE_FUEL_KINDS if thermal else (LEGACY_KINDS if legacy else ELECTRIC_KINDS))
	var energy_keys: Array = CURRENT_ENERGY_KEYS if thermal else (LEGACY_ENERGY_KEYS if legacy else ELECTRIC_ENERGY_KEYS)
	if state.has("rebuild") and (not state.rebuild is bool or not state.rebuild):
		return "Save is not a rebuild scene."
	for key in ["devices", "links", "imports"]:
		if not state.get(key) is Array:
			return "Save field '%s' must be an array." % key
	if hierarchy:
		if not state.get("stations") is Array:
			return "Save schemas 6, 7, 8 and 9 require a stations array."
		if state.stations.size() > MAX_STATIONS:
			return "Save contains too many electric-thermal stations."
	elif state.has("stations") or state.has("next_station_id"):
		return "Station hierarchy requires save schema 6/model 15."
	if state.devices.size() > MAX_DEVICES or state.imports.size() > MAX_IMPORTS:
		return "Save contains too many devices or imported datasets."
	if not state.get("templates") is Dictionary:
		return "Save templates must be an object."
	for kind in kinds:
		if not state.templates.get(kind) is Dictionary:
			return "Missing or invalid %s template." % kind
		var errors: Array[String] = Model.validate(kind, state.templates[kind])
		if not errors.is_empty():
			return "Invalid %s template: %s" % [kind, "; ".join(errors)]
	for kind in state.templates:
		if not kind in kinds:
			return "Unknown template kind: %s." % str(kind)
	if not finite_number(state.get("elapsed_s")) or float(state.elapsed_s) < 0.0 or float(state.elapsed_s) > Series.MAX_TIME_S:
		return "Elapsed time must be finite and within the supported simulation range."
	if not state.get("physical_lines") is bool:
		return "Physical-lines display setting must be a boolean."
	if not state.get("energy") is Dictionary:
		return "Accumulated energy must be an object."
	for key in energy_keys:
		if not finite_number(state.energy.get(key)) or float(state.energy[key]) < 0.0:
			return "Accumulated %s energy must be finite and nonnegative." % key
	for key in state.energy:
		if not key in energy_keys:
			return "Unknown accumulated energy field: %s." % str(key)
	if tower_schema:
		var tower_error: String = Tower.validate_energy(state.get("tower_energy"))
		if not tower_error.is_empty(): return "Accumulated tower energy: " + tower_error
	elif state.has("tower_energy") or (state.get("rankine_energy") is Dictionary and state.rankine_energy.has("salt_input_mwhth")):
		return "Tower and salt history require schema12/model21."
	if rankine_schema:
		var rankine_error: String = Rankine.validate_energy(state.get("rankine_energy"))
		if not rankine_error.is_empty(): return "Accumulated Rankine energy: "+rankine_error
		if not _balanced(float(state.rankine_energy.oil_input_mwhth),float(state.get("high_temp_energy",{}).get("rankine_oil_input_mwhth",0.0))): return "Rankine oil draw must agree with high-temperature ledger"
	elif state.has("rankine_energy"):
		return "Rankine accumulated energy requires schema 11/model 20."
	if tower_schema and not _balanced(float(state.rankine_energy.get("salt_input_mwhth",0.0)),float(state.tower_energy.rankine_salt_input_mwhth)):
		return "Rankine salt draw must agree with tower ledger."
	if high_temp_schema:
		if not rankine_schema and state.get("high_temp_energy",{}).has("rankine_oil_input_mwhth"): return "Rankine oil history requires schema11"
		var high_error: String = HighTemp.validate_energy(state.get("high_temp_energy"))
		if not high_error.is_empty(): return "Accumulated high-temperature energy: " + high_error
	elif state.has("high_temp_energy"):
		return "High-temperature accumulated energy requires schema 10/model 19."
	if solar_schema:
		var solar_error: String = Solar.validate_energy(state.get("solar_energy"))
		if not solar_error.is_empty(): return "Accumulated solar energy: " + solar_error
	elif state.has("solar_energy"):
		return "Solar accumulated energy requires save schema 9/model 18."
	if fuel_schema:
		var supply_error: String = FuelSupply.validate(state.get("fuel_supply"))
		if not supply_error.is_empty():
			return "Fuel supply: " + supply_error
		var fuel_error: String = FuelSupply.validate_energy(state.get("fuel_energy"))
		if not fuel_error.is_empty():
			return "Accumulated fuel energy: " + fuel_error
	elif state.has("fuel_supply") or state.has("fuel_energy"):
		return "Fuel supply and accumulated fuel energy require save schema 8/model 17."
	# Charging/discharging are AC-side transfers. Conversion/self-discharge losses
	# are recorded separately against stored inventory, never subtracted twice.
	var supplied: float = float(state.energy.generated) + float(state.energy.get("discharge", 0.0))
	var used: float = float(state.energy.delivered) + float(state.energy.curtailed) + float(state.energy.loss) + float(state.energy.get("served", 0.0)) + float(state.energy.get("charge", 0.0)) + float(state.energy.get("boiler_electric", 0.0))
	if fuel_schema:
		used += float(state.fuel_energy.auxiliary_mwh)
	if solar_schema:
		used += float(state.solar_energy.auxiliary_mwh)
	if high_temp_schema:
		used += float(state.high_temp_energy.auxiliary_mwh) + float(state.high_temp_energy.oil_auxiliary_mwh)
	if rankine_schema:
		used += float(state.rankine_energy.auxiliary_electric_mwh)
	if tower_schema:
		used += float(state.tower_energy.auxiliary_mwh)
	if not is_finite(supplied) or not is_finite(used):
		return "Accumulated energy totals must remain finite."
	var balance: float = supplied - used
	if absf(balance) > EPS * maxf(1.0, maxf(supplied, used)):
		return "Accumulated energy does not satisfy generation + discharge = delivery + curtailment + loss + served + charge + boiler electric input + fuel boiler auxiliary electricity + solar collector auxiliary electricity."
	if thermal:
		var thermal_error: String = _validate_thermal_energy(state)
		if not thermal_error.is_empty():
			return thermal_error
	elif state.has("thermal_energy"):
		return "Thermal accumulated energy requires save schema 5/model 14 or schema 6/model 15."

	var devices_by_id: Dictionary = {}
	var stations_by_id: Dictionary = {}
	var footprints: Array[Dictionary] = []
	var interior_footprints: Dictionary = {}
	if hierarchy:
		var station_error: String = _validate_stations(state, stations_by_id, footprints, dimension_profile)
		if not station_error.is_empty():
			return station_error
	var receiver_parents: Dictionary = {}
	var maximum_id := -1
	for index in state.devices.size():
		var device: Variant = state.devices[index]
		if not device is Dictionary:
			return "Device %d must be an object." % index
		var key: String = _identifier(device.get("id"))
		if key.is_empty():
			return "Device %d requires a bounded nonnegative integer ID." % index
		var id: int = key.to_int()
		if hierarchy and stations_by_id.has(key):
			return "Device %s ID collides with a station container." % key
		if devices_by_id.has(key):
			return "Duplicate device ID %s." % key
		if not device.get("kind") is String or not device.kind in kinds:
			return "Device %s has an unsupported kind." % key
		if (device.kind in Catalog.NEW_STORAGE_KINDS or device.kind == "solar_thermal" or Catalog.is_high_temp(device.kind) or Catalog.is_rankine(device.kind) or Catalog.is_tower(device.kind)) and dimension_profile != Spatial.METRIC_PROFILE:
			return "Solar collectors require metric_v1 dimensions; explicitly migrate the legacy illustrative scene first."
		if not device.get("params") is Dictionary:
			return "Device %s parameters must be an object." % key
		var errors: Array[String] = Model.validate(device.kind, device.params)
		if not errors.is_empty():
			return "Device %s parameters: %s" % [key, "; ".join(errors)]
		if device.kind in THERMAL_KINDS:
			if not device.get("model_profile") is String or device.model_profile != Catalog.model_profile(device.kind):
				return "Device %s requires thermal model_profile %s." % [key, Catalog.model_profile(device.kind)]
			if device.has("model_profile_version") and (not integer_number(device.model_profile_version) or float(device.model_profile_version) != 1.0):
				return "Device %s requires thermal model_profile_version 1." % key
		elif device.has("model_profile") or device.has("model_profile_version"):
			return "Device %s has an unsupported model_profile for its electric kind." % key
		var state_error: String = _validate_device_state(device)
		if not state_error.is_empty():
			return "Device %s state: %s" % [key, state_error]
		if not finite_number(device.get("x")) or not finite_number(device.get("z")):
			return "Device %s coordinates must be finite numbers." % key
		var has_parent: bool = device.has("parent_station_id")
		var has_interior: bool = device.has("interior_x") or device.has("interior_z")
		if (has_parent or has_interior) and not hierarchy:
			return "Device %s station hierarchy requires save schema 6/model 15." % key
		if has_interior and not has_parent:
			return "Device %s interior coordinates require a parent station." % key
		var position := Vector2(float(device.x), float(device.z))
		var site_radius := radius(device.kind, device.params, dimension_profile)
		if not is_finite(site_radius):
			return "Device %s has invalid metric dimensions." % key
		if device.kind == "solar_tower_receiver" and not has_parent:
			return "Tower receiver requires a commissioned tower_station parent."
		if has_parent:
			if not device.kind in STATION_INTERNAL_KINDS:
				return "Device %s kind cannot be placed inside an electric-thermal station." % key
			var parent_key: String = _identifier(device.parent_station_id)
			if parent_key.is_empty() or not stations_by_id.has(parent_key):
				return "Device %s references a missing or invalid parent station." % key
			if stations_by_id[parent_key].get("kind","thermal_station")=="tower_station_preview": return "Uncommissioned tower preview cannot contain operating devices"
			if not finite_number(device.get("interior_x")) or not finite_number(device.get("interior_z")):
				return "Device %s requires complete finite interior coordinates." % key
			position = Vector2(float(device.interior_x), float(device.interior_z))
			var tower_parent: bool = stations_by_id[parent_key].get("kind", "thermal_station") == "tower_station"
			if device.kind == "solar_tower_receiver":
				if not tower_parent or receiver_parents.has(parent_key): return "Each tower_station permits at most one receiver."
				if position.length() > EPS: return "Tower receiver must remain at its fixed site center."
				receiver_parents[parent_key] = true
			if tower_parent:
				var placement_error: String = Spatial.tower_equipment_position_error(device.kind, device.params, position)
				if not placement_error.is_empty(): return "Device %s: %s" % [key, placement_error]
			var half_width: float = Spatial.TOWER_INTERIOR_DIMENSIONS_M.x * Spatial.WORLD_UNITS_PER_METER * 0.5 if tower_parent else interior_half_width
			var half_depth: float = Spatial.TOWER_INTERIOR_DIMENSIONS_M.z * Spatial.WORLD_UNITS_PER_METER * 0.5 if tower_parent else interior_half_depth
			if absf(position.x) + site_radius > half_width + EPS or absf(position.y) + site_radius > half_depth + EPS:
				return "Device %s footprint extends outside its station interior." % key
			if not interior_footprints.has(parent_key):
				interior_footprints[parent_key] = []
			for other in interior_footprints[parent_key]:
				if position.distance_to(other.position) < site_radius + float(other.radius) - EPS:
					return "Device %s overlaps device %s inside station %s." % [key, str(other.id), parent_key]
			interior_footprints[parent_key].append({"id":id, "position":position, "radius":site_radius})
		else:
			# Older flat thermal devices remain on the base. Parented devices retain
			# finite world x/z as provenance, but only their interior has a footprint.
			if absf(position.x) + site_radius > FIELD_HALF_WIDTH + EPS or absf(position.y) + site_radius > FIELD_HALF_DEPTH + EPS:
				return "Device %s footprint extends outside the buildable field." % key
			for other in footprints:
				if position.distance_to(other.position) < site_radius + float(other.radius) - EPS:
					return "Device %s overlaps %s %s." % [key, str(other.get("kind", "device")), str(other.id)]
			footprints.append({"id":id, "position":position, "radius":site_radius})
		devices_by_id[key] = device
		maximum_id = maxi(maximum_id, id)
	if not integer_number(state.get("next_id")) or float(state.next_id) <= maximum_id or float(state.next_id) < 0.0 or float(state.next_id) > MAX_ID + 1:
		return "Next device ID must be an unused bounded integer greater than every saved ID."
	if hierarchy and stations_by_id.has(str(int(state.next_id))):
		return "Next device ID must not collide with an existing station container."
	if hierarchy and devices_by_id.has(str(int(state.next_station_id))):
		return "Next station ID must not collide with an existing device."

	var outgoing: Dictionary = {}
	for index in state.links.size():
		var link: Variant = state.links[index]
		if not link is Dictionary:
			return "Line %d must be an object." % index
		var source: String = _identifier(link.get("from"))
		var target: String = _identifier(link.get("to"), true)
		if source.is_empty() or target.is_empty():
			return "Line %d endpoint IDs must be bounded integers." % index
		if not devices_by_id.has(source) or (target != "-1" and not devices_by_id.has(target)):
			return "Line %d references a missing device." % index
		if hierarchy:
			var boundary_error: String = _validate_station_link(devices_by_id[source], devices_by_id.get(target, {}))
			if not boundary_error.is_empty():
				return "Line %d: %s" % [index, boundary_error]
		if legacy:
			var source_kind: String = devices_by_id[source].kind
			var allowed: bool = (source_kind == "station" and target == "-1") or (source_kind in ["wind", "pv"] and target != "-1" and devices_by_id[target].kind == "station")
			if not allowed:
				return "Line %d must connect wind/PV to a station, or a station to the external grid." % index
			if outgoing.has(source):
				return "Device %s has more than one outgoing connection." % source
			outgoing[source] = true
		if link.has("capacity_mw") and link.has("capacity_mwth"):
			return "Line %d cannot contain both electric and thermal capacities." % index
		var mass_link: bool = str(link.get("carrier",""))==Catalog.MASS_CARRIER
		var heat_link: bool = link.has("capacity_mwth") or (devices_by_id[source].kind in THERMAL_KINDS and not Catalog.is_rankine(devices_by_id[source].kind))
		var capacity_key: String = "mass_flow_capacity_kg_s" if mass_link else "capacity_mwth" if heat_link else "capacity_mw"
		if not finite_number(link.get(capacity_key)) or float(link[capacity_key]) <= 0.0:
			return "Line %d %s capacity must be finite and positive." % [index, capacity_key]
		if mass_link and not rankine_schema: return "Mass-flow cycle requires schema11"
		if heat_link or mass_link:
			if not thermal:
				return "Line %d thermal capacity requires save schema 5/model 14 or schema 6/model 15." % index
			for field in ["from_port", "to_port", "carrier", "unit", "grade_id"]:
				if not link.get(field) is String or str(link[field]).is_empty():
					return "Thermal line %d requires explicit %s." % [index, field]
			if not finite_number(link.get("loss_fraction")) or float(link.loss_fraction) != 0.0:
				return "Thermal line %d requires loss_fraction=0 in thermal_stage1_v1." % index
		if not finite_number(link.get("loss_fraction")) or float(link.loss_fraction) < 0.0 or float(link.loss_fraction) >= 1.0:
			return "Line %d loss fraction must be finite and within [0, 1)." % index
	# Use exactly the same port/carrier/radial checks as live construction and
	# dispatch. This prevents a hand-edited save bypassing connection validation.
	var topology_errors: Array[String] = Catalog.validate_topology(state.devices, state.links)
	if not topology_errors.is_empty():
		return "Invalid connection topology: %s" % "; ".join(topology_errors)

	var bindings: Dictionary = {}
	for index in state.imports.size():
		var dataset: Variant = state.imports[index]
		if not dataset is Dictionary:
			return "Imported dataset %d must be an object." % index
		var errors: Array[String] = Series.validate_series(dataset)
		if not errors.is_empty():
			return "Imported dataset %d: %s" % [index, "; ".join(errors)]
		var target: String = dataset.target_device
		if dataset.field in Series.GLOBAL_ONLY_FIELDS and not target.is_empty():
			return "Imported dataset %d: cloud cover and precipitation must be global weather." % index
		if not target.is_empty():
			if not target.is_valid_int() or str(target.to_int()) != target or not devices_by_id.has(target):
				return "Imported dataset %d is bound to an unknown/noncanonical device ID." % index
			if not devices_by_id[target].kind in ["wind", "pv"]:
				return "Imported dataset %d must bind to a generating device." % index
			# Validate the current rating; older direct measurements may exceed a
			# subsequently reduced rating and are deliberately clipped by Model.solve.
			var device: Dictionary = devices_by_id[target]
			var params: Dictionary = Model.defaults(device.kind)
			params.merge(device.params, true)
			var rating: Variant = params.get("rated_mw") if device.kind == "wind" else params.get("inverter_capacity_mw")
			if not finite_number(rating) or float(rating) <= 0.0:
				return "Imported dataset %d has an invalid generator rating." % index
		elif dataset.field == "power":
			return "Direct power must bind to one generating device."
		var binding: String = target + ":" + str(dataset.field)
		if bindings.has(binding):
			return "Duplicate imported field %s for target '%s'." % [str(dataset.field), target]
		bindings[binding] = true
	return ""

## Containers have no dispatch parameters, inventory, ports or parent. Their ID
## namespace is distinct from the flat device graph used by simulation and GLPK.
static func _validate_stations(state: Dictionary, stations_by_id: Dictionary, footprints: Array[Dictionary], dimension_profile: String = "legacy_illustrative") -> String:
	var station_radius: float = Spatial.STATION_CLEARANCE_RADIUS_WORLD if dimension_profile == Spatial.METRIC_PROFILE else STATION_RADIUS
	var maximum_id: int = STATION_ID_MIN - 1
	for index in state.stations.size():
		var station: Variant = state.stations[index]
		if not station is Dictionary:
			return "Station %d must be an object." % index
		for field in station:
			if not field in ["id", "name", "x", "z", "kind"]:
				return "Station %d has unsupported field %s; containers cannot nest or store energy." % [index, str(field)]
		var facility_kind: Variant=station.get("kind","thermal_station")
		if not facility_kind is String or not facility_kind in ["thermal_station","tower_station_preview","tower_station"]: return "Unknown facility kind"
		if facility_kind == "tower_station" and int(state.schema) < 12: return "Commissioned tower requires schema12/model21."
		if station.has("kind") and int(state.schema)<11: return "Facility kinds require schema11"
		if facility_kind in ["tower_station_preview","tower_station"] and dimension_profile!=Spatial.METRIC_PROFILE: return "Tower preview requires metric_v1"
		station_radius=radius(facility_kind,{},dimension_profile) if dimension_profile==Spatial.METRIC_PROFILE else STATION_RADIUS
		if not is_finite(station_radius): return "Invalid facility footprint"
		var key: String = _identifier(station.get("id"))
		if key.is_empty() or key.to_int() < STATION_ID_MIN:
			return "Station %d requires an integer ID in the reserved station domain." % index
		if stations_by_id.has(key):
			return "Duplicate station ID %s." % key
		if not station.get("name") is String or station.name.strip_edges().is_empty() or station.name.length() > 128:
			return "Station %s requires a nonblank name of at most 128 characters." % key
		if not finite_number(station.get("x")) or not finite_number(station.get("z")):
			return "Station %s coordinates must be finite numbers." % key
		var position := Vector2(float(station.x), float(station.z))
		if absf(position.x) + station_radius > FIELD_HALF_WIDTH + EPS or absf(position.y) + station_radius > FIELD_HALF_DEPTH + EPS:
			return "Station %s footprint extends outside the buildable field." % key
		for other in footprints:
			if position.distance_to(other.position) < station_radius + float(other.radius) - EPS:
				return "Station %s overlaps station %s." % [key, str(other.id)]
		footprints.append({"id":key.to_int(), "kind":"station", "position":position, "radius":station_radius})
		stations_by_id[key] = station
		maximum_id = maxi(maximum_id, key.to_int())
	if not integer_number(state.get("next_station_id")) or float(state.next_station_id) <= maximum_id or float(state.next_station_id) > MAX_ID + 1:
		return "Next station ID must be an unused bounded integer greater than every saved station ID."
	return ""

## Only AC input to an internal boiler and secondary heat output from an internal
## exchanger may cross a container boundary. Legacy flat devices keep their old
## topology rules, but cannot bridge an interior through a parentless heat node.
static func _validate_station_link(source: Dictionary, target: Dictionary) -> String:
	var source_parent: int = int(source.get("parent_station_id", -1))
	var target_parent: int = int(target.get("parent_station_id", -1))
	if source_parent == target_parent:
		return ""
	# Explicit top-level storage extensions may exchange their fixed carrier
	# across the facility envelope; all port/grade/direction checks still apply.
	if source_parent == -1 and source.kind == "molten_salt_store" and target.get("kind") == "salt_steam_generator": return ""
	if target_parent == -1 and target.get("kind") == "molten_salt_store" and source.kind == "solar_tower_receiver": return ""
	if source_parent == -1 and source.kind == "solid_thermal_store" and target.get("kind") == "heat_exchanger": return ""
	if target_parent == -1 and target.get("kind") == "solid_thermal_store" and source.kind in ["electric_boiler", "fuel_boiler", "solar_thermal"]: return ""
	if source_parent == -1 and source.kind == "station" and target.get("kind") in ["electric_boiler", "fuel_boiler", "solar_thermal", "parabolic_trough", "oil_water_exchanger", "steam_generator", "steam_condenser", "feedwater_pump", "solar_tower_receiver", "molten_salt_store", "salt_steam_generator"]:
		return ""
	if target_parent == -1 and source.kind=="steam_turbine" and target.get("kind")=="station": return ""
	if target_parent == -1 and source.kind == "heat_exchanger" and target.get("kind") == "heat_demand":
		return ""
	return "Station boundaries allow only external AC station to internal boiler, or internal heat exchanger to external heat demand."

## The cumulative port-flow ledgers are independent of current device inventory:
## devices may be removed, so do not reconstruct historical SOC from initial_soc.
static func _validate_thermal_energy(state: Dictionary) -> String:
	if not state.get("thermal_energy") is Dictionary:
		return "Accumulated thermal energy must be an object."
	var thermal: Dictionary = state.thermal_energy
	for key in THERMAL_ENERGY_KEYS:
		if not finite_number(thermal.get(key)) or float(thermal[key]) < 0.0:
			return "Accumulated thermal %s energy must be finite and nonnegative." % key
	for key in thermal:
		if not key in THERMAL_ENERGY_KEYS:
			return "Unknown accumulated thermal energy field: %s." % str(key)
	var requested: float = float(thermal.demand)
	var accounted: float = float(thermal.served) + float(thermal.unserved)
	if not _balanced(requested, accounted):
		return "Accumulated thermal demand must equal served + unserved heat."
	# boiler_heat retains its pre-fuel meaning: electric-boiler heat output only.
	var supplied: float = float(thermal.boiler_heat) + float(thermal.discharge)
	if int(state.schema) >= 8:
		supplied += float(state.fuel_energy.heat_output_mwhth)
	if int(state.schema) >= 9:
		supplied += float(state.solar_energy.useful_mwhth)
	if int(state.schema) >= 10:
		supplied += float(state.high_temp_energy.oil_water_output_mwhth)
	var used: float = float(thermal.served) + float(thermal.charge) + float(thermal.network_loss) + float(thermal.exchanger_loss)
	# Storage conversion/self-discharge losses belong to inventory, not a second
	# network sink. Boiler conversion loss likewise is not an additional AC load.
	if not _balanced(supplied, used):
		return "Accumulated thermal energy must satisfy electric boiler heat + fuel boiler heat + solar useful heat + discharge = served + charge + network loss + exchanger loss."
	var boiler_input: float = float(state.energy.boiler_electric)
	var boiler_accounted: float = float(thermal.boiler_heat) + float(state.energy.boiler_conversion_loss)
	if not _balanced(boiler_input, boiler_accounted):
		return "Accumulated boiler electric input must equal boiler heat + conversion loss."
	return ""

static func _balanced(supplied: float, used: float) -> bool:
	return is_finite(supplied) and is_finite(used) and absf(supplied - used) <= EPS * maxf(1.0, maxf(supplied, used))

static func _validate_device_state(device: Dictionary) -> String:
	# Missing inventory must never silently reset a save to initial_soc.
	if Catalog.is_storage(device.kind) and not device.get("state") is Dictionary:
		return "Stored inventory state must be an object."
	var errors: Array[String] = Catalog.validate_state(device.kind, device.params, device.get("state", {}))
	return "; ".join(errors)
