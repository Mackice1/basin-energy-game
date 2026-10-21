extends SceneTree
## Actual engine-rendered fuel resource/independent boiler acceptance. All edits
## here use controller/GUI calls, not native OS input. Restart is a new process.
const SAVE_PATH := "user://fuel_stage_restart.json"
const RECORD_PATH := "user://fuel_stage_record.json"
var game
var checks := 0
var failures: Array[String] = []
var records: Dictionary = {"input":"Godot controller and GUI calls; no native-input claim","captures":[]}
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL FUEL_STAGE_GUI ",label)
func canonical(value: Variant) -> String: return JSON.stringify(JSON.parse_string(JSON.stringify(value)))
func settle() -> void:
	for index in 4: await process_frame
	if is_instance_valid(game) and game.booted: game.update_interaction_visuals()
	await RenderingServer.frame_post_draw
func capture(label: String) -> void:
	await settle()
	var path := "user://" + label + ".png"
	var pixels := root.get_texture().get_image()
	check(pixels.save_png(path) == OK,"actual rendered image writes " + label)
	records.captures.append({"name":label,"path":ProjectSettings.globalize_path(path),"pixels":str(pixels.get_size()),"window":str(root.size),"observed_fps":Engine.get_frames_per_second(),"observed_process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"performance_scope":"instantaneous cloud software-renderer observation, not comparative/hardware performance proof"})
func record(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path,FileAccess.WRITE)
	check(file != null,"open evidence record")
	if file != null: file.store_string(JSON.stringify(value,"  ")); file.close()
func assert_ledgers() -> void:
	check(game.fuel_energy.input_mwh > 0 and game.fuel_energy.heat_output_mwhth > 0 and game.fuel_energy.auxiliary_mwh > 0,"rendered example contains actual nonzero gas/heat/auxiliary history")
	check(absf(game.fuel_energy.input_mwh-game.fuel_energy.heat_output_mwhth-game.fuel_energy.conversion_loss_mwh) < 1.0e-9,"saved gas ledger conserves LHV")
	check(game.energy.boiler_electric > 0 and game.thermal_energy.boiler_heat > 0,"electric boiler remains independently active")
	check(game.validate_state(game.state()).is_empty(),"actual rendered state passes complete physical/save validation")
func run() -> void:
	root.size = Vector2i(1440,900); root.gui_embed_subwindows = true
	game = load("res://main.tscn").instantiate(); root.add_child(game); await settle()
	game.set_process(false)
	if "--restart" in OS.get_cmdline_user_args() or "--native-save" in OS.get_cmdline_user_args():
		await restart(); finish(); return
	game.fuel_example(); game.paused = true
	check(game.devices.size() == 9 and game.links.size() == 11 and game.stations.size() == 1,"actual graphical fixture has nine devices and eleven links")
	check(game.result.get("valid",false) and game.result.get("fuel",{}).get("input_mw",0.0) > 0.0,"initial rendered joint example has positive audited gas flow")
	check(game.advance(60.0),"rendered controller advances sixty real simulated seconds")
	game.refresh(); assert_ledgers()
	game.undo_states.clear()
	var frozen := canonical(game.state()); var revision: int = game.scene_revision
	var sid: int = game.stations[0].id; var fuel_id := -1
	for device in game.devices:
		if device.kind == "fuel_boiler": fuel_id = int(device.id)
	check(fuel_id >= 0,"fuel boiler has its own device ID")
	var dock = game.find_child("RightDock",true,false)
	for dimensions in [Vector2i(1440,900),Vector2i(1024,768)]:
		root.size = dimensions; await settle()
		var label := "%dx%d" % [dimensions.x,dimensions.y]
		game.distance = 100.0; game.target = Vector3(game.stations[0].x-8,0,game.stations[0].z); game.update_camera()
		dock.close_panels(); dock.toggle_panel("fuel"); await settle()
		var resource_panel: Control = dock.panels.fuel
		check(root.get_visible_rect().encloses(resource_panel.get_global_rect()),label + " resource panel fits logical window")
		var resource_scroll: ScrollContainer = game.fuel_summary.get_parent().get_parent()
		resource_scroll.scroll_vertical = 0; await settle()
		check(not resource_scroll.get_h_scroll_bar().visible,label + " resource controls need no horizontal scroll")
		await capture("fuel_resources_" + label)
		resource_scroll.ensure_control_visible(game.fuel_summary); await settle()
		check(game.fuel_summary.text.contains("累计燃料") and game.fuel_summary.text.contains("累计教学燃料费"),label + " historical meter units visible")
		await capture("fuel_meters_" + label)
		for iteration in 4:
			game.fuel_controls.max_input_mw.value = 1.0 + iteration
			game.fuel_supply_enabled.button_pressed = false
			game.sync_fuel_resource_form(); game.refresh(); dock.close_panels(); dock.toggle_panel("fuel")
			check(canonical(game.state()) == frozen and game.scene_revision == revision and game.undo_states.is_empty(),label + " repeated resource cancel/display never changes model")
		dock.close_panels(); game.open_station(sid); await settle()
		var interior = game.station_interior
		interior._select(fuel_id); interior.set_camera_view(135.0,26.0,4.2); await settle()
		check(interior.equipment_nodes.has(fuel_id) and interior.equipment_nodes[fuel_id].get_meta("visual_backend","") == "blender_glb",label + " independent gas model uses real authored GLB")
		check(interior.equipment_nodes[fuel_id].get_meta("module_count",0) == 1,label + " single module visual cannot duplicate physical output")
		check(interior.tools.has("fuel_boiler") and interior.tools.fuel_boiler.is_visible_in_tree(),label + " station offers independent fuel boiler tool")
		check(interior.selected_label.text.contains("燃料输入") and interior.selected_label.text.contains("辅机用电"),label + " gas and AC reports are distinct")
		check(root.get_visible_rect().encloses(Rect2(Vector2(interior.position),Vector2(interior.size))),label + " station window remains bounded")
		await capture("fuel_station_" + label)
		interior.close_station(); await settle()
		check(canonical(game.state()) == frozen and game.scene_revision == revision and game.undo_states.is_empty(),label + " selection/navigation/camera/resize are state-isolated")
	check(game.write_save(SAVE_PATH),"actual rendered gas save writes")
	records.state = game.state(); records.save_sha256 = FileAccess.get_sha256(SAVE_PATH)
	records.checks = checks + 1; records.failures = failures.duplicate()
	record(RECORD_PATH,records)
	finish()
func restart() -> void:
	var native := "--native-save" in OS.get_cmdline_user_args()
	var input_path := "res://evidence/fuel_stage/native_mouse_state.json" if native else SAVE_PATH
	var prefix := "fuel_native_restart" if native else "fuel_restart"
	check(FileAccess.file_exists(input_path) and (native or FileAccess.file_exists(RECORD_PATH)),"fresh process finds saved fuel stage")
	if not FileAccess.file_exists(input_path): return
	var original: Dictionary = {"state":JSON.parse_string(FileAccess.get_file_as_string(input_path)),"save_sha256":FileAccess.get_sha256(input_path)} if native else JSON.parse_string(FileAccess.get_file_as_string(RECORD_PATH))
	check(game.read_save(input_path),"fresh graphical process reads actual schema8 save")
	check(canonical(game.state()) == canonical(original.state),"fresh process preserves all resources, stocks, meters and coordinates")
	check(game.paused and game.speed == 1.0 and game.elapsed_s == float(original.state.elapsed_s),"fresh process resumes paused at original saved time")
	assert_ledgers()
	var frozen := var_to_bytes(game.state()); var revision: int = game.scene_revision; var undo := var_to_bytes(game.undo_states)
	var fuel_id := -1
	for device in game.devices:
		if device.kind == "fuel_boiler": fuel_id = int(device.id)
	game.open_station(int(game.stations[0].id)); await settle(); game.station_interior._select(fuel_id)
	game.station_interior.set_camera_view(135.0,26.0,4.2); await capture(prefix + "_station_1440x900")
	game.station_interior.close_station()
	var service = game.optimization_controller
	service.solver_executable = "/workspace/shared/glpk/bin/glpsol"
	var options := {"horizon_hours":1.0,"step_minutes":30.0,"load_multiplier":1.0,"strict_supply":false,"timeout_s":20}
	service.panel.configure(options); service.start(options)
	check(service.pid > 0,"fresh-process loaded world launches real GLPK")
	var deadline := Time.get_ticks_msec() + 30000
	while service.pid > 0 and Time.get_ticks_msec() < deadline: await create_timer(0.05).timeout
	check(service.pid < 0 and service.last_result.get("status","") == "optimal","fresh-process actual mixed-boiler world optimizes")
	check(service.last_result.get("validation",{}).get("valid",false),"fresh-process GLPK independent audit succeeds")
	var fuel_total: float = service.last_result.get("totals",{}).get("fuel",{}).get("input_mwh",0.0)
	check(fuel_total > 0.0,"fresh-process real optimization retains positive gas use")
	service.panel.open(); await capture(prefix + "_optimization_1440x900"); service.panel.hide()
	check(var_to_bytes(game.state()) == frozen and game.scene_revision == revision and var_to_bytes(game.undo_states) == undo,"fresh process optimization/inspection leaves complete world and undo bytes unchanged")
	check(FileAccess.get_sha256(input_path) == original.save_sha256,"fresh process never rewrites input save")
	record("user://" + prefix + "_glpk.json",service.last_result)
	records.checks = checks + 1; records.failures = failures.duplicate(); records.state_unchanged = var_to_bytes(game.state()) == frozen
	records.input_sha256 = original.save_sha256; records.optimized_fuel_mwh = fuel_total
	records.input_source = input_path
	record("user://" + prefix + "_record.json",records)
func finish() -> void:
	print("FUEL_STAGE_GUI checks=",checks," failures=",failures.size()," restart=","--restart" in OS.get_cmdline_user_args()," native_save=","--native-save" in OS.get_cmdline_user_args()," input=Godot-controller-GUI-calls")
	quit(0 if failures.is_empty() else 1)
