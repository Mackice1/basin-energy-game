extends SceneTree
## Real SubViewport/container input events against a minimal host. The host is
## authoritative; this test deliberately has no simulation timer or terrain.
const Interior = preload("res://scripts/station_interior.gd")
const Model = preload("res://scripts/energy_model.gd")

class Host:
	extends Node
	var devices: Array = []
	var stations: Array = [{"id":0,"name":"测试电热站","x":10.0,"z":20.0},{"id":1,"name":"空白电热站","x":50.0,"z":20.0}]
	var links: Array = []
	var templates: Dictionary = {}
	var result := {"valid":true,"devices":{}}
	var paused := true
	var speed := 1.0
	var dimension_profile := "legacy_illustrative"
	var selected_id := -1
	var next_id := 0
	var parameter_calls := 0
	var line_dialog_calls := 0
	var mutation_calls := 0
	var elapsed_s := 4321.0
	var param_dialog := Window.new()
	func _init() -> void:
		param_dialog.theme = Theme.new()
		param_dialog.theme.default_font_size = 18
		param_dialog.hide()
		add_child(param_dialog)
		var model := Model.new()
		for kind in ["electric_boiler","thermal_store","heat_exchanger"]: templates[kind] = model.defaults(kind)
	func station(id: int) -> Dictionary:
		for item in stations:
			if int(item.id) == id: return item
		return {}
	func device(id: int) -> Dictionary:
		for item in devices:
			if int(item.id) == id: return item
		return {}
	func add_internal_device(sid: int, kind: String, position: Vector2) -> bool:
		mutation_calls += 1
		var params: Dictionary = templates[kind].duplicate(true)
		devices.append({"id":next_id,"kind":kind,"parent_station_id":sid,"interior_x":position.x,"interior_z":position.y,"params":params,"state":{"energy_mwhth":params.capacity_mwhth * 0.5} if kind == "thermal_store" else {}})
		next_id += 1
		return true
	func move_internal_device(id: int, position: Vector2) -> bool:
		mutation_calls += 1
		device(id).interior_x = position.x
		device(id).interior_z = position.y
		return true
	func remove_internal_device(id: int) -> bool:
		mutation_calls += 1
		devices = devices.filter(func(item): return int(item.id) != id)
		links = links.filter(func(edge): return int(edge.from) != id and int(edge.to) != id)
		return true
	func connect_internal_devices(first: int, second: int) -> bool:
		mutation_calls += 1
		var source := device(first)
		var target := device(second)
		if source.is_empty() or target.is_empty(): return false
		if source.kind == "heat_exchanger" or (source.kind == "thermal_store" and target.kind == "electric_boiler"):
			var old_first := first
			first = second
			second = old_first
			source = device(first)
			target = device(second)
		if not (source.kind == "electric_boiler" and target.kind in ["thermal_store","heat_exchanger"] or source.kind == "thermal_store" and target.kind == "heat_exchanger"): return false
		for edge in links:
			if int(edge.from) == first and int(edge.to) == second: return false
		links.append({"from":first,"to":second,"from_port":"heat_out","to_port":"heat_in" if target.kind == "thermal_store" else "hot_in","carrier":"heat_water","grade_id":"hw_primary_90_60","capacity_mwth":2.0,"loss_fraction":0.0})
		return true
	func select_device(id: int) -> void: selected_id = id
	func open_parameters(as_template: bool) -> void:
		assert(not as_template)
		parameter_calls += 1
	func open_line_settings() -> void: line_dialog_calls += 1
	func toggle_run() -> void: paused = not paused
	func set_simulation_speed(value: float) -> bool:
		speed = value
		return true

var checks := 0
var failures: Array[String] = []
var host: Host
var interior
var original_base_disable_3d := false

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		print("FAIL ", message)

func _initialize() -> void: call_deferred("run")

func click_world(point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = interior.camera.unproject_position(Vector3(point.x, 0, point.y)) * interior.view_container.size / Vector2(interior.viewport.size)
	interior.view_container.gui_input.emit(event)
	event.pressed = false
	interior.view_container.gui_input.emit(event)

func motion_world(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = interior.camera.unproject_position(Vector3(point.x, 0, point.y)) * interior.view_container.size / Vector2(interior.viewport.size)
	interior.view_container.gui_input.emit(event)

func drag_view(button: MouseButton, relative: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = button
	press.pressed = true
	press.position = interior.view_container.size * 0.5
	interior.view_container.gui_input.emit(press)
	var motion := InputEventMouseMotion.new()
	motion.position = press.position + relative
	motion.relative = relative
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT if button == MOUSE_BUTTON_RIGHT else MOUSE_BUTTON_MASK_MIDDLE
	interior.view_container.gui_input.emit(motion)
	press.pressed = false
	interior.view_container.gui_input.emit(press)

func run() -> void:
	root.size = Vector2i(1440, 900)
	root.gui_embed_subwindows = true
	host = Host.new()
	root.add_child(host)
	interior = Interior.new()
	host.add_child(interior)
	interior.setup(host)
	check(not interior.visible, "setup does not open a station or mutate the host")
	check(not interior.open_station(999), "unknown station cannot open")
	original_base_disable_3d = root.disable_3d
	check(interior.open_station(0), "opens known station")
	await process_frame
	await process_frame
	check(interior.visible, "interior Window visible")
	check(interior.theme == host.param_dialog.theme, "interior inherits host modal theme")
	check(interior.camera.projection == Camera3D.PROJECTION_PERSPECTIVE and interior.camera_distance == 62.0, "default camera uses a human-legible oblique perspective")
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	for index in 40: interior.view_container.gui_input.emit(wheel)
	check(interior.camera_distance == 18.0, "wheel zoom clamps at safe near distance")
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	for index in 40: interior.view_container.gui_input.emit(wheel)
	check(interior.camera_distance == 110.0, "wheel zoom clamps at full-yard distance")
	interior.find_child("ResetInteriorView", true, false).pressed.emit()
	check(interior.camera_distance == 62.0 and interior.camera_pitch == 30.0, "panorama button restores empty-yard framing and angle")
	check(interior.viewport.own_world_3d, "interior owns an isolated 3D world")
	check(root.disable_3d and not interior.viewport.disable_3d, "hidden base 3D rendering is suspended while the independent plant viewport stays enabled")
	check(interior.viewport.world_3d != root.world_3d, "interior has no base-map world geometry")
	check(interior.scene_root.find_child("StationFloor", true, false) != null, "distinct internal floor")
	check(interior.camera.get_viewport() == interior.viewport, "dedicated camera belongs to interior viewport")
	check(host.devices.is_empty() and host.mutation_calls == 0, "new station is genuinely empty; opening seeds no devices")
	check(interior.connections_root.get_child_count() == 0, "empty station has no decorative pipes or cables")
	check(not interior.placement_grid.visible, "grid stays hidden during normal exploration")
	check(interior.scene_root.find_child("StationFloor", true, false).mesh.size.y > 0.8, "plant is grounded on a thick concrete foundation")
	var original_camera: Transform3D = interior.camera.transform
	var camera_calls := host.mutation_calls
	drag_view(MOUSE_BUTTON_RIGHT, Vector2(105, -40))
	check(not interior.camera.transform.is_equal_approx(original_camera), "right-drag orbits the perspective camera")
	check(interior.camera_pitch >= 16.0 and interior.camera.position.y > 0, "orbit never moves the camera below ground")
	drag_view(MOUSE_BUTTON_RIGHT, Vector2(0, -10000))
	check(interior.camera_pitch == 16.0 and interior.camera.position.y > 0, "orbit clamps at safe minimum elevation")
	drag_view(MOUSE_BUTTON_RIGHT, Vector2(0, 10000))
	check(interior.camera_pitch == 76.0, "orbit clamps before top-down singularity")
	drag_view(MOUSE_BUTTON_MIDDLE, Vector2(100000, -100000))
	check(absf(interior.camera_target.x) <= 24.0 and absf(interior.camera_target.z) <= 24.0, "middle-drag pan is bounded to the station")
	check(host.paused and host.elapsed_s == 4321.0 and host.mutation_calls == camera_calls, "orbit/pan/zoom do not mutate or unpause host simulation")
	interior.reset_camera()
	check(interior.camera.transform.is_equal_approx(original_camera), "reset restores camera position, target and angle")
	check(interior.summary_label.text.contains("空站"), "empty station has build guidance")
	check(not interior.tools.has("heat_demand"), "external demand is excluded from internal construction")
	check(interior.device_picker.item_count == 1, "empty picker is explicit")
	interior.tools.electric_boiler.pressed.emit()
	motion_world(Vector2(-14, -4))
	check(is_instance_valid(interior.preview) and interior.preview.preview_valid, "ray-projected placement preview")
	check(interior.placement_grid.visible, "build mode reveals a faint placement grid")
	var build_calls := host.mutation_calls
	drag_view(MOUSE_BUTTON_RIGHT, Vector2(50, 12))
	check(interior.interaction_mode == "build" and host.mutation_calls == build_calls, "right-drag explores without cancelling construction or placing equipment")
	interior.reset_camera()
	click_world(Vector2(-14, -4))
	check(host.devices.size() == 1 and host.device(0).kind == "electric_boiler", "GUI grid click builds boiler through host")
	check(Vector2(host.device(0).interior_x, host.device(0).interior_z).is_equal_approx(Vector2(-14,-4)), "viewport-to-floor ray maps to correct snapped coordinates")
	var calls := host.mutation_calls
	click_world(Vector2(-14, -4))
	click_world(Vector2(24, 24))
	check(host.devices.size() == 1 and host.mutation_calls == calls, "overlap and bounds rejected before host mutation")
	check(interior.placement_error("heat_demand", Vector2.ZERO) != "", "demand cannot be injected through placement tools")
	check(interior.placement_error("thermal_store", Vector2(20, 0)) != "", "store uses radius five, including bounds")
	interior.tools.thermal_store.pressed.emit()
	click_world(Vector2(0, -4))
	interior.tools.heat_exchanger.pressed.emit()
	click_world(Vector2(14, -4))
	check(host.devices.size() == 3 and interior.equipment_nodes.size() == 3, "all original thermal equipment visuals are present")
	check(interior.equipment_nodes[0].has_named_port("ac_in"), "original boiler AC port retained")
	check(interior.equipment_nodes[2].has_named_port("warm_out"), "original exchanger 70/40 port retained")
	interior.tools.select.pressed.emit()
	click_world(Vector2(0, -4))
	check(interior.selected_id == 1 and host.selected_id == 1, "clicking model selects host device")
	check(interior.selected_label.text.contains("MWhth") and interior.selected_label.text.contains("SOC"), "store shows thermal inventory and SOC")
	interior.tools.parameters.pressed.emit()
	check(host.parameter_calls == 1 and host.selected_id == 1, "parameter button delegates existing host modal")
	interior.tools.lines.pressed.emit()
	check(host.line_dialog_calls == 1 and host.selected_id == 1, "device lines button opens existing host line editor")
	interior.tools.move.pressed.emit()
	click_world(Vector2(-14, -4))
	check(interior.interaction_mode == "move" and host.device(1).interior_x == 0, "invalid move stays pending and does not mutate")
	click_world(Vector2(0, 8))
	check(host.device(1).interior_z == 8 and interior.interaction_mode == "select", "move commits host coordinates and ends placement")
	interior.tools.connect.pressed.emit()
	click_world(Vector2(-14, -4))
	check(interior.pending_link == 0, "first model click retains connection endpoint")
	click_world(Vector2(0, 8))
	check(host.links.size() == 1 and interior.pending_link == -1, "second model click connects typed heat ports")
	interior._select_choice(interior.link_from, 1)
	interior._select_choice(interior.link_to, 2)
	interior.find_child("ConnectSelectedPorts", true, false).pressed.emit()
	check(host.links.size() == 2, "dropdown connection delegates to host")
	check(interior.connections_root.get_child_count() == host.links.size(), "exactly one visible route for each actual host link")
	for route in interior.connections_root.get_children():
		var source_id: int = route.get_meta("from")
		var target_id: int = route.get_meta("to")
		check((route.get_meta("source_position") as Vector3).is_equal_approx(interior._port(source_id, route.get_meta("from_port"))), "pipe starts at the actual named source port")
		check((route.get_meta("target_position") as Vector3).is_equal_approx(interior._port(target_id, route.get_meta("to_port"))), "pipe ends at the actual named target port")
		var points: PackedVector3Array = route.get_meta("route_points")
		var orthogonal := true
		for index in range(points.size() - 1):
			var delta := points[index + 1] - points[index]
			var nonzero := int(absf(delta.x) > 0.001) + int(absf(delta.y) > 0.001) + int(absf(delta.z) > 0.001)
			if nonzero > 1: orthogonal = false
		check(orthogonal, "pipe route follows orthogonal elevated segments with elbows")
	interior.set_interaction_mode("select")
	check(not interior.placement_grid.visible, "grid hides again after construction")
	interior._select(0)
	check(interior.name_labels[0].visible and not interior.name_labels[2].visible, "equipment names only appear on selected or hovered equipment")
	var paused_devices: Array = host.devices.duplicate(true)
	var paused_links: Array = host.links.duplicate(true)
	for yaw in [145.0, 40.0, -100.0]:
		interior.set_camera_view(yaw, 30.0, 56.0)
		var visual: Node3D = interior.equipment_nodes[2]
		var bounds: AABB = visual.get_meta("pick_bounds")
		var pixel: Vector2 = interior.camera.unproject_position(visual.to_global(bounds.get_center())) * interior.view_container.size / Vector2(interior.viewport.size)
		check(interior.device_at_view(pixel) == 2, "3D body picking remains correct after orbit to %.0f degrees" % yaw)
		var world := Vector2(8, -12)
		var floor_pixel: Vector2 = interior.camera.unproject_position(Vector3(world.x, 0, world.y)) * interior.view_container.size / Vector2(interior.viewport.size)
		check((interior.floor_at(floor_pixel) as Vector2).is_equal_approx(world), "perspective floor projection remains accurate after orbit")
	interior.set_camera_view(145, 30, 56)
	drag_view(MOUSE_BUTTON_MIDDLE, Vector2(90, 35))
	var panned_visual: Node3D = interior.equipment_nodes[2]
	var panned_bounds: AABB = panned_visual.get_meta("pick_bounds")
	var panned_pixel: Vector2 = interior.camera.unproject_position(panned_visual.to_global(panned_bounds.get_center())) * interior.view_container.size / Vector2(interior.viewport.size)
	check(interior.device_at_view(panned_pixel) == 2, "3D picking remains correct after middle-drag pan")
	check(host.paused and host.devices == paused_devices and host.links == paused_links and host.elapsed_s == 4321.0, "camera exploration preserves paused inventory, topology and elapsed time")
	interior.reset_camera()
	var nodes_before: Dictionary = {}
	for id in interior.equipment_nodes: nodes_before[id] = interior.equipment_nodes[id].get_instance_id()
	var pipe_before: int = interior.connections_root.get_child(0).get_instance_id()
	host.result.devices = {"0":{"electric_input_mw":0.7,"heat_output_mwth":0.665},"1":{"charge_mwth":0.11,"discharge_mwth":0.0},"2":{"hot_input_mwth":0.5,"warm_output_mwth":0.48}}
	host.device(1).state.energy_mwhth = 1.25
	for index in 20: interior.refresh()
	for id in nodes_before: check(interior.equipment_nodes[id].get_instance_id() == nodes_before[id], "runtime refresh preserves equipment node %d" % id)
	check(interior.connections_root.get_child(0).get_instance_id() == pipe_before, "runtime refresh does not rebuild pipes")
	var first_visual: Node3D = interior.equipment_nodes[0]
	var saved_port: Vector3 = first_visual.named_port_locals.heat_out
	first_visual.named_port_locals.heat_out += Vector3(0.1, 0, 0)
	interior.refresh()
	check((interior.connections_root.get_child(0).get_meta("source_position") as Vector3).is_equal_approx(interior._port(0, "heat_out")), "pipe routing refreshes when authoritative visual port location changes")
	first_visual.named_port_locals.heat_out = saved_port
	interior.refresh()
	check(interior.summary_label.text.contains("0.70000 MW") and interior.summary_label.text.contains("0.480 MWth"), "live metrics read current host dispatch")
	check(host.elapsed_s == 4321.0 and host.device(1).state.energy_mwhth == 1.25, "refresh does not advance simulation or inventory")
	host.devices.append({"id":90,"kind":"station","params":{},"state":{}})
	host.devices.append({"id":91,"kind":"heat_demand","params":{},"state":{}})
	host.links.append({"from":90,"to":0,"carrier":"electricity_ac","from_port":"ac_out","to_port":"ac_in"})
	host.links.append({"from":2,"to":91,"carrier":"heat_water","grade_id":"hw_secondary_70_40","from_port":"warm_out","to_port":"heat_in"})
	interior.refresh()
	check(interior.equipment_nodes.size() == 3, "external source and demand never become internal visuals")
	check(interior.input_ports_label.text.contains("#90 变电站") and interior.output_ports_label.text.contains("#91 热需求"), "external port groups show exact host endpoint mappings")
	check(interior.output_ports_label.text.contains("70/40°C"), "secondary grade visibly distinguished")
	check(interior.connections_root.get_child_count() == host.links.size(), "external routes also require actual host links")
	var cable = interior.connections_root.find_child("ACCable_90_0", false, false)
	check(cable != null and cable.find_child("ACCableTray", true, false) != null, "AC cable has a distinct low cable tray, separate from heat pipes")
	host.links.append({"from":0,"to":2,"carrier":"heat_water","from_port":"missing_port","to_port":"hot_in"})
	interior.refresh()
	check(interior.connections_root.get_child_count() == host.links.size() - 1, "unknown ports never produce invented centre-to-centre pipes")
	host.links.pop_back()
	interior.refresh()
	interior.run_button.pressed.emit()
	check(not host.paused, "interior run button controls host pause")
	interior.speed_control.speed_changed.emit(15.0)
	check(host.speed == 15.0 and host.elapsed_s == 4321.0, "speed controls host rate without advancing another clock")
	interior.set_interaction_mode("select")
	interior._select(1)
	interior.request_remove()
	check(interior.remove_confirmation.visible and not host.device(1).is_empty(), "remove requires visible confirmation")
	interior.remove_confirmation.canceled.emit()
	interior.remove_confirmation.hide()
	check(not host.device(1).is_empty(), "cancel preserves selected device")
	interior.request_remove()
	interior._select(2)
	interior.remove_confirmation.confirmed.emit()
	interior.remove_confirmation.hide()
	check(host.device(1).is_empty() and not host.device(2).is_empty(), "confirmation applies snapshotted target despite later selection")
	check(host.links.size() == 2, "host removes incident internal connections only")
	interior.refresh()
	check(not interior.equipment_nodes.has(1), "removed device disappears from view")
	check(interior.open_station(1), "can switch to second station")
	interior.hide()
	check(root.disable_3d == original_base_disable_3d and interior.refresh_timer.is_stopped(), "direct parent hide restores base drawing and stops visual refresh")
	interior.open_station(1)
	check(root.disable_3d and not interior.viewport.disable_3d, "reentry suspends only base rendering again")
	check(interior.equipment_nodes.is_empty() and interior.selected_id == -1, "switching stations clears foreign models and selection")
	interior.find_child("ReturnToBase", true, false).pressed.emit()
	check(host.selected_id == 1, "return restores station selection in host")
	check(not interior.visible and interior.refresh_timer.is_stopped(), "return closes window and stops read-only refresh timer")
	check(root.disable_3d == original_base_disable_3d, "return restores the original base rendering flag")
	check(not host.paused and host.speed == 15.0 and host.elapsed_s == 4321.0, "return preserves host simulation state")
	check(interior.open_station(0), "repeated entry restores existing station")
	await process_frame
	interior.tools.move.pressed.emit()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	interior.start_build("electric_boiler")
	interior.window_input.emit(escape)
	check(interior.visible and interior.interaction_mode == "select", "first Escape cancels active construction")
	interior.window_input.emit(escape)
	check(not interior.visible, "Escape in selection mode returns to base")
	if "--capture-interior" in OS.get_cmdline_user_args():
		host.add_internal_device(0, "thermal_store", Vector2(0, 8))
		host.connect_internal_devices(0, 3)
		host.connect_internal_devices(3, 2)
		interior.open_station(0)
		interior._select(3)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var path := "user://station_interior_capture.png"
		check(root.get_texture().get_image().save_png(path) == OK, "GUI screenshot saved")
		print("INTERIOR_CAPTURE ", ProjectSettings.globalize_path(path))
	interior.close_station()
	root.disable_3d = true
	interior.open_station(0)
	interior.close_station()
	check(root.disable_3d, "closing preserves a base viewport that was already disabled before entry")
	root.disable_3d = original_base_disable_3d
	host.queue_free()
	await process_frame
	# A new metric project keeps host coordinates in the common 0.1-unit/m
	# world. Civil scenery scales once, never the equipment root or inventory.
	host = Host.new()
	host.dimension_profile = "metric_v1"
	root.add_child(host)
	interior = Interior.new()
	host.add_child(interior)
	interior.setup(host)
	interior.open_station(0)
	await process_frame
	await process_frame
	check(interior.dimension_profile == "metric_v1" and is_equal_approx(interior.visual_scale, 0.1), "metric station reads the host dimension profile")
	var floor_node: MeshInstance3D = interior.scene_root.find_child("StationFloor", true, false)
	check(is_equal_approx((floor_node.global_transform * floor_node.get_aabb()).size.x, 4.8), "metric civil yard is 48 meters at 0.1 world units per meter")
	check(interior.equipment_root.scale == Vector3.ONE and interior.connections_root.scale == Vector3.ONE, "equipment coordinates and actual port positions are not double-scaled")
	check(is_equal_approx(interior.camera_distance, 6.2), "metric camera overview scales with the physical yard")
	interior.set_camera_view(145, 1, 0.01)
	check(is_equal_approx(interior.camera_distance, 1.8) and interior.camera.position.y > 0, "metric camera uses scaled safe near bounds")
	interior.reset_camera()
	var ordinary_template: Dictionary = host.templates.electric_boiler.duplicate(true)
	host.templates.electric_boiler.rated_electric_mw = 1000.0
	interior.start_build("electric_boiler")
	check(interior.interaction_mode == "select" and not is_instance_valid(interior.preview) and interior.status_label.text.contains("超出厂区"), "oversize module groups are rejected before any giant preview is instantiated")
	check(host.devices.is_empty() and host.mutation_calls == 0, "oversize preview guard leaves host equipment and simulation untouched")
	host.templates.electric_boiler = ordinary_template.duplicate(true)
	interior.start_build("electric_boiler")
	motion_world(Vector2(-1.2, -0.4))
	check(is_instance_valid(interior.preview), "ordinary metric template still produces a placement preview")
	host.templates.electric_boiler.rated_electric_mw = 1000.0
	motion_world(Vector2(-1.2, -0.4))
	check(not is_instance_valid(interior.preview) and interior.interaction_mode == "select", "a template enlarged during placement also cancels before giant instantiation")
	host.templates.electric_boiler = ordinary_template
	interior.start_build("electric_boiler")
	click_world(Vector2(-1.2, -0.4))
	check(host.devices.size() == 1 and Vector2(host.device(0).interior_x, host.device(0).interior_z).is_equal_approx(Vector2(-1.2, -0.4)), "metric grid snaps two-meter positions without changing host units")
	check(interior.placement_error("electric_boiler", Vector2(2.4, 0)) != "", "metric placement enforces the 24-meter half-yard boundary")
	var metric_visual: Node3D = interior.equipment_nodes[0]
	var metric_bounds: AABB = metric_visual.get_meta("pick_bounds")
	check(metric_bounds.size.x < 2.0 and metric_bounds.size.z < 2.0, "metric equipment geometry is meter-based, not legacy enlarged symbols")
	check(interior.name_labels[0].position.y >= metric_bounds.end.y + 0.19, "metric name annotation sits above the actual model AABB with clear separation")
	interior.set_interaction_mode("select")
	interior._select(0)
	check(interior.selected_label.text.contains("-12.0") and interior.selected_label.text.contains("米"), "metric location readout converts world coordinates to meters")
	var metric_pixel: Vector2 = interior.camera.unproject_position(metric_visual.to_global(metric_bounds.get_center())) * interior.view_container.size / Vector2(interior.viewport.size)
	check(interior.device_at_view(metric_pixel) == 0, "metric 3D body picking matches actual equipment dimensions")
	var metric_inventory: Array = host.devices.duplicate(true)
	for index in 10: interior.refresh()
	check(host.devices == metric_inventory and host.paused and host.elapsed_s == 4321.0, "metric display refresh does not change inventory, pause or host time")
	interior.close_station()
	check(root.disable_3d == original_base_disable_3d, "metric station also restores base drawing on exit")
	host.queue_free()
	await process_frame
	print("STATION_INTERIOR checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
