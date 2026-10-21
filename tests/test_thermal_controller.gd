extends SceneTree
## Real world controller integration. Only terrain, rendering and editor widgets
## are isolated; every report, inventory transition and audit uses Model.dispatch.

class Fixture:
	extends "res://scripts/world_game.gd"
	var last_notice := ""
	var irradiance := 1000.0
	func _ready(): pass
	func tell(message: String): last_notice = message
	func exclusion(_x: float, _z: float) -> String: return ""
	func slope_at(_x: float, _z: float) -> float: return 0.0
	func height_at(_x: float, _z: float) -> float: return 0.0
	func rebuild_equipment(): pass
	func rebuild_cables(): pass
	func update_status(): pass
	func update_camera(): pass
	func set_mode(value: String): mode = value; pending_link = -2
	func select_device(id: int): selected_id = id
	func start_build(kind: String): build_kind = kind; set_mode("build")
	func ask(message: String, action: Callable): last_notice = message; confirm_action = action
	func weather_at(_t: float) -> Dictionary:
		return {"wind_speed_mps":12.0, "irradiance_wm2":irradiance, "air_temp_c":25.0}

class ParameterInput:
	extends RefCounted
	var values: Dictionary = {}
	func get_parameters() -> Dictionary: return values.duplicate(true)
	func get_validation_errors() -> Array: return []

const SPECS := [["pv", Vector2(-65,0)], ["station", Vector2(-40,0)],
	["electric_boiler", Vector2(-15,0)], ["thermal_store", Vector2(10,-20)],
	["heat_exchanger", Vector2(10,10)], ["heat_demand", Vector2(35,10)],
	["load", Vector2(-40,25)], ["battery", Vector2(-40,-25)]]
const HEAT_KEYS := ["demand", "served", "unserved", "boiler_heat", "charge", "discharge",
	"network_loss", "exchanger_loss", "storage_loss"]
var checks := 0
var failures: Array[String] = []
var fixtures: Array = []
var save_paths: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func near(actual: float, expected: float, label: String, tolerance: float = 1.0e-9) -> void:
	check(is_finite(actual) and absf(actual - expected) <= tolerance,
		"%s (actual=%.14f expected=%.14f)" % [label, actual, expected])

func fixture() -> Fixture:
	var game := Fixture.new()
	game.cfg = {"max_build_slope_degrees":8.0}
	game.booted = true
	for kind in game.KINDS:
		game.templates[kind] = game.model.defaults(kind)
	fixtures.append(game)
	return game

func chain(pv_mw: float = 2.0) -> Fixture:
	var game := fixture()
	for spec in SPECS:
		check(game.add_equipment(spec[0], spec[1], false), "fixture places " + spec[0])
	game.device(0).params.merge({"dc_capacity_mw":pv_mw, "inverter_capacity_mw":pv_mw,
		"inverter_efficiency":1.0, "temp_coefficient_per_c":0.0, "dc_loss_fraction":0.0}, true)
	game.device(1).params = {"capacity_mw":10.0, "loss_fraction":0.0}
	game.device(3).params.self_discharge_per_h = 0.0
	game.device(5).params.demand_mwth = 0.0
	game.device(6).params.demand_mw = 0.0
	game.device(7).state.energy_mwh = 0.0
	for pair in [[0,1], [1,2], [2,3], [2,4], [3,4], [4,5], [1,6], [7,1]]:
		var edge: Dictionary = game.connection_candidate(pair[0], pair[1])
		edge.loss_fraction = 0.0
		game.links.append(edge)
	game.refresh()
	check(game.result.get("valid", false), "fixture has valid real electric/thermal dispatch: " + game.last_notice)
	return game

func click_connect(game: Fixture, first: int, second: int) -> void:
	game.set_mode("link")
	game.link_to(first)
	check(game.pending_link == first, "first click retains endpoint %d" % first)
	game.link_to(second)

func remove_edge(game: Fixture, source: int, target: int) -> void:
	game.links = game.links.filter(func(edge): return not (int(edge.from) == source and int(edge.to) == target))

func assert_ledgers(game: Fixture, label: String) -> void:
	var e: Dictionary = game.energy
	var h: Dictionary = game.thermal_energy
	near(e.generated + e.discharge, e.curtailed + e.loss + e.served + e.charge + e.boiler_electric + e.delivered, label + " AC conservation")
	near(h.boiler_heat + h.discharge, h.served + h.charge + h.network_loss + h.exchanger_loss, label + " heat network conservation")
	near(h.demand, h.served + h.unserved, label + " heat demand conservation")
	near(e.boiler_electric, h.boiler_heat + e.boiler_conversion_loss, label + " boiler cross-carrier conservation")
	check(game.validate_state(game.state()).is_empty(), label + " complete schema 5 state validates")

func path_for(label: String) -> String:
	var path := "user://thermal_controller_test/%d_%s.json" % [OS.get_process_id(), label]
	save_paths.append(path)
	return path

func write_fixture(path: String, value: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "open isolated fixture file")
	if file != null:
		file.store_string(JSON.stringify(value)); file.close()

func _initialize() -> void: call_deferred("run")

func run() -> void:
	test_construction_and_connections()
	test_single_commit_and_ledgers()
	test_service_and_disconnection()
	test_island_and_atomic_rejection()
	test_save_resume_undo_and_rejection()
	test_parameters_and_legacy()
	test_example()
	for game in fixtures: cleanup(game)
	for path in save_paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("THERMAL_CONTROLLER checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func test_construction_and_connections() -> void:
	var game := fixture()
	game.templates.thermal_store.initial_soc = 0.375
	for spec in SPECS:
		check(game.add_equipment(spec[0], spec[1]), "controller builds " + spec[0])
	for id in [2,3,4,5]:
		check(game.device(id).model_profile == "thermal_stage1_v1", "new thermal device has versioned profile")
		check(game.device(id).params == game.templates[game.device(id).kind], "new thermal parameters copy template")
	near(game.device(3).state.energy_mwhth, 1.5, "new store uses initial SOC once")
	check(game.device(3).state.size() == 1 and not game.device(3).state.has("energy_mwh"), "heat inventory has no electric field")
	for id in [2,4,5]: check(game.device(id).state.is_empty(), "stateless thermal device stays stateless")
	game.device(3).params.initial_soc = 0.9
	near(game.templates.thermal_store.initial_soc, 0.375, "device parameters do not alias construction template")
	game.start_heat_demand_node()
	check(game.mode == "build" and game.build_kind == "heat_demand", "dedicated heat-demand action enters placement")
	check(not "heat_demand" in game.BUILDABLE_KINDS and not "load" in game.BUILDABLE_KINDS, "both demand kinds stay outside equipment build catalog")
	for pair in [[1,0], [2,1], [3,2], [4,2], [4,3], [5,4]]:
		var before := game.links.size()
		click_connect(game, pair[0], pair[1])
		check(game.links.size() == before + 1 and game.pending_link == -2, "reverse clicks create legal directed edge")
	for spec in [[2,3,"heat_out","heat_in","hw_primary_90_60"],
		[2,4,"heat_out","hot_in","hw_primary_90_60"],
		[3,4,"heat_out","hot_in","hw_primary_90_60"],
		[4,5,"warm_out","heat_in","hw_secondary_70_40"]]:
		var edge: Dictionary = game.connection_candidate(spec[1], spec[0])
		check(edge.from == spec[0] and edge.to == spec[1], "thermal direction canonicalized")
		check(edge.from_port == spec[2] and edge.to_port == spec[3] and edge.grade_id == spec[4], "thermal ports and grade explicit")
		check(edge.carrier == "heat_water" and edge.unit == "MWth" and edge.capacity_mwth == 2.0 and edge.loss_fraction == 0.0 and not edge.has("capacity_mw"), "thermal edge has only MWth capacity")
	var boiler_ac: Dictionary = game.links[1]
	check(boiler_ac.from == 1 and boiler_ac.to == 2 and boiler_ac.to_port == "ac_in" and boiler_ac.carrier == "electricity_ac" and boiler_ac.unit == "MW", "boiler AC input coexists with multiple heat outputs")
	for pair in [[2,5], [3,5], [1,3], [0,2], [4,1], [5,0], [2,2], [3,-1], [2,999]]:
		var before: PackedByteArray = var_to_bytes(game.state())
		var revision := game.scene_revision
		click_connect(game, pair[0], pair[1])
		check(var_to_bytes(game.state()) == before and game.scene_revision == revision, "invalid cross-carrier/grade/endpoint pair is atomic")
		check(game.last_notice.contains("不能连接"), "invalid pair gives connection reason")
	var count := game.links.size()
	var duplicate_before: PackedByteArray = var_to_bytes(game.state())
	click_connect(game, 5, 4)
	check(game.links.size() == count and var_to_bytes(game.state()) == duplicate_before, "duplicate ports rejected without checkpoint")
	check(game.last_notice.contains("未连接"), "duplicate gives validation reason")
	assert_ledgers(game, "constructed scene")

func test_single_commit_and_ledgers() -> void:
	var game := chain(4.0)
	game.device(6).params.demand_mw = 0.5
	var frozen: PackedByteArray = var_to_bytes(game.state())
	for i in 8:
		game.refresh(); game.solve_at(0.0)
	check(var_to_bytes(game.state()) == frozen, "refresh/preview never commit either SOC or cumulative ledger")
	var dat: Dictionary = game.dispatch_inputs(0.0)
	var expected: Dictionary = game.model.dispatch(game.devices, game.links, dat.weather, dat.direct, 0.25)
	check(expected.valid and expected.commit_allowed and expected.audit_errors.is_empty(), "real fractional dispatch passes independent audit")
	near(expected.boiler_electric_mw, 2.0, "surplus boiler input exact")
	near(expected.thermal.charge_mwth, 1.96, "boiler output charged at heat port")
	near(expected.charge_mw, 1.5, "remaining electricity charges battery separately")
	check(game.advance(0.25), "advance fractional real electric/heat transaction")
	near(game.device(3).state.energy_mwhth, 1.9208 * 0.25 / 3600.0, "thermal SOC commits exactly once", 1.0e-12)
	near(game.device(7).state.energy_mwh, 1.35 * 0.25 / 3600.0, "electric SOC commits exactly once", 1.0e-12)
	for key in game.energy:
		near(game.energy[key], expected.get(key + "_mw", 0.0) * 0.25 / 3600.0, "electric cumulative field " + key, 1.0e-12)
	for key in HEAT_KEYS:
		var amount: float = expected.thermal.get(key + "_mwth", 0.0) * 0.25 / 3600.0
		if key == "storage_loss": amount = expected.thermal.storage_conversion_loss_mwth * 0.25 / 3600.0 + expected.thermal.self_discharge_mwhth
		near(game.thermal_energy[key], amount, "thermal cumulative field " + key, 1.0e-12)
	frozen = var_to_bytes(game.state())
	check(game.advance(0.0), "zero duration accepted")
	game.refresh(); game.solve_at(game.elapsed_s)
	check(var_to_bytes(game.state()) == frozen, "zero duration and endpoint report do not perform a second commit")
	check(game.advance(2.0), "multiple one-second substeps advance")
	near(game.device(3).state.energy_mwhth, 1.9208 * 2.25 / 3600.0, "multi-step thermal inventory exact")
	near(game.device(7).state.energy_mwh, 1.35 * 2.25 / 3600.0, "multi-step electric inventory exact")
	near(game.thermal_energy.storage_loss, (1.96 - 1.9208) * 2.25 / 3600.0, "thermal conversion loss integrated once")
	near(game.energy.storage_loss, 0.15 * 2.25 / 3600.0, "battery conversion loss remains electric")
	near(game.elapsed_s, 2.25, "fractional elapsed time preserved")
	check(game.thermal_energy.size() == HEAT_KEYS.size(), "all schema 5 heat ledger keys present")
	assert_ledgers(game, "charged scene")

func test_service_and_disconnection() -> void:
	var game := chain()
	remove_edge(game, 2, 3); remove_edge(game, 3, 4); remove_edge(game, 7, 1)
	game.device(5).params.demand_mwth = 2.0
	game.refresh()
	near(game.result.boiler_electric_mw, 2.0, "2 MW reaches boiler")
	near(game.result.thermal.boiler_heat_mwth, 1.96, "boiler converts 0.98")
	near(game.result.thermal.served_mwth, 1.9208, "exchanger converts 0.98")
	near(game.result.thermal.unserved_mwth, 0.0792, "thermal shortfall is explicit")
	near(game.result.boiler_conversion_loss_mw, 0.04, "boiler conversion loss explicit")
	near(game.result.thermal.exchanger_loss_mwth, 0.0392, "exchanger loss explicit")
	near(game.result.unserved_mw, 0.0, "heat shortfall does not invent electric demand")
	check(game.advance(3.5), "partial heat service integrates")
	near(game.thermal_energy.unserved, 0.0792 * 3.5 / 3600.0, "missing heat accumulates in thermal ledger")
	game.checkpoint(); remove_edge(game, 4, 5); game.refresh()
	near(game.result.thermal.demand_mwth, 2.0, "disconnect preserves requested heat")
	near(game.result.thermal.unserved_mwth, 2.0, "disconnected heat demand remains fully unserved")
	near(game.result.boiler_electric_mw, 0.0, "no useful heat sink means no boiler electricity")
	check(game.thermal_connection_status(5).contains("未连接"), "disconnected demand is identified")
	game.undo()
	near(game.result.thermal.served_mwth, 1.9208, "undo restores heat connection and service")
	var before: PackedByteArray = var_to_bytes(game.state())
	game.selected_id = 4; game.remove_selected()
	check(var_to_bytes(game.state()) == before, "demolition remains pending before confirmation")
	game.confirm_action.call()
	check(game.device(4).is_empty() and not game.device(5).is_empty(), "demolishing exchanger does not delete independent heat demand")
	near(game.result.thermal.unserved_mwth, 2.0, "demolition exposes missing heat")
	game.undo()
	check(var_to_bytes(game.state()) == before, "demolition undo restores topology, stock and ledgers")
	assert_ledgers(game, "direct heat service")
	# Stored heat works after the generator is disconnected, without a powered boiler.
	var stored := chain()
	stored.device(3).state.energy_mwhth = 0.2
	stored.device(5).params.demand_mwth = 0.4
	remove_edge(stored, 0, 1); stored.refresh()
	near(stored.result.boiler_electric_mw, 0.0, "unpowered boiler cannot make heat")
	near(stored.result.thermal.served_mwth, 0.4, "stored heat serves disconnected electric island")
	check(stored.advance(1.0), "stored heat-only transaction commits")
	near(stored.device(3).state.energy_mwhth, 0.2 - 0.4 / 0.98 / 0.98 / 3600.0, "both discharge and exchanger losses deducted once")
	stored.device(3).state.energy_mwhth = 0.0; stored.refresh()
	near(stored.result.thermal.served_mwth, 0.0, "empty store does not supply heat")
	near(stored.result.thermal.unserved_mwth, 0.4, "empty store retains shortfall")

func test_island_and_atomic_rejection() -> void:
	var game := fixture()
	game.templates.thermal_store.initial_soc = 0.25
	check(game.add_equipment("thermal_store", Vector2.ZERO, false), "place isolated store")
	check(game.add_equipment("heat_demand", Vector2(20,0), false), "place disconnected demand")
	var split := fixture()
	split.restore(game.state())
	var frozen: PackedByteArray = var_to_bytes(game.state())
	game.refresh(); game.solve_at(0.0); game.advance(0.0)
	check(var_to_bytes(game.state()) == frozen, "paused isolated store does not self-discharge")
	check(game.advance(3600.0), "one hour isolated self-discharge")
	for dt in [0.25,29.75,870.0,2700.0]: check(split.advance(dt), "partitioned isolated self-discharge")
	near(game.device(0).state.energy_mwhth, exp(-0.002), "island decay matches analytic exponential", 1.0e-11)
	near(split.device(0).state.energy_mwhth, game.device(0).state.energy_mwhth, "pure decay independent of call partition", 1.0e-11)
	near(game.thermal_energy.storage_loss, 1.0 - exp(-0.002), "island self-discharge appears once in heat losses", 1.0e-11)
	near(game.thermal_energy.demand, 1.0, "disconnected one-hour heat request accumulates")
	near(game.thermal_energy.unserved, 1.0, "disconnected one-hour shortage accumulates")
	near(game.thermal_energy.charge + game.thermal_energy.discharge, 0.0, "island exchanges no heat at ports")
	assert_ledgers(game, "isolated storage")
	for invalid_dt in [-1.0, INF, NAN]:
		frozen = var_to_bytes(game.state())
		check(not game.advance(invalid_dt), "invalid duration rejected")
		check(var_to_bytes(game.state()) == frozen, "invalid duration cannot mutate inventory, time or ledgers")
	var live := chain()
	live.device(3).state.energy_mwhth = 0.25
	live.links[2].grade_id = "hw_secondary_70_40"
	frozen = var_to_bytes(live.state())
	var revision := live.scene_revision
	check(not live.advance(1.0), "invalid live thermal grade rejects advance")
	check(var_to_bytes(live.state()) == frozen and live.scene_revision == revision and live.paused, "rejected thermal transaction has no partial state or ledger commit")
	check(not live.last_notice.is_empty(), "rejected thermal transaction explains blocker")

func test_save_resume_undo_and_rejection() -> void:
	var control := chain()
	control.device(3).params.self_discharge_per_h = 0.002
	control.device(3).params.initial_soc = 0.85
	check(control.advance(3.25), "charge before save")
	var stored: float = control.device(3).state.energy_mwhth
	check(stored > 0.0 and stored < 0.01, "save contains nonzero runtime inventory distinct from initial SOC")
	var path := path_for("resume")
	check(control.write_save(path), "write real isolated schema 5 file")
	var on_disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(on_disk.schema == 13 and on_disk.model_version == 22, "controller persists schema 13 model 22")
	for key in HEAT_KEYS: check(on_disk.thermal_energy.has(key), "persisted heat field " + key)
	check(on_disk.energy.has("boiler_electric") and on_disk.energy.has("boiler_conversion_loss"), "persisted electric boiler ledger fields")
	var resumed := fixture()
	resumed.paused = false; resumed.speed = 60.0; resumed.accumulator = 0.4
	check(resumed.read_save(path), "fresh controller restores real file")
	near(resumed.device(3).state.energy_mwhth, stored, "restore preserves actual heat inventory, ignoring initial SOC", 1.0e-12)
	check(resumed.paused and resumed.speed == 1.0 and resumed.accumulator == 0.0, "load resumes safely paused at 1x")
	check(resumed.links == on_disk.links and resumed.imports == on_disk.imports, "load restores complete topology and inputs")
	var saw_charge := false
	var saw_discharge := false
	for phase in [[4.75,1000.0,0.0], [2.5,0.0,1.0], [1.25,0.0,0.5], [5.0,1000.0,0.25], [2.75,1000.0,0.0], [0.5,0.0,1.5]]:
		for game in [control,resumed]:
			game.irradiance = phase[1]; game.device(5).params.demand_mwth = phase[2]
			check(game.advance(phase[0]), "continued real heat-storage trajectory advances")
		saw_charge = saw_charge or control.result.thermal.charge_mwth > 0.0
		saw_discharge = saw_discharge or control.result.thermal.discharge_mwth > 0.0
		near(resumed.elapsed_s, control.elapsed_s, "resumed trajectory time agrees", 1.0e-12)
		near(resumed.device(3).state.energy_mwhth, control.device(3).state.energy_mwhth, "resumed thermal inventory agrees at every phase", 1.0e-12)
		near(resumed.device(7).state.energy_mwh, control.device(7).state.energy_mwh, "resumed electric inventory agrees at every phase", 1.0e-12)
		for key in control.energy: near(resumed.energy[key], control.energy[key], "resumed electric ledger agrees: " + key, 1.0e-12)
		for key in HEAT_KEYS: near(resumed.thermal_energy[key], control.thermal_energy[key], "resumed thermal ledger agrees: " + key, 1.0e-12)
		assert_ledgers(resumed, "resumed trajectory")
	check(saw_charge and saw_discharge, "saved trajectory includes both charging and discharging")
	var before: PackedByteArray = var_to_bytes(resumed.state())
	resumed.checkpoint(); remove_edge(resumed, 3, 4); resumed.refresh()
	check(resumed.advance(0.75), "advance after disconnect before undo")
	resumed.undo()
	check(var_to_bytes(resumed.state()) == before, "undo restores elapsed time, both ledgers, inventory and cable atomically")
	var invalid_path := path_for("invalid")
	for damage in ["profile","stock","topology","missing_ledger"]:
		var bad: Dictionary = resumed.state()
		match damage:
			"profile": bad.devices[2].model_profile = "thermal_stage1_v99"
			"stock": bad.devices[3].state = {"energy_mwh":1.0}
			"topology": bad.links[2].grade_id = "hw_secondary_70_40"
			"missing_ledger": bad.thermal_energy.erase("storage_loss")
		write_fixture(invalid_path, bad)
		var revision := resumed.scene_revision
		var undo_count := resumed.undo_states.size()
		check(not resumed.read_save(invalid_path), "corrupt " + damage + " rejects whole file")
		check(var_to_bytes(resumed.state()) == before and resumed.scene_revision == revision and resumed.undo_states.size() == undo_count, "invalid file cannot partially overwrite live state")

func test_parameters_and_legacy() -> void:
	var game := chain()
	game.device(3).state.energy_mwhth = 1.25
	game.parameter_id = 3; game.param_scope = "device"
	var editor := ParameterInput.new()
	game.parameter_form = editor
	editor.values = game.device(3).params.duplicate(true)
	editor.values.capacity_mwhth = 1.0
	var frozen: PackedByteArray = var_to_bytes(game.state())
	var revision := game.scene_revision
	game.apply_parameters()
	check(var_to_bytes(game.state()) == frozen and game.scene_revision == revision, "capacity cannot shrink below current heat inventory")
	check(game.param_errors.text.contains("库存"), "capacity rejection explains inventory protection")
	editor.values.capacity_mwhth = 5.0; editor.values.initial_soc = 0.9
	game.apply_parameters()
	near(game.device(3).params.capacity_mwhth, 5.0, "valid capacity increase applied")
	near(game.device(3).state.energy_mwhth, 1.25, "editing initial SOC does not refill live heat inventory")
	check(game.scene_revision > revision, "parameter mutation invalidates old optimization revision")
	game.undo()
	check(var_to_bytes(game.state()) == frozen, "parameter undo restores state and parameters together")
	for schema in [3,4]:
		var source := chain()
		var old: Dictionary = source.state()
		old.schema = schema; old.model_version = 11 if schema == 3 else 12
		for storage_kind in source.Catalog.NEW_STORAGE_KINDS: old.templates.erase(storage_kind)
		old.erase("stations");old.erase("next_station_id");old.erase("dimension_profile")
		old.erase("tower_energy"); old.templates.erase("solar_tower_receiver"); old.templates.erase("molten_salt_store"); old.templates.erase("salt_steam_generator"); old.erase("rankine_energy"); old.templates.erase("steam_generator"); old.templates.erase("steam_turbine"); old.templates.erase("steam_condenser"); old.templates.erase("feedwater_pump"); old.erase("high_temp_energy"); old.templates.erase("parabolic_trough"); old.templates.erase("high_temp_store"); old.templates.erase("oil_water_exchanger"); old.erase("solar_energy"); old.templates.erase("solar_thermal"); old.erase("fuel_supply"); old.erase("fuel_energy")
		old.devices = old.devices.filter(func(d): return d.kind in (["pv","station"] if schema == 3 else ["pv","station","load","battery"]))
		old.links = old.links.filter(func(edge): return (int(edge.from) == 0 and int(edge.to) == 1) or (schema == 4 and ((int(edge.from) == 1 and int(edge.to) == 6) or (int(edge.from) == 7 and int(edge.to) == 1))))
		old.next_id = 2 if schema == 3 else 8
		for kind in source.THERMAL_KINDS: old.templates.erase(kind)
		old.erase("thermal_energy"); old.energy.erase("boiler_electric"); old.energy.erase("boiler_conversion_loss")
		if schema == 3:
			old.templates.erase("load"); old.templates.erase("battery")
			old.energy = {"generated":0.0,"delivered":0.0,"curtailed":0.0,"loss":0.0}
		var legacy_path := path_for("legacy%d" % schema)
		write_fixture(legacy_path, old)
		var migrated := fixture()
		check(migrated.read_save(legacy_path), "read legacy electric schema %d: %s" % [schema,migrated.last_notice])
		check(migrated.devices.size() == old.devices.size() and migrated.links == JSON.parse_string(JSON.stringify(old.links)), "legacy restore never invents thermal devices or cables")
		for kind in migrated.KINDS: check(migrated.templates.has(kind), "legacy restore backfills future " + kind + " template")
		check(migrated.thermal_energy == migrated.THERMAL_ENERGY_ZERO, "legacy restore begins zero heat history")
		near(migrated.energy.boiler_electric + migrated.energy.boiler_conversion_loss, 0.0, "legacy boiler accounting starts at zero")
		check(migrated.add_equipment("thermal_store", Vector2(10,-20), false), "thermal construction works after legacy restore")
		near(migrated.device(old.next_id).state.energy_mwhth, 0.0, "legacy scene new store respects empty default")
		assert_ledgers(migrated, "migrated schema %d" % schema)

func test_example() -> void:
	var game := fixture()
	game.thermal_example()
	check(game.devices.size() == 8 and game.links.size() == 8, "thermal example builds complete eight-device chain")
	check(not game.station(game.selected_id).is_empty(), "thermal example selects whole station")
	check(game.paused and game.elapsed_s == 0.0, "thermal example begins paused at zero")
	near(game.device(4).state.energy_mwhth, 0.0, "thermal example has no free initial heat")
	check(game.result.get("valid", false), "thermal example has valid physical dispatch")
	check(game.result.thermal.demand_mwth > 0.0 and game.result.served_mw > 0.0, "example contains independently tracked electric and heat demand")
	assert_ledgers(game, "thermal example")
	game.undo()
	check(game.devices.is_empty() and game.links.is_empty(), "thermal example can be undone to empty scene")

func cleanup(controller: Fixture) -> void:
	for key in ["camera","lod_camera","terrain","labels","infrastructure","selection","overlay",
		"equipment","cables","confirmation","param_dialog","param_errors","param_target",
		"data_dialog","data_list","line_dialog","line_capacity","line_loss","line_choice"]:
		var node = controller.get(key)
		if is_instance_valid(node) and node.get_parent() == null: node.free()
	controller.free()
