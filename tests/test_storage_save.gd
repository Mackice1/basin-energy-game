extends SceneTree
## Save-format regressions for the first dispatchable load and battery model.
## Pure validation tests: no terrain boot, user save writes, or live-state edits.
const Validator = preload("res://scripts/save_validator.gd")
const Model = preload("res://scripts/energy_model.gd")
const Series = preload("res://scripts/series_import.gd")
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		push_error(label)

func accepted(state: Variant, label: String) -> void:
	var reason: String = Validator.validate(state)
	check(reason.is_empty(), "%s (%s)" % [label, reason])

func rejected(state: Variant, label: String) -> void:
	check(not Validator.validate(state).is_empty(), label)

func cable(source: Variant, target: Variant) -> Dictionary:
	return {"from":source, "to":target, "capacity_mw":10.0, "loss_fraction":0.0}

func fixture() -> Dictionary:
	var templates: Dictionary = {}
	for kind in ["wind", "pv", "station", "load", "battery"]:
		templates[kind] = Model.defaults(kind)
	var battery: Dictionary = Model.defaults("battery")
	battery.capacity_mwh = 5.0
	return {"schema":4, "model_version":12, "rebuild":true,
		"devices":[
			{"id":0, "kind":"wind", "x":-30.0, "z":0.0, "params":Model.defaults("wind")},
			{"id":1, "kind":"pv", "x":-10.0, "z":20.0, "params":Model.defaults("pv")},
			{"id":2, "kind":"station", "x":10.0, "z":0.0, "params":Model.defaults("station")},
			{"id":3, "kind":"load", "x":30.0, "z":20.0, "params":Model.defaults("load")},
			{"id":4, "kind":"battery", "x":35.0, "z":-10.0, "params":battery, "state":{"energy_mwh":2.7}}],
		"links":[cable(0,2), cable(1,2), cable(2,-1), cable(2,3), cable(2,4)],
		"templates":templates, "imports":[], "next_id":5, "elapsed_s":3600.0,
		"energy":{"generated":10.0, "delivered":0.0, "curtailed":1.0, "loss":0.0,
			"served":6.0, "unserved":2.0, "charge":3.0, "discharge":0.0, "storage_loss":0.3},
		"physical_lines":true}

func legacy_fixture() -> Dictionary:
	var result: Dictionary = fixture()
	result.schema = 3
	result.model_version = 11
	result.devices.resize(3)
	result.links.resize(3)
	result.templates.erase("load")
	result.templates.erase("battery")
	result.next_id = 3
	result.energy = {"generated":10.0, "delivered":8.0, "curtailed":1.0, "loss":1.0}
	return result

func _initialize() -> void:
	var state: Dictionary = fixture()
	var encoded: String = JSON.stringify(state)
	accepted(state, "schema 4 permits station fanout to grid, load and battery")
	accepted(JSON.parse_string(encoded), "schema 4 battery inventory survives JSON numeric round trip")
	check(JSON.stringify(state) == encoded, "new save validation never mutates devices, ports or state")
	check(is_equal_approx(JSON.parse_string(encoded).devices[4].state.energy_mwh, 2.7), "SOC energy survives encoding without reset")
	accepted(legacy_fixture(), "schema 3/model 11 old saves remain loadable")
	var legacy_encoded: String = JSON.stringify(legacy_fixture())
	accepted(JSON.parse_string(legacy_encoded), "schema 3 JSON round trip remains valid")
	check(JSON.stringify(legacy_fixture()) == legacy_encoded, "legacy validation does not migrate the source")
	check(Validator.radius("load") == 4.0 and Validator.radius("battery") == 4.0, "new devices use four-unit construction radius")

	for version in [0, 3, 4.5, "4", INF, NAN]:
		state = fixture(); state.schema = version
		rejected(state, "mismatched or invalid current schema %s" % str(version))
	for version in [11, 13, "12", 12.5, null]:
		state = fixture(); state.model_version = version
		rejected(state, "wrong current model version %s" % str(version))
	state = legacy_fixture(); state.model_version = 12
	rejected(state, "legacy schema cannot silently claim the current energy model")
	state = legacy_fixture(); state.templates.load = Model.defaults("load")
	rejected(state, "legacy template set stays exactly the original three kinds")
	state = legacy_fixture(); state.energy.served = 0.0
	rejected(state, "legacy energy ledger rejects new fields rather than misreading them")
	state = fixture(); state.devices[3].kind = "electrolyzer"
	rejected(state, "unimplemented device kind cannot enter a new save")
	for kind in ["wind", "pv", "station", "load", "battery"]:
		state = fixture(); state.templates.erase(kind)
		rejected(state, "current schema requires %s template" % kind)
		state = fixture(); state.templates[kind] = {}
		accepted(state, "current partial %s template uses model defaults" % kind)
	state = fixture(); state.templates.boiler = {}
	rejected(state, "unknown template kind rejected")
	state = fixture(); state.templates.battery.capacity_mwh = -1.0
	rejected(state, "battery template parameter validation is shared with model")
	state = fixture(); state.templates.load.demand_mw = -1.0
	rejected(state, "load template parameter validation is shared with model")

	for value in [null, [], "bad", 3.0]:
		state = fixture(); state.devices[4].state = value
		rejected(state, "malformed battery state %s" % str(value))
	state = fixture(); state.devices[4].erase("state")
	rejected(state, "new battery save must include actual inventory")
	state = fixture(); state.devices[4].state = {}
	rejected(state, "missing battery energy cannot reset to initial SOC on load")
	for value in [-0.01, 5.0001, INF, NAN, "2.7", true, null]:
		state = fixture(); state.devices[4].state.energy_mwh = value
		rejected(state, "out-of-bounds or mistyped stored energy %s" % str(value))
	for value in [0, 0.0, 5, 5.0]:
		state = fixture(); state.devices[4].state.energy_mwh = value
		accepted(state, "empty/full battery bound %s is accepted" % str(value))
	state = fixture(); state.devices[4].state.soc = 0.5
	rejected(state, "unknown battery state fields are not silently lost")
	state = fixture(); state.devices[3].state = {"energy_mwh":1.0}
	rejected(state, "load cannot carry undeclared battery inventory")
	state = fixture(); state.devices[3].state = {}
	accepted(state, "stateless device may carry an empty state object")
	state = fixture(); state.devices[4].params = {}
	state.devices[4].state.energy_mwh = float(Model.defaults("battery").capacity_mwh)
	accepted(state, "partial battery parameters use default capacity for SOC bound")
	state.devices[4].state.energy_mwh += 0.01
	rejected(state, "default battery capacity still bounds partial parameters")

	for key in fixture().energy:
		state = fixture(); state.energy.erase(key)
		rejected(state, "current energy ledger requires %s" % str(key))
		for value in [-1.0, INF, NAN, "0", true]:
			state = fixture(); state.energy[key] = value
			rejected(state, "current %s rejects invalid energy %s" % [str(key), str(value)])
	state = fixture(); state.energy.unserved = 99.0; state.energy.storage_loss = 0.0
	accepted(state, "unserved energy is diagnostic and never creates a balance sink")
	state.energy.storage_loss = 0.3
	accepted(state, "storage loss is internal inventory accounting, not a second AC sink")
	state = fixture(); state.energy.discharge = 2.43; state.energy.served += 2.43
	accepted(state, "cumulative charging and later discharge use their own balance terms")
	state.energy.generated += 0.1
	rejected(state, "new AC energy mismatch rejected")
	state = fixture(); state.energy.loss = 0.3
	rejected(state, "counting storage loss again in AC loss breaks the ledger")
	state = fixture(); state.energy.unknown = 0.0
	rejected(state, "unknown energy field rejected")
	state = fixture(); state.energy.generated = 1.0e308; state.energy.discharge = 1.0e308
	state.energy.delivered = 1.0e308; state.energy.served = 1.0e308
	rejected(state, "overflow in otherwise finite cumulative totals cannot bypass conservation")

	state = fixture(); state.links[0].from_port = "out"; state.links[0].to_port = "in"; state.links[0].carrier = "electricity_ac"
	state.links[4].from_port = "out"; state.links[4].to_port = "ac"; state.links[4].carrier = "electricity_ac"
	accepted(state, "explicit supported port and carrier metadata accepted")
	state = fixture(); state.links[4] = cable(4,2)
	accepted(state, "battery cable may be stored in either direction")
	for value in ["heat_low", "electricity_dc", "hydrogen", "", null, 7]:
		state = fixture(); state.links[0].carrier = value
		rejected(state, "unsupported carrier %s rejected" % str(value))
	for value in ["in", "unknown", "", null, 3]:
		state = fixture(); state.links[0].from_port = value
		rejected(state, "invalid source port %s rejected" % str(value))
	state = fixture(); state.links[0].to_port = "out"
	rejected(state, "input/output port reversal rejected")
	state = fixture(); state.links[4].to_port = "in"
	rejected(state, "battery requires its declared ac port")
	state = fixture(); state.links.append(state.links[0].duplicate(true))
	rejected(state, "duplicate line rejected")
	state = fixture(); state.links.append(cable(4,2))
	rejected(state, "opposite battery edge cannot duplicate its bidirectional cable")
	state = fixture(); state.links.append(cable(2,2))
	rejected(state, "self-loop rejected")
	state = fixture(); state.links.append(cable(3,2))
	rejected(state, "load cannot generate a reverse edge or cycle")
	state = fixture(); state.links.append(cable(2,0))
	rejected(state, "station cannot feed a generating-device output")
	state = fixture(); state.links[0].to = 999
	rejected(state, "missing line endpoint rejected")
	state = fixture(); state.devices.append({"id":5, "kind":"station", "x":-10.0, "z":-30.0, "params":Model.defaults("station")}); state.next_id = 6
	state.links.append(cable(5,3))
	rejected(state, "a load cannot attach to two stations")
	state.links.pop_back(); state.links.append(cable(4,5))
	rejected(state, "a battery cannot bridge two station islands")
	state.links.pop_back(); state.links.append(cable(0,5))
	rejected(state, "a generator cannot duplicate its output across stations")
	state.links.pop_back(); state.links.append(cable(2,5))
	rejected(state, "unsupported station interconnect rejected")
	state = fixture(); state.links = []
	accepted(state, "disconnected devices are legal saved islands")

	for value in ["0", "01", 0.5, -1, INF, NAN, true, 2147483648.0]:
		state = fixture(); state.devices[0].id = value
		rejected(state, "new device ID rejects coercion or unsupported bounds %s" % str(value))
		state = fixture(); state.links[0].from = value
		rejected(state, "new line source ID rejects coercion or unsupported bounds %s" % str(value))
	state = fixture(); state.devices[1].id = 0.0
	rejected(state, "integer-valued float cannot duplicate an integer device ID")
	state = fixture(); state.next_id = 4
	rejected(state, "next ID must exceed battery and load IDs")
	state = fixture(); state.devices[4].id = 2147483646; state.links[4].to = 2147483646; state.next_id = 2147483647
	accepted(state, "maximum bounded numeric device ID and exhausted next ID accepted")
	state = fixture(); state.links[2].to = "-1"
	rejected(state, "external-grid sentinel must remain numeric")

	state = fixture(); state.devices[3].x = 91.0; state.devices[3].z = 61.0
	accepted(state, "load footprint exactly inside field accepted")
	state.devices[3].x = 91.01
	rejected(state, "new device footprint outside field rejected")
	state = fixture(); state.devices[4].x = state.devices[3].x; state.devices[4].z = state.devices[3].z
	rejected(state, "battery/load overlap rejected")
	state = fixture(); state.imports = [Series.parse("time,power\n0,2000\n3600,1000", {"field":"power", "target_device":"0", "time_column":"time", "value_column":"power", "time_unit":"s", "value_unit":"kW"}).series]
	accepted(state, "new save retains original generation-series compatibility")
	state.imports[0].target_device = "3"
	rejected(state, "existing power import cannot silently change into a load demand")

	print("STORAGE_SAVE_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
