extends SceneTree
## Schema 5 is a strict, non-mutating boundary for two independent energy ledgers.
## Does not boot terrain, write user saves, or alter any live controller state.
const Validator = preload("res://scripts/save_validator.gd")
const Model = preload("res://scripts/energy_model.gd")
const Series = preload("res://scripts/series_import.gd")
const KINDS := ["wind", "pv", "station", "load", "battery", "electric_boiler", "thermal_store", "heat_exchanger", "heat_demand"]
const THERMAL_KINDS := ["electric_boiler", "thermal_store", "heat_exchanger", "heat_demand"]
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

func rejected(state: Variant, label: String) -> void:
	var before: PackedByteArray = var_to_bytes(state)
	check(not Validator.validate(state).is_empty(), label)
	check(var_to_bytes(state) == before, label + " rejection preserves input")

func cable(source: int, target: int) -> Dictionary:
	return {"from":source, "to":target, "capacity_mw":10.0, "loss_fraction":0.0}

func heat_link(source: int, target: int, from_port: String, to_port: String, secondary: bool = false) -> Dictionary:
	return {"from":source, "to":target, "from_port":from_port, "to_port":to_port,
		"carrier":"heat_water", "unit":"MWth", "grade_id":"hw_secondary_70_40" if secondary else "hw_primary_90_60",
		"capacity_mwth":2.0, "loss_fraction":0.0}

func fixture() -> Dictionary:
	var templates: Dictionary = {}
	var devices: Array = []
	var positions: Array[Vector2] = [Vector2(-65,-20), Vector2(-65,20), Vector2(-35,0), Vector2(-35,30),
		Vector2(-35,-30), Vector2(-5,0), Vector2(20,-20), Vector2(25,10), Vector2(55,10)]
	for i in KINDS.size():
		var kind: String = KINDS[i]
		templates[kind] = Model.defaults(kind)
		var device: Dictionary = {"id":i, "kind":kind, "x":positions[i].x, "z":positions[i].y,
			"params":Model.defaults(kind), "state":{}}
		if kind in THERMAL_KINDS:
			device.model_profile = "thermal_stage1_v1"
		if kind == "battery":
			device.state = {"energy_mwh":2.7}
		if kind == "thermal_store":
			device.state = {"energy_mwhth":1.23456789}
			device.params.initial_soc = 0.8
		devices.append(device)
	var boiler_cable: Dictionary = cable(2,5)
	boiler_cable.merge({"from_port":"out", "to_port":"ac_in", "carrier":"electricity_ac", "unit":"MW"})
	return {"schema":5, "model_version":14, "rebuild":true, "devices":devices,
		"links":[cable(0,2), cable(1,2), cable(2,-1), cable(2,3), cable(2,4), boiler_cable,
			heat_link(5,7,"heat_out","hot_in"), heat_link(5,6,"heat_out","heat_in"),
			heat_link(6,7,"heat_out","hot_in"), heat_link(7,8,"warm_out","heat_in",true)],
		"templates":templates, "imports":[], "next_id":9, "elapsed_s":3600.0,
		"energy":{"generated":10.0, "delivered":2.0, "curtailed":1.0, "loss":0.0, "served":3.0,
			"unserved":1.0, "charge":2.0, "discharge":0.0, "storage_loss":0.3,
			"boiler_electric":2.0, "boiler_conversion_loss":0.04},
		"thermal_energy":{"demand":2.0, "served":1.6, "unserved":0.4, "boiler_heat":1.96,
			"charge":0.5, "discharge":0.25, "network_loss":0.0, "exchanger_loss":0.11, "storage_loss":0.15},
		"physical_lines":true}

func old_fixture(schema: int) -> Dictionary:
	var state: Dictionary = fixture()
	state.schema = schema
	state.model_version = 11 if schema == 3 else 12
	state.devices.resize(3 if schema == 3 else 5)
	state.links.resize(3 if schema == 3 else 5)
	state.next_id = state.devices.size()
	state.erase("thermal_energy")
	state.energy.erase("boiler_electric")
	state.energy.erase("boiler_conversion_loss")
	state.energy.delivered += 2.0
	for kind in THERMAL_KINDS:
		state.templates.erase(kind)
	if schema == 3:
		state.templates.erase("load")
		state.templates.erase("battery")
		state.energy = {"generated":10.0, "delivered":9.0, "curtailed":1.0, "loss":0.0}
	return state

func _initialize() -> void:
	var state: Dictionary = fixture()
	accepted(state, "schema 5 supports all nine kinds and separate electric/heat ledgers")
	var encoded: String = JSON.stringify(state)
	var restored: Dictionary = JSON.parse_string(encoded)
	accepted(restored, "schema 5 survives numeric JSON round trip")
	check(is_equal_approx(restored.devices[6].state.energy_mwhth, 1.23456789), "thermal inventory round trip preserves actual energy")
	check(restored.devices[6].state.size() == 1 and not restored.devices[6].state.has("energy_mwh"), "heat storage never aliases electric battery state")
	check(not is_equal_approx(restored.devices[6].state.energy_mwhth, restored.devices[6].params.capacity_mwhth * restored.devices[6].params.initial_soc), "saved stock is distinct from new-build initial SOC")
	check(restored.devices[4].state == {"energy_mwh":2.7}, "existing battery state keeps its electric field")
	for schema in [3,4]:
		state = old_fixture(schema)
		accepted(state, "old schema %d stays loadable" % schema)
		accepted(JSON.parse_string(JSON.stringify(state)), "old schema %d JSON remains loadable" % schema)
		check(state.devices.size() == (3 if schema == 3 else 5), "validating old schema never inserts thermal devices")
		state.thermal_energy = fixture().thermal_energy
		rejected(state, "old schema cannot hide a new thermal ledger")
		state = old_fixture(schema); state.devices[0].state = {"energy_mwhth":1.0}
		rejected(state, "old generator cannot hide fabricated stored heat")

	for value in [false,"true",1,null,{},[]]:
		state = fixture(); state.rebuild = value
		rejected(state, "malformed rebuild marker cannot cause coercion or runtime error")
	state = fixture(); state.erase("rebuild")
	accepted(state, "optional rebuild marker retains legacy compatibility")
	state = fixture(); state.devices = []; state.links = []; state.next_id = 0
	accepted(state, "empty current scene may retain cumulative historical energy")
	state = fixture(); state.devices.resize(5); state.links.resize(5); state.next_id = 5
	accepted(state, "schema 5 electric-only scene does not invent thermal devices")
	for value in [0,1,2,6,14,-1,5.5,"5",null,true,INF,NAN]:
		state = fixture(); state.schema = value
		rejected(state, "unsupported or malformed schema %s" % str(value))
	for value in [11,12,13,15,14.5,"14",null,true,INF,NAN]:
		state = fixture(); state.model_version = value
		rejected(state, "schema 5 requires exact model 14: %s" % str(value))
	for kind in KINDS:
		state = fixture(); state.templates.erase(kind)
		rejected(state, "schema 5 requires %s template" % kind)
		state = fixture(); state.templates[kind] = {}
		accepted(state, "partial %s templates retain model defaults" % kind)
	state = fixture(); state.templates.steam_turbine = {}
	rejected(state, "unimplemented template is rejected")
	state = fixture(); state.devices[5].kind = "steam_boiler"
	rejected(state, "unimplemented thermal kind is rejected")
	for index in [5,6,7,8]:
		state = fixture(); state.devices[index].erase("model_profile")
		rejected(state, "every thermal device requires an explicit profile")
		for value in ["thermal_stage1_v2","steam_90_60","",1,true,null]:
			state = fixture(); state.devices[index].model_profile = value
			rejected(state, "unknown or mistyped thermal profile rejected")
		state = fixture(); state.devices[index].model_profile_version = 1
		accepted(state, "optional explicit thermal profile version 1 accepted")
		for value in [0,2,1.5,"1",true,null,INF]:
			state = fixture(); state.devices[index].model_profile_version = value
			rejected(state, "unknown explicit thermal profile version rejected")
	state = fixture(); state.devices[0].model_profile = "thermal_stage1_v1"
	rejected(state, "electric device cannot silently adopt a thermal profile")

	for value in [null,[],"bad",3.0]:
		state = fixture(); state.devices[6].state = value
		rejected(state, "malformed thermal storage state rejected")
	state = fixture(); state.devices[6].erase("state")
	rejected(state, "missing heat inventory cannot reset to initial SOC")
	state = fixture(); state.devices[6].state = {}
	rejected(state, "empty heat inventory cannot reset to initial SOC")
	for value in [-0.001,4.000001,INF,NAN,"1.2",true,null]:
		state = fixture(); state.devices[6].state.energy_mwhth = value
		rejected(state, "forged or invalid thermal stock %s rejected" % str(value))
	for value in [0,0.0,4,4.0]:
		state = fixture(); state.devices[6].state.energy_mwhth = value
		accepted(state, "thermal stock bound %s accepted" % str(value))
	for field in ["energy_mwh","soc","temperature_c","steam","unexpected"]:
		state = fixture(); state.devices[6].state[field] = 1.0
		rejected(state, "unknown thermal inventory field %s rejected" % field)
	state = fixture(); state.devices[6].state = {"energy_mwh":1.2}
	rejected(state, "electric inventory field cannot replace thermal stock")
	state = fixture(); state.devices[4].state = {"energy_mwhth":2.7}
	rejected(state, "thermal inventory field cannot replace battery stock")
	for index in [0,1,2,3,5,7,8]:
		state = fixture(); state.devices[index].state = {"energy_mwhth":1.0}
		rejected(state, "stateless kind cannot store forged heat")
		state = fixture(); state.devices[index].state = null
		rejected(state, "stateless kind cannot have malformed state")
		state = fixture(); state.devices[index].erase("state")
		accepted(state, "stateless kind may omit empty state")
	state = fixture(); state.devices[6].params.capacity_mwhth = 1.0
	rejected(state, "shrinking storage below current inventory is rejected")
	state = fixture(); state.devices[6].params.initial_soc = 0.0
	accepted(state, "changing initial SOC never rewrites saved heat stock")
	state = fixture(); state.devices[6].params = {}; state.devices[6].state.energy_mwhth = 4.0
	accepted(state, "default thermal capacity bounds partial device parameters")
	state.devices[6].state.energy_mwhth += 0.0001
	rejected(state, "partial thermal parameters still reject overcapacity stock")
	for index in [5,6,7,8]:
		state = fixture(); state.devices[index].params.unrecognized = 1.0
		rejected(state, "unknown thermal parameter rejected")

	for key in fixture().energy:
		state = fixture(); state.energy.erase(key)
		rejected(state, "schema 5 requires electric field %s" % key)
		for value in [-1.0,INF,NAN,"0",true,null]:
			state = fixture(); state.energy[key] = value
			rejected(state, "electric ledger invalid %s rejected" % key)
	for key in fixture().thermal_energy:
		state = fixture(); state.thermal_energy.erase(key)
		rejected(state, "schema 5 requires thermal field %s" % key)
		for value in [-1.0,INF,NAN,"0",true,null]:
			state = fixture(); state.thermal_energy[key] = value
			rejected(state, "thermal ledger invalid %s rejected" % key)
	state = fixture(); state.erase("thermal_energy")
	rejected(state, "missing schema 5 heat ledger rejected")
	state = fixture(); state.thermal_energy.unknown = 0.0
	rejected(state, "unknown heat ledger field rejected")
	state = fixture(); state.energy.unknown = 0.0
	rejected(state, "unknown electric ledger field rejected")
	state = fixture(); state.thermal_energy.demand += 0.1
	rejected(state, "thermal demand must equal served plus unserved")
	state = fixture(); state.thermal_energy.charge += 0.1
	rejected(state, "thermal network must conserve heat")
	state = fixture(); state.energy.delivered += state.energy.boiler_conversion_loss
	rejected(state, "boiler conversion loss cannot be subtracted twice from AC ledger")
	state = fixture(); state.energy.boiler_conversion_loss += 0.1
	rejected(state, "boiler electric and thermal ledgers must agree")
	state = fixture(); state.thermal_energy.exchanger_loss += state.thermal_energy.storage_loss
	rejected(state, "storage loss cannot be subtracted twice from thermal network")
	state = fixture(); state.thermal_energy.storage_loss = 9.0; state.energy.storage_loss = 7.0
	accepted(state, "storage losses belong to inventory and are not extra network sinks")
	state = fixture(); state.thermal_energy.demand = 1e308; state.thermal_energy.served = 1e308; state.thermal_energy.unserved = 1e308
	rejected(state, "overflow cannot defeat thermal demand accounting")
	state = fixture(); state.thermal_energy.boiler_heat = 1e308; state.thermal_energy.discharge = 1e308
	rejected(state, "overflow cannot defeat thermal network accounting")
	state = fixture(); state.thermal_energy.demand = 1e308; state.thermal_energy.served = 1e308
	state.thermal_energy.unserved = 0.0; state.thermal_energy.boiler_heat = 1e308
	state.energy.boiler_electric = 1e308; state.energy.boiler_conversion_loss = 1e308
	state.energy.generated = 1e308
	rejected(state, "overflow cannot defeat boiler cross-carrier accounting")

	for index in [6,7,8,9]:
		for field in ["from_port","to_port","carrier","unit","grade_id","capacity_mwth","loss_fraction"]:
			state = fixture(); state.links[index].erase(field)
			rejected(state, "thermal link requires explicit %s" % field)
		for field in ["from_port","to_port","carrier","unit","grade_id"]:
			for value in ["unknown","",null,1,true]:
				state = fixture(); state.links[index][field] = value
				rejected(state, "malformed thermal %s rejected" % field)
		state = fixture(); state.links[index].capacity_mw = 2.0
		rejected(state, "thermal edge cannot include both capacities")
		state = fixture(); state.links[index].capacity_mw = 2.0; state.links[index].erase("capacity_mwth")
		rejected(state, "thermal edge cannot replace thermal capacity with electric MW")
		for value in [0,-1,10000.1,INF,NAN,true,"2",null]:
			state = fixture(); state.links[index].capacity_mwth = value
			rejected(state, "invalid thermal edge capacity rejected")
		for value in [-1,0.01,1,INF,NAN,true,"0",null]:
			state = fixture(); state.links[index].loss_fraction = value
			rejected(state, "thermal stage 1 must retain fixed zero network loss")
		state = fixture(); state.links.append(state.links[index].duplicate(true))
		rejected(state, "duplicate same thermal ports rejected")
	state = fixture(); state.links[6].to = 8; state.links[6].to_port = "heat_in"
	rejected(state, "primary boiler heat cannot bypass exchanger to secondary demand")
	state = fixture(); state.links[8] = heat_link(6,5,"heat_out","ac_in")
	rejected(state, "heat cannot enter electric boiler input")
	state = fixture(); state.links[6] = heat_link(5,5,"heat_out","ac_in")
	rejected(state, "thermal self connection rejected")
	state = fixture(); state.links[6].to = 999
	rejected(state, "missing thermal endpoint rejected")
	state = fixture(); state.links[6].grade_id = "hw_secondary_70_40"
	rejected(state, "forged primary thermal edge grade rejected")
	state = fixture(); state.links[9].grade_id = "hw_primary_90_60"
	rejected(state, "forged secondary thermal edge grade rejected")
	state = fixture(); state.links[5].to_port = "heat_out"
	rejected(state, "station AC cannot enter a boiler heat output")
	state = fixture(); state.links[5].capacity_mwth = 2.0
	rejected(state, "boiler AC input retains electric MW capacity")
	state = fixture(); state.links[6].voltage_level = "AC_BUS"
	rejected(state, "thermal edge must not pretend to have AC voltage")
	state = fixture(); state.links = []
	accepted(state, "thermal disconnected islands retain inventory and demand")

	check(Validator.radius("electric_boiler") == 4.0 and Validator.radius("thermal_store") == 5.0 and Validator.radius("heat_exchanger") == 4.0 and Validator.radius("heat_demand") == 4.0, "thermal footprints agree with construction and visual bounds")
	state = fixture(); state.devices[6].x = 90.0; state.devices[6].z = 60.0
	accepted(state, "thermal store footprint may touch field boundary")
	state.devices[6].x = 90.001
	rejected(state, "thermal store radius prevents clipping past field boundary")
	state = fixture(); state.devices[6].x = state.devices[5].x + 8.9; state.devices[6].z = state.devices[5].z
	rejected(state, "thermal store radius prevents device overlap")
	state = fixture(); state.imports = [Series.parse("time,power\n0,2000\n3600,1000", {"field":"power", "target_device":"0", "time_column":"time", "value_column":"power", "time_unit":"s", "value_unit":"kW"}).series]
	accepted(state, "existing generator power CSV remains compatible")
	state.imports[0].target_device = "8"
	rejected(state, "electric generator CSV cannot be repurposed as heat demand")

	print("THERMAL_SAVE_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
