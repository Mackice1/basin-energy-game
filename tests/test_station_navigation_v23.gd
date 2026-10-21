extends SceneTree
const Interior = preload("res://scripts/station_interior.gd")
const ControllerTest = preload("res://tests/test_station_controller.gd")
class Host:
	extends ControllerTest.Fixture
	var detail_requests: Array[int] = []
	func _process(_delta: float) -> void: pass
	func open_device_details(id: int) -> void: detail_requests.append(id)
var host
var interior
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error(message)
func _initialize() -> void: call_deferred("run")
func press(position: Vector2, down := true, button := MOUSE_BUTTON_LEFT, double := false) -> void:
	var e := InputEventMouseButton.new()
	e.position = position; e.pressed = down; e.button_index = button; e.double_click = double
	interior.view_container.gui_input.emit(e)
func motion(position: Vector2, delta: Vector2, mask := MOUSE_BUTTON_MASK_LEFT) -> void:
	var e := InputEventMouseMotion.new()
	e.position = position; e.relative = delta; e.button_mask = mask
	interior.view_container.gui_input.emit(e)
func pixel(id: int) -> Vector2:
	var visual: Node3D = interior.equipment_nodes[id]
	var bounds: AABB = visual.get_meta("pick_bounds")
	return interior.camera.unproject_position(visual.to_global(bounds.get_center())) * interior.view_container.size / Vector2(interior.viewport.size)
func run() -> void:
	root.size = Vector2i(1440, 900); root.gui_embed_subwindows = true
	host = Host.new(); host.cfg = {"max_build_slope_degrees":8.0}; host.dimension_profile = "metric_v1"; host.booted = true
	for kind in host.KINDS: host.templates[kind] = host.model.defaults(kind)
	root.add_child(host)
	host.add_station(Vector2.ZERO, false)
	host.add_internal_device(1000000, "electric_boiler", Vector2(-1.2, -0.8))
	host.add_internal_device(1000000, "thermal_store", Vector2(0.8, -0.6))
	host.undo_states.clear()
	interior = Interior.new(); host.add_child(interior); host.station_interior = interior
	interior.setup(host); interior.open_station(1000000)
	await process_frame; await process_frame
	var snapshot: PackedByteArray = var_to_bytes(host.state())
	var start := pixel(0)
	var camera_before: Vector3 = interior.camera_target
	press(start)
	check(interior.selected_id == -1, "selection waits for release")
	motion(start + Vector2(3,0), Vector2(3,0))
	check(interior.camera_target == camera_before, "subthreshold jitter cannot pan")
	press(start + Vector2(3,0), false)
	check(interior.selected_id == 0, "subthreshold release selects device")
	press(start); motion(start + Vector2(35,15), Vector2(35,15)); press(start + Vector2(35,15), false)
	check(not interior.camera_target.is_equal_approx(camera_before), "left body drag pans")
	check(interior.selected_id == 0 and not interior._move_drag_active and not is_instance_valid(interior.preview), "pan keeps selection and never starts move preview")
	check(var_to_bytes(host.state()) == snapshot and host.undo_states.is_empty(), "browse gesture preserves authoritative state and undo")
	camera_before = interior.camera_target
	start = Vector2(30,30)
	press(start); motion(start + Vector2(15,10), Vector2(15,10)); press(start + Vector2(15,10), false)
	check(not interior.camera_target.is_equal_approx(camera_before) and interior.selected_id == 0, "blank-space drag pans without clearing selection")
	camera_before = interior.camera_target
	motion(start + Vector2(10,10), Vector2(10,10))
	check(interior.camera_target == camera_before, "held button with no viewport press cannot pan")
	press(start); interior._view_mouse_exited(); motion(start+Vector2(20,0),Vector2(20,0)); press(start,false)
	check(interior.camera_target == camera_before, "leaving viewport cancels gesture")
	press(start)
	var outside := InputEventMouseButton.new()
	outside.button_index = MOUSE_BUTTON_LEFT; outside.pressed = false; outside.position = Vector2(-40,-40)
	interior.window_input.emit(outside)
	motion(start+Vector2(20,0),Vector2(20,0)); press(start,false)
	check(interior.camera_target == camera_before and not interior._left_pan_pending, "outside release clears pending selection/pan")
	press(start); interior.focus_exited.emit(); motion(start+Vector2(20,0),Vector2(20,0)); press(start,false)
	check(interior.camera_target == camera_before, "losing focus cancels gesture")
	press(start); interior.set_interaction_mode("connect"); motion(start+Vector2(20,0),Vector2(20,0)); press(start,false)
	check(interior.camera_target == camera_before and not interior._left_pan_pending, "mode switch cancels gesture")
	interior.set_interaction_mode("select"); interior.reset_camera()
	start = pixel(1); press(start,true,MOUSE_BUTTON_LEFT,true); press(start,false)
	check(host.detail_requests == [1], "double click opens clicked device details")
	interior.tools.details.pressed.emit()
	check(host.detail_requests == [1,1], "visible details button opens selected device")
	interior._clear_selection()
	check(interior.tools.details.disabled, "details action disabled without selection")
	interior._select(0); interior._start_move(); start = pixel(0)
	press(start); motion(start+Vector2(12,0),Vector2(12,0))
	check(interior._move_drag_active and is_instance_valid(interior.preview), "explicit Move still previews device drag")
	check(var_to_bytes(host.state()) == snapshot, "explicit move preview is uncommitted")
	interior._view_mouse_exited()
	check(var_to_bytes(host.state()) == snapshot, "cancel explicit move preserves state")
	interior.set_interaction_mode("select"); camera_before = interior.camera_target
	press(Vector2(100,100),true,MOUSE_BUTTON_MIDDLE); motion(Vector2(120,100),Vector2(20,0),MOUSE_BUTTON_MASK_MIDDLE); press(Vector2(120,100),false,MOUSE_BUTTON_MIDDLE)
	check(not interior.camera_target.is_equal_approx(camera_before), "middle pan preserved")
	var yaw: float = interior.camera_yaw
	press(Vector2(100,100),true,MOUSE_BUTTON_RIGHT); motion(Vector2(120,100),Vector2(20,0),MOUSE_BUTTON_MASK_RIGHT); press(Vector2(120,100),false,MOUSE_BUTTON_RIGHT)
	check(not is_equal_approx(interior.camera_yaw,yaw), "right orbit preserved")
	interior.close_station()
	for property in ["camera", "lod_camera", "terrain", "labels", "infrastructure", "selection", "overlay", "equipment", "cables", "confirmation", "param_dialog", "param_errors", "param_target", "data_dialog", "data_list", "line_dialog", "line_capacity", "line_loss", "line_choice"]:
		var node = host.get(property)
		if is_instance_valid(node) and node.get_parent() == null: node.free()
	host.free(); await process_frame
	print("STATION_NAVIGATION_V23 checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
