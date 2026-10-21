extends SceneTree
## UI gestures exercise the real authoritative controller, checkpoint and undo.
## The fixture suppresses terrain/UI plumbing, not placement or model rules.
const Interior = preload("res://scripts/station_interior.gd")
const ControllerTest = preload("res://tests/test_station_controller.gd")

class Host:
	extends ControllerTest.Fixture
	func _process(_delta: float) -> void: pass

var checks := 0
var failures: Array[String] = []
var host: Host
var interior
const SITE := 1000000

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL ", message)

func _initialize() -> void: call_deferred("run")

func press(position: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT, down: bool = true) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = down
	event.position = position
	interior.view_container.gui_input.emit(event)

func motion(position: Vector2, mask: int = 0, relative := Vector2.ZERO) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.button_mask = mask
	event.relative = relative
	interior.view_container.gui_input.emit(event)

func escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	interior.window_input.emit(event)

func undo_shortcut(command_key: bool = false) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_Z
	event.pressed = true
	event.meta_pressed = command_key
	event.ctrl_pressed = not command_key
	interior.window_input.emit(event)

func body_pixel(id: int) -> Vector2:
	var visual: Node3D = interior.equipment_nodes[id]
	var bounds: AABB = visual.get_meta("pick_bounds")
	return interior.camera.unproject_position(visual.to_global(bounds.get_center())) * interior.view_container.size / Vector2(interior.viewport.size)

func floor_pixel(point: Vector2) -> Vector2:
	return interior.camera.unproject_position(Vector3(point.x, 0, point.y)) * interior.view_container.size / Vector2(interior.viewport.size)

func begin_drag(id: int, target: Vector2) -> Vector2:
	var start := body_pixel(id)
	press(start)
	var item: Dictionary = host.device(id)
	var origin := Vector2(float(item.interior_x), float(item.interior_z))
	var grab: Vector2 = interior.floor_at(start)
	var finish := floor_pixel(grab + target - origin)
	motion(finish, MOUSE_BUTTON_MASK_LEFT, finish - start)
	return finish

func invariant_state(before: Dictionary, message: String) -> void:
	check(var_to_bytes(host.state()) == var_to_bytes(before), message)

func run() -> void:
	root.size = Vector2i(1440, 900)
	root.gui_embed_subwindows = true
	host = Host.new()
	host.cfg = {"max_build_slope_degrees":8.0}
	host.dimension_profile = "metric_v1"
	host.booted = true
	for kind in host.KINDS: host.templates[kind] = host.model.defaults(kind)
	root.add_child(host)
	check(host.add_station(Vector2.ZERO, false), "fixture station is authoritative")
	for spec in [["electric_boiler", Vector2(-1.2, -0.8)], ["thermal_store", Vector2(0.8, -0.6)], ["heat_exchanger", Vector2(0, 1.0)]]:
		check(host.add_internal_device(SITE, spec[0], spec[1]), "fixture exact metric placement " + spec[0])
	host.device(1).state.energy_mwhth = 1.25
	host.elapsed_s = 4321.0
	host.undo_states.clear()
	interior = Interior.new()
	host.add_child(interior)
	host.station_interior = interior
	interior.setup(host)
	check(interior.open_station(SITE), "metric interior opens")
	await process_frame
	await process_frame
	var original := host.state()
	var camera_before: Transform3D = interior.camera.transform
	motion(body_pixel(0))
	check(interior.hovered_id == 0 and interior.equipment_nodes[0].hovered and interior.equipment_nodes[0].selection_ring.visible, "hover immediately highlights the hovered body")
	check(interior.name_labels[0].visible and not interior.name_labels[2].visible, "hover reveals only relevant name labels")
	var title_node: Label3D = interior.name_labels[0]
	var nominal_height: float = title_node.pixel_size * title_node.font_size * interior.viewport.get_visible_rect().size.y * absf(interior.camera.get_camera_projection().y.y) * 0.5
	check(title_node.fixed_size and is_equal_approx(nominal_height, 22.0), "station-owned labels use projection-normalized 22px screen sizing")
	check(interior.hover_label.text.contains("AC") and interior.hover_label.text.contains("90/60°C") and interior.hover_label.text.contains("1.960 MWth"), "boiler hover explains carrier, direction, grade and derived thermal capacity")
	press(body_pixel(0)); press(body_pixel(0), MOUSE_BUTTON_LEFT, false)
	check(interior.selected_id == 0 and interior.equipment_nodes[0].get_meta("interaction_highlight") == "selected", "click selects with persistent highlight")
	check(interior.camera.transform.is_equal_approx(camera_before), "selection does not unexpectedly reframe the camera")
	interior.find_child("FocusInternalSelection", true, false).pressed.emit()
	check(is_equal_approx(interior.camera_target.x, -1.2) and is_equal_approx(interior.camera_target.z, -0.8), "Focus centres only the selected equipment")
	check(interior.camera_distance >= interior.MIN_CAMERA_DISTANCE * interior.visual_scale and interior.camera_pitch >= interior.MIN_CAMERA_PITCH, "Focus respects the same safe zoom and elevation limits")
	interior.find_child("ResetInteriorView", true, false).pressed.emit()
	check(interior.selected_id == 0 and not is_equal_approx(interior.camera_target.x, -1.2), "Panorama restores full-station framing without clearing selection")
	invariant_state(original, "hover, select, focus and panorama preserve saved state")
	var finish := begin_drag(0, Vector2(-1.2, 0.4))
	check(interior._move_drag_active and is_instance_valid(interior.preview), "body drag starts a separate placement ghost")
	check(interior.preview.preview_valid and Vector2(interior.preview.position.x, interior.preview.position.z).is_equal_approx(Vector2(-1.2, 0.4)), "drag ghost preserves body grab offset and two-metre grid")
	check(interior.equipment_nodes[0].position.is_equal_approx(Vector3(-1.2, 0, -0.8)), "original visual stays in its committed position during preview")
	invariant_state(original, "drag motion has no saved-state effects before release")
	check(host.undo_states.is_empty(), "drag preview creates no undo checkpoints")
	for index in 5: interior.refresh()
	invariant_state(original, "repeated runtime refresh during drag does not commit a position")
	press(finish, MOUSE_BUTTON_LEFT, false)
	check(Vector2(host.device(0).interior_x, host.device(0).interior_z).is_equal_approx(Vector2(-1.2, 0.4)), "valid release commits the preview location")
	check(host.undo_states.size() == 1, "one successful gesture creates exactly one real undo snapshot")
	press(finish, MOUSE_BUTTON_LEFT, false)
	check(host.undo_states.size() == 1, "duplicate release cannot create another move or checkpoint")
	check(host.device(1).state.energy_mwhth == 1.25 and host.elapsed_s == 4321.0 and host.devices.size() == 3 and host.dimension_profile == "metric_v1", "drag preserves stock, time, count and scale")
	var undo_camera: Transform3D = interior.camera.transform
	var undo_target: Vector3 = interior.camera_target
	undo_shortcut()
	invariant_state(original, "Ctrl+Z uses real host undo and restores the full pre-drag state")
	check(interior.visible and interior.station_id == SITE and interior.selected_id == 0, "Ctrl+Z reopens the same station and preserves surviving selection")
	check(interior.camera.transform.is_equal_approx(undo_camera) and interior.camera_target.is_equal_approx(undo_target), "Ctrl+Z preserves exact station view and camera target")
	check(root.disable_3d and host.paused, "undo keeps base rendering suspended and respects authoritative paused restore")
	await process_frame
	# Collision and boundary failures never call host move/checkpoint.
	finish = begin_drag(0, Vector2(0.8, -0.6))
	check(not interior.preview.preview_valid and not str(interior.preview.get_meta("placement_error")).is_empty(), "overlapping preview is invalid with an explicit reason")
	press(finish, MOUSE_BUTTON_LEFT, false)
	check(interior.interaction_mode == "select" and interior.status_label.text.contains("保留原位"), "invalid drop returns to selection and explains the preserved original")
	invariant_state(original, "overlap drop is atomic")
	check(host.undo_states.is_empty(), "overlap drop creates no undo snapshot")
	finish = begin_drag(0, Vector2(-2.4, 0))
	press(finish, MOUSE_BUTTON_LEFT, false)
	check(interior.status_label.text.contains("边界"), "boundary failure provides the authoritative reason")
	invariant_state(original, "out-of-bounds drop leaves state intact")
	# Escape, viewport exit, dropped mouse-up, and tool switching cancel ghosts.
	finish = begin_drag(0, Vector2(-1.2, 0.4))
	escape()
	check(interior.visible and interior.interaction_mode == "select" and interior.selected_id == 0 and not is_instance_valid(interior.preview), "first Escape cancels drag but retains selection")
	press(finish, MOUSE_BUTTON_LEFT, false)
	invariant_state(original, "release after Escape never commits stale preview")
	escape()
	check(interior.visible and interior.selected_id == -1, "second Escape clears selection and keeps station open")
	escape()
	check(not interior.visible and not root.disable_3d, "third Escape closes station and restores base rendering")
	interior.open_station(SITE)
	await process_frame
	finish = begin_drag(0, Vector2(-1.2, 0.4))
	interior.view_container.mouse_exited.emit()
	press(finish, MOUSE_BUTTON_LEFT, false)
	check(not interior._move_drag_active and not is_instance_valid(interior.preview), "leaving viewport cancels active drag and ghost")
	invariant_state(original, "dragging over UI cannot commit device movement")
	finish = begin_drag(0, Vector2(-1.2, 0.4))
	motion(finish, 0)
	check(not interior._move_drag_active and interior.interaction_mode == "select", "lost release/button mask cancels gesture instead of leaving stuck drag")
	invariant_state(original, "lost-release cancellation preserves state")
	finish = begin_drag(0, Vector2(-1.2, 0.4))
	interior.set_interaction_mode("connect")
	press(finish, MOUSE_BUTTON_LEFT, false)
	check(not is_instance_valid(interior.preview) and not interior._move_drag_active, "changing tools discards the drag ghost")
	invariant_state(original, "tool change then release cannot commit a stale move")
	interior.set_interaction_mode("select")
	finish = begin_drag(0, Vector2(-1.2, 0.4))
	interior.focus_exited.emit()
	press(finish, MOUSE_BUTTON_LEFT, false)
	check(not interior._move_drag_active and not is_instance_valid(interior.preview), "focus loss cancels ghost and pointer capture")
	invariant_state(original, "focus loss and delayed release are atomic")
	finish = begin_drag(0, Vector2(-1.2, 0.4))
	var original_pixel := floor_pixel(interior._move_drag_grab)
	motion(original_pixel, MOUSE_BUTTON_MASK_LEFT)
	press(original_pixel, MOUSE_BUTTON_LEFT, false)
	check(host.undo_states.is_empty() and interior.status_label.text.contains("位置未改变"), "dragging back to original snapped position produces no checkpoint")
	invariant_state(original, "no-op drag preserves exact state")
	finish = begin_drag(0, Vector2(-1.2, 0.4))
	interior.hide()
	check(not interior._move_drag_active and not is_instance_valid(interior.preview) and interior.interaction_mode == "select", "external hide cancels all transient gesture state")
	interior.open_station(SITE)
	await process_frame
	press(finish, MOUSE_BUTTON_LEFT, false)
	invariant_state(original, "hide, re-open and stale release cannot move the device")
	interior.set_interaction_mode("connect")
	# Switching a selection during a held gesture discards the previous target.
	interior.set_interaction_mode("select")
	finish = begin_drag(0, Vector2(-1.2, 0.4))
	interior._select(1)
	press(finish, MOUSE_BUTTON_LEFT, false)
	check(interior.selected_id == 1 and interior.interaction_mode == "select" and not is_instance_valid(interior.preview), "selection change cancels the old drag target")
	invariant_state(original, "selection change and delayed release cannot move either device")
	interior.set_interaction_mode("connect")
	# Canonical host candidate, duplicate rejection, and reverse-click direction.
	interior._click_device(2)
	check(interior.pending_link == 2 and interior.equipment_nodes[0].get_meta("interaction_highlight") == "compatible" and interior.equipment_nodes[1].get_meta("interaction_highlight") == "compatible", "reverse-order source selection highlights compatible canonical upstream endpoints")
	motion(body_pixel(0))
	check(interior.hover_label.text.contains("#0.heat_out → #2.hot_in") and interior.hover_label.text.contains("heat_water") and interior.hover_label.text.contains("2.000 MWth"), "link hover explains canonical direction, carrier, grade and real candidate capacity")
	interior._click_device(0)
	check(host.links.size() == 1 and int(host.links[0].from) == 0 and int(host.links[0].to) == 2, "reverse clicks still commit canonical output-to-input connection")
	var linked := host.state()
	var link_undos := host.undo_states.size()
	interior._click_device(0)
	check(interior.equipment_nodes[2].get_meta("interaction_highlight") != "compatible", "duplicate endpoints are not advertised as compatible")
	interior._click_device(2)
	check(interior.status_label.text.contains("重复") and host.undo_states.size() == link_undos, "duplicate link is rejected before mutation with useful reason")
	invariant_state(linked, "link preview and duplicate rejection preserve topology")
	escape()
	check(interior.pending_link == -1 and interior.interaction_mode == "select" and interior.selected_id >= 0, "Escape cancels link endpoint before clearing selection")
	interior.tools.cancel.pressed.emit()
	check(interior.selected_id == -1 and interior.visible, "explicit cancel control clears selection without closing")
	# A right-drag initiated on UI must not become an orbit upon entering view.
	camera_before = interior.camera.transform
	motion(body_pixel(1), MOUSE_BUTTON_MASK_RIGHT, Vector2(100, 80))
	check(interior.camera.transform.is_equal_approx(camera_before), "right button mask without viewport press never rotates camera")
	press(body_pixel(1), MOUSE_BUTTON_RIGHT)
	interior.view_container.mouse_exited.emit()
	motion(body_pixel(1), MOUSE_BUTTON_MASK_RIGHT, Vector2(100, 80))
	check(interior.camera.transform.is_equal_approx(camera_before), "viewport exit prevents later UI drag from continuing an orbit")
	interior.set_camera_view(INF, 30, 6)
	check(interior.camera.transform.is_equal_approx(camera_before), "non-finite camera input rejected atomically")
	interior.set_camera_view(720, -100, -1)
	check(interior.camera_pitch == interior.MIN_CAMERA_PITCH and is_equal_approx(interior.camera_distance, 1.8) and interior.camera.position.y > 0, "camera clamps extreme near/elevation requests above ground")
	interior.set_camera_view(-720, 1000, 1000)
	check(interior.camera_pitch == interior.MAX_CAMERA_PITCH and is_equal_approx(interior.camera_distance, 11.0), "camera clamps extreme far/top requests")
	invariant_state(linked, "all camera and interrupted gesture flows leave model state unchanged")
	# Click-to-place stays available alongside dragging; a no-op click adds no undo.
	interior.reset_camera()
	interior._select(0)
	interior._start_move()
	interior._click_floor(Vector2(-1.2, -0.8))
	check(host.undo_states.size() == link_undos and interior.interaction_mode == "select", "click-move to same snapped location produces no checkpoint")
	interior._start_move()
	interior._click_floor(Vector2(-1.2, 0.4))
	check(host.undo_states.size() == link_undos + 1 and is_equal_approx(host.device(0).interior_z, 0.4), "legacy click-to-place move remains available and commits once")
	# Undo while dragging cancels the preview first without consuming prior edits.
	var before_preview_undo := host.state()
	var undos_before_preview := host.undo_states.size()
	finish = begin_drag(0, Vector2(-1.2, -0.8))
	undo_shortcut()
	check(interior.visible and not interior._move_drag_active and not is_instance_valid(interior.preview) and host.undo_states.size() == undos_before_preview, "Ctrl+Z during drag cancels only the current preview")
	press(finish, MOUSE_BUTTON_LEFT, false)
	invariant_state(before_preview_undo, "canceled drag Ctrl+Z and delayed release do not undo earlier edits")
	undo_camera = interior.camera.transform
	interior.find_child("UndoInteriorEdit", true, false).pressed.emit()
	invariant_state(linked, "explicit Undo button restores the most recent successful move")
	check(interior.visible and interior.selected_id == 0 and interior.camera.transform.is_equal_approx(undo_camera), "toolbar undo preserves visible station, selected device and camera")
	undo_shortcut(true)
	invariant_state(original, "Command+Z also reverses the preceding link through the same host stack")
	check(interior.visible and interior.tools.undo.disabled, "Undo becomes disabled when authoritative history is exhausted")
	undo_shortcut()
	invariant_state(original, "empty-history Ctrl+Z is harmless")
	check(interior.visible and interior.status_label.text.contains("没有可撤销"), "empty-history shortcut keeps the station open with clear feedback")
	# Removing the selected device via undo clears only the invalid selection.
	check(host.add_internal_device(SITE, "electric_boiler", Vector2(-1.2, 1.4)), "fixture adds a new undoable internal device")
	interior.refresh()
	interior._select(int(host.devices.back().id))
	undo_shortcut()
	check(interior.visible and interior.selected_id == -1 and host.devices.size() == 3, "undoing selected device creation reopens station without a stale selection")
	invariant_state(original, "undo creation preserves original topology and inventory")
	interior.close_station()
	# world_game/map allocate these detached nodes before _ready; fixture owns them.
	for property in ["camera", "lod_camera", "terrain", "labels", "infrastructure", "selection", "overlay", "equipment", "cables", "confirmation", "param_dialog", "param_errors", "param_target", "data_dialog", "data_list", "line_dialog", "line_capacity", "line_loss", "line_choice"]:
		var node = host.get(property)
		if is_instance_valid(node) and node.get_parent() == null: node.free()
	host.queue_free()
	await process_frame
	print("STATION_INTERACTION_POLISH checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
