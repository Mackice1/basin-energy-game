extends SceneTree
## Demand is a separate setting/connection-node workflow. The real HUD, editor,
## save boundary and forecast snapshot must continue using compatible load data.
## Flat terrain and no equipment rebuilding keep this regression headless.

class DemandGame:
	extends "res://scripts/world_game.gd"
	func _ready():
		cfg = {"max_build_slope_degrees": 8.0}
		for kind in KINDS:
			templates[kind] = model.defaults(kind)
		make_ui()
		booted = true
		set_process(false)
	func exclusion(_x: float, _z: float) -> String: return ""
	func slope_at(_x: float, _z: float) -> float: return 0.0
	func height_at(_x: float, _z: float) -> float: return 0.0
	func rebuild_equipment(): pass
	func rebuild_cables(): pass
	func pick_ground(_position: Vector2) -> Vector2: return Vector2(60, 20)
	func weather_at(_time: float) -> Dictionary:
		return {"wind_speed_mps": 12.0, "irradiance_wm2": 800.0, "air_temp_c": 25.0}

var game: DemandGame
var checks := 0
var failures: Array[String] = []

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error("DEMAND_ENTRY_FAIL: " + description)

func _initialize() -> void:
	call_deferred("_run")

func same_json(left: Variant, right: Variant) -> bool:
	# JSON restores numeric values as floats; compare serialized data semantics.
	return JSON.parse_string(JSON.stringify(left)) == JSON.parse_string(JSON.stringify(right))

func legacy_load_scene() -> Dictionary:
	var scene := game.state()
	scene.devices = [
		{"id": 1, "kind": "pv", "x": -30.0, "z": 0.0, "params": game.model.defaults("pv")},
		{"id": 5, "kind": "station", "x": 0.0, "z": 0.0, "params": game.model.defaults("station")},
		{"id": 12, "kind": "load", "x": 20.0, "z": 0.0, "params": {"demand_mw": 2.125, "priority": 3}},
		{"id": 22, "kind": "battery", "x": 40.0, "z": 0.0, "params": game.model.defaults("battery"), "state": {"energy_mwh": 2.75}}
	]
	scene.links = [
		{"from": 1, "to": 5, "capacity_mw": 8.0, "loss_fraction": 0.02},
		{"from": 5, "to": 12, "capacity_mw": 8.0, "loss_fraction": 0.02},
		{"from": 22, "to": 5, "capacity_mw": 3.0, "loss_fraction": 0.02}
	]
	scene.next_id = 31
	scene.elapsed_s = 120.0
	return scene

func find_button(node: Node, caption: String) -> Button:
	if node is Button and node.text == caption:
		return node
	for child in node.get_children():
		var found := find_button(child, caption)
		if found != null:
			return found
	return null

func pick_id(picker: OptionButton, id: int) -> bool:
	for index in range(picker.item_count):
		if int(picker.get_item_metadata(index)) == id:
			picker.select(index)
			picker.item_selected.emit(index)
			return true
	return false

func edit_parameter(key: String, value: String) -> void:
	var editor: LineEdit = game.parameter_form._fields[key]
	editor.text = value
	editor.text_changed.emit(value)

func test_existing_demand(dock: Control) -> void:
	var picker: OptionButton = dock.panels.demand.find_child("DemandPicker", true, false)
	check(picker != null, "demand panel provides its own node picker")
	if picker == null:
		return
	check(pick_id(picker, 12), "restored load is listed by stable ID in demand picker")
	check(game.selected_id == 12, "demand picker selects the existing load node")
	check(game.selection_label.text.contains("需求节点") and game.selection_label.text.contains("12"), "legacy load is presented as a demand node")
	check(int(game.device_picker.get_item_metadata(game.device_picker.selected)) == 12, "demand selection stays synchronized with general selection")
	var before := game.state()
	var edit := find_button(dock.panels.demand, "编辑所选需求")
	check(edit != null and edit.is_visible_in_tree() and not edit.disabled, "selected demand has a reachable edit action")
	if edit == null:
		return
	edit.pressed.emit()
	check(game.param_dialog.visible and game.parameter_kind() == "load", "demand edit opens the compatible load parameter form")
	check(game.parameter_id == 12 and game.param_scope == "device", "demand edit targets the selected node only")
	if not game.param_dialog.visible or game.parameter_kind() != "load":
		return
	check(same_json(game.parameter_form.get_parameters(), {"demand_mw": 2.125, "priority": 3}), "restored demand and priority are preserved in the editor")
	edit_parameter("demand_mw", "3.5")
	edit_parameter("priority", "1")
	game.apply_parameters()
	check(not game.param_dialog.visible, "valid demand settings apply successfully")
	check(same_json(game.device(12).params, {"demand_mw": 3.5, "priority": 1}), "demand MW and priority commit to the existing node")
	var expected := before.duplicate(true)
	expected.devices[2].params = {"demand_mw": 3.5, "priority": 1}
	check(same_json(game.state(), expected), "editing demand preserves IDs, kind, positions, links, templates, clock, energy and battery inventory")
	check(game.result.get("demand_mw", 0.0) == 3.5, "real-time dispatch reads the edited demand")

func test_new_demand(dock: Control) -> void:
	# New construction has its own explicitly supported metric fixture. The
	# preceding legacy edit assertions remain untouched and preserve stable IDs.
	var reference_scene := game.state()
	reference_scene.dimension_profile = "metric_v1"
	for item in reference_scene.devices: item.site_geometry_profile = "reference_size_v1"
	check(game.validate_state(reference_scene).is_empty(), "new-demand metric reference fixture is valid")
	game.restore(reference_scene)
	var add := find_button(dock.panels.demand, "添加需求接入点")
	check(add != null and add.is_visible_in_tree() and not add.disabled, "demand panel exposes a reachable add-connection-node action")
	if add == null:
		return
	var before := game.state()
	add.pressed.emit()
	check(game.mode == "build" and game.build_kind == "load", "demand action enters compatible connection-node placement")
	check(game.state() == before, "entering demand placement alone does not change scene data")
	for key in game.tool_buttons:
		check(not game.tool_buttons[key].button_pressed, key + " equipment button is not selected during demand placement")
	var point := Vector2(600, 650)
	check(not game.pointer_over_ui(point), "demand placement test uses uncovered map space")
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = point
	game._unhandled_input(event)
	check(game.devices.size() == before.devices.size() + 1, "demand action permits placing a connection node on the map")
	check(game.device(31).get("kind", "") == "load", "new demand node retains save and solver kind load")
	check(game.device(31).get("site_geometry_profile", "") == "reference_size_v1", "new demand node carries the current explicit geometry marker")
	check(game.device(31).get("params", {}) == game.templates.load, "new demand node receives demand defaults")
	check(game.links == before.links and game.device(22).state.energy_mwh == 2.75, "adding demand preserves network links and actual battery inventory")
	game.set_mode("select")
	var picker: OptionButton = dock.panels.demand.find_child("DemandPicker", true, false)
	if picker != null:
		check(pick_id(picker, 31) and game.selected_id == 31, "new demand immediately appears in the demand picker")
	check(game.result.get("unserved_mw", 0.0) >= 2.0 - 1e-9, "unconnected demand remains visible as shortage")

func test_snapshot() -> void:
	var before := game.state()
	check(game.validate_state(before).is_empty(), "demand workflow still produces a compatible current save")
	var encoded: Variant = JSON.parse_string(JSON.stringify(before))
	check(game.validate_state(encoded).is_empty(), "demand workflow state survives JSON serialization")
	var service = load("res://scripts/optimization_controller.gd").new()
	service.host = game
	var request: Dictionary = service.snapshot({"horizon_hours": 2.0, "step_minutes": 60.0, "load_multiplier": 1.5, "strict_supply": false})
	check(not request.has("error"), "GLPK forecast accepts restored and newly placed demand nodes")
	if not request.has("error"):
		check(request.devices.size() == game.devices.size(), "forecast keeps every existing device and demand node")
		check(request.steps.size() == 2, "forecast uses requested horizon")
		for step in request.steps:
			check(step.demand_mw.get("12", -1.0) == 5.25, "forecast retains edited existing demand and explicit multiplier")
			check(step.demand_mw.get("31", -1.0) == 3.0, "forecast retains new demand and explicit multiplier")
		var baseline: Dictionary = service.make_baseline(request)
		check(not baseline.has("error"), "forecast baseline remains valid after demand workflow")
		if not baseline.has("error"):
			for step in baseline.steps:
				check(step.unserved_mw >= 3.0 - 1e-9, "forecast comparison preserves isolated demand shortage")
	check(game.state() == before, "forecast preparation preserves all live demand and battery state")
	service.free()

func _run() -> void:
	root.size = Vector2i(1600, 1000)
	game = DemandGame.new()
	root.add_child(game)
	var restored := legacy_load_scene()
	check(game.validate_state(restored).is_empty(), "existing load save fixture is valid")
	game.restore(JSON.parse_string(JSON.stringify(restored)))
	check(same_json(game.state(), restored), "restoring existing load state does not rename or discard stored data")
	await process_frame
	await process_frame
	for kind in ["wind", "pv", "station", "battery"]:
		check(game.tool_buttons.has(kind), kind + " remains available in equipment construction toolbar")
	check(not game.tool_buttons.has("load"), "electric demand is absent from equipment construction toolbar")
	check("load" in game.KINDS and game.templates.has("load"), "load stays supported by model and compatible templates")
	var dock = game.find_child("RightDock", true, false)
	check(dock != null and dock.panels.has("demand") and dock.buttons.has("demand"), "dedicated demand section is present")
	if dock != null and dock.panels.has("demand") and dock.buttons.has("demand"):
		check(dock.buttons.demand.tooltip_text == "用电 / 用热需求", "demand entry has the intended navigation title")
		check(not dock.panels.demand.visible, "demand panel starts collapsed")
		dock.buttons.demand.pressed.emit()
		await process_frame
		await process_frame
		check(dock.active_key == "demand" and dock.panels.demand.visible, "demand entry opens its own panel")
		test_existing_demand(dock)
		test_new_demand(dock)
		test_snapshot()
	game.clear_ghost()
	await process_frame
	for key in ["camera", "lod_camera", "terrain", "labels", "infrastructure", "selection", "overlay", "equipment", "cables"]:
		var node = game.get(key)
		if is_instance_valid(node) and node.get_parent() == null:
			node.free()
	game.free()
	await process_frame
	print("DEMAND_ENTRY_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
