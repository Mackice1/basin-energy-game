extends SceneTree
## Fuel station UI integration: real controller edits, save/restore, named ports,
## exact report presentation and small-window reachability. Dispatch conservation
## is covered by the separate realtime/GLPK fuel suites, not mocked here.
const Interior = preload("res://scripts/station_interior.gd")
const Form = preload("res://scripts/parameter_form.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
const ControllerTest = preload("res://tests/test_station_controller.gd")
const SITE := 1000000
const FUEL := 0
const STORE := 1
const HX := 2
const FUEL_2 := 3
const AC := 4

class Host:
	extends ControllerTest.Fixture
	func _process(_delta: float) -> void: pass

var checks := 0
var failures: Array[String] = []
var host: Host
var interior

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		print("FAIL ", label)

func _initialize() -> void: call_deferred("run")

func settle() -> void:
	for index in 4: await process_frame

func fixture() -> Host:
	var result := Host.new()
	result.cfg = {"max_build_slope_degrees": 8.0}
	result.dimension_profile = "metric_v1"
	result.booted = true
	for kind in result.KINDS: result.templates[kind] = result.model.defaults(kind)
	root.add_child(result)
	return result

func press(point: Vector2, down: bool = true) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = point
	interior.view_container.gui_input.emit(event)

func motion(point: Vector2, mask: int = 0, relative := Vector2.ZERO) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.relative = relative
	event.button_mask = mask
	interior.view_container.gui_input.emit(event)

func body_pixel(id: int) -> Vector2:
	var visual: Node3D = interior.equipment_nodes[id]
	var bounds: AABB = visual.get_meta("pick_bounds")
	return interior.camera.unproject_position(visual.to_global(bounds.get_center())) * interior.view_container.size / Vector2(interior.viewport.size)

func floor_pixel(point: Vector2) -> Vector2:
	return interior.camera.unproject_position(Vector3(point.x, 0, point.y)) * interior.view_container.size / Vector2(interior.viewport.size)

func begin_drag(id: int, target: Vector2) -> Vector2:
	# V23 keeps device placement gestures in the explicit Move tool.
	interior._select(id)
	interior._start_move()
	var start := body_pixel(id)
	press(start)
	var item: Dictionary = host.device(id)
	var origin := Vector2(float(item.interior_x), float(item.interior_z))
	var grab: Vector2 = interior.floor_at(start)
	var finish := floor_pixel(grab + target - origin)
	motion(finish, MOUSE_BUTTON_MASK_LEFT, finish - start)
	return finish

func invariant(before: PackedByteArray, undo_count: int, label: String) -> void:
	check(var_to_bytes(host.state()) == before and host.undo_states.size() == undo_count, label)

func run() -> void:
	root.size = Vector2i(1440, 900)
	root.gui_embed_subwindows = true
	host = fixture()
	check(host.add_station(Vector2.ZERO, false), "empty station constructed")
	interior = Interior.new()
	host.add_child(interior)
	host.station_interior = interior
	interior.setup(host)
	check(interior.open_station(SITE), "empty station opens")
	await settle()
	check(interior.INTERNAL_KINDS.count("fuel_boiler") == 1 and interior.tools.has("fuel_boiler"), "exactly one new fuel construction kind")
	check(interior.tools.fuel_boiler.text.contains("燃气热水锅炉"), "recognizable Chinese fuel build button")
	var empty := var_to_bytes(host.state())
	interior.tools.fuel_boiler.pressed.emit()
	motion(floor_pixel(Vector2(-1.2, -0.8)))
	check(interior.interaction_mode == "build" and is_instance_valid(interior.preview), "fuel build uses native placement preview")
	check(interior.status_label.text.contains("占地半径") and interior.status_label.text.contains("米"), "fuel construction explains metric footprint")
	interior._cancel_current_interaction()
	invariant(empty, 0, "fuel build cancel preserves authoritative state")
	interior.start_build("fuel_boiler")
	interior._click_floor(Vector2(-1.2, -0.8))
	check(host.devices.size() == 1 and host.device(FUEL).kind == "fuel_boiler", "fuel placement creates one authoritative device")
	check(host.undo_states.size() == 1 and host.device(FUEL).parent_station_id == SITE, "fuel placement creates one undo and correct membership")
	interior.set_interaction_mode("select")
	interior.undo_edit()
	invariant(empty, 0, "fuel construction undo restores empty station")
	check(host.add_internal_device(SITE, "fuel_boiler", Vector2(-1.2, -0.8)), "rebuild first fuel boiler")
	check(host.add_internal_device(SITE, "thermal_store", Vector2(0.8, -0.6)), "build thermal store")
	check(host.add_internal_device(SITE, "heat_exchanger", Vector2(0, 1.0)), "build exchanger")
	check(host.add_internal_device(SITE, "fuel_boiler", Vector2(-1.2, 1.2)), "build second independent fuel boiler")
	check(host.add_equipment("station", Vector2(-15, 0), false), "build external AC station")
	if host.devices.size() != 5:
		print("FUEL_STATION fixture failed; stopping dependent checks")
		cleanup(host)
		quit(1)
		return
	host.device(STORE).state.energy_mwhth = 1.25
	host.elapsed_s = 4321.0
	host.undo_states.clear()
	interior.refresh()
	interior.reset_camera()
	await settle()
	for port_id in ["ac_in", "heat_out"]:
		check(interior.equipment_nodes[FUEL].has_named_port(port_id), "fuel visual exposes named port " + port_id)
		check(not Catalog.port("fuel_boiler", port_id).is_empty(), "catalog agrees on fuel port " + port_id)
	check(not interior.equipment_nodes[FUEL].has_named_port("fuel_in"), "shared fuel supply is not an invented fuel-stock link")
	check(interior._connection_candidate(FUEL, STORE).get("to_port") == "heat_in", "fuel connects to primary store input")
	check(interior._connection_candidate(HX, FUEL).get("from") == FUEL, "reverse fuel/exchanger click retains canonical direction")
	check(interior._connection_candidate(FUEL, FUEL_2).is_empty(), "boiler-to-boiler heat link rejected")
	interior.set_interaction_mode("connect")
	interior._click_device(HX)
	check(interior.equipment_nodes[FUEL].compatible_target and interior.equipment_nodes[FUEL_2].compatible_target, "both fuel boilers become compatible upstream choices")
	motion(body_pixel(FUEL))
	check(interior.connection_help.text.contains("AC 辅机") and interior.connection_help.text.contains("1.800 MWth"), "fuel hover explains auxiliary input and thermal rating on connection tab")
	interior._click_device(FUEL)
	check(host.links.size() == 1 and int(host.links[0].from) == FUEL and int(host.links[0].to) == HX, "reverse scene clicks commit valid fuel heat connection")
	check(host.connect_internal_devices(FUEL, STORE), "fuel may also feed store through canonical controller")
	for id in [FUEL, FUEL_2]:
		var edge: Dictionary = host.connection_candidate(AC, id)
		check(edge.get("to_port") == "ac_in" and edge.get("carrier") == "electricity_ac", "external AC maps to individual fuel auxiliary input")
		host.links.append(edge)
	host.station_port_dialog = ConfirmationDialog.new()
	host.station_port_picker = OptionButton.new()
	host.station_port_dialog.add_child(host.station_port_picker)
	host.add_child(host.station_port_dialog)
	host.mode = "link"
	host.pending_link = AC
	host.choose_station_port(SITE)
	check(host.station_port_picker.item_count == 2, "facade boundary picker exposes both fuel auxiliary inputs")
	var mapped: Array[int] = []
	for index in host.station_port_picker.item_count:
		mapped.append(int(host.station_port_picker.get_item_metadata(index)))
		check(host.station_port_picker.get_item_text(index).contains("燃气"), "boundary entry distinguishes fuel auxiliary AC")
	check(mapped.has(FUEL) and mapped.has(FUEL_2), "boundary entries preserve separate device IDs")
	host.station_port_dialog.hide()
	host.mode = "select"
	host.refresh()
	interior.refresh()
	check(interior.connections_root.has_node("ACCable_%d_%d" % [AC, FUEL]) and interior.connections_root.has_node("ACCable_%d_%d" % [AC, FUEL_2]), "interior renders both incoming auxiliary AC cables")
	check(interior.input_ports_label.text.contains("#0 燃气辅机 ac_in") and interior.input_ports_label.text.contains("#3 燃气辅机 ac_in"), "mapping sidebar identifies both boiler inputs")
	await test_parameters()
	test_readouts()
	await test_small_windows()
	await test_gesture_cancel_and_undo()
	test_save()
	interior.close_station()
	cleanup(host)
	await process_frame
	print("FUEL_STATION checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func test_parameters() -> void:
	var form := Form.new()
	form.theme = interior.theme
	root.add_child(form)
	form.size = Vector2(760, 320)
	var original: Dictionary = host.device(FUEL).params.duplicate(true)
	form.set_parameters("fuel_boiler", original, false)
	check(form._fields.size() == 3 and form.get_parameters() == original, "fuel editor covers exact three-field contract")
	check(form.get_validation_errors().is_empty(), "fuel defaults validate in form")
	for key in ["rated_fuel_mw", "thermal_efficiency", "auxiliary_electric_ratio"]:
		check(form._fields.has(key) and not form._fields[key].get_meta("parameter_note").is_empty(), "fuel parameter has explanation " + key)
	check(form._fields.rated_fuel_mw.get_meta("parameter_unit") == "MW(LHV)", "fuel rating unit explicitly LHV")
	check(form._fields.auxiliary_electric_ratio.tooltip_text.contains("不是热输出比例"), "auxiliary denominator explicit")
	form._fields.auxiliary_electric_ratio.text = "0"
	check(not form.get_validation_errors().is_empty(), "zero auxiliary ratio rejected visibly")
	form._fields.rated_fuel_mw.text = "3.0"
	check(host.device(FUEL).params == original, "unapplied parameter draft does not mutate device")
	form.set_parameters("fuel_boiler", original, false)
	await settle()
	check(form._groups.get_child_count() == 3, "fuel editor separates device, auxiliary and shared resource groups")
	check(form._scroll.size.y < form._groups.size.y and not form._scroll.get_h_scroll_bar().visible, "all fuel parameter groups reachable by vertical scrolling")
	check(form._groups.size.x <= form._scroll.size.x, "fuel groups do not require horizontal scrolling")
	form._scroll.scroll_vertical = int(form._groups.size.y)
	await settle()
	var final_group: Control = form._groups.get_child(2)
	check(form._scroll.get_global_rect().intersects(final_group.get_global_rect()), "shared resource explanation reachable at bottom")
	form.queue_free()
	# The production host dialog owns cancellation, application and undo.
	host.make_parameter_dialog(interior.theme)
	interior._select(FUEL)
	var saved := var_to_bytes(host.state())
	var history := host.undo_states.size()
	interior._open_parameters()
	check(host.param_dialog.visible and host.parameter_kind() == "fuel_boiler", "station parameter command opens selected fuel boiler")
	host.parameter_form._fields.rated_fuel_mw.text = "1.5"
	host.param_dialog.hide()
	invariant(saved, history, "closing fuel parameter draft leaves model unchanged")
	interior._open_parameters()
	check(host.parameter_form.get_parameters() == original, "reopening fuel parameters discards canceled draft")
	host.parameter_form._fields.rated_fuel_mw.text = "1.5"
	host.apply_parameters()
	check(host.device(FUEL).params.rated_fuel_mw == 1.5 and host.undo_states.size() == history + 1, "valid fuel parameter apply checkpoints one device edit")
	check(host.device(FUEL_2).params == original and host.templates.fuel_boiler == original, "fuel edit leaves other boiler and future template unchanged")
	interior.set_interaction_mode("select")
	interior.undo_edit()
	invariant(saved, history, "fuel parameter undo restores resource and device state")
	await settle()

func test_readouts() -> void:
	# Deliberately distinct report numbers expose accidentally reused heat/electric
	# fields. This presentation-only fixture does not claim a real dispatch result.
	host.result.devices[str(FUEL)] = {"fuel_input_mw": 1.1, "heat_output_mwth": 0.99, "conversion_loss_mw": 0.11, "auxiliary_electric_mw": 0.011, "auxiliary_electric_loss_mw": 0.011, "fuel_volume_nm3_per_h": 110.0, "fuel_cost_per_h": 330.0}
	interior._select(FUEL)
	for text in ["燃料输入 1.100 MW(LHV)", "热输出 0.990 MWth", "燃料转换散失 0.110 MW", "辅机用电 0.011 MW", "辅机电散失 0.011 MW", "燃气体积 110.00 Nm³/h", "燃料成本 330.00 元/h", "占地半径", "共享天然气供应已关闭"]:
		check(interior.selected_label.text.contains(text), "selected fuel readout includes " + text)
	check(interior.summary_label.text.contains("天然气 1.100 MW(LHV)") and interior.summary_label.text.contains("燃料成本 330.00 元/h"), "station summary includes fuel without folding it into electricity")
	check(interior.summary_label.text.contains("AC 输入 0.01100 MW") and interior.summary_label.text.contains("热源出热 0.9900 MWth"), "station totals include fuel auxiliary input and heat exactly once")
	host.refresh()
	interior.refresh()

func test_small_windows() -> void:
	var before := var_to_bytes(host.state())
	var history := host.undo_states.size()
	for physical in [Vector2i(1024, 768), Vector2i(1440, 900)]:
		root.size = physical
		interior.size = Vector2i(mini(1320, physical.x - 48), mini(850, physical.y - 48))
		interior._fit_to_parent_window()
		await settle()
		var area := Rect2(Vector2.ZERO, Vector2(interior.size)).grow(1)
		for node_name in ["StationBuildToolbar", "StationEditToolbar"]:
			var row: Control = interior.find_child(node_name, true, false)
			check(row is HFlowContainer, "responsive fuel toolbar retained " + node_name)
			for child in row.get_children():
				if child is Button:
					check(child.is_visible_in_tree() and area.encloses(child.get_global_rect()), "small-window command reachable " + str(child.name))
		check(area.encloses(interior.status_label.get_global_rect()) and interior.view_container.size.y >= 320, "fuel toolbar retains usable viewport and visible status")
		for tab in 2:
			interior.sidebar_tabs.current_tab = tab
			await settle()
			var page: ScrollContainer = interior.sidebar_tabs.get_child(tab)
			check(area.encloses(page.get_global_rect()) and not page.get_h_scroll_bar().visible, "fuel sidebar tab remains bounded and vertically scrollable")
		check(interior.sidebar_tabs.get_theme_stylebox("panel").bg_color == Color("14212b"), "dark readable sidebar preserved")
	invariant(before, history, "responsive layout does not edit fuel resources or station")
	interior.sidebar_tabs.current_tab = 0

func test_gesture_cancel_and_undo() -> void:
	interior._select(FUEL)
	interior.set_interaction_mode("select")
	interior.reset_camera()
	await settle()
	var before := var_to_bytes(host.state())
	var history := host.undo_states.size()
	var finish := begin_drag(FUEL, Vector2(-1.2, -1.6))
	check(interior._move_drag_active and is_instance_valid(interior.preview), "fuel body uses native drag preview")
	interior.size -= Vector2i(8, 8)
	await settle()
	press(finish, false)
	check(not interior._move_drag_active and not is_instance_valid(interior.preview), "resize cancels fuel drag and stale release")
	invariant(before, history, "resize cancellation preserves fuel state and undo stack")
	finish = begin_drag(FUEL, Vector2(-1.2, -1.6))
	interior._cancel_current_interaction()
	press(finish, false)
	invariant(before, history, "explicit cancel prevents fuel drag commit")
	# A bounded successful click move shares the same placement/undo API.
	interior._select(FUEL)
	interior._start_move()
	interior._click_floor(Vector2(-1.2, -1.6))
	check(host.undo_states.size() == history + 1 and is_equal_approx(host.device(FUEL).interior_z, -1.6), "fuel move commits once")
	interior.undo_edit()
	invariant(before, history, "fuel move undo restores resources, links, inventory and clock")
	check(interior.visible and interior.selected_id == FUEL, "fuel undo preserves open station and selection")

func test_save() -> void:
	host.fuel_supply = {"enabled": true, "max_input_mw": 2.5, "lower_heating_value_kwh_per_nm3": 10.0, "price_per_mwh": 300.0}
	host.refresh()
	var saved := host.state()
	check(saved.schema == 12 and host.validate_state(saved).is_empty(), "fuel station saves valid schema 12")
	var path := "user://fuel_station_test/%d.json" % OS.get_process_id()
	check(host.write_save(path), "fuel station save written")
	var restored := fixture()
	check(restored.read_save(path), "fuel station save reads back: " + restored.last_notice)
	check(restored.dimension_profile == "metric_v1" and JSON.stringify(restored.devices) == JSON.stringify(JSON.parse_string(JSON.stringify(host.devices))) and JSON.stringify(restored.links) == JSON.stringify(JSON.parse_string(JSON.stringify(host.links))), "fuel save preserves metric device parameters, layout and ports")
	check(restored.fuel_supply == host.fuel_supply and restored.fuel_energy == host.fuel_energy, "shared fuel resource and ledger round-trip independently of devices")
	check(restored.device(STORE).state.energy_mwhth == 1.25 and restored.elapsed_s == 4321.0, "fuel save preserves thermal inventory and simulation clock")
	DirAccess.remove_absolute(path)
	cleanup(restored)

func cleanup(game: Host) -> void:
	for property in ["camera", "lod_camera", "terrain", "labels", "infrastructure", "selection", "overlay", "equipment", "cables", "confirmation", "param_dialog", "param_errors", "param_target", "data_dialog", "data_list", "line_dialog", "line_capacity", "line_loss", "line_choice", "station_port_dialog", "station_port_picker"]:
		var node = game.get(property)
		if is_instance_valid(node) and node.get_parent() == null: node.free()
	game.queue_free()
