extends SceneTree
## Headless UI/controller regressions. Uses the real controls, parameter actions,
## status formatter and energy solver, with flat ground and no rendered equipment.
## Does not initialize Terrain3D, write scene files, or access real save slots.
## These checks do not replace desktop visual or native-popup acceptance testing.

class UIController:
	extends "res://scripts/world_game.gd"
	var world_clicks := 0
	var fixture_weather := {"wind_speed_mps": 12.0, "irradiance_wm2": 800.0, "temperature_c": 25.0}

	func _ready():
		cfg = {"max_build_slope_degrees": 8.0}
		for kind in ["wind", "pv", "station"]:
			templates[kind] = model.defaults(kind)
		make_ui()
		booted = true
		set_process(false)

	func exclusion(_x: float, _z: float) -> String: return ""
	func slope_at(_x: float, _z: float) -> float: return 0.0
	func height_at(_x: float, _z: float) -> float: return 0.0
	func rebuild_equipment(): pass
	func rebuild_cables(): pass
	func pick_ground(_position: Vector2) -> Vector2: return Vector2.ZERO
	func nearest(_position: Vector2) -> int: return -2
	func select_site(_position: Vector2): world_clicks += 1

	func solve_at(_time: float) -> Dictionary:
		last_weather = fixture_weather.duplicate(true)
		return model.solve(devices, links, fixture_weather)

var game: UIController
var checks := 0
var failures: Array[String] = []

func _initialize(): call_deferred("_run")

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("VISUAL_UI_FAIL: " + description)

func fixture() -> void:
	game.param_dialog.hide()
	game.devices = [
		{"id": 0, "kind": "wind", "x": -20.0, "z": 0.0, "params": game.model.defaults("wind")},
		{"id": 7, "kind": "station", "x": 30.0, "z": 0.0, "params": game.model.defaults("station")}
	]
	game.links = [
		{"from": 0, "to": 7, "capacity_mw": 8.0, "loss_fraction": 0.02},
		{"from": 7, "to": -1, "capacity_mw": 4.0, "loss_fraction": 0.02}
	]
	for kind in ["wind", "pv", "station"]:
		game.templates[kind] = game.model.defaults(kind)
	game.imports = []
	game.undo_states = []
	game.next_id = 8
	game.elapsed_s = 0.0
	game.energy = {"generated": 0.0, "delivered": 0.0, "curtailed": 0.0, "loss": 0.0}
	game.selected_id = 0
	game.mode = "select"
	game.paused = true
	game.refresh()

func find_button(node: Node, caption: String, prefix: bool = false) -> Button:
	if node is Button and (node.text.begins_with(caption) if prefix else node.text == caption):
		return node
	for child in node.get_children():
		var found := find_button(child, caption, prefix)
		if found != null:
			return found
	return null

func press_button(node: Node, caption: String, prefix: bool = false) -> void:
	var found := find_button(node, caption, prefix)
	check(found != null, "button exists: " + caption)
	if found != null:
		found.pressed.emit()

func edit_parameter(key: String, value: String) -> void:
	var editor: LineEdit = game.parameter_form._fields[key]
	editor.text = value
	editor.text_changed.emit(value)

func choose_device(index: int) -> void:
	game.device_picker.select(index)
	game.device_picker.item_selected.emit(index)

func click(position: Vector2) -> void:
	for is_pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = is_pressed
		root.push_input(event)

func check_metric(key: String, expected: float, description: String) -> void:
	check(game.metric_values[key].text == "%.3f" % expected, description)

func test_metrics() -> void:
	game.paused = false
	game.select_device(7)
	var station: Dictionary = game.result.devices["7"]
	check(station.input_mw > 0.0 and station.mw == 0.0, "fixture distinguishes station throughput from generation")
	check(game.device_summary.text.contains("运行 · 输送中"), "active station is transporting rather than idle")
	check(game.device_summary.text.contains("接收容量已满"), "saturated station reports receiving-capacity constraint")
	check(game.metric_names["device_available"].text == "实际输入", "station input uses an input label")
	check_metric("device_available", station.input_mw, "station input metric uses allocated input power")
	check_metric("device_sent", station.sent_mw, "station output metric uses its sending-side power")
	check_metric("generated", game.result.generated_mw - game.result.curtailed_mw, "actual generation subtracts curtailment")
	check_metric("available", game.result.generated_mw, "available generation is retained separately")
	check_metric("net", game.result.delivered_mw, "net export uses grid-received power")
	check(game.result.curtailed_mw > 0.0, "fixture exercises nonzero curtailment")
	game.select_device(0)
	check(game.metric_names["device_available"].text == "可用出力", "generator selection restores available-power label")
	check_metric("device_available", game.result.devices["0"].mw, "generator available metric is independent of dispatch")
	game.paused = true
	game.update_status()
	check(game.device_summary.text.contains("运行 · 已暂停"), "paused generator does not claim to be running")
	game.links = []
	game.paused = false
	game.refresh()
	check_metric("generated", 0.0, "disconnected generation is fully curtailed, not shown as actual output")
	check_metric("available", 5.0, "disconnected generator retains weather-available power")
	game.select_device(7)
	check(game.device_summary.text.contains("待机 / 无输入"), "station with no input is idle")
	check_metric("device_available", 0.0, "disconnected station input is zero")
	fixture()

func test_device_picker() -> void:
	check(game.device_picker.item_count == 3, "picker contains placeholder and both devices")
	check(int(game.device_picker.get_item_metadata(0)) == -2, "placeholder has an explicit negative sentinel in metadata")
	choose_device(2)
	check(game.selected_id == 7, "noncontiguous device ID is not confused with its menu index")
	for iteration in range(20):
		game.update_status()
	check(game.device_picker.selected == 2 and game.selected_id == 7, "repeated runtime updates retain the chosen device")
	choose_device(0)
	check(game.selected_id == -2, "placeholder clears selection instead of selecting device zero")
	game.select_device(7)
	game.select_device(-1)
	check(game.device_picker.selected == 0, "external grid selection clears the previous device in the picker")
	game.select_device(7)
	game.devices.reverse()
	game.update_status()
	check(int(game.device_picker.get_item_metadata(game.device_picker.selected)) == 7, "reordered menu preserves selection by stable ID")
	game.devices = game.devices.filter(func(item): return int(item.id) != 7)
	game.update_status()
	check(game.device_picker.item_count == 2 and game.device_picker.selected == 0, "removed device does not leave a stale picker selection")
	fixture()

func test_parameters() -> void:
	game.select_device(0)
	var original: Dictionary = game.state()
	game.open_parameters(false)
	check(not game.param_target.visible, "single-device dialog does not expose template kind selector")
	check(game.parameter_scope_label.text.contains("仅当前设备 #0"), "single-device scope names the target")
	edit_parameter("rated_mw", "4.0")
	press_button(game.param_dialog, "取消")
	check(not game.param_dialog.visible and game.state() == original, "cancel preserves all serializable scene state")
	game.open_parameters(false)
	check(game.parameter_form.get_parameters().rated_mw == 5.0, "reopening discards cancelled draft")
	edit_parameter("rated_mw", "4.0")
	game.param_dialog.close_requested.emit()
	check(not game.param_dialog.visible and game.state() == original, "window close also discards unapplied changes")
	game.open_parameters(false)
	var undo_before := game.undo_states.size()
	edit_parameter("rated_mw", "-1")
	game.apply_parameters()
	check(game.param_dialog.visible and game.state() == original, "invalid apply remains open and is atomic")
	check(game.undo_states.size() == undo_before, "rejected apply creates no undo checkpoint")
	check(game.param_errors.text.begins_with("未应用："), "rejected apply explains the error")
	edit_parameter("rated_mw", "4.0")
	check(game.parameter_form.get_validation_errors().is_empty(), "corrected numeric draft passes model validation")
	check(not game.param_errors.text.begins_with("未应用："), "manual correction clears stale submit error")
	game.apply_parameters()
	check(not game.param_dialog.visible, "successful apply closes the dialog")
	check(game.device(0).params.rated_mw == 4.0 and game.templates.wind.rated_mw == 5.0, "single apply leaves future template unchanged")
	check(game.device(7).params == original.devices[1].params, "single apply leaves other devices unchanged")
	game.undo()
	check(game.state() == original, "single-device parameter edit is fully undoable")
	game.select_device(0)
	game.open_parameters(false)
	edit_parameter("rated_mw", "-1")
	game.apply_parameters()
	press_button(game.param_dialog, "恢复参考默认", true)
	check(game.parameter_form.get_parameters() == game.model.defaults("wind"), "restore-defaults button restores the draft")
	check(not game.param_errors.text.begins_with("未应用："), "restore-defaults button clears stale submit error")
	check(game.state() == original, "restoring defaults alone does not commit changes")
	edit_parameter("rotor_diameter_m", "1000")
	edit_parameter("hub_height_m", "600")
	check(game.parameter_form.get_validation_errors().is_empty(), "oversized fixture is physically valid before site validation")
	game.apply_parameters()
	check(game.param_errors.text.begins_with("尺寸不适合"), "single apply retains site/footprint validation")
	check(game.state() == original and game.undo_states.size() == undo_before, "site rejection also preserves scene and undo history")
	game.param_dialog.hide()
	game.open_parameters(true)
	check(game.param_target.visible and game.parameter_scope_label.text.contains("仅未来新建模板"), "template dialog declares future-only scope")
	edit_parameter("rated_mw", "4.0")
	game.apply_parameters()
	check(game.templates.wind.rated_mw == 4.0 and game.device(0).params.rated_mw == 5.0, "template apply leaves existing equipment unchanged")
	check(game.add_equipment("wind", Vector2(-45, 0)), "new equipment can be placed using modified template")
	check(game.device(8).params.rated_mw == 4.0, "future equipment receives the committed template")
	game.undo()
	check(game.device(8).is_empty() and game.templates.wind.rated_mw == 4.0, "undoing placement preserves its preexisting template")
	game.open_parameters(true)
	edit_parameter("rated_mw", "3.0")
	game.param_target.select(1)
	game.param_target.item_selected.emit(1)
	check(game.parameter_form.get_parameters() == game.templates.pv, "switching type loads the correct template")
	game.param_target.select(0)
	game.param_target.item_selected.emit(0)
	check(game.parameter_form.get_parameters().rated_mw == 4.0, "switching back discards uncommitted template draft")
	press_button(game.param_dialog, "取消")
	game.undo()
	check(game.state() == original, "template edit is fully undoable")
	fixture()

func test_ui_events_and_layout() -> void:
	var body: VBoxContainer = game.device_picker.get_parent()
	var scroll: ScrollContainer = body.get_parent()
	var dock = game.find_child("RightDock", true, false)
	var shell: PanelContainer = dock.panels.energy
	check(not shell.visible, "energy panel starts collapsed")
	dock.toggle_panel("energy")
	await process_frame
	await process_frame
	var footer: PanelContainer = game.notice.get_parent().get_parent()
	var right_point := shell.global_position + Vector2(3, 3)
	var footer_point := footer.global_position + Vector2(3, 3)
	check(game.pointer_over_ui(right_point) and game.pointer_over_ui(footer_point), "HUD regions are included in pointer mask")
	click(right_point)
	await process_frame
	check(game.world_clicks == 0, "right-panel padding does not click through to the world")
	click(footer_point)
	await process_frame
	check(game.world_clicks == 0, "footer padding does not click through to the world")
	var map_point := Vector2(250, 350)
	check(not game.pointer_over_ui(map_point), "test world point is outside all HUD regions")
	click(map_point)
	await process_frame
	check(game.world_clicks == 1, "uncovered map click reaches the controller")
	game.select_device(0)
	game.open_parameters(false)
	click(map_point)
	await process_frame
	check(game.world_clicks == 1, "parameter modal blocks underlying map interaction")
	game.param_dialog.hide()
	var previous_size := shell.size
	for caption in ["功率与能量分项", "技术详情"]:
		press_button(body, caption, true)
	await process_frame
	await process_frame
	await process_frame
	check(scroll.get_v_scroll_bar().visible, "expanded details use vertical scrolling")
	check(body.size.y > scroll.size.y, "expanded content remains inside bounded scroll viewport")
	check(shell.size == previous_size, "expanding details does not grow the HUD shell")
	check(shell.get_global_rect().end.y <= root.size.y, "right HUD shell remains within viewport height")
	check(not scroll.get_h_scroll_bar().visible and body.size.x <= scroll.size.x, "expanded CJK content fits without horizontal clipping")

func _run() -> void:
	root.size = Vector2i(1600, 1000)
	game = UIController.new()
	root.add_child(game)
	fixture()
	await process_frame
	await process_frame
	test_metrics()
	test_device_picker()
	test_parameters()
	await process_frame
	await process_frame
	await test_ui_events_and_layout()
	# The base class preallocates these nodes, but this lightweight _ready does
	# not parent them. Free them explicitly to avoid misleading leak diagnostics.
	for key in ["camera", "lod_camera", "terrain", "labels", "infrastructure", "selection", "overlay", "equipment", "cables"]:
		var node = game.get(key)
		if is_instance_valid(node) and node.get_parent() == null:
			node.free()
	game.free()
	await process_frame
	print("VISUAL_UI_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
