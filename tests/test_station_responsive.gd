extends SceneTree
## Bounded station UI checks: geometry at two supported screen sizes, connection
## direction, and repeated interrupted input with the authoritative host unchanged.
const Interior = preload("res://scripts/station_interior.gd")
const ControllerTest = preload("res://tests/test_station_controller.gd")
const SITE := 1000000

class Host:
	extends ControllerTest.Fixture
	func _process(_delta: float) -> void: pass

var checks := 0
var failures: Array[String] = []
var host: Host
var interior

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL ", message)

func _initialize() -> void: call_deferred("run")

func settle() -> void:
	for index in 4: await process_frame

func body_pixel(id: int) -> Vector2:
	var visual: Node3D = interior.equipment_nodes[id]
	var bounds: AABB = visual.get_meta("pick_bounds")
	return interior.camera.unproject_position(visual.to_global(bounds.get_center())) * interior.view_container.size / Vector2(interior.viewport.size)

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

func begin_drag() -> Vector2:
	var start := body_pixel(0)
	press(start)
	var end := start + Vector2(40, 30)
	motion(end, MOUSE_BUTTON_MASK_LEFT, end - start)
	return end

func invariant_state(before: PackedByteArray, message: String) -> void:
	check(var_to_bytes(host.state()) == before and host.undo_states.is_empty(), message)

func check_layout(label: String) -> void:
	var window_rect := Rect2(Vector2.ZERO, Vector2(interior.size)).grow(1)
	check(interior.size.x <= root.size.x and interior.size.y <= root.size.y - 24, label + ": station fits parent with title bar clearance")
	check(interior.position.x >= 0 and interior.position.y >= 24 and interior.position.x + interior.size.x <= root.size.x and interior.position.y + interior.size.y <= root.size.y, label + ": complete window stays inside parent")
	check(interior.view_container.size.x >= 540 and interior.view_container.size.y >= 320, label + ": useful viewport retained")
	check(window_rect.encloses(interior.view_container.get_global_rect()), label + ": viewport does not push outside station")
	check(window_rect.encloses(interior.status_label.get_global_rect()), label + ": status remains visible below viewport")
	check(interior.status_label.tooltip_text == interior.status_label.text, label + ": complete long status accessible by tooltip")
	check(interior.title_label.clip_text and interior.title_label.tooltip_text == interior.title_label.text, label + ": long title bounded with full tooltip")
	var commands: Array[Control] = []
	for node_name in ["StationBuildToolbar", "StationEditToolbar"]:
		var row: Control = interior.find_child(node_name, true, false)
		check(row is HFlowContainer, label + ": responsive command group " + node_name)
		for child in row.get_children():
			if child is Button: commands.append(child)
	for command in commands:
		check(command.is_visible_in_tree() and command.size.y >= 34 and window_rect.encloses(command.get_global_rect()), label + ": reachable command " + str(command.name))
		for other in commands:
			if command.get_index() == other.get_index() and command.get_parent() == other.get_parent(): continue
			check(not command.get_global_rect().intersects(other.get_global_rect()), label + ": commands do not overlap " + str(command.name) + "/" + str(other.name))
	for node_name in ["StationOverviewScroll", "StationConnectionsScroll"]:
		var scroll: ScrollContainer = interior.find_child(node_name, true, false)
		check(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED and not scroll.get_h_scroll_bar().visible, label + ": sidebar has no horizontal scrolling " + node_name)
		if scroll.is_visible_in_tree():
			check(window_rect.encloses(scroll.get_global_rect()), label + ": active sidebar stays within window")
			check(scroll.get_child(0).size.x <= scroll.size.x, label + ": sidebar content cannot grow wider than its viewport")
	check(interior.sidebar_tabs.size.x >= 300 and interior.sidebar_tabs.size.x <= 350, label + ": sidebar width stays readable and bounded")
	check(not interior.view_container.get_global_rect().intersects(interior.sidebar_tabs.get_global_rect()), label + ": sidebar never overlaps scene")

func run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1440, 900)
	root.gui_embed_subwindows = true
	host = Host.new()
	host.cfg = {"max_build_slope_degrees": 8.0}
	host.dimension_profile = "metric_v1"
	host.booted = true
	for kind in host.KINDS: host.templates[kind] = host.model.defaults(kind)
	root.add_child(host)
	check(host.add_station(Vector2.ZERO, false), "fixture station created")
	for spec in [["electric_boiler", Vector2(-1.2, -0.8)], ["thermal_store", Vector2(0.8, -0.6)], ["heat_exchanger", Vector2(0, 1.0)]]:
		check(host.add_internal_device(SITE, spec[0], spec[1]), "fixture device " + spec[0])
	host.station(SITE).name = "东部综合能源基地电热储能站 · 长名称响应式检查"
	host.device(1).state.energy_mwhth = 1.25
	host.elapsed_s = 4321.0
	host.undo_states.clear()
	interior = Interior.new()
	host.add_child(interior)
	host.station_interior = interior
	interior.setup(host)
	check(interior.open_station(SITE), "station opens")
	await settle()
	interior._select(1)
	var original := var_to_bytes(host.state())
	var camera_before: Transform3D = interior.camera.transform
	for target in [Vector2i(1024, 768), Vector2i(1440, 900), Vector2i(1024, 768), Vector2i(1440, 900)]:
		root.size = target
		await settle()
		interior.size = Vector2i(mini(1320, target.x - 48), mini(850, target.y - 48))
		interior._fit_to_parent_window()
		await settle()
		for tab in 2:
			interior.sidebar_tabs.current_tab = tab
			await settle()
			check_layout(str(target) + " tab " + str(tab))
		interior.sidebar_tabs.current_tab = 0
		check(interior.selected_id == 1 and interior.camera.transform.is_equal_approx(camera_before), "resize and tab switches preserve selection and camera")
		invariant_state(original, "resize and tab switches preserve metric state, inventory and clock")
	check(interior.selected_label.text.contains("1.250 / 4.000 MWhth") and interior.selected_label.text.contains("SOC %.1f%%" % (1.25 / 4.0 * 100.0)), "selected device retains readable live inventory and SOC")
	check(interior.selected_label.text.contains("充热 0.000 MWth\n放热 0.000 MWth"), "charge/discharge each have their own explicit unit")
	check(interior.sidebar_tabs.get_theme_stylebox("panel").bg_color == Color("14212b") and interior.sidebar_tabs.get_theme_color("font_selected_color") == Color("edf3f6"), "sidebar theme keeps dark surface and bright readable tab text")
	check(interior.find_child("InternalLinkSourceLabel", true, false).text.contains("起点") and interior.find_child("InternalLinkTargetLabel", true, false).text.contains("终点"), "connection dropdown direction explicitly labelled")
	for index in 3:
		interior.set_interaction_mode("connect")
		check(interior.sidebar_tabs.current_tab == 1, "connect opens the relevant sidebar page")
		interior._click_device(2)
		check(interior.connection_help.text.contains("终点已选") and interior.connection_help.text.contains("绿色起点"), "reverse-order connection identifies exchanger as target")
		check(interior.name_labels[2].text.contains("终点已选") and interior.name_labels[0].text.contains("可作起点"), "scene labels distinguish canonical start from first click")
		motion(body_pixel(0))
		check(interior.connection_help.is_visible_in_tree() and interior.connection_help.text.contains("AC 电输入") and interior.connection_help.text.contains("1.960 MWth") and interior.connection_help.text.contains("#0.heat_out → #2.hot_in"), "active connection tab mirrors live hover carrier, capacity and canonical direction")
		interior.view_container.mouse_exited.emit()
		check(not interior.connection_help.text.contains("悬停 #"), "leaving scene clears stale hover details from connection tab")
		interior._cancel_current_interaction()
		check(interior.pending_link == -1 and interior.sidebar_tabs.current_tab == 0 and interior.visible, "cancel clears endpoint and restores overview without closing")
		interior._cancel_current_interaction()
		interior._cancel_current_interaction()
		check(interior.selected_id == -1 and interior.visible, "repeated cancel is safe with no active selection")
		invariant_state(original, "repeated reverse preview/cancel does not add links or checkpoints")
	interior._select_choice(interior.link_from, 1)
	interior._select_choice(interior.link_to, 1)
	interior._sync_connection_help()
	check(interior.connect_button.disabled and interior.connection_help.text.contains("自身"), "self-link disables submission and explains why")
	interior._select_choice(interior.link_to, 2)
	interior._sync_connection_help()
	check(not interior.connect_button.disabled and interior.connection_help.text.contains("#1.heat_out → #2.hot_in"), "valid dropdown pair previews actual canonical ports")
	for index in 3:
		interior._select(0)
		var finish := begin_drag()
		check(interior._move_drag_active and is_instance_valid(interior.preview), "real move preview starts before resize")
		interior.size -= Vector2i(8, 8)
		await settle()
		check(not interior._move_drag_active and not is_instance_valid(interior.preview) and interior.interaction_mode == "select", "resize cancels drag atomically")
		check(interior.status_label.text.contains("尺寸改变") and interior.status_label.text.contains("保留原位"), "resize cancellation explains preserved position")
		press(finish, false)
		invariant_state(original, "late release after resize never commits or creates undo")
	interior._orbit_drag = true
	interior._pan_drag = true
	interior.size -= Vector2i(8, 8)
	await settle()
	check(not interior._orbit_drag and not interior._pan_drag, "resize discards stale camera mouse gestures")
	camera_before = interior.camera.transform
	motion(body_pixel(1), MOUSE_BUTTON_MASK_RIGHT, Vector2(80, 60))
	check(interior.camera.transform.is_equal_approx(camera_before), "stale held mouse cannot continue orbit after resize")
	interior.start_build("electric_boiler")
	motion(interior.view_container.size * 0.5)
	check(is_instance_valid(interior.preview), "build preview starts")
	interior.size -= Vector2i(8, 8)
	await settle()
	check(interior.interaction_mode == "build" and not is_instance_valid(interior.preview), "resize clears stale build ghost while keeping chosen construction tool")
	interior._cancel_current_interaction()
	invariant_state(original, "all interrupted input preserves topology, meter dimensions, inventory and time")
	for index in 2:
		interior.close_station()
		check(interior.open_station(SITE), "repeated reopen succeeds")
		await settle()
		check(interior.sidebar_tabs.current_tab == 0 and interior.pending_link == -1 and interior.selected_id == -1, "reopen clears transient tabs/endpoint/selection")
		invariant_state(original, "reopen has no simulation side effect")
	# Match the real game's fixed logical canvas. The parent physically shrinks,
	# but an embedded popup must not be shrunk again in logical coordinates.
	root.content_scale_size = Vector2i(1600, 1000)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	for physical_size in [Vector2i(1440, 900), Vector2i(1024, 768), Vector2i(1440, 900)]:
		root.size = physical_size
		interior.close_station()
		check(interior.open_station(SITE), "scaled parent opens station")
		# Headless DisplayServer clamps popup_centered to min_size because its
		# usable monitor rectangle is empty. Native popup opening is checked by
		# rendered QA; this fixture verifies the real logical resize path.
		if DisplayServer.get_name() == "headless": interior.size = Vector2i(1320, 850)
		interior._fit_to_parent_window()
		await settle()
		var logical_size := root.get_visible_rect().size
		check(logical_size.is_equal_approx(Vector2(1600, 1000)), "real canvas-items setup uses 1600 × 1000 logical coordinates")
		check(interior.size == Vector2i(1320, 850), "logical resize path does not double-shrink station")
		var rendered_size: Vector2 = root.get_final_transform().basis_xform(Vector2(interior.size))
		check(rendered_size.x > physical_size.x * 0.80 and rendered_size.x < physical_size.x, "rendered station keeps useful width on physical display " + str(physical_size))
		check(rendered_size.y > physical_size.y * 0.65 and rendered_size.y < physical_size.y, "rendered station fits display while retaining useful height")
		check(Rect2(Vector2.ZERO, logical_size).encloses(Rect2(Vector2(interior.position), Vector2(interior.size))), "scaled popup fits logical parent")
		interior._select(0)
		var late_release := begin_drag()
		check(interior._move_drag_active, "scaled-parent drag begins")
		root.size -= Vector2i(1, 1)
		await settle()
		check(not interior._move_drag_active and not is_instance_valid(interior.preview), "physical root resize cancels gesture even when logical popup does not resize")
		press(late_release, false)
		invariant_state(original, "scaled resize and delayed release preserve authoritative state")
	interior.close_station()
	for property in ["camera", "lod_camera", "terrain", "labels", "infrastructure", "selection", "overlay", "equipment", "cables", "confirmation", "param_dialog", "param_errors", "param_target", "data_dialog", "data_list", "line_dialog", "line_capacity", "line_loss", "line_choice"]:
		var node = host.get(property)
		if is_instance_valid(node) and node.get_parent() == null: node.free()
	host.queue_free()
	await process_frame
	print("STATION_RESPONSIVE checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
