extends SceneTree
## Pure fuel-resource/catalog/schema boundaries; no terrain, GUI or user-save writes.
const Catalog = preload("res://scripts/device_catalog.gd")
const Fuel = preload("res://scripts/fuel_supply.gd")
const Validator = preload("res://scripts/save_validator.gd")
const Model = preload("res://scripts/energy_model.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func near(actual: float, expected: float, label: String) -> void:
	check(absf(actual - expected) < 1.0e-8, "%s: %.10f / %.10f" % [label, actual, expected])

func accepted(state: Dictionary, label: String) -> void:
	var before: PackedByteArray = var_to_bytes(state)
	var error: String = Validator.validate(state)
	check(error.is_empty(), label + ": " + error)
	check(var_to_bytes(state) == before, label + " leaves input unchanged")

func rejected(state: Dictionary, label: String, expected: String = "") -> void:
	var before: PackedByteArray = var_to_bytes(state)
	var error: String = Validator.validate(state)
	check(not error.is_empty(), label)
	if not expected.is_empty():
		check(error.contains(expected), label + " reason: " + error)
	check(var_to_bytes(state) == before, label + " leaves rejected input unchanged")

func empty_state(schema: int = 8) -> Dictionary:
	var state: Dictionary = {"schema":schema, "model_version": {3:11, 4:12, 5:14, 6:15, 7:16, 8:17}[schema],
		"rebuild":true, "devices":[], "links":[], "imports":[], "templates":{},
		"next_id":0, "elapsed_s":0.0, "physical_lines":true, "energy":{}}
	var kinds: Array = Validator.CURRENT_KINDS if schema >= 8 else (Validator.PRE_FUEL_KINDS if schema >= 5 else (Validator.ELECTRIC_KINDS if schema == 4 else Validator.LEGACY_KINDS))
	var keys: Array = Validator.CURRENT_ENERGY_KEYS if schema >= 5 else (Validator.ELECTRIC_ENERGY_KEYS if schema == 4 else Validator.LEGACY_ENERGY_KEYS)
	for kind in kinds:
		state.templates[kind] = Model.defaults(kind)
	for key in keys:
		state.energy[key] = 0.0
	if schema >= 5:
		state.thermal_energy = {}
		for key in Validator.THERMAL_ENERGY_KEYS:
			state.thermal_energy[key] = 0.0
	if schema >= 6:
		state.stations = []
		state.next_station_id = Validator.STATION_ID_MIN
	if schema >= 7:
		state.dimension_profile = "legacy_illustrative"
	if schema >= 8:
		state.fuel_supply = Fuel.defaults()
		state.fuel_energy = Fuel.initial_energy()
	return state

func device(id: int, kind: String, x: float = 0.0, z: float = 0.0) -> Dictionary:
	var result: Dictionary = {"id":id, "kind":kind, "params":Model.defaults(kind), "state":Catalog.initial_state(kind), "x":x, "z":z}
	if Catalog.is_thermal(kind):
		result.model_profile = Catalog.model_profile(kind)
		result.model_profile_version = 1
	return result

func cable(source: int, target: int) -> Dictionary:
	return {"from":source, "to":target, "from_port":"out", "to_port":"ac_in", "carrier":"electricity_ac", "unit":"MW", "capacity_mw":1.0, "loss_fraction":0.0}

func pipe(source: int, target: int, from_port: String = "heat_out", to_port: String = "hot_in", secondary: bool = false) -> Dictionary:
	return {"from":source, "to":target, "from_port":from_port, "to_port":to_port,
		"carrier":"heat_water", "unit":"MWth", "grade_id":"hw_secondary_70_40" if secondary else "hw_primary_90_60",
		"capacity_mwth":2.0, "loss_fraction":0.0}

func fixture() -> Dictionary:
	var state: Dictionary = empty_state()
	state.stations = [{"id":1000000, "name":"Natural-gas hot-water station", "x":0.0, "z":0.0}]
	state.next_station_id = 1000001
	state.devices = [device(0,"station",-40.0), device(1,"fuel_boiler"), device(2,"thermal_store"), device(3,"heat_exchanger"), device(4,"heat_demand",50.0)]
	var positions: Array[Vector2] = [Vector2(-12,-8), Vector2(12,-8), Vector2(0,10)]
	for index in range(1,4):
		state.devices[index].parent_station_id = 1000000
		state.devices[index].interior_x = positions[index - 1].x
		state.devices[index].interior_z = positions[index - 1].y
	state.links = [cable(0,1), pipe(1,2,"heat_out","heat_in"), pipe(1,3), pipe(2,3), pipe(3,4,"warm_out","heat_in",true)]
	state.next_id = 5
	state.elapsed_s = 3600.0
	state.fuel_supply.enabled = true
	state.fuel_supply.max_input_mw = 2.0
	state.fuel_energy = {"input_mwh":2.0, "volume_nm3":200.0, "cost":600.0, "heat_output_mwhth":1.8, "conversion_loss_mwh":0.2, "auxiliary_mwh":0.02}
	state.energy.generated = 0.02
	state.thermal_energy.demand = 1.764
	state.thermal_energy.served = 1.764
	state.thermal_energy.exchanger_loss = 0.036
	return state

func test_catalog() -> void:
	check(Catalog.SCHEMA_VERSION == 3, "catalog snapshot version increases for new implemented kind")
	check(Catalog.implemented_kinds().count("fuel_boiler") == 1, "exactly one new fuel boiler kind")
	check(Catalog.is_thermal("fuel_boiler"), "fuel boiler is a thermal converter")
	check(Catalog.model_profile("fuel_boiler") == "thermal_stage1_v1", "fuel boiler uses the same fixed hot-water profile")
	check(Catalog.defaults("fuel_boiler") == {"rated_fuel_mw":2.0,"thermal_efficiency":0.90,"auxiliary_electric_ratio":0.01}, "fuel boiler defaults specify LHV input and separate auxiliary")
	check(Model.validate("fuel_boiler",{}).is_empty(), "energy model delegates fuel validation")
	for key in ["rated_fuel_mw", "thermal_efficiency", "auxiliary_electric_ratio"]:
		for value in [-1.0, 0.0, NAN, INF, "1", true, null]:
			check(not Model.validate("fuel_boiler",{key:value}).is_empty(), "fuel parameter %s rejects %s" % [key,value])
	check(Model.validate("fuel_boiler",{"rated_fuel_mw":10000.0,"thermal_efficiency":1.0,"auxiliary_electric_ratio":0.001}).is_empty(), "inclusive valid fuel bounds")
	check(Model.validate("fuel_boiler",{"auxiliary_electric_ratio":0.2}).is_empty(), "maximum auxiliary ratio accepted")
	for params in [{"rated_fuel_mw":10000.1},{"thermal_efficiency":1.001},{"auxiliary_electric_ratio":0.0009},{"auxiliary_electric_ratio":0.201},{"fuel":"coal"},{"steam_pressure_bar":10.0}]:
		check(not Model.validate("fuel_boiler",params).is_empty(), "unsupported parameter or bound rejected: " + str(params))
	check(Catalog.initial_state("fuel_boiler").is_empty(), "fuel boiler has no fuel stock")
	check(not Catalog.validate_state("fuel_boiler",{}, {"energy_mwh":1.0}).is_empty(), "fuel boiler cannot hide inventory")
	var ports: Array = Catalog.ports("fuel_boiler")
	check(ports.size() == 2, "fuel resource is not a third network port")
	check(Catalog.port("fuel_boiler","ac_in").carrier == "electricity_ac", "auxiliary AC input")
	check(Catalog.port("fuel_boiler","heat_out").grade_id == "hw_primary_90_60", "primary hot-water output")
	check(Catalog.port("fuel_boiler","fuel_in").is_empty() and Catalog.port("fuel_boiler","steam_out").is_empty(), "no fabricated fuel-pipe or steam interface")
	var state: Dictionary = fixture()
	check(Catalog.validate_topology(state.devices,state.links).is_empty(), "fuel AC and primary branches are legal")
	var second: Dictionary = device(5,"station",-60.0)
	state.devices.append(second)
	check(not Catalog.validate_link(state.devices,state.links,cable(5,1)).is_empty(), "fuel auxiliary has only one electric-station attachment")
	check(not Catalog.validate_link(state.devices,[],pipe(1,4,"heat_out","heat_in")).is_empty(), "primary fuel boiler cannot bypass secondary heat exchanger")
	var invalid_link: Dictionary = cable(0,1)
	invalid_link.erase("to_port")
	check(not Catalog.validate_link(state.devices,[],invalid_link).is_empty(), "auxiliary electrical links must be explicit")
	invalid_link = pipe(1,3); invalid_link.carrier = "natural_gas"
	check(not Catalog.validate_link(state.devices,[],invalid_link).is_empty(), "gas cannot masquerade as a heat link")

func test_resource() -> void:
	var supply: Dictionary = Fuel.defaults()
	check(supply.enabled == false and supply.max_input_mw == 0.0, "fuel is disabled and rate zero by default")
	check(Fuel.validate(supply).is_empty(), "complete default resource validates")
	check(Fuel.normalized({"enabled":true,"max_input_mw":2.0}).max_input_mw == 2.0, "valid partial runtime config normalizes")
	for value in [null, false, [], "gas", {"enabled":"true"}, {"max_input_mw":INF}, {"other":1}]:
		check(Fuel.normalized(value) == Fuel.defaults(), "invalid runtime fuel config fails closed")
		check(not Fuel.validate(value).is_empty(), "incomplete or malformed config is rejected by save boundary")
	for key in supply:
		var incomplete: Dictionary = supply.duplicate(true)
		incomplete.erase(key)
		check(not Fuel.validate(incomplete).is_empty(), "save fuel config requires " + key)
	for key in ["max_input_mw","lower_heating_value_kwh_per_nm3","price_per_mwh"]:
		for value in [-1.0,NAN,INF,"10",true,null]:
			var invalid: Dictionary = supply.duplicate(true)
			invalid[key] = value
			check(not Fuel.validate(invalid).is_empty(), "fuel config rejects %s=%s" % [key,value])
	for update in [{"enabled":1},{"max_input_mw":10000.1},{"lower_heating_value_kwh_per_nm3":0.0},{"lower_heating_value_kwh_per_nm3":101.0},{"price_per_mwh":1000001.0},{"fuel_kind":"coal"},{"tank_stock_nm3":10.0},{"enabled":true,"max_input_mw":2.0,"lower_heating_value_kwh_per_nm3":1.0e-320}]:
		var invalid: Dictionary = supply.duplicate(true)
		invalid.merge(update,true)
		check(not Fuel.validate(invalid).is_empty(), "fuel resource refuses unsupported config " + str(update))
	near(Fuel.volume_nm3(2.0,supply),200.0,"2 MWh at10 kWh/Nm3 means200 Nm3")
	near(Fuel.cost(2.0,supply),600.0,"teaching cost is input MWh times configured CNY/MWh")
	supply.lower_heating_value_kwh_per_nm3 = 8.0
	supply.price_per_mwh = 0.0
	near(Fuel.volume_nm3(2.0,supply),250.0,"volume uses configured LHV without changing thermal input")
	near(Fuel.cost(2.0,supply),0.0,"explicit zero teaching tariff is valid")
	check(Fuel.validate(supply).is_empty(), "configured zero price is not a fuel-enable switch")
	check(Fuel.initial_energy() == {"input_mwh":0.0,"volume_nm3":0.0,"cost":0.0,"heat_output_mwhth":0.0,"conversion_loss_mwh":0.0,"auxiliary_mwh":0.0},"migration fuel ledger starts at zero")
	check(Fuel.validate_energy(Fuel.initial_energy()).is_empty(),"zero fuel ledger validates")
	var ledger: Dictionary = fixture().fuel_energy
	check(Fuel.validate_energy(ledger).is_empty(),"three-way fuel/electric/heat fixture validates")
	for key in Fuel.ENERGY_KEYS:
		for value in [-1.0,NAN,INF,"0",true,null]:
			var invalid: Dictionary = ledger.duplicate(true)
			invalid[key] = value
			check(not Fuel.validate_energy(invalid).is_empty(),"fuel ledger rejects %s=%s" % [key,value])
		var missing: Dictionary = ledger.duplicate(true)
		missing.erase(key)
		check(not Fuel.validate_energy(missing).is_empty(),"fuel ledger requires " + key)
	for update in [{"heat_output_mwhth":1.9},{"conversion_loss_mwh":0.3},{"auxiliary_mwh":0.0},{"auxiliary_mwh":0.5},{"volume_nm3":0.0},{"inventory_mwh":1.0}]:
		var invalid: Dictionary = ledger.duplicate(true)
		invalid.merge(update,true)
		check(not Fuel.validate_energy(invalid).is_empty(),"fuel ledger physical check " + str(update))
	var zero: Dictionary = Fuel.initial_energy(); zero.cost = 1.0
	check(not Fuel.validate_energy(zero).is_empty(),"no charge may be fabricated without fuel input")

func test_save() -> void:
	accepted(fixture(),"schema8/model17 preserves independent fuel resource and ledgers")
	accepted(JSON.parse_string(JSON.stringify(fixture())),"fuel save survives JSON numeric ID round trip")
	accepted(empty_state(),"new empty save has disabled resource and zero fuel")
	var state: Dictionary = empty_state(); state.dimension_profile = "metric_v1"
	accepted(state,"schema8 retains explicit metric profile")
	for schema in [3,4,5,6,7]:
		state = empty_state(schema)
		accepted(state,"legacy schema%d remains valid" % schema)
		accepted(JSON.parse_string(JSON.stringify(state)),"legacy schema%d round trip stays valid" % schema)
		check(not state.has("fuel_supply") and not state.has("fuel_energy") and not state.templates.has("fuel_boiler"),"legacy validation does not mutate migration input")
		state.fuel_supply = Fuel.defaults()
		rejected(state,"legacy schema cannot hide fuel supply", "schema 8")
		state = empty_state(schema); state.fuel_energy = Fuel.initial_energy()
		rejected(state,"legacy schema cannot hide fuel ledger", "schema 8")
	state = empty_state(7); state.templates.fuel_boiler = Model.defaults("fuel_boiler")
	rejected(state,"new device template cannot be smuggled into old schema", "Unknown template")
	for field in ["fuel_supply","fuel_energy","dimension_profile"]:
		state = fixture(); state.erase(field)
		rejected(state,"schema8 requires " + field)
	state = fixture(); state.model_version = 16
	rejected(state,"schema8 requires model17","version 17")
	state = fixture(); state.templates.erase("fuel_boiler")
	rejected(state,"schema8 requires fuel boiler template","fuel_boiler template")
	state = fixture(); state.devices[1].model_profile = "steam_v1"
	rejected(state,"fuel boiler rejects steam model profile","model_profile")
	state = fixture(); state.devices[1].state = {"fuel_nm3":100.0}
	rejected(state,"fuel boiler cannot persist tank inventory","Only storage")
	state = fixture(); state.devices[1].params.auxiliary_electric_ratio = 0.0
	rejected(state,"save disallows free auxiliary energy","auxiliary_electric_ratio")
	for id in [-1,0.5,"1",true,INF,NAN,2147483648.0]:
		state = fixture(); state.devices[1].id = id
		rejected(state,"fuel ID is a finite bounded integer")
	state = fixture(); state.devices[1].parent_station_id = 1000001
	rejected(state,"fuel boiler rejects missing parent station","parent station")
	state = fixture(); state.devices[1].interior_x = INF
	rejected(state,"fuel boiler rejects nonfinite interior position","interior")
	state = fixture(); state.devices[1].interior_x = 30.0
	rejected(state,"fuel boiler footprint stays inside station","outside")
	state = fixture(); state.stations.append({"id":1000001,"name":"Other station","x":0.0,"z":35.0}); state.next_station_id = 1000002; state.devices[1].parent_station_id = 1000001
	rejected(state,"fuel heat cannot cross station interiors","boundaries")
	state = fixture(); state.energy.generated = 0.0
	rejected(state,"fuel auxiliary is a real AC sink","Accumulated energy")
	state = fixture(); state.thermal_energy.boiler_heat = 1.8
	rejected(state,"fuel heat cannot be counted twice in electric boiler ledger","thermal energy")
	state = fixture(); state.fuel_energy.heat_output_mwhth = 1.0
	rejected(state,"fuel input conversion must conserve energy","Fuel input")
	state = fixture(); state.fuel_supply.enabled = false; state.fuel_supply.max_input_mw = 0.0
	accepted(state,"disabling present fuel does not erase historical metering")
	state = fixture(); state.fuel_supply.lower_heating_value_kwh_per_nm3 = 8.0; state.fuel_supply.price_per_mwh = 400.0
	accepted(state,"historical volume and cost retain prior LHV and tariff")
	state = fixture(); state.devices.clear(); state.links.clear()
	accepted(state,"removing devices does not invalidate historical independent ledgers")
	state = fixture(); state.fuel_supply.extra = true
	rejected(state,"unknown resource data rejected","Unknown fuel supply")
	state = fixture(); state.fuel_energy.extra = true
	rejected(state,"unknown ledger data rejected","Unknown accumulated fuel")
	state = fixture(); state.links[0].carrier = "natural_gas"
	rejected(state,"resource cannot be forged as network carrier","topology")
	state = fixture(); state.devices[4].kind = "fuel_stock"
	rejected(state,"no unintended fuel stock device","unsupported kind")

func _initialize() -> void:
	test_catalog()
	test_resource()
	test_save()
	print("FUEL_CATALOG_SAVE_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
