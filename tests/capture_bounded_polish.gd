extends SceneTree
## Actual software-rendered V16.2 two-size layout acceptance. These pointer
## events are Godot GUI/controller injections, not native OS-input evidence.
## Run a second process with -- --restart and the same isolated HOME/XDG dirs.
const SAVE_PATH := "user://bounded_polish_restart.json"
const RECORD_PATH := "user://bounded_polish_record.json"
var game
var checks := 0
var failures: Array[String] = []
var records: Dictionary = {"input":"Godot controller and GUI signal injection", "sizes":[], "captures":[]}
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); print("FAIL BOUNDED_POLISH_GUI ", message)
func canonical(value) -> String: return JSON.stringify(JSON.parse_string(JSON.stringify(value)))
func rect_data(control: Control) -> Dictionary:
	var value := control.get_global_rect()
	return {"x":value.position.x, "y":value.position.y, "width":value.size.x, "height":value.size.y}
func frame_settle() -> void:
	for index in 4: await process_frame
	await RenderingServer.frame_post_draw
func capture(label: String) -> void:
	await frame_settle()
	var path := "user://" + label + ".png"
	var pixels := root.get_texture().get_image()
	var content_pixels := Vector2i(root.get_visible_rect().size * root.get_stretch_transform().get_scale())
	check(pixels.get_size() == root.size or pixels.get_size() == content_pixels, label + " captures actual rendered window/content pixels without resampling")
	check(pixels.save_png(path) == OK, "write " + label)
	records.captures.append({"name":label, "path":ProjectSettings.globalize_path(path), "pixels":str(pixels.get_size()), "physical_window":str(root.size), "logical_canvas":str(root.get_visible_rect().size), "final_transform":str(root.get_final_transform())})
func press(interior, at: Vector2, down: bool = true) -> void:
	var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.pressed = down; event.position = at
	interior.view_container.gui_input.emit(event)
func motion(interior, at: Vector2, mask: int = 0) -> void:
	var event := InputEventMouseMotion.new(); event.position = at; event.button_mask = mask
	interior.view_container.gui_input.emit(event)
func body_pixel(interior, id: int) -> Vector2:
	var visual: Node3D = interior.equipment_nodes[id]
	var bounds: AABB = visual.get_meta("pick_bounds")
	return interior.camera.unproject_position(visual.to_global(bounds.get_center())) * interior.view_container.size / Vector2(interior.viewport.size)
func escape(interior) -> void:
	var event := InputEventKey.new(); event.keycode = KEY_ESCAPE; event.pressed = true
	interior.window_input.emit(event)

func assert_layout(interior, label: String) -> Dictionary:
	var boundary := Rect2(Vector2.ZERO, Vector2(interior.size))
	var logical_window := Rect2(Vector2(interior.position), Vector2(interior.size))
	var physical_window: Rect2 = root.get_final_transform() * logical_window
	check(root.get_visible_rect().encloses(logical_window), label + " embedded window fits parent logical canvas")
	check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(physical_window), label + " final scaled station window is wholly inside actual physical parent window")
	check(boundary.encloses(interior.view_container.get_global_rect()), label + " viewport fits station client bounds")
	check(interior.view_container.size.x >= 400 and interior.view_container.size.y >= 300, label + " 3D construction viewport remains usable")
	check(boundary.encloses(interior.status_label.get_global_rect()) and interior.status_label.size.y >= 28, label + " status is readable inside client bounds")
	var controls: Array = interior.tools.values()
	for name in ["ResetInteriorView", "ReturnToBase"]: controls.append(interior.find_child(name, true, false))
	var buttons: Array = []
	var data := {"root":str(root.size), "root_logical_viewport":str(root.get_visible_rect().size), "root_content_scale_size":str(root.content_scale_size), "root_final_transform":str(root.get_final_transform()), "station":str(interior.size), "position":str(interior.position), "physical_station_rect":str(physical_window), "viewport":rect_data(interior.view_container), "status":rect_data(interior.status_label), "buttons":{}}
	for node in controls:
		if buttons.has(node): continue
		check(node != null and node is Button, label + " expected toolbar/header button exists")
		if node == null: continue
		buttons.append(node)
		check(node.visible and node.size.x > 10 and node.size.y >= 30 and boundary.encloses(node.get_global_rect()), label + " button " + node.name + " is visible and unclipped")
		data.buttons[str(node.name)] = rect_data(node)
	for a in buttons.size():
		for b in range(a + 1, buttons.size()):
			check(not buttons[a].get_global_rect().grow(-0.5).intersects(buttons[b].get_global_rect().grow(-0.5)), label + " buttons " + buttons[a].name + "/" + buttons[b].name + " never overlap")
	var tabs := interior.find_child("StationSidebarTabs", true, false) as TabContainer
	check(tabs != null, label + " sidebar has separate overview/connection pages")
	if tabs != null:
		check(boundary.encloses(tabs.get_global_rect()) and tabs.size.x <= 330, label + " sidebar width is bounded")
		check(not tabs.get_global_rect().grow(-0.5).intersects(interior.view_container.get_global_rect().grow(-0.5)), label + " sidebar and scene do not overlap")
		data.sidebar = rect_data(tabs)
	for name in ["StationOverviewScroll", "StationConnectionsScroll"]:
		var scroll := interior.find_child(name, true, false) as ScrollContainer
		check(scroll != null, label + " " + name + " exists")
		if scroll != null and scroll.is_visible_in_tree():
			check(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, label + " sidebar never requires horizontal scrolling")
			var child := scroll.get_child(0) as Control
			check(child != null and child.size.x <= scroll.size.x + 1.0, label + " page content fits its allocated width")
	return data

func run() -> void:
	root.size = Vector2i(1440, 900)
	root.gui_embed_subwindows = true
	game = load("res://main.tscn").instantiate(); root.add_child(game)
	await frame_settle()
	game.set_process(false)
	if "--restart" in OS.get_cmdline_user_args():
		await restart(); finish(); return
	game.thermal_example(); game.paused = true
	check(game.advance(600.0), "existing physical example advances to real nonzero thermal stock")
	game.refresh(); game.undo_states.clear()
	check(game.devices.size() == 8 and game.links.size() == 8 and game.stations.size() == 1, "bounded polish retains existing eight-device/eight-link example")
	check(game.device(4).state.energy_mwhth > 0, "real stock is nonzero before UI exploration")
	var before := canonical(game.state())
	var revision: int = game.scene_revision
	var sid: int = game.stations[0].id
	var dock = game.find_child("RightDock", true, false)
	if dock != null: dock.close_panels()
	for dimensions in [Vector2i(1024, 768), Vector2i(1440, 900)]:
		root.size = dimensions
		await frame_settle()
		var label := "%dx%d" % [dimensions.x, dimensions.y]
		game.select_device(sid); game.focus_selected(); game.update_interaction_visuals()
		await capture("refinement_base_" + label)
		var camera_before: Transform3D = game.camera.transform
		game.open_station(sid); await frame_settle()
		var interior = game.station_interior
		interior._select(4); interior.set_camera_view(135, 26, 4.2); await frame_settle()
		var data := assert_layout(interior, label + " overview")
		await capture("refinement_overview_" + label)
		var tabs := interior.find_child("StationSidebarTabs", true, false) as TabContainer
		if tabs != null: tabs.current_tab = 1
		interior.set_interaction_mode("connect"); interior._click_device(4); motion(interior, body_pixel(interior, 3))
		await frame_settle()
		data.connections = assert_layout(interior, label + " connections")
		check(interior.hover_label.text.contains("重复"), label + " existing connected pair reports duplicate without changing topology")
		await capture("refinement_connections_" + label)
		for iteration in 12:
			interior.set_interaction_mode("connect"); interior._click_device(4); motion(interior, body_pixel(interior, 3)); escape(interior)
			interior._select(4); interior._start_move()
			var occupied: Vector2 = interior.camera.unproject_position(Vector3(game.device(3).interior_x, 0, game.device(3).interior_z)) * interior.view_container.size / Vector2(interior.viewport.size)
			motion(interior, occupied)
			check(is_instance_valid(interior.preview) and not interior.preview.preview_valid, label + " cycle %d invalid preview remains transient" % iteration)
			escape(interior); press(interior, occupied, false)
			check(interior.preview == null and interior.pending_link == -1 and not interior._move_drag_active, label + " cycle %d cancellation clears all preview state" % iteration)
			check(canonical(game.state()) == before and game.undo_states.is_empty() and game.scene_revision == revision, label + " cycle %d leaves model/history isolated" % iteration)
		interior.close_station(); await frame_settle()
		check(game.camera.transform.is_equal_approx(camera_before) and not root.disable_3d, label + " return restores exact base view and rendering")
		check(canonical(game.state()) == before, label + " layout/selection/tab/tooltip flows preserve full scene")
		records.sizes.append(data)
	check(game.write_save(SAVE_PATH), "post-exploration actual save writes")
	records.state = game.state(); records.save_sha256 = FileAccess.get_sha256(SAVE_PATH)
	records.checks = checks; records.failures = failures
	var file := FileAccess.open(RECORD_PATH, FileAccess.WRITE)
	check(file != null, "rendered evidence record opens")
	if file != null: file.store_string(JSON.stringify(records, "  ")); file.close()
	finish()

func restart() -> void:
	check(FileAccess.file_exists(SAVE_PATH) and FileAccess.file_exists(RECORD_PATH), "fresh process finds prior real save and layout record")
	if not FileAccess.file_exists(RECORD_PATH): return
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RECORD_PATH))
	check(game.read_save(SAVE_PATH), "fresh process reads save through actual validator")
	check(canonical(game.state()) == canonical(saved.state), "fresh process preserves full serialized state")
	check(game.device(4).state.energy_mwhth > 0 and game.elapsed_s == 600, "fresh process retains real thermal inventory and simulation time")
	check(game.paused and game.speed == 1 and game.accumulator == 0, "fresh process resets only playback controls")
	for dimensions in [Vector2i(1024, 768), Vector2i(1440, 900)]:
		root.size = dimensions; await frame_settle()
		game.open_station(int(game.stations[0].id)); await frame_settle()
		game.station_interior._select(4); game.station_interior.set_camera_view(135, 26, 4.2)
		assert_layout(game.station_interior, "restart %s" % dimensions)
		game.station_interior.close_station()
		check(canonical(game.state()) == canonical(saved.state), "fresh process resize and station navigation remain read-only")
	check(FileAccess.get_sha256(SAVE_PATH) == saved.save_sha256, "restart and inspection never rewrite input save")
	var file := FileAccess.open("user://bounded_polish_restart_record.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"checks":checks, "failures":failures, "input_sha256":saved.save_sha256, "state_unchanged":canonical(game.state()) == canonical(saved.state)}, "  ")); file.close()

func finish() -> void:
	print("BOUNDED_POLISH_GUI checks=", checks, " failures=", failures.size(), " restart=", "--restart" in OS.get_cmdline_user_args(), " input=Godot-injection")
	quit(0 if failures.is_empty() else 1)
