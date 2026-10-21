extends SceneTree
## Controller integration for editable station containers. Terrain/rendering are
## isolated; all physical reports, inventory transitions and GLPK solves are real.
const Optimization = preload("res://scripts/optimization_controller.gd")

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
	func ask(message: String, action: Callable): last_notice = message; confirm_action = action
	func weather_at(_t: float) -> Dictionary:
		return {"wind_speed_mps":12.0, "irradiance_wm2":irradiance, "air_temp_c":25.0}

class InteriorProbe:
	extends Window
	var opened_id := -1
	func open_station(id: int): opened_id = id

const PV := 0
const AC_STATION := 1
const DEMAND := 2
const BOILER := 3
const STORE := 4
const EXCHANGER := 5
const SITE := 1000000
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
	for kind in game.KINDS: game.templates[kind] = game.model.defaults(kind)
	fixtures.append(game)
	return game

func chain() -> Fixture:
	var game := fixture()
	for spec in [["pv",Vector2(-60,0)], ["station",Vector2(-30,0)], ["heat_demand",Vector2(65,0)]]:
		check(game.add_equipment(spec[0], spec[1], false), "fixture places external " + spec[0])
	check(game.add_station(Vector2(25,0), false), "fixture places station container")
	for spec in [["electric_boiler",Vector2(-12,0)], ["thermal_store",Vector2.ZERO], ["heat_exchanger",Vector2(12,0)]]:
		check(game.add_internal_device(SITE, spec[0], spec[1]), "fixture places internal " + spec[0])
	game.device(PV).params.merge({"dc_capacity_mw":2.0, "inverter_capacity_mw":2.0,
		"inverter_efficiency":1.0, "temp_coefficient_per_c":0.0, "dc_loss_fraction":0.0}, true)
	game.device(AC_STATION).params = {"capacity_mw":10.0,"loss_fraction":0.0}
	game.device(DEMAND).params.demand_mwth = 2.0
	game.device(STORE).params.self_discharge_per_h = 0.0
	for pair in [[PV,AC_STATION],[AC_STATION,BOILER],[BOILER,STORE],[BOILER,EXCHANGER],[STORE,EXCHANGER],[EXCHANGER,DEMAND]]:
		var edge: Dictionary = game.connection_candidate(pair[0],pair[1])
		edge.loss_fraction = 0.0
		game.links.append(edge)
	game.refresh()
	check(game.result.get("valid",false), "fixture has valid physical dispatch: " + game.last_notice)
	check(game.validate_state(game.state()).is_empty(), "fixture hierarchy validates: " + game.validate_state(game.state()))
	return game

func remove_edge(game: Fixture, a: int, b: int) -> void:
	game.links = game.links.filter(func(edge): return not (int(edge.from) == a and int(edge.to) == b))

func frozen(game: Fixture) -> PackedByteArray:
	return var_to_bytes(game.state())

func click_connect(game: Fixture, first: int, second: int) -> void:
	game.set_mode("link"); game.link_to(first); game.link_to(second)

func path_for(label: String) -> String:
	var path := "user://station_controller_test/%d_%s.json" % [OS.get_process_id(),label]
	save_paths.append(path)
	return path

func write_fixture(path: String, value: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "open isolated test file")
	if file != null: file.store_string(JSON.stringify(value)); file.close()

func assert_ledgers(game: Fixture, label: String) -> void:
	var e: Dictionary = game.energy
	var h: Dictionary = game.thermal_energy
	near(e.generated + e.discharge, e.delivered + e.curtailed + e.loss + e.served + e.charge + e.boiler_electric, label + " AC conservation")
	near(h.boiler_heat + h.discharge, h.served + h.charge + h.network_loss + h.exchanger_loss, label + " heat conservation")
	near(e.boiler_electric, h.boiler_heat + e.boiler_conversion_loss, label + " cross-carrier conservation")
	near(h.demand, h.served + h.unserved, label + " demand conservation")
	check(game.validate_state(game.state()).is_empty(), label + " schema 6 validates: " + game.validate_state(game.state()))

func _initialize() -> void: call_deferred("run")

func run() -> void:
	test_construction_and_open()
	test_interior_placement()
	test_high_id_cursor_roundtrips()
	test_boundary_connections()
	test_boundary_picker()
	test_runtime_single_expansion()
	test_movement_and_base_collision()
	test_child_and_group_deletion()
	test_file_roundtrip_and_legacy()
	test_invalid_hierarchy_atomicity()
	test_example()
	test_real_glpk_single_expansion()
	for game in fixtures: cleanup(game)
	for path in save_paths:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("STATION_CONTROLLER checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func test_construction_and_open() -> void:
	var game := fixture()
	check(game.add_equipment("thermal_station", Vector2.ZERO), "base catalog constructs a container")
	check(game.stations.size() == 1 and game.devices.is_empty(), "container is separate from physical energy devices")
	check(game.station(SITE).id == SITE and game.next_station_id == SITE + 1 and game.next_id == 0, "station and device IDs have separate counters")
	check(game.device(SITE).is_empty() and game.station(-1).is_empty(), "station lookup never invents a physical device")
	check(not game.station(SITE).has("state") and not game.station(SITE).has("params"), "container has neither energy inventory nor duplicate equipment capacity")
	check("thermal_station" in game.BUILDABLE_KINDS, "base build catalog exposes station")
	for kind in game.INTERNAL_KINDS: check(not kind in game.BUILDABLE_KINDS, "internal " + kind + " stays off base build catalog")
	game.templates.thermal_store.initial_soc = 0.375
	check(game.add_internal_device(SITE,"thermal_store",Vector2.ZERO), "construct station store")
	near(game.device(0).state.energy_mwhth,1.5,"construction applies configured initial SOC exactly once")
	check(game.device(0).model_profile == "thermal_stage1_v1" and game.device(0).parent_station_id == SITE, "internal device retains thermal profile and parent")
	check(game.device(0).interior_x == 0.0 and game.device(0).interior_z == 0.0, "interior coordinates are explicit")
	game.device(0).params.initial_soc = 0.9
	near(game.templates.thermal_store.initial_soc,0.375,"internal device parameters do not alias template")
	var probe := InteriorProbe.new(); game.station_interior = probe
	game.mode = "move"; game.pending_link = 0
	var before := frozen(game)
	game.open_station(SITE)
	check(probe.opened_id == SITE and game.mode == "select" and game.pending_link == -2, "enter station resets stale base interaction and opens correct parent")
	check(frozen(game) == before,"opening a station never changes inventory or topology")
	game.open_station(SITE + 77)
	check(probe.opened_id == SITE,"missing station cannot open a different interior")
	var detached: Dictionary = game.state()
	detached.stations[0].name = "changed"; detached.devices[0].state.energy_mwhth = 0.0
	check(game.station(SITE).name != "changed", "snapshot station metadata deeply detached")
	near(game.device(0).state.energy_mwhth,1.5,"snapshot child inventory deeply detached")
	assert_ledgers(game,"constructed container")

func test_interior_placement() -> void:
	var game := fixture()
	check(game.add_station(Vector2(-25,0)) and game.add_station(Vector2(25,0)), "place two independent parent sites")
	check(game.add_internal_device(SITE,"thermal_store",Vector2.ZERO), "place first internal footprint")
	check(game.add_internal_device(SITE + 1,"thermal_store",Vector2.ZERO), "same interior coordinate allowed in different station")
	check(not game.same_internal_station(0,1) and game.same_internal_station(0,0), "same-parent lookup uses real child membership")
	check(not game.same_internal_station(0,9999) and not game.same_internal_station(SITE,SITE), "containers and missing devices are not internal peers")
	for spec in [[SITE,"electric_boiler",Vector2(8,0)], [SITE,"thermal_store",Vector2(19.01,0)],
		[SITE,"electric_boiler",Vector2(0,20.01)], [SITE,"electric_boiler",Vector2(NAN,0)],
		[SITE,"electric_boiler",Vector2(0,INF)], [SITE,"pv",Vector2(-12,0)], [99999,"electric_boiler",Vector2.ZERO]]:
		var before := frozen(game); var revision := game.scene_revision; var undo_count := game.undo_states.size()
		check(not game.can_place_internal(spec[0],spec[1],spec[2]).is_empty(), "interior guard gives rejection reason")
		check(not game.add_internal_device(spec[0],spec[1],spec[2]), "invalid interior placement rejected")
		check(frozen(game) == before and game.scene_revision == revision and game.undo_states.size() == undo_count, "invalid placement never checkpoints or mutates")
	check(game.can_place_internal(SITE,"electric_boiler",Vector2(9,0)).is_empty(), "touching circular footprints are allowed")
	check(game.can_place_internal(SITE,"thermal_store",Vector2(19,0)).is_empty(), "whole footprint can touch station boundary")
	check(game.move_internal_device(0,Vector2(-12,0)), "move internal equipment through controller")
	check(game.device(0).interior_x == -12.0 and game.device(0).interior_z == 0.0, "internal move updates layout coordinates")
	check(game.add_internal_device(SITE,"electric_boiler",Vector2(0,0)), "freed interior space reusable")
	var before := frozen(game)
	check(not game.move_internal_device(0,Vector2(-8,0)) and frozen(game) == before, "internal move overlap rejected atomically")
	check(not game.move_internal_device(0,Vector2(0,24)) and frozen(game) == before, "internal move bounds rejected atomically")
	check(not game.move_internal_device(SITE,Vector2.ZERO), "container cannot be moved through child API")

func test_high_id_cursor_roundtrips() -> void:
	# Valid saved cursors may sit immediately below the separate station domain.
	# Exercise both add paths, then actually write/read the resulting scene.
	for build_mode in ["base", "internal"]:
		var source := fixture()
		check(source.add_station(Vector2(25,0),false),"prepare station-domain cursor fixture")
		source.next_id = SITE - 1
		var saved: Dictionary = source.state()
		check(source.validate_state(saved).is_empty(),"high next-device cursor fixture is a valid schema 6 save")
		var old_path := path_for("high_device_cursor_" + build_mode); write_fixture(old_path,saved)
		var game := fixture()
		check(game.read_save(old_path),"read valid high device cursor before " + build_mode + " construction")
		var built: bool = game.add_equipment("pv",Vector2(-30,0)) if build_mode == "base" else game.add_internal_device(SITE,"thermal_store",Vector2.ZERO)
		check(built and not game.device(SITE - 1).is_empty(),"construction uses last device ID below existing station")
		check(game.next_id == SITE + 1 and game.station(game.next_id).is_empty(),"post-build next device cursor skips occupied station ID")
		check(game.next_station_id == SITE + 2 and game.next_station_id != game.next_id,"both ID cursors remain distinct after device increment")
		check(game.validate_state(game.state()).is_empty(),"device increment cannot make previously valid hierarchy unsavable")
		var path := path_for("high_device_cursor_roundtrip_" + build_mode)
		check(game.write_save(path),"write high-ID " + build_mode + " scene after construction")
		var resumed := fixture()
		check(resumed.read_save(path),"read back high-ID " + build_mode + " scene: " + resumed.last_notice)
		check(resumed.next_id == game.next_id and resumed.next_station_id == game.next_station_id,"restart preserves normalized separate ID cursors")
		check(resumed.station(SITE).id == SITE and resumed.device(SITE - 1).kind == ("pv" if build_mode == "base" else "thermal_store"),"restart preserves station and newly built high-ID equipment")
		check(resumed.validate_state(resumed.state()).is_empty(),"resumed normalized high-ID hierarchy validates")
	# Older scenes can have physical IDs inside the later station ID domain.
	var source := fixture()
	check(source.add_equipment("pv",Vector2(-30,0),false),"prepare old high-ID physical equipment")
	source.devices[0].id = SITE + 1; source.next_id = SITE + 2
	check(source.validate_state(source.state()).is_empty(),"physical ID above station cursor is a valid old scene")
	var old_path := path_for("high_legacy_physical_id"); write_fixture(old_path,source.state())
	var game := fixture(); check(game.read_save(old_path),"read legacy high physical ID scene")
	check(game.add_station(Vector2(25,0)),"build station just below existing high physical ID")
	check(game.station(SITE).id == SITE and game.device(SITE + 1).kind == "pv","station construction preserves existing high-ID device")
	check(game.next_id == SITE + 2 and game.next_station_id == SITE + 3,"station increment skips occupied physical ID and live device cursor")
	check(game.validate_state(game.state()).is_empty(),"station increment keeps high-ID hierarchy valid")
	var path := path_for("high_station_cursor_roundtrip")
	check(game.write_save(path),"write normalized station cursor after construction")
	var resumed := fixture(); check(resumed.read_save(path),"read back high station cursor: " + resumed.last_notice)
	check(resumed.next_station_id == SITE + 3 and resumed.next_id == SITE + 2,"restart retains both high-ID cursors")
	check(resumed.validate_state(resumed.state()).is_empty(),"reloaded station and legacy high-ID physical equipment validate")
	# Exhausted cursors must reject before checkpoints, allocating no invalid IDs.
	game.next_id = game.SaveValidator.MAX_ID + 1
	var before := frozen(game); var revision := game.scene_revision
	check(not game.add_equipment("battery",Vector2(0,30)) and frozen(game) == before and game.scene_revision == revision,"exhausted base device ID rejects atomically")
	check(not game.add_internal_device(SITE,"thermal_store",Vector2.ZERO) and frozen(game) == before and game.scene_revision == revision,"exhausted internal device ID rejects atomically")
	game.next_station_id = game.SaveValidator.MAX_ID + 1; before = frozen(game)
	check(not game.add_station(Vector2(0,30)) and frozen(game) == before and game.scene_revision == revision,"exhausted station ID rejects atomically")
	check(game.validate_state(game.state()).is_empty(),"both exhausted cursor sentinels remain a valid save")
	var exhausted_path := path_for("exhausted_cursor_roundtrip")
	check(game.write_save(exhausted_path),"write both exhausted cursor sentinels")
	var exhausted := fixture(); check(exhausted.read_save(exhausted_path),"read both exhausted cursor sentinels")
	check(exhausted.next_id == game.SaveValidator.MAX_ID + 1 and exhausted.next_station_id == game.SaveValidator.MAX_ID + 1,"restore must not increment exhausted cursor beyond allowed sentinel")
	check(exhausted.validate_state(exhausted.state()).is_empty(),"exhausted-cursor restart stays savable")

func test_boundary_connections() -> void:
	var game := chain()
	game.links = []; game.refresh()
	for pair in [[BOILER,STORE],[EXCHANGER,BOILER],[EXCHANGER,STORE]]:
		check(game.connect_internal_devices(pair[0],pair[1]), "legal same-station heat connection canonicalizes reverse clicks")
	var before := frozen(game)
	check(not game.connect_internal_devices(STORE,BOILER) and frozen(game) == before, "duplicate internal edge rejected atomically")
	check(not game.connect_internal_devices(AC_STATION,BOILER), "internal API excludes external boundary connection")
	check(not game.connect_internal_devices(EXCHANGER,DEMAND), "internal API excludes external heat demand")
	for spec in [[BOILER,AC_STATION,AC_STATION,BOILER,"electricity_ac","out","ac_in"],
		[DEMAND,EXCHANGER,EXCHANGER,DEMAND,"heat_water","warm_out","heat_in"]]:
		var edge: Dictionary = game.connection_candidate(spec[0],spec[1])
		check(edge.get("from") == spec[2] and edge.get("to") == spec[3], "boundary canonicalizes physical child endpoints")
		check(edge.get("carrier") == spec[4] and edge.get("from_port") == spec[5] and edge.get("to_port") == spec[6], "boundary uses actual child carrier and ports")
		click_connect(game,spec[0],spec[1])
		check(game.links.any(func(line): return int(line.from) == spec[2] and int(line.to) == spec[3]), "normal boundary link commits actual physical endpoints")
	for edge in game.links: check(int(edge.from) != SITE and int(edge.to) != SITE, "container never becomes an energy topology endpoint")
	check(game.connection_candidate(AC_STATION,SITE).is_empty(), "container ID cannot silently become AC device")
	check(game.connection_candidate(SITE,DEMAND).is_empty(), "container ID cannot silently become heat source")
	check(game.add_station(Vector2(25,35)), "place second station for isolation regression")
	var other_store := game.next_id
	check(game.add_internal_device(SITE + 1,"thermal_store",Vector2.ZERO), "place other-station heat sink")
	before = frozen(game)
	check(not game.connect_internal_devices(BOILER,other_store) and frozen(game) == before, "interior API blocks cross-parent heat")
	check(game.connection_candidate(BOILER,other_store).is_empty(), "base candidate blocks cross-parent primary heat")
	click_connect(game,BOILER,other_store)
	check(frozen(game) == before, "normal link tool cannot bypass cross-parent restriction")
	assert_ledgers(game,"boundary topology")

func test_boundary_picker() -> void:
	var game := chain()
	game.links = []; game.refresh()
	game.station_port_dialog = ConfirmationDialog.new()
	game.station_port_picker = OptionButton.new()
	game.station_port_dialog.add_child(game.station_port_picker)
	root.add_child(game.station_port_dialog)
	var before := frozen(game)
	game.set_mode("link"); game.choose_station_port(SITE)
	check(game.station_port_picker.item_count == 2,"uncommitted station boundary exposes boiler AC and exchanger heat ports only")
	var offered: Array = []
	for i in game.station_port_picker.item_count: offered.append(int(game.station_port_picker.get_item_metadata(i)))
	check(BOILER in offered and EXCHANGER in offered and not STORE in offered,"boundary choices map to actual children and omit internal-only store")
	check(frozen(game) == before,"opening boundary picker does not create phantom physical devices or lines")
	game.station_port_dialog.hide()
	game.pending_link = AC_STATION; game.choose_station_port(SITE)
	check(game.station_port_picker.item_count == 1 and int(game.station_port_picker.get_item_metadata(0)) == BOILER,"external AC endpoint filters picker to boiler input")
	game.link_to(int(game.station_port_picker.get_item_metadata(0)))
	check(game.links.size() == 1 and int(game.links[0].from) == AC_STATION and int(game.links[0].to) == BOILER,"selected boundary port links external AC directly to physical boiler")
	game.station_port_dialog.hide()
	game.pending_link = DEMAND; game.choose_station_port(SITE)
	check(game.station_port_picker.item_count == 1 and int(game.station_port_picker.get_item_metadata(0)) == EXCHANGER,"external demand filters picker to exchanger output")
	game.link_to(int(game.station_port_picker.get_item_metadata(0)))
	check(game.links.size() == 2 and int(game.links[1].from) == EXCHANGER and int(game.links[1].to) == DEMAND,"selected heat boundary links actual exchanger to external demand")
	game.station_port_dialog.hide()
	game.pending_link = PV; game.choose_station_port(SITE)
	check(game.station_port_picker.item_count == 0 and not game.station_port_dialog.visible,"incompatible source offers no boundary and keeps dialog hidden")
	game.station_port_dialog.free()

func test_runtime_single_expansion() -> void:
	var game := chain()
	near(game.result.generated_mw,2.0,"one 2 MW source remains exactly one source")
	near(game.result.boiler_electric_mw,2.0,"one boiler consumes only its 2 MW input")
	near(game.result.thermal.boiler_heat_mwth,1.96,"boiler heat calculated exactly once")
	near(game.result.thermal.served_mwth,1.9208,"exchanger conversion applied exactly once")
	near(game.result.thermal.unserved_mwth,0.0792,"station wrapper never fills heat deficit")
	check(game.result.devices.size() == game.devices.size() and not game.result.devices.has(str(SITE)), "physical result contains no synthetic container device")
	var flat: Array = game.devices.duplicate(true)
	for d in flat:
		d.erase("parent_station_id"); d.erase("interior_x"); d.erase("interior_z")
	var dat: Dictionary = game.dispatch_inputs(0.0)
	var reference: Dictionary = game.model.dispatch(flat,game.links,dat.weather,dat.direct,1.0)
	check(var_to_bytes(reference) == var_to_bytes(game.model.dispatch(game.devices,game.links,dat.weather,dat.direct,1.0)), "hierarchy leaves complete physical dispatch identical to flat reference")
	var before := frozen(game)
	for i in 4: game.refresh(); game.solve_at(0.0); game.advance(0.0)
	check(frozen(game) == before, "container previews never commit child SOC or ledgers")
	check(game.advance(2.5), "grouped runtime advances real fractional steps")
	near(game.energy.boiler_electric,2.0 * 2.5 / 3600.0,"boiler electrical ledger integrates once")
	near(game.thermal_energy.served,1.9208 * 2.5 / 3600.0,"station served heat integrates once")
	assert_ledgers(game,"grouped runtime")

func test_movement_and_base_collision() -> void:
	var game := chain()
	game.device(STORE).state.energy_mwhth = 1.25; game.refresh()
	var children: PackedByteArray = var_to_bytes(game.devices)
	var edges: PackedByteArray = var_to_bytes(game.links)
	var report: PackedByteArray = var_to_bytes(game.result)
	var before := frozen(game)
	check(game.move_station(SITE,Vector2(25,30)), "move whole station facade")
	check(game.station(SITE).x == 25.0 and game.station(SITE).z == 30.0, "parent world location changes")
	check(var_to_bytes(game.devices) == children, "parent movement preserves every child including inventory and interior coordinates")
	check(var_to_bytes(game.links) == edges and var_to_bytes(game.result) == report, "parent movement preserves topology and physical result")
	check(game.can_place("pv",Vector2(25,0)).is_empty(), "base collision ignores stale world coordinates of parented children")
	check(not game.can_place("pv",Vector2(25,30)).is_empty(), "base collision includes station facade footprint")
	check(not game.can_place("thermal_station",Vector2(-30,0)).is_empty(), "station facade collides with external equipment")
	check(game.can_place("thermal_station",Vector2(25,30),SITE).is_empty(), "station move guard excludes its own footprint")
	var moved := frozen(game); var revision := game.scene_revision
	for position in [Vector2(-30,0),Vector2(90,0),Vector2(0,60),Vector2(NAN,0),Vector2(0,INF)]:
		check(not game.move_station(SITE,position) and frozen(game) == moved and game.scene_revision == revision, "invalid whole-station move is atomic")
	game.undo()
	check(frozen(game) == before,"undo restores exact parent move without inventory change")

func test_child_and_group_deletion() -> void:
	var game := chain()
	game.device(STORE).state.energy_mwhth = 1.25
	check(game.advance(0.5), "accumulate actual history before demolition")
	var before := frozen(game)
	check(game.remove_internal_device(STORE), "delete individual internal device")
	check(game.device(STORE).is_empty() and not game.station(SITE).is_empty(), "child deletion keeps its station and peers")
	check(game.links.size() == 4 and game.links.all(func(edge): return int(edge.from) != STORE and int(edge.to) != STORE), "child deletion removes only its incident heat pipes")
	game.undo(); check(frozen(game) == before,"child deletion undo restores stock, pipes and ledgers exactly")
	game.selected_id = SITE; game.remove_selected()
	check(frozen(game) == before and game.confirm_action.is_valid(), "whole-station demolition waits for confirmation")
	game.confirm_action.call()
	check(game.stations.is_empty() and game.devices.size() == 3,"whole-station demolition removes three internals and preserves external devices")
	check(game.links.size() == 1 and int(game.links[0].from) == PV and int(game.links[0].to) == AC_STATION,"whole-station deletion removes internal and both external boundary edges")
	near(game.result.thermal.unserved_mwth,2.0,"external heat demand survives deleted supply station")
	check(game.energy == bytes_to_var(before).energy and game.thermal_energy == bytes_to_var(before).thermal_energy,"demolition preserves accumulated history")
	game.undo(); check(frozen(game) == before,"station deletion undo restores complete exact group and edges")
	check(not game.remove_station(SITE + 99) and frozen(game) == before,"missing station deletion leaves state untouched")
	check(not game.remove_internal_device(PV) and frozen(game) == before,"internal deletion API cannot remove outside source")

func test_file_roundtrip_and_legacy() -> void:
	var control := chain()
	control.device(STORE).state.energy_mwhth = 0.25
	control.device(STORE).params.initial_soc = 0.9
	control.device(DEMAND).params.demand_mwth = 0.5
	check(control.advance(3.25),"nonzero station inventory evolves before save")
	var stored: float = control.device(STORE).state.energy_mwhth
	var path := path_for("schema6_resume")
	check(control.write_save(path),"write actual station file through controller")
	var disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(disk.schema == 12 and disk.model_version == 21 and disk.stations.size() == 1,"persist schema 12/model 21 separate stations")
	check(disk.next_station_id >= 1000000 and disk.devices.size() == 6,"save contains real devices once and separate next station ID")
	var resumed := fixture(); resumed.paused = false; resumed.speed = 60.0; resumed.accumulator = 0.4
	check(resumed.read_save(path),"restore saved station via FileAccess: " + resumed.last_notice)
	near(resumed.device(STORE).state.energy_mwhth,stored,"actual nonzero inventory survives restart instead of initial_soc",1.0e-12)
	check(resumed.stations == disk.stations and resumed.links == disk.links,"save/load restores station metadata and all physical edges")
	check(resumed.paused and resumed.speed == 1.0 and resumed.accumulator == 0.0,"load safely pauses and resets rate")
	for phase in [[0.75,1000.0,0.25],[2.5,0.0,1.0],[0.5,1000.0,0.0]]:
		for game in [control,resumed]:
			game.irradiance = phase[1]; game.device(DEMAND).params.demand_mwth = phase[2]
			check(game.advance(phase[0]),"resumed grouped trajectory advances")
		near(resumed.device(STORE).state.energy_mwhth,control.device(STORE).state.energy_mwhth,"restart follows identical real inventory trajectory",1.0e-12)
		for key in control.energy: near(resumed.energy[key],control.energy[key],"restart electric ledger " + key,1.0e-12)
		for key in control.thermal_energy: near(resumed.thermal_energy[key],control.thermal_energy[key],"restart heat ledger " + key,1.0e-12)
	assert_ledgers(resumed,"resumed station")
	# A true old save has no hierarchy fields and keeps legacy flat equipment.
	var old := fixture()
	for spec in [["pv",Vector2(-65,0)],["station",Vector2(-40,0)],["electric_boiler",Vector2(-15,0)],
		["thermal_store",Vector2(10,-20)],["heat_exchanger",Vector2(10,10)],["heat_demand",Vector2(35,10)]]:
		check(old.add_equipment(spec[0],spec[1],false),"prepare legacy flat thermal " + spec[0])
	for pair in [[0,1],[1,2],[2,3],[2,4],[3,4],[4,5]]: old.links.append(old.connection_candidate(pair[0],pair[1]))
	old.device(3).state.energy_mwhth = 0.625
	# Pre-hierarchy world-generated electrical cables carried a blank grade tag.
	for edge in old.links:
		if edge.get("carrier", "electricity_ac") == "electricity_ac": edge.grade_id = ""
	var legacy: Dictionary = old.state(); legacy.schema = 5; legacy.model_version = 14
	legacy.erase("stations"); legacy.erase("next_station_id"); legacy.erase("dimension_profile")
	legacy.erase("tower_energy"); legacy.templates.erase("solar_tower_receiver"); legacy.templates.erase("molten_salt_store"); legacy.templates.erase("salt_steam_generator"); legacy.erase("rankine_energy"); legacy.templates.erase("steam_generator"); legacy.templates.erase("steam_turbine"); legacy.templates.erase("steam_condenser"); legacy.templates.erase("feedwater_pump"); legacy.erase("high_temp_energy"); legacy.templates.erase("parabolic_trough"); legacy.templates.erase("high_temp_store"); legacy.templates.erase("oil_water_exchanger"); legacy.erase("solar_energy"); legacy.templates.erase("solar_thermal"); legacy.erase("fuel_supply"); legacy.erase("fuel_energy"); legacy.templates.erase("fuel_boiler")
	var legacy_path := path_for("schema5_flat"); write_fixture(legacy_path,legacy)
	var migrated := fixture()
	check(migrated.read_save(legacy_path),"parentless schema 5 thermal save still loads: " + migrated.last_notice)
	check(migrated.stations.is_empty() and migrated.devices.size() == 6,"legacy load does not silently group or duplicate devices")
	check(migrated.devices.all(func(d): return not d.has("parent_station_id")),"legacy thermal devices remain valid base devices")
	near(migrated.device(3).state.energy_mwhth,0.625,"legacy actual heat inventory preserved")
	check(migrated.next_station_id >= 1000000 and migrated.state().schema == 12,"legacy load upgrades future saves and station counter")
	var legacy_frozen := frozen(migrated)
	var optimizer := Optimization.new(); optimizer.host = migrated
	var options := {"horizon_hours":1.0,"step_minutes":60.0,"load_multiplier":1.0,"strict_supply":false,"timeout_s":20}
	var legacy_snapshot: Dictionary = optimizer.snapshot(options)
	check(not legacy_snapshot.has("error"),"legacy empty electrical grade remains accepted by optimization snapshot")
	if not legacy_snapshot.has("error"):
		for edge in legacy_snapshot.links:
			if edge.get("carrier", "electricity_ac") == "electricity_ac": check(not edge.has("grade_id"),"snapshot removes legacy blank electric heat-grade metadata before GLPK")
	check(frozen(migrated) == legacy_frozen,"legacy grade normalization does not mutate loaded scene or saved cable data")
	migrated.links[0].grade_id = "hw_primary_90_60"
	check(optimizer.snapshot(options).has("error"),"nonempty heat grade on electrical cable remains invalid")
	migrated.links[0].grade_id = ""
	optimizer.free()
	check(migrated.add_station(Vector2(55,-25)),"legacy flat thermal scene accepts new grouped station alongside old devices")
	check(migrated.add_internal_device(SITE,"electric_boiler",Vector2.ZERO),"legacy and new grouped devices coexist")
	assert_ledgers(migrated,"legacy migration")

func test_invalid_hierarchy_atomicity() -> void:
	var game := chain()
	game.device(STORE).state.energy_mwhth = 0.75
	var before := frozen(game)
	var path := path_for("invalid_hierarchy")
	for damage in ["missing_parent","duplicate_station","station_device_id","outside","overlap","missing_coordinate","wrong_internal_kind","station_as_edge","invalid_counter"]:
		var bad: Dictionary = game.state()
		match damage:
			"missing_parent": bad.devices[BOILER].parent_station_id = SITE + 30
			"duplicate_station": bad.stations.append(bad.stations[0].duplicate(true))
			"station_device_id": bad.stations[0].id = BOILER
			"outside": bad.devices[BOILER].interior_x = 21.0
			"overlap": bad.devices[BOILER].interior_x = 0.0
			"missing_coordinate": bad.devices[STORE].erase("interior_z")
			"wrong_internal_kind": bad.devices[DEMAND].merge({"parent_station_id":SITE,"interior_x":0.0,"interior_z":12.0})
			"station_as_edge": bad.links[1].to = SITE
			"invalid_counter": bad.next_station_id = SITE
		write_fixture(path,bad)
		var revision := game.scene_revision; var undo_count := game.undo_states.size()
		check(not game.read_save(path),"malformed hierarchy rejected: " + damage)
		check(frozen(game) == before and game.scene_revision == revision and game.undo_states.size() == undo_count,"malformed hierarchy load cannot partially replace live scene: " + damage)

func test_example() -> void:
	var game := fixture(); var before := frozen(game)
	game.thermal_example()
	check(game.stations.size() == 1 and game.devices.size() == 8 and game.links.size() == 8,"thermal example groups existing eight physical devices into one facade")
	check(game.selected_id == SITE and game.station(SITE).id == SITE,"thermal example selects station facade")
	var internal: Array = game.devices.filter(func(d): return d.has("parent_station_id"))
	check(internal.size() == 3 and internal.all(func(d): return int(d.parent_station_id) == SITE),"thermal example contains exactly boiler, store and exchanger internally")
	for kind in ["electric_boiler", "thermal_store", "heat_exchanger"]: check(internal.filter(func(d): return d.kind == kind).size() == 1,"example has exactly one internal " + kind)
	near(game.device(4).state.energy_mwhth,0.0,"example station starts with no free thermal inventory")
	check(game.paused and game.elapsed_s == 0.0 and game.result.get("valid",false),"example begins paused with valid physical result")
	check(game.result.served_mw > 0 and game.result.thermal.demand_mwth > 0,"example retains independent electric and thermal demand")
	assert_ledgers(game,"grouped example")
	game.undo(); check(frozen(game) == before,"example undo restores entire previous scene")

func test_real_glpk_single_expansion() -> void:
	var game := chain()
	game.device(STORE).state.energy_mwhth = 0.375
	remove_edge(game,BOILER,STORE); remove_edge(game,STORE,EXCHANGER); game.refresh()
	var before := frozen(game)
	var service := Optimization.new(); service.host = game; service.request_id = "station-controller-regression"
	var options := {"horizon_hours":1.0,"step_minutes":60.0,"load_multiplier":1.0,"strict_supply":false,
		"terminal_soc_fraction":null,"terminal_heat_soc_fraction":null,"heat_service_weight":1.0,"timeout_s":20}
	var snapshot: Dictionary = service.snapshot(options)
	check(not snapshot.has("error"),"real optimization controller accepts hierarchy: " + str(snapshot.get("error","")))
	if snapshot.has("error"): service.free(); return
	check(snapshot.devices.size() == game.devices.size() and snapshot.links.size() == game.links.size(),"optimization expands physical equipment and connections exactly once")
	check(snapshot.devices.all(func(d): return int(d.id) != SITE and d.kind != "thermal_station"),"optimization excludes facade from energy variables")
	for kind in ["electric_boiler", "thermal_store", "heat_exchanger"]: check(snapshot.devices.filter(func(d): return d.kind == kind).size() == 1,"optimization includes exactly one " + kind)
	check(snapshot.forecast.capacity_expansion == false,"optimization cannot add duplicate capacity")
	near(snapshot.devices[STORE].state.energy_mwhth,0.375,"optimization starts from real nonzero child inventory")
	var baseline: Dictionary = service.make_baseline(snapshot)
	check(not baseline.has("error") and baseline.steps.size() == 1,"real baseline accepts grouped scene snapshot")
	if not baseline.has("error"): near(baseline.steps[0].thermal.served_mwth,1.9208,"baseline applies one boiler and one exchanger")
	var input_path := path_for("glpk_input"); var output_path := path_for("glpk_output")
	write_fixture(input_path,snapshot)
	var solver := OS.get_environment("BASIN_GLPK") if OS.has_environment("BASIN_GLPK") else "glpsol"
	if solver == "glpsol" and FileAccess.file_exists("/workspace/shared/glpk/bin/glpsol"): solver = "/workspace/shared/glpk/bin/glpsol"
	var python := OS.get_environment("BASIN_PYTHON") if OS.has_environment("BASIN_PYTHON") else "python3"
	var output: Array = []
	var code := OS.execute(python,PackedStringArray([ProjectSettings.globalize_path("res://tools/dispatch_solver.py"),
		"--input",ProjectSettings.globalize_path(input_path),"--output",ProjectSettings.globalize_path(output_path),"--glpsol",solver]),output,true)
	check(code == 0,"real GLPK subprocess succeeds: " + str(output))
	if FileAccess.file_exists(output_path):
		var solved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output_path))
		check(solved.get("status","") == "optimal" and solved.get("validation",{}).get("valid",false),"actual GLPK result passes independent audit: " + str(solved.get("message", solved.get("errors",[]))))
		check(solved.get("steps",[]).size() == 1,"GLPK returns requested single interval")
		if solved.get("steps",[]).size() == 1:
			var step: Dictionary = solved.steps[0]
			near(step.boiler_electric_mw,2.0,"GLPK cannot double boiler capacity through parent",2.0e-6)
			near(step.thermal.served_mwth,1.9208,"GLPK serves exactly one physical conversion chain",2.0e-6)
			near(step.thermal.unserved_mwth,0.0792,"GLPK wrapper never hides physical shortfall",2.0e-6)
			near(step.thermal.energy_mwhth,0.375,"GLPK counts isolated nonzero inventory once",2.0e-6)
			check(not step.get("devices",{}).has(str(SITE)),"GLPK has no synthetic station energy report")
	else: check(false,"GLPK produced an actual result file")
	check(frozen(game) == before,"snapshot, baseline and GLPK leave complete live hierarchy unchanged")
	service.free()

func cleanup(controller: Fixture) -> void:
	for key in ["camera","lod_camera","terrain","labels","infrastructure","selection","overlay",
		"equipment","cables","confirmation","param_dialog","param_errors","param_target",
		"data_dialog","data_list","line_dialog","line_capacity","line_loss","line_choice","station_interior"]:
		var node = controller.get(key)
		if is_instance_valid(node) and node.get_parent() == null: node.free()
	controller.free()
