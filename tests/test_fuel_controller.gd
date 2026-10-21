extends SceneTree
## Real controller boundary: independently configured external gas, AC-coupled
## useful heat, integrated ledgers, transactional edits and read-only real GLPK.
const Fuel = preload("res://scripts/fuel_supply.gd")
const Validator = preload("res://scripts/save_validator.gd")
const Optimization = preload("res://scripts/optimization_controller.gd")

class Fixture:
	extends "res://scripts/world_game.gd"
	var last_notice := ""
	func _ready(): pass
	func _process(_dt: float): pass
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
	func weather_at(_t: float) -> Dictionary:
		return {"wind_speed_mps":12.0, "irradiance_wm2":1000.0, "air_temp_c":25.0}

var checks := 0
var failures: Array[String] = []
var fixtures: Array = []
var paths: Array[String] = []
const PAIRS := [["input_mwh","input_mw"],["heat_output_mwhth","heat_output_mwth"],
	["conversion_loss_mwh","conversion_loss_mw"],["auxiliary_mwh","auxiliary_electric_mw"],
	["volume_nm3","volume_nm3_per_h"],["cost","cost_per_h"]]

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL FUEL_CONTROLLER ", label)

func near(actual: float, expected: float, label: String, tolerance: float = 1.0e-9) -> void:
	check(is_finite(actual) and absf(actual - expected) <= tolerance,
		"%s: actual=%.14f expected=%.14f" % [label,actual,expected])

func canonical(value: Variant) -> String: return JSON.stringify(JSON.parse_string(JSON.stringify(value)))

func same_values(a: Variant, b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return absf(float(a)-float(b)) <= 1.0e-12 * maxf(1.0,maxf(absf(float(a)),absf(float(b))))
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not same_values(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in a.size():
			if not same_values(a[index],b[index]): return false
		return true
	return a == b

func fixture() -> Fixture:
	var game := Fixture.new()
	game.cfg = {"max_build_slope_degrees":8.0}; game.booted = true
	game.dimension_profile = "metric_v1"
	for kind in game.KINDS: game.templates[kind] = game.model.defaults(kind)
	root.add_child(game); fixtures.append(game)
	return game

func path_for(label: String) -> String:
	var path := "user://fuel_controller_test/%d_%s.json" % [OS.get_process_id(),label]
	paths.append(path); return path

func write_value(path: String, value: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path,FileAccess.WRITE)
	check(file != null,"isolated fixture file opens")
	if file != null: file.store_string(JSON.stringify(value,"  ")); file.close()

func chain() -> Fixture:
	var game := fixture()
	for spec in [["pv",Vector2(-40,0)],["station",Vector2(-15,0)],["heat_demand",Vector2(45,0)]]:
		check(game.add_equipment(spec[0],spec[1],false),"place external " + spec[0])
	check(game.add_station(Vector2(15,0),false),"place station for gas boiler")
	check(game.add_internal_device(1000000,"fuel_boiler",Vector2(-1,-0.7)),"place independent gas hot-water boiler")
	check(game.add_internal_device(1000000,"heat_exchanger",Vector2(1,1)),"place separate secondary exchanger")
	game.device(0).params.merge({"dc_capacity_mw":0.1,"inverter_capacity_mw":0.1,
		"inverter_efficiency":1.0,"temp_coefficient_per_c":0.0,"dc_loss_fraction":0.0},true)
	game.device(1).params = {"capacity_mw":10.0,"loss_fraction":0.0}
	game.device(2).params.demand_mwth = 2.0
	for pair in [[0,1],[1,3],[3,4],[4,2]]:
		var line: Dictionary = game.connection_candidate(pair[0],pair[1])
		line.loss_fraction = 0.0; game.links.append(line)
	game.refresh()
	check(game.result.get("valid",false),"disabled-fuel chain dispatches validly: " + game.last_notice)
	check(game.validate_state(game.state()).is_empty(),"constructed gas chain is valid current save")
	return game

func assert_ledgers(game: Fixture, label: String) -> void:
	var e: Dictionary = game.energy; var h: Dictionary = game.thermal_energy; var f: Dictionary = game.fuel_energy
	near(e.generated + e.discharge, e.curtailed + e.loss + e.served + e.charge + e.boiler_electric + e.delivered + f.auxiliary_mwh,label + " AC includes real auxiliary sink")
	near(h.boiler_heat + f.heat_output_mwhth + h.discharge,h.served + h.charge + h.network_loss + h.exchanger_loss,label + " heat includes gas once")
	near(f.input_mwh,f.heat_output_mwhth + f.conversion_loss_mwh,label + " gas conversion conserves LHV")
	near(e.boiler_electric,h.boiler_heat + e.boiler_conversion_loss,label + " electric boiler accounting remains separate")
	near(h.demand,h.served + h.unserved,label + " thermal shortfall explicit")
	check(game.validate_state(game.state()).is_empty(),label + " full current save conserves all carriers")

func test_resource_form_and_ledgers() -> void:
	var game := chain()
	check(game.fuel_supply == Fuel.defaults() and game.fuel_energy == Fuel.initial_energy(),"building does not create fuel or enable free supply")
	near(game.result.fuel.input_mw,0.0,"default supply yields zero gas")
	var panel := VBoxContainer.new(); root.add_child(panel); game.make_fuel_resource_ui(panel)
	var before := var_to_bytes(game.state()); var history := game.undo_states.size(); var revision := game.scene_revision
	for iteration in 12:
		game.fuel_supply_enabled.button_pressed = true
		game.fuel_controls.max_input_mw.value = 2.0 + iteration
		game.fuel_controls.price_per_mwh.value = 400.0 + iteration
		game.refresh(); game.update_fuel_resource_summary()
		check(var_to_bytes(game.state()) == before and game.undo_states.size() == history and game.scene_revision == revision,"resource draft/display does not mutate model %d" % iteration)
		game.sync_fuel_resource_form()
		check(not game.fuel_supply_enabled.button_pressed and game.fuel_controls.max_input_mw.value == 0.0 and game.fuel_controls.price_per_mwh.value == 300.0,"cancel restores applied resource values %d" % iteration)
	check(game.apply_fuel_supply(Fuel.defaults()) and game.undo_states.size() == history,"no-op apply adds no undo checkpoint")
	var invalid := Fuel.defaults(); invalid.max_input_mw = -1.0
	check(not game.apply_fuel_supply(invalid),"invalid resource rejected visibly")
	check(var_to_bytes(game.state()) == before and game.scene_revision == revision and game.undo_states.size() == history,"invalid resource is fully atomic")
	game.fuel_supply_enabled.button_pressed = true
	# SpinBox.apply reads actual user text. Programmatic value changes alone may
	# await a frame before refreshing that text and are not a typing simulation.
	game.fuel_controls.max_input_mw.get_line_edit().text = "1.5"
	game.fuel_controls.lower_heating_value_kwh_per_nm3.get_line_edit().text = "10.0"
	game.fuel_controls.price_per_mwh.get_line_edit().text = "300.0"
	game.apply_fuel_resource_form()
	check(game.fuel_supply.enabled and game.fuel_supply.max_input_mw == 1.5 and game.paused,"explicit form apply enables shared supply and pauses")
	check(game.undo_states.size() == history + 1,"resource apply creates exactly one undo state")
	near(game.result.fuel.input_mw,1.5,"bounded fuel rate used")
	near(game.result.fuel.heat_output_mwth,1.35,"gas thermal efficiency applied")
	near(game.result.fuel.auxiliary_electric_mw,0.015,"auxiliary is one percent of fuel input")
	near(game.result.thermal.served_mwth,1.323,"separate exchanger efficiency retained")
	check(game.model.audit_dispatch(game.devices,game.links,game.result,game.fuel_supply).is_empty(),"independent runtime audit checks explicit resource")
	before = var_to_bytes(game.state())
	for iteration in 8: game.refresh(); game.solve_at(game.elapsed_s); game.update_fuel_resource_summary()
	check(var_to_bytes(game.state()) == before,"repeated display/preview cannot bill fuel or advance heat")
	var expected: Dictionary = game.result.fuel.duplicate(true)
	check(game.advance(0.25),"fractional gas transaction advances")
	for pair in PAIRS: near(game.fuel_energy[pair[0]],expected[pair[1]]*0.25/3600.0,"single gas ledger commit " + pair[0],1.0e-12)
	check(game.advance(2.0),"successive gas transactions advance")
	assert_ledgers(game,"integrated gas scene")
	var historical := game.fuel_energy.duplicate(true)
	var saved := var_to_bytes(game.state())
	var changed := game.fuel_supply.duplicate(true); changed.price_per_mwh = 400.0; changed.lower_heating_value_kwh_per_nm3 = 8.0
	check(game.apply_fuel_supply(changed),"new teaching tariff and LHV accepted")
	check(game.fuel_energy == historical,"changing tariff/LHV never rewrites historical meters")
	changed.price_per_mwh = 999.0
	near(game.fuel_supply.price_per_mwh,400.0,"applied resource owns deep copy")
	game.undo(); check(var_to_bytes(game.state()) == saved,"undo restores resource and all physical ledgers")
	for mode in ["no_ac","no_heat","disabled"]:
		var disconnected := fixture(); disconnected.restore(game.state())
		if mode == "disabled":
			var off := disconnected.fuel_supply.duplicate(true); off.enabled = false; disconnected.apply_fuel_supply(off)
		else:
			disconnected.links = disconnected.links.filter(func(edge): return not (int(edge.from) == 1 and int(edge.to) == 3) if mode == "no_ac" else not (int(edge.from) == 3 and int(edge.to) == 4))
		disconnected.refresh()
		check(disconnected.result.valid,mode + " remains valid")
		for key in ["input_mw","heat_output_mwth","auxiliary_electric_mw"]: near(disconnected.result.fuel[key],0.0,mode + " has zero " + key)
		check(disconnected.advance(0.5),mode + " advances without free heat")
		check(disconnected.fuel_energy == historical,mode + " does not invent gas consumption")
		assert_ledgers(disconnected,mode)
	panel.queue_free()

func legacy_state(game: Fixture, schema: int) -> Dictionary:
	var state: Dictionary = game.state()
	state.schema = schema; state.model_version = {3:11,4:12,5:14,6:15,7:16}[schema]
	for storage_kind in game.Catalog.NEW_STORAGE_KINDS: state.templates.erase(storage_kind)
	state.erase("fuel_supply"); state.erase("fuel_energy"); state.templates.erase("fuel_boiler"); state.templates.erase("solar_thermal"); state.erase("tower_energy"); state.templates.erase("solar_tower_receiver"); state.templates.erase("molten_salt_store"); state.templates.erase("salt_steam_generator"); state.erase("rankine_energy"); state.templates.erase("steam_generator"); state.templates.erase("steam_turbine"); state.templates.erase("steam_condenser"); state.templates.erase("feedwater_pump"); state.erase("high_temp_energy"); state.templates.erase("parabolic_trough"); state.templates.erase("high_temp_store"); state.templates.erase("oil_water_exchanger"); state.erase("solar_energy")
	if schema < 7: state.erase("dimension_profile")
	if schema < 6: state.erase("stations"); state.erase("next_station_id")
	if schema < 5:
		state.erase("thermal_energy"); state.energy.erase("boiler_electric"); state.energy.erase("boiler_conversion_loss")
		for kind in ["electric_boiler","thermal_store","heat_exchanger","heat_demand"]: state.templates.erase(kind)
	if schema == 3:
		state.templates.erase("load"); state.templates.erase("battery")
		state.energy = {"generated":0.0,"delivered":0.0,"curtailed":0.0,"loss":0.0}
	return state

func test_legacy_and_save() -> void:
	for schema in [3,4,5,6,7]:
		var source := fixture(); source.elapsed_s = 123.25
		var old := legacy_state(source,schema); var old_bytes := var_to_bytes(old)
		var path := path_for("legacy_%d" % schema); write_value(path,old)
		var input_hash := FileAccess.get_sha256(path)
		var migrated := fixture()
		check(migrated.read_save(path),"old schema %d reads through real boundary: %s" % [schema,migrated.last_notice])
		check(migrated.fuel_supply == Fuel.defaults() and migrated.fuel_energy == Fuel.initial_energy(),"schema %d migration starts disabled and unbilled" % schema)
		check(migrated.devices.is_empty() and migrated.links.is_empty() and migrated.elapsed_s == 123.25,"schema %d creates no fuel devices or links and retains clock" % schema)
		check(migrated.state().schema == 13 and migrated.state().model_version == 22 and migrated.templates.has("fuel_boiler"),"schema %d next write upgrades explicit version/template" % schema)
		check(var_to_bytes(old) == old_bytes and FileAccess.get_sha256(path) == input_hash,"schema %d read never rewrites original" % schema)
		check(migrated.validate_state(migrated.state()).is_empty(),"schema %d migrated current state validates" % schema)
	var game := chain(); var supply := Fuel.defaults(); supply.enabled = true; supply.max_input_mw = 1.5
	game.apply_fuel_supply(supply); check(game.advance(3.25),"meter fuel before save")
	var path := path_for("current"); check(game.write_save(path),"current fuel save writes")
	var frozen := canonical(game.state()); var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(disk.schema == 13 and disk.model_version == 22,"new write pairs schema13/model22")
	var restored := fixture(); restored.paused = false; restored.speed = 60.0; restored.accumulator = 0.5
	check(restored.read_save(path),"fresh controller reads gas save: " + restored.last_notice)
	check(canonical(restored.state()) == frozen,"new read preserves entire scene/resources/all ledgers")
	check(restored.paused and restored.speed == 1.0 and restored.accumulator == 0.0,"read resumes safely paused")
	for dt in [0.25,1.5,2.0]:
		check(game.advance(dt) and restored.advance(dt),"saved fuel trajectory advances")
		check(same_values(game.state(),restored.state()),"resumed gas trajectory matches at every phase within JSON float precision")
	assert_ledgers(restored,"resumed scene")
	frozen = canonical(restored.state())
	var invalid_path := path_for("invalid")
	for damage in ["missing_resource","missing_ledger","negative_input","bad_aux","heat_double_count"]:
		var bad: Dictionary = restored.state()
		match damage:
			"missing_resource": bad.erase("fuel_supply")
			"missing_ledger": bad.fuel_energy.erase("auxiliary_mwh")
			"negative_input": bad.fuel_supply.max_input_mw = -1.0
			"bad_aux": bad.devices[3].params.auxiliary_electric_ratio = 0.0
			"heat_double_count": bad.thermal_energy.boiler_heat += bad.fuel_energy.heat_output_mwhth
		write_value(invalid_path,bad); var revision := restored.scene_revision; var history := restored.undo_states.size()
		check(not restored.read_save(invalid_path),"corrupt gas save rejected: " + damage)
		check(canonical(restored.state()) == frozen and restored.scene_revision == revision and restored.undo_states.size() == history,"corrupt save is atomic: " + damage)

func test_example() -> void:
	var game := fixture(); var before := var_to_bytes(game.state())
	game.fuel_example()
	check(game.devices.size() == 9 and game.stations.size() == 1 and game.links.size() == 11,"joint example contains exactly nine devices/one site/eleven links")
	check(game.devices.filter(func(d): return d.has("parent_station_id")).size() == 4,"both boilers and separate storage/exchanger are station-internal")
	check(game.devices.filter(func(d): return d.kind == "fuel_boiler").size() == 1,"example adds exactly one independently modeled gas boiler")
	check(game.fuel_supply.enabled and game.fuel_supply.max_input_mw == 1.5,"example explicitly enables bounded teaching supply")
	check(game.result.valid and game.result.fuel.input_mw > 0.0 and game.result.boiler_electric_mw > 0.0,"joint example dispatches gas and electric heat")
	check(game.validate_state(game.state()).is_empty(),"joint example validates with separate ledgers")
	check(game.advance(1.25),"joint example advances")
	assert_ledgers(game,"joint example")
	game.undo(); check(var_to_bytes(game.state()) == before,"joint example is a single undoable edit")

func test_real_glpk_read_only() -> void:
	var source := chain(); var supply := Fuel.defaults(); supply.enabled = true; supply.max_input_mw = 1.5
	source.apply_fuel_supply(supply); check(source.advance(1.25),"GLPK source has real nonzero meters")
	var path := path_for("glpk"); check(source.write_save(path),"save actual gas state for optimizer")
	var game := fixture(); check(game.read_save(path),"optimizer starts from freshly loaded save")
	var frozen := canonical(game.state()); var input_hash := FileAccess.get_sha256(path)
	var service := Optimization.new(); root.add_child(service); service.setup(game)
	service.solver_executable = (OS.get_environment("BASIN_GLPK") if not OS.get_environment("BASIN_GLPK").is_empty() else "glpsol")
	var options := {"horizon_hours":2.0,"step_minutes":60.0,"load_multiplier":1.0,"strict_supply":false,"timeout_s":20}
	service.request_id = "fuel_controller"
	var snapshot: Dictionary = service.snapshot(options)
	check(not snapshot.has("error") and snapshot.steps.size() == 2,"real fuel snapshot has requested horizon")
	if not snapshot.has("error"):
		check(snapshot.fuel_supply == game.fuel_supply and snapshot.devices.size() == game.devices.size(),"frozen optimizer preserves resource and fleet")
		var baseline: Dictionary = service.make_baseline(snapshot)
		check(not baseline.has("error") and baseline.steps.size() == 2,"same-snapshot realtime baseline succeeds")
		if baseline.steps.size() == 2: check(baseline.steps[0].fuel.input_mw > 0.0,"baseline includes positive separately metered fuel")
	check(canonical(game.state()) == frozen,"snapshot and baseline leave world unchanged")
	service.start(options); check(service.pid > 0,"real asynchronous GLPK process launched")
	var deadline := Time.get_ticks_msec() + 30000; var heartbeat := 0
	while service.pid > 0 and Time.get_ticks_msec() < deadline:
		heartbeat += 1; await create_timer(0.02).timeout
	check(heartbeat > 0 and service.pid < 0,"UI event loop stays live until solver terminates")
	check(service.last_result.get("status","") == "optimal","fresh-load real GLPK reaches optimal result")
	check(service.last_result.get("validation",{}).get("valid",false),"real GLPK independent raw decision/physical audit passes")
	var positive := false
	for step in service.last_result.get("steps",[]):
		var fuel: Dictionary = step.get("fuel",{})
		positive = positive or float(fuel.get("input_mw",0.0)) > 0.0
		near(fuel.get("input_mw",0.0),fuel.get("heat_output_mwth",0.0)+fuel.get("conversion_loss_mw",0.0),"optimized fuel conversion",1.0e-6)
		near(fuel.get("auxiliary_electric_mw",0.0),fuel.get("input_mw",0.0)*0.01,"optimized auxiliary coupling",1.0e-6)
	check(positive,"real GLPK includes positive gas consumption")
	check(canonical(game.state()) == frozen and FileAccess.get_sha256(path) == input_hash,"real GLPK never mutates actual world or input save")
	write_value("user://fuel_controller_glpk_result.json",service.last_result)
	var changed := game.fuel_supply.duplicate(true); changed.max_input_mw = 0.5
	check(game.apply_fuel_supply(changed),"resource edit changes optimizer revision")
	await create_timer(0.05).timeout
	check(service.last_result.is_empty(),"resource edit invalidates previous optimization result")
	service.queue_free()

func cleanup(game: Fixture) -> void:
	for property in game.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0: continue
		var value: Variant = game.get(property.name)
		if is_instance_valid(value) and value is Node and value.get_parent() == null: value.free()
	game.queue_free()

func _initialize() -> void: call_deferred("run")
func run() -> void:
	test_resource_form_and_ledgers()
	test_legacy_and_save()
	test_example()
	await test_real_glpk_read_only()
	for game in fixtures: cleanup(game)
	for path in paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	await process_frame
	print("FUEL_CONTROLLER checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
