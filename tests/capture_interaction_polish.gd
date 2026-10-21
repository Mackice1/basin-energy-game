extends SceneTree
## Real rendered scene and actual disk restart. Pointer events here are injected
## through Godot controller/GUI signals, not a claim of native OS mouse coverage.
## Run once normally, then in a fresh process with -- --restart using the same
## isolated HOME/XDG paths. PNGs and the record are written only under user://.
var game
var checks := 0
var failures: Array[String] = []
var records: Dictionary = {"input":"Godot controller and GUI signal injection", "captures":[]}
const SAVE_PATH := "user://interaction_polish_restart.json"
const RECORD_PATH := "user://interaction_polish_record.json"
func _initialize(): call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL INTERACTION_POLISH_GUI ",label)
func canonical(value) -> String: return JSON.stringify(JSON.parse_string(JSON.stringify(value)))
func capture(name: String) -> void:
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	var path := "user://" + name + ".png"
	check(root.get_texture().get_image().save_png(path) == OK, "capture " + name)
	records.captures.append(ProjectSettings.globalize_path(path))
func click_game(position: Vector2, double_click: bool = false) -> void:
	var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true; event.position = position; event.double_click = double_click
	game._unhandled_input(event)
	event.pressed = false; game._input(event)
func run() -> void:
	root.size = Vector2i(1440,900); root.gui_embed_subwindows = true
	game = load("res://main.tscn").instantiate(); root.add_child(game)
	await process_frame; await process_frame
	if "--native-save" in OS.get_cmdline_user_args():
		await validate_native_save(); finish(); return
	if "--restart" in OS.get_cmdline_user_args():
		await restart(); finish(); return
	game.thermal_example(); game.paused = true
	check(game.advance(600.0), "advance single real clock to nonzero thermal stock")
	game.refresh(); game.set_process(false)
	check(game.devices.size() == 8 and game.stations.size() == 1 and game.links.size() == 8, "existing thermal example has unchanged physical topology")
	check(game.device(4).state.energy_mwhth > 0, "real thermal inventory is nonzero before UI exploration")
	var before := canonical(game.state())
	var sid: int = game.stations[0].id
	for entry in [game.quick_station_enter,game.station_enter_button]:
		game.select_device(sid); game.update_interaction_visuals()
		entry.pressed.emit(); await process_frame
		check(game.station_interior.visible and game.station_interior.station_id == sid, "actual entry button signal opens currently selected facility")
		game.station_interior.close_station()
		check(canonical(game.state()) == before, "entry button navigation does not mutate saved state")
	var dock = game.find_child("RightDock",true,false)
	if dock != null: dock.close_panels()
	game.reset_camera(); game.select_device(-2); game.update_interaction_visuals()
	await capture("polish_base_overview")
	game.select_device(sid); game.focus_selected(); game.distance = 25.0; game.update_camera(); game.update_interaction_visuals()
	await capture("polish_facility_selected")
	var pixel: Vector2 = game.camera.unproject_position(game.station_nodes[str(sid)].get_port_position("ac_in"))
	check(game.nearest(pixel) == sid and not game.pointer_over_ui(pixel), "real facility port is a selectable exposed screen point")
	game.select_device(-2); click_game(pixel)
	check(game.selected_id == sid and not game.station_interior.visible, "single click selects facility without entering")
	var base_camera: Transform3D = game.camera.transform
	var base_target: Vector3 = game.target
	var base_distance: float = game.distance
	click_game(pixel,true)
	check(game.station_interior.visible, "double click enters facility using actual controller picking")
	await process_frame; await process_frame
	var interior = game.station_interior
	interior._select(4)
	interior.set_camera_view(135.0,26.0,4.2)
	await capture("polish_interior_selected")
	for view in [[-35.0,24.0,4.2],[45.0,42.0,4.6]]:
		interior.set_camera_view(view[0],view[1],view[2]); interior.refresh()
	check(canonical(game.state()) == before, "selection and three interior camera views preserve complete state")
	interior.set_camera_view(135.0,26.0,4.2)
	interior.set_interaction_mode("move")
	var occupied: Vector2 = interior.camera.unproject_position(Vector3(game.device(3).interior_x,0,game.device(3).interior_z)) * interior.view_container.size / Vector2(interior.viewport.size)
	var hover := InputEventMouseMotion.new(); hover.position = occupied
	interior.view_container.gui_input.emit(hover)
	check(is_instance_valid(interior.preview) and not interior.preview.preview_valid, "occupied layout preview uses invalid placement feedback")
	await capture("polish_interior_invalid_move")
	interior._cancel_current_interaction()
	check(canonical(game.state()) == before, "invalid preview and cancel preserve layout, ledgers, stock and time")
	interior.close_station()
	check(game.selected_id == sid and game.camera.transform.is_equal_approx(base_camera) and game.target == base_target and game.distance == base_distance, "return restores facility selection and exact base view")
	game.set_mode("link"); game.link_to(2)
	check(game.pending_link == 2, "connection source is pending without mutating topology")
	game.cancel_interaction()
	check(game.pending_link == -2 and game.link_preview == null and canonical(game.state()) == before, "cancelled connection leaves no pending route or saved mutation")
	check(game.write_save(SAVE_PATH), "write actual post-exploration save")
	records["state"] = game.state(); records["checks"] = checks
	records["base_camera"] = str(base_camera)
	var file := FileAccess.open(RECORD_PATH,FileAccess.WRITE)
	check(file != null, "open capture and restart evidence record")
	if file != null: file.store_string(JSON.stringify(records,"  ")); file.close()
	finish()
func restart() -> void:
	check(FileAccess.file_exists(RECORD_PATH) and FileAccess.file_exists(SAVE_PATH), "separate process finds prior actual save")
	if not FileAccess.file_exists(RECORD_PATH): return
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RECORD_PATH))
	check(game.read_save(SAVE_PATH), "fresh process loads actual save")
	check(canonical(game.state()) == canonical(saved.state), "fresh process preserves all devices, links, parameters, time and ledgers")
	check(game.paused and game.speed == 1.0 and game.accumulator == 0.0, "fresh process resets only run controls safely")
	check(game.device(4).state.energy_mwhth > 0 and game.device(4).state.energy_mwhth == saved.state.devices[4].state.energy_mwhth, "fresh process keeps actual nonzero thermal stock")
	game.open_station(int(game.stations[0].id)); await process_frame
	game.station_interior._select(4); game.station_interior.set_camera_view(135,26,4.2)
	await capture("polish_restarted_interior")
	check(canonical(game.state()) == canonical(saved.state), "fresh-process station entry remains read-only")
func finish() -> void:
	print("INTERACTION_POLISH_GUI checks=",checks," failures=",failures.size()," restart=", "--restart" in OS.get_cmdline_user_args()," input=Godot-injection")
	quit(0 if failures.is_empty() else 1)

func validate_native_save() -> void:
	var path := "res://evidence/polish/native_mouse_state.json"
	check(FileAccess.file_exists(path), "native OS-input save exists")
	if not FileAccess.file_exists(path): return
	var input_hash := FileAccess.get_sha256(path)
	var expected = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(expected is Dictionary, "native save is valid JSON")
	if not expected is Dictionary: return
	check(game.validate_state(expected) == "", "native edited save passes terrain, hierarchy and inventory validation")
	check(game.read_save(path), "fresh process restores actual native-input save")
	check(canonical(game.state()) == canonical(expected), "native restart restores all saved content exactly")
	check(game.paused and game.speed == 1 and game.accumulator == 0, "native restart resets only run controls")
	var frozen := canonical(game.state())
	var sid: int = game.stations[0].id
	game.open_station(sid); await process_frame
	check(game.station_interior.visible and root.disable_3d, "native saved facility reopens in fresh process")
	game.station_interior.close_station()
	check(not root.disable_3d and canonical(game.state()) == frozen, "native restart navigation is read-only")
	var e: Dictionary = game.energy; var h: Dictionary = game.thermal_energy
	check(absf(e.generated + e.discharge - e.delivered - e.curtailed - e.loss - e.served - e.charge - e.boiler_electric) < 1e-8, "native electrical cumulative ledger balances")
	check(absf(h.boiler_heat + h.discharge - h.served - h.charge - h.network_loss - h.exchanger_loss) < 1e-8, "native thermal cumulative ledger balances")
	check(absf(e.boiler_electric - h.boiler_heat - e.boiler_conversion_loss) < 1e-8, "native cross-carrier cumulative conversion balances")
	var service = game.optimization_controller
	var snapshot: Dictionary = service.snapshot({"horizon_hours":1.0,"step_minutes":30.0,"load_multiplier":1.0,"strict_supply":false,"timeout_s":20})
	check(not snapshot.has("error"), "native snapshot accepted by real optimization controller")
	if snapshot.has("error"): return
	check(snapshot.devices.size() == expected.devices.size() and snapshot.links.size() == expected.links.size(), "native optimization expands each real device and link once")
	check(snapshot.devices.all(func(d): return d.kind != "thermal_station"), "facility facade never becomes duplicate solver capacity")
	var baseline: Dictionary = service.make_baseline(snapshot)
	check(not baseline.has("error") and baseline.steps.size() == 2, "same native snapshot produces valid two-interval baseline")
	var input_path := "res://evidence/polish/native_solver_input.json"
	var output_path := "res://evidence/polish/native_solver_output.json"
	var input := FileAccess.open(input_path,FileAccess.WRITE)
	check(input != null, "native solver input evidence is writable")
	if input == null: return
	input.store_string(JSON.stringify(snapshot,"  ")); input.close()
	var output: Array = []
	var code := OS.execute("python3",PackedStringArray([ProjectSettings.globalize_path("res://tools/dispatch_solver.py"),"--input",ProjectSettings.globalize_path(input_path),"--output",ProjectSettings.globalize_path(output_path),"--glpsol","/workspace/shared/glpk/bin/glpsol"]),output,true)
	check(code == 0, "real GLPK subprocess succeeds for native-input layout: " + str(output))
	check(FileAccess.file_exists(output_path), "real GLPK writes native result evidence")
	if not FileAccess.file_exists(output_path): return
	var solved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(output_path))
	check(solved.get("status","") == "optimal" and solved.get("validation",{}).get("valid",false), "native GLPK result is optimal and passes independent physical audit")
	check(solved.get("steps",[]).size() == 2, "native GLPK returns both requested intervals")
	check(canonical(game.state()) == frozen, "native snapshot, baseline and real GLPK preserve live inventory, time, layout and ledgers")
	check(FileAccess.get_sha256(path) == input_hash, "native save on disk is unchanged by restart or optimization")
	var report := {"input_sha256":input_hash,"checks":checks,"failures":failures.size(),"devices":game.devices.size(),"links":game.links.size(),"elapsed_s":game.elapsed_s,"thermal_inventory_mwhth":game.device(4).state.energy_mwhth,"solver_status":solved.get("status",""),"solver_audit":solved.get("validation",{}),"world_unchanged":canonical(game.state()) == frozen}
	var record := FileAccess.open("res://evidence/polish/native_restart_solver_record.json",FileAccess.WRITE)
	if record != null: record.store_string(JSON.stringify(report,"  ")); record.close()
	print("NATIVE_POLISH_RESTART_GLPK checks=",checks," failures=",failures.size()," input_sha256=",input_hash," stock=",game.device(4).state.energy_mwhth," world_unchanged=",canonical(game.state()) == frozen)
