extends SceneTree
## Non-mutating schema-6 validation for the two-level electric-thermal layout.
## Container geometry is independent of the existing flat dispatch/energy graph.
const Validator = preload("res://scripts/save_validator.gd")
const Model = preload("res://scripts/energy_model.gd")
const KINDS := ["wind", "pv", "station", "load", "battery", "electric_boiler", "thermal_store", "heat_exchanger", "heat_demand"]
const INTERNAL := ["electric_boiler", "thermal_store", "heat_exchanger"]
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func accepted(state: Variant, label: String) -> void:
	var before: PackedByteArray = var_to_bytes(state)
	var reason: String = Validator.validate(state)
	check(reason.is_empty(), "%s (%s)" % [label, reason])
	check(var_to_bytes(state) == before, label + " preserves input")

func rejected(state: Variant, label: String, expected: String = "") -> void:
	var before: PackedByteArray = var_to_bytes(state)
	var reason: String = Validator.validate(state)
	check(not reason.is_empty(), label)
	if not expected.is_empty():
		check(reason.contains(expected), "%s reports %s (%s)" % [label, expected, reason])
	check(var_to_bytes(state) == before, label + " rejection preserves input")

func cable(source: int, target: int) -> Dictionary:
	return {"from":source, "to":target, "capacity_mw":10.0, "loss_fraction":0.0}

func heat_link(source: int, target: int, from_port: String, to_port: String, secondary: bool = false) -> Dictionary:
	return {"from":source, "to":target, "from_port":from_port, "to_port":to_port,
		"carrier":"heat_water", "unit":"MWth", "grade_id":"hw_secondary_70_40" if secondary else "hw_primary_90_60",
		"capacity_mwth":2.0, "loss_fraction":0.0}

func fixture() -> Dictionary:
	var templates: Dictionary = {}
	for kind in KINDS:
		templates[kind] = Model.defaults(kind)
	var devices: Array = []
	var kinds: Array[String] = ["wind", "station", "electric_boiler", "thermal_store", "heat_exchanger", "heat_demand"]
	var positions: Array[Vector2] = [Vector2(-65,0), Vector2(-40,0), Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2(50,0)]
	var interiors: Array[Vector2] = [Vector2(-12,-8), Vector2(12,-8), Vector2(0,10)]
	for index in kinds.size():
		var kind: String = kinds[index]
		var device: Dictionary = {"id":index, "kind":kind, "x":positions[index].x, "z":positions[index].y, "params":Model.defaults(kind), "state":{}}
		if kind in INTERNAL or kind == "heat_demand":
			device.model_profile = "thermal_stage1_v1"
		if kind in INTERNAL:
			device.parent_station_id = 1000000
			device.interior_x = interiors[index - 2].x
			device.interior_z = interiors[index - 2].y
		if kind == "thermal_store":
			device.state = {"energy_mwhth":1.23456789}
			device.params.initial_soc = 0.8
		devices.append(device)
	var boiler_cable: Dictionary = cable(1,2)
	boiler_cable.merge({"from_port":"out", "to_port":"ac_in", "carrier":"electricity_ac", "unit":"MW"})
	return {"schema":6, "model_version":15, "rebuild":true, "devices":devices,
		"stations":[{"id":1000000, "name":"电热站 A", "x":0.0, "z":0.0}], "next_station_id":1000001,
		"links":[cable(0,1), cable(1,-1), boiler_cable,
			heat_link(2,3,"heat_out","heat_in"), heat_link(2,4,"heat_out","hot_in"),
			heat_link(3,4,"heat_out","hot_in"), heat_link(4,5,"warm_out","heat_in",true)],
		"templates":templates, "imports":[], "next_id":6, "elapsed_s":3600.0,
		"energy":{"generated":10.0, "delivered":2.0, "curtailed":1.0, "loss":0.0, "served":3.0,
			"unserved":1.0, "charge":2.0, "discharge":0.0, "storage_loss":0.3,
			"boiler_electric":2.0, "boiler_conversion_loss":0.04},
		"thermal_energy":{"demand":2.0, "served":1.6, "unserved":0.4, "boiler_heat":1.96,
			"charge":0.5, "discharge":0.25, "network_loss":0.0, "exchanger_loss":0.11, "storage_loss":0.15},
		"physical_lines":true}

func make_flat(state: Dictionary) -> void:
	var positions: Array[Vector2] = [Vector2(-15,-20), Vector2(10,-20), Vector2(20,5)]
	for index in [2,3,4]:
		state.devices[index].erase("parent_station_id")
		state.devices[index].erase("interior_x")
		state.devices[index].erase("interior_z")
		state.devices[index].x = positions[index - 2].x
		state.devices[index].z = positions[index - 2].y

func old_fixture(schema: int) -> Dictionary:
	var state: Dictionary = fixture()
	make_flat(state)
	state.schema = schema
	state.model_version = 14 if schema == 5 else (12 if schema == 4 else 11)
	state.erase("stations")
	state.erase("next_station_id")
	if schema < 5:
		state.devices.resize(2)
		state.links.resize(2)
		state.next_id = 2
		state.erase("thermal_energy")
		state.energy.erase("boiler_electric")
		state.energy.erase("boiler_conversion_loss")
		state.energy.delivered += 2.0
		for kind in ["electric_boiler", "thermal_store", "heat_exchanger", "heat_demand"]:
			state.templates.erase(kind)
	if schema == 3:
		state.templates.erase("load")
		state.templates.erase("battery")
		state.energy = {"generated":10.0, "delivered":9.0, "curtailed":1.0, "loss":0.0}
	return state

func add_second_station(state: Dictionary) -> void:
	state.stations.append({"id":1000001, "name":"电热站 B", "x":0.0, "z":35.0})
	state.next_station_id = 1000002

func _initialize() -> void:
	var state: Dictionary = fixture()
	accepted(state, "schema6/model15 accepts flat dispatch graph with visual station hierarchy")
	var restored: Dictionary = JSON.parse_string(JSON.stringify(state))
	accepted(restored, "station and parent numeric IDs survive JSON float round trip")
	check(int(restored.stations[0].id) == state.stations[0].id and restored.stations[0].name == state.stations[0].name and restored.stations[0].x == state.stations[0].x and restored.stations[0].z == state.stations[0].z, "station position and name round trip exactly")
	check(restored.devices[3].state.energy_mwhth == 1.23456789, "stored heat survives without resetting to initial SOC")
	check(restored.energy == state.energy and restored.thermal_energy == state.thermal_energy, "container adds no extra energy ledger")
	for index in state.links.size():
		check(int(restored.links[index].from) == state.links[index].from and int(restored.links[index].to) == state.links[index].to, "container leaves flat link endpoint IDs intact")
	check(Validator.STATION_RADIUS == 8.0 and Validator.INTERIOR_HALF_WIDTH == 24.0 and Validator.INTERIOR_HALF_DEPTH == 24.0, "save and controller geometry contract")

	for schema in [3,4,5]:
		state = old_fixture(schema)
		accepted(state, "schema %d legacy scene remains loadable" % schema)
		accepted(JSON.parse_string(JSON.stringify(state)), "schema %d legacy JSON remains loadable" % schema)
		state.devices[0].id = 2147483646
		state.links[0].from = 2147483646
		state.next_id = 2147483647
		accepted(state, "schema %d retains legacy maximum device ID" % schema)
		state = old_fixture(schema); state.stations = []
		rejected(state, "old schema cannot hide hierarchy containers", "schema 6")
		state = old_fixture(schema); state.next_station_id = 1000000
		rejected(state, "old schema cannot hide hierarchy allocator", "schema 6")
		state = old_fixture(schema); state.devices[0].parent_station_id = 1000000
		rejected(state, "old schema cannot hide child metadata", "schema 6")
		state = old_fixture(schema); state.devices[0].interior_x = 0.0
		rejected(state, "old schema cannot hide interior metadata", "schema 6")

	for value in [0,3,4,5,14,15.5,"15",true,null,INF,NAN]:
		state = fixture(); state.model_version = value
		rejected(state, "schema6 requires exact model15")
	for key in ["stations", "next_station_id"]:
		state = fixture(); state.erase(key)
		rejected(state, "schema6 requires %s" % key)
	for value in [null,{},true,"stations",1]:
		state = fixture(); state.stations = value
		rejected(state, "station collection must be an array")
	state = fixture(); state.stations = []; state.devices = []; state.links = []; state.next_id = 0; state.next_station_id = 1000000
	accepted(state, "empty hierarchy preserves historical ledgers")
	state = fixture(); state.devices = []; state.links = []; state.next_id = 0
	accepted(state, "empty station container is valid and has no inventory")
	state = fixture(); make_flat(state); state.stations = []; state.next_station_id = 1000000
	accepted(state, "schema6 preserves parentless legacy thermal equipment")
	state = fixture(); make_flat(state)
	accepted(state, "legacy flat equipment can coexist with a new empty station")

	for value in [null,[],"station",1,true]:
		state = fixture(); state.stations[0] = value
		rejected(state, "station record must be an object")
	for key in ["id", "name", "x", "z"]:
		state = fixture(); state.stations[0].erase(key)
		rejected(state, "station requires %s" % key)
	for value in [-1,0,999999,1000000.5,2147483647.0,"1000000",true,null,INF,NAN]:
		state = fixture(); state.stations[0].id = value
		rejected(state, "station ID requires reserved bounded integer")
	for value in [null,1,true,"","  \n\t", "x".repeat(129)]:
		state = fixture(); state.stations[0].name = value
		rejected(state, "station name must be nonblank bounded text")
	state = fixture(); state.stations[0].name = "x".repeat(128)
	accepted(state, "maximum station name length accepted")
	for field in ["parent_station_id", "stations", "children", "devices", "params", "capacity_mw", "capacity_mwhth", "energy", "state", "kind", "interior_x"]:
		state = fixture(); state.stations[0][field] = {}
		rejected(state, "station cannot hide nested hierarchy or dispatch field %s" % field, "Unknown facility kind" if field=="kind" else "unsupported field")
	state = fixture(); add_second_station(state); state.stations[1].id = 1000000.0
	rejected(state, "numeric equivalent IDs cannot duplicate stations", "Duplicate station")
	state = fixture(); state.stations.resize(Validator.MAX_STATIONS + 1)
	rejected(state, "station collection bound rejects oversized scene", "too many")
	for value in [0,999999,1000000,1000001.5,2147483648.0,"1000001",true,null,INF,NAN]:
		state = fixture(); state.next_station_id = value
		rejected(state, "next station ID must be bounded unused integer")
	state = fixture(); state.stations[0].id = 2147483646; state.next_station_id = 2147483647
	for device in state.devices:
		if device.has("parent_station_id"):
			device.parent_station_id = 2147483646
	accepted(state, "maximum station ID and exhausted allocator accepted")
	state = fixture(); state.devices[0].id = 1000000; state.links[0].from = 1000000; state.next_id = 1000001
	rejected(state, "station and device IDs cannot collide", "collides")
	state = fixture(); state.devices[0].id = 2147483646; state.links[0].from = 2147483646; state.next_id = 2147483647
	accepted(state, "schema6 preserves high legacy IDs outside actual station IDs")
	state = fixture(); state.next_id = 1000000
	rejected(state, "next device ID cannot collide with station", "Next device ID")
	state = fixture(); state.devices[0].id = 1000001; state.links[0].from = 1000001; state.next_id = 1000002
	rejected(state, "next station ID cannot collide with device", "Next station ID")

	for index in [2,3,4]:
		for value in [-1,0,2,1000001,1000000.5,"1000000",true,null,INF,NAN]:
			state = fixture(); state.devices[index].parent_station_id = value
			rejected(state, "internal parent must name actual station integer ID")
		for field in ["interior_x", "interior_z"]:
			state = fixture(); state.devices[index].erase(field)
			rejected(state, "parent requires complete %s" % field, "interior coordinates")
			for value in ["0",true,null,INF,NAN]:
				state = fixture(); state.devices[index][field] = value
				rejected(state, "interior coordinate must remain finite numeric")
		state = fixture(); state.devices[index].erase("parent_station_id")
		rejected(state, "interior without parent rejected", "require a parent")
		for field in ["x", "z"]:
			state = fixture(); state.devices[index].erase(field)
			rejected(state, "parented device retains global provenance %s" % field)
			for value in ["0",null,true,INF,NAN]:
				state = fixture(); state.devices[index][field] = value
				rejected(state, "parented global provenance must remain finite")
	for index in [0,1,5]:
		state = fixture(); state.devices[index].parent_station_id = 1000000; state.devices[index].interior_x = 0.0; state.devices[index].interior_z = 0.0
		rejected(state, "external kind cannot have station parent", "cannot be placed inside")
	for kind in ["pv", "load", "battery"]:
		state = fixture(); state.links = []; state.devices[0].kind = kind; state.devices[0].params = Model.defaults(kind)
		state.devices[0].state = {"energy_mwh":1.0} if kind == "battery" else {}
		state.devices[0].parent_station_id = 1000000; state.devices[0].interior_x = 0.0; state.devices[0].interior_z = 0.0
		rejected(state, "all other electric kinds remain external", "cannot be placed inside")

	for field in ["x", "z"]:
		for value in ["0",null,true,INF,NAN]:
			state = fixture(); state.stations[0][field] = value
			rejected(state, "station ground coordinate requires finite number")
	state = fixture(); state.stations[0].x = 87.0; state.stations[0].z = 57.0
	accepted(state, "station radius8 can touch base field boundary")
	state.stations[0].x += 0.01
	rejected(state, "station footprint cannot leave base field", "outside the buildable field")
	state = fixture(); state.stations[0].z = -57.01
	rejected(state, "negative station footprint cannot leave base field")
	state = fixture(); add_second_station(state); state.stations[1].z = 16.0
	accepted(state, "station footprints may touch")
	state.stations[1].z = 15.99
	rejected(state, "station footprints cannot overlap", "overlaps station")
	state = fixture(); state.stations[0].x = -28.0
	accepted(state, "station and external AC station footprints may touch")
	state.stations[0].x = -28.01
	rejected(state, "station collides with external electric device", "overlaps station")
	state = fixture(); state.stations[0].x = 38.01
	rejected(state, "station collides with external heat demand", "overlaps station")
	state = fixture(); state.devices[0].x = 0.0
	rejected(state, "external generator still has base collision footprint")
	state = fixture(); state.devices[5].x = 91.01
	rejected(state, "external heat demand still obeys base field bounds")
	state = fixture()
	for index in [2,3,4]:
		state.devices[index].x = 1e12
		state.devices[index].z = -1e12
	accepted(state, "parented provenance ignores base bounds and shared ground overlap")
	for index in [2,3,4]:
		var site_radius: float = Validator.radius(state.devices[index].kind)
		state = fixture(); state.devices[index].interior_x = 24.0 - site_radius; state.devices[index].interior_z = 24.0 - site_radius
		accepted(state, "internal footprint may touch both interior edges")
		state.devices[index].interior_x += 0.01
		rejected(state, "internal footprint cannot leave station interior", "outside its station interior")
		state = fixture(); state.devices[index].interior_z = -(24.01 - site_radius)
		rejected(state, "negative interior boundary includes device radius")
	state = fixture(); state.devices[3].interior_x = -3.0; state.devices[3].interior_z = -8.0
	accepted(state, "interior footprints may touch exactly")
	state.devices[3].interior_x -= 0.01
	rejected(state, "interior boiler and storage cannot overlap", "inside station")
	state = fixture(); add_second_station(state); state.links = []
	state.devices[3].parent_station_id = 1000001
	state.devices[3].interior_x = state.devices[2].interior_x; state.devices[3].interior_z = state.devices[2].interior_z
	accepted(state, "different interiors have independent overlapping coordinates")
	state.devices[3].parent_station_id = 1000000
	rejected(state, "same coordinates collide only within same station")

	state = fixture(); add_second_station(state)
	accepted(state, "second station may remain empty with existing flat links unchanged")
	for index in [2,3,4]:
		state = fixture(); add_second_station(state); state.devices[index].parent_station_id = 1000001
		rejected(state, "internal heat edges cannot cross station parents", "Station boundaries")
	for index in [2,3,4]:
		state = fixture()
		state.devices[index].erase("parent_station_id"); state.devices[index].erase("interior_x"); state.devices[index].erase("interior_z")
		state.devices[index].x = 20.0; state.devices[index].z = -25.0
		rejected(state, "legacy thermal component cannot bridge station interior", "Station boundaries")
	state = fixture(); state.links = [state.links[2]]
	accepted(state, "external AC station feeds internal boiler through declared AC port")
	state.links[0].from = 0
	rejected(state, "external wind cannot directly cross station boundary", "Station boundaries")
	state = fixture(); state.links = [state.links[6]]
	accepted(state, "internal exchanger feeds external secondary heat demand")
	state = fixture(); state.links = [cable(2,-1)]
	rejected(state, "internal device cannot cross boundary to external grid", "Station boundaries")
	state = fixture(); state.links[2].to = 1000000
	rejected(state, "visual station container cannot become a dispatch endpoint", "missing device")
	state = fixture(); state.links[2].from = 1000000
	rejected(state, "visual station container cannot become dispatch source", "missing device")
	state = fixture(); state.links[3].capacity_mw = 2.0
	rejected(state, "hierarchy retains strict electric versus heat line units")
	state = fixture(); state.links[4].grade_id = "hw_secondary_70_40"
	rejected(state, "hierarchy retains strict temperature grade validation")
	state = fixture(); state.devices[3].state.energy_mwhth = 5.0
	rejected(state, "hierarchy retains actual inventory bounds")
	state = fixture(); state.energy.generated += 1.0
	rejected(state, "hierarchy retains independent electric ledger balance")
	state = fixture(); state.thermal_energy.served += 1.0
	rejected(state, "hierarchy retains independent heat ledger balance")
	state = fixture(); state.links = []
	accepted(state, "unconnected internal equipment remains valid")

	print("STATION_SAVE_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
