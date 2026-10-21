extends SceneTree
## Controller regression: real placement guards, visual nodes, state, save and
## undo, with deterministic terrain/picking. Input is dispatched to controller
## methods; this does not claim native OS mouse or GPU rendering coverage.

class Fixture:
	extends "res://scripts/world_game.gd"
	var cursor := Vector2.ZERO
	var press_ground := Vector2.ZERO
	var picked_id := -2
	var over_ui := false
	var blocked_modal := false
	var last_notice := ""
	func _ready():
		cfg = {"max_build_slope_degrees":8.0, "grid_export_mw":4.0}
		dimension_profile = "metric_v1"
		for kind in KINDS: templates[kind] = model.defaults(kind)
		for child in [equipment, cables, camera, lod_camera, labels, selection]: add_child(child)
		font_full = load("res://assets/BasinUI.otf")
		booted = true
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
		update_camera()
	func exclusion(_x: float, _z: float) -> String: return ""
	func slope_at(_x: float, _z: float) -> float: return 0.0
	func height_at(_x: float, _z: float) -> float: return 0.0
	func pick_ground(position: Vector2) -> Vector2: return press_ground if position == Vector2(400,400) else cursor
	func nearest(_position: Vector2) -> int: return picked_id
	func pointer_over_ui(_position: Vector2, _padding: Vector2 = Vector2.ZERO) -> bool: return over_ui
	func modal_visible() -> bool: return blocked_modal
	func update_status(): pass
	func tell(message: String): last_notice = message
	func select_site(_point: Vector2): pass
	func weather_at(_t: float) -> Dictionary:
		return {"wind_speed_mps":12.0,"irradiance_wm2":1000.0,"air_temp_c":25.0}

class InteriorProbe:
	extends Window
	var entered := -1
	var entries := 0
	func open_station(id: int): entered = id; entries += 1

const SITE := 1000000
const PV := 0
const AC := 1
const BATTERY := 2
const BOILER := 3
const STORE := 4
const EXCHANGER := 5
var checks := 0
var failures: Array[String] = []
var game: Fixture

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); print("FAIL INTERACTION_POLISH ", label)

func frozen() -> PackedByteArray: return var_to_bytes(game.state())
func button(pressed: bool, double_click: bool = false, position: Vector2 = Vector2(-1,-1)) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed
	event.position = (Vector2(400,400) if pressed else Vector2(500,400)) if position.x < 0 else position; event.double_click = double_click
	return event
func motion(position: Vector2, mask: int = MOUSE_BUTTON_MASK_LEFT) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.position = position; event.relative = Vector2(40,15); event.button_mask = mask
	return event
func set_input_left(pressed: bool) -> void:
	var event := button(pressed)
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func escape() -> void:
	var event := InputEventKey.new(); event.pressed = true; event.keycode = KEY_ESCAPE
	game._input(event)
func start_drag(id: int) -> void:
	game.select_device(id); game.set_mode("move"); game.picked_id = id
	var item: Dictionary = game.station(id) if id == SITE else game.device(id)
	game.press_ground = Vector2(float(item.x),float(item.z))
	game._unhandled_input(button(true))
	game._unhandled_input(motion(Vector2(410,400)))
func snapshot_unchanged(before: PackedByteArray, revision: int, undos: int, label: String) -> void:
	check(frozen() == before, label + " preserves complete saved state")
	check(game.scene_revision == revision and game.undo_states.size() == undos, label + " adds no edit or undo")
func _initialize(): call_deferred("run")
func run() -> void:
	root.size = Vector2i(1440,900)
	root.gui_embed_subwindows = true
	game = Fixture.new(); root.add_child(game)
	for spec in [["pv",Vector2(-45,0)],["station",Vector2(-20,0)],["battery",Vector2(-20,25)]]:
		check(game.add_equipment(spec[0],spec[1],false), "fixture places " + spec[0])
	check(game.add_station(Vector2(30,0),false), "fixture places metric facility")
	for spec in [["electric_boiler",Vector2(-1.0,-0.7)],["thermal_store",Vector2(0.9,-0.6)],["heat_exchanger",Vector2(0,1.0)]]:
		check(game.add_internal_device(SITE,spec[0],spec[1]), "fixture places " + spec[0])
	game.device(STORE).state.energy_mwhth = 0.625
	game.device(BATTERY).state.energy_mwh = 0.25
	game.elapsed_s = 123.5; game.refresh(); game.undo_states.clear()
	check(game.validate_state(game.state()).is_empty(), "fixture is a valid nonzero inventory save")
	test_selection_camera_and_entry()
	test_drag_transactions()
	test_link_and_build_previews()
	await test_station_navigation()
	test_disk_roundtrip()
	for key in ["terrain","infrastructure","overlay","confirmation","param_dialog","param_errors","param_target","data_dialog","data_list","line_dialog","line_capacity","line_loss","line_choice","station_interior"]:
		var node = game.get(key)
		if is_instance_valid(node) and node.get_parent() == null: node.free()
	game.free(); await process_frame
	print("INTERACTION_POLISH checks=",checks," failures=",failures.size()," input=controller-dispatch")
	quit(0 if failures.is_empty() else 1)

func test_selection_camera_and_entry() -> void:
	var before := frozen(); var revision := game.scene_revision; var undos := game.undo_states.size()
	var probe := InteriorProbe.new(); game.station_interior = probe
	game.picked_id = SITE; game._unhandled_input(button(true)); game._input(button(false,false,Vector2(400,400)))
	check(game.selected_id == SITE and probe.entries == 0, "single click selects facility without entering")
	game._input(button(false))
	check(game.drag_candidate == -2 and not game.drag_active, "simple release clears drag candidate")
	game._unhandled_input(button(true,true)); game._input(button(false,false,Vector2(400,400)))
	check(probe.entered == SITE and probe.entries == 1 and game.mode == "select", "double click enters selected facility once")
	game._input(button(false)); game.select_device(BATTERY); game.focus_selected()
	check(Vector2(game.target.x,game.target.z).is_equal_approx(Vector2(-20,25)) and game.target.y >= 0.0 and game.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "focus frames selected equipment")
	check(game.distance >= 8.0 and game.distance <= 235.0, "focus respects camera distance limits")
	var camera_before := game.camera.transform
	var right := InputEventMouseButton.new(); right.button_index = MOUSE_BUTTON_RIGHT; right.pressed = true
	game.over_ui = true; game._input(right); game.over_ui = false
	game._unhandled_input(motion(Vector2(450,450),MOUSE_BUTTON_MASK_RIGHT))
	check(game.camera.transform.is_equal_approx(camera_before), "camera drag started over UI stays blocked after leaving UI")
	right.pressed = false; game._input(right)
	game._unhandled_input(motion(Vector2(450,450),MOUSE_BUTTON_MASK_RIGHT))
	check(not game.camera.transform.is_equal_approx(camera_before), "camera orbit resumes after blocked button is released")
	game._unhandled_input(button(true)); game._unhandled_input(motion(Vector2(440,420))); game._input(button(false))
	check(not game.left_pan_pending and game.mode == "select", "left camera drag ends without entering Move tool")
	escape(); check(game.selected_id == -2, "Escape in select mode clears selection")
	snapshot_unchanged(before,revision,undos,"selection, focus, camera, entry and Escape")

func test_drag_transactions() -> void:
	var before := frozen(); var revision := game.scene_revision; var undos := game.undo_states.size()
	game.select_device(BATTERY); game.set_mode("move"); game.picked_id = BATTERY; game.press_ground = Vector2(-20,25); game._unhandled_input(button(true))
	game._unhandled_input(motion(Vector2(403,400)))
	check(not game.drag_active and game.mode == "move", "explicit Move tool small pointer movement stays pending")
	game.cursor = Vector2(0,25); game._unhandled_input(motion(Vector2(410,400)))
	check(game.drag_active and game.mode == "move" and is_instance_valid(game.ghost), "crossing drag threshold begins transient move preview")
	set_input_left(true); game._process(0.0); set_input_left(false)
	check(is_instance_valid(game.ghost) and game.ghost.preview_valid, "valid drag destination is indicated before commit")
	snapshot_unchanged(before,revision,undos,"live drag preview")
	escape()
	check(game.mode == "select" and not game.drag_active and game.ghost == null, "Escape terminates drag and clears preview")
	snapshot_unchanged(before,revision,undos,"cancelled drag")
	for scenario in ["overlap","outside","ui","modal"]:
		start_drag(BATTERY)
		game.cursor = Vector2(-20,0) if scenario == "overlap" else Vector2(INF,INF) if scenario == "outside" else Vector2(0,25)
		game.over_ui = scenario == "ui"; game.blocked_modal = scenario == "modal"
		game._input(button(false)); game.over_ui = false; game.blocked_modal = false
		check(game.mode == "select" and not game.drag_active and game.ghost == null, scenario + " release is terminal and clears ghost")
		snapshot_unchanged(before,revision,undos,scenario + " drag rejection")
	for interruption in ["lost-release","focus-loss","right-click"]:
		start_drag(BATTERY); game.cursor = Vector2(0,25)
		if interruption == "lost-release": game._process(0.0)
		elif interruption == "focus-loss": game._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		else:
			var cancel := InputEventMouseButton.new(); cancel.pressed = true; cancel.button_index = MOUSE_BUTTON_RIGHT
			game._input(cancel); cancel.pressed = false; game._input(cancel)
		check(not game.drag_active and game.mode == "select" and game.ghost == null, interruption + " cancels interrupted drag")
		snapshot_unchanged(before,revision,undos,interruption + " drag interruption")
	start_drag(BATTERY); game.cursor = Vector2(-20,25); game._input(button(false))
	snapshot_unchanged(before,revision,undos,"same-location drag release")
	start_drag(BATTERY); game.cursor = Vector2(0,25); game._input(button(false))
	check(game.device(BATTERY).x == 0 and game.device(BATTERY).z == 25, "valid release commits destination")
	check(game.scene_revision == revision + 1 and game.undo_states.size() == undos + 1, "whole drag creates exactly one checkpoint")
	check(game.device(BATTERY).state.energy_mwh == 0.25 and game.device(STORE).state.energy_mwhth == 0.625 and game.elapsed_s == 123.5, "successful move preserves time and both energy inventories")
	check(not game.drag_active and game.mode == "select" and game.ghost == null, "successful drag clears all transient state")
	var committed := frozen(); game._input(button(false))
	check(frozen() == committed and game.undo_states.size() == undos + 1, "duplicate release cannot commit twice")
	game.undo(); check(frozen() == before and game.undo_states.size() == undos, "one undo restores exact pre-drag save")
	game.select_device(BATTERY); game.set_mode("move"); game.picked_id = BATTERY; game.press_ground = Vector2(-18,28)
	game._unhandled_input(button(true)); game._unhandled_input(motion(Vector2(410,400)))
	check(game.drag_offset.is_equal_approx(Vector2(2,3)), "off-center body grab records its terrain offset")
	game.cursor = Vector2(2,28); game._input(button(false))
	check(Vector2(game.device(BATTERY).x,game.device(BATTERY).z).is_equal_approx(Vector2(0,25)), "release subtracts grab offset instead of snapping equipment to pointer")
	check(game.undo_states.size() == undos + 1, "off-center drag still records one transaction")
	game.undo(); check(frozen() == before, "off-center drag is exactly reversible")
	var children := var_to_bytes(game.devices); var links := var_to_bytes(game.links)
	start_drag(SITE); game.cursor = Vector2(45,20); game._input(button(false))
	check(game.station(SITE).x == 45 and game.station(SITE).z == 20, "facility drag uses same atomic controller path")
	check(var_to_bytes(game.devices) == children and var_to_bytes(game.links) == links, "facility drag never relocates or duplicates internal physical equipment")
	check(game.undo_states.size() == undos + 1, "facility drag also creates one undo")
	game.undo(); check(frozen() == before, "facility drag undo restores complete layout and inventory")

func test_link_and_build_previews() -> void:
	var before := frozen(); var revision := game.scene_revision; var undos := game.undo_states.size()
	game.set_mode("link"); game.link_to(PV); game.picked_id = AC; game.update_interaction_visuals()
	check(game.pending_link == PV and game.compatible_target(AC), "connection mode retains source and recognizes typed compatible target")
	check(is_instance_valid(game.link_preview), "compatible hover produces a transient route")
	snapshot_unchanged(before,revision,undos,"connection route preview")
	game.picked_id = EXCHANGER; game.update_interaction_visuals()
	check(not game.compatible_target(EXCHANGER) and game.link_preview == null, "incompatible energy carrier removes route preview")
	game.picked_id = AC; game.update_interaction_visuals(); escape()
	check(game.mode == "select" and game.pending_link == -2 and game.link_preview == null, "Escape cancels pending source and visual route")
	snapshot_unchanged(before,revision,undos,"cancelled connection")
	game.start_build("battery"); game.cursor = Vector2(0,25); game._process(0.0)
	check(is_instance_valid(game.ghost) and game.ghost.preview_valid, "build preview still uses authoritative placement guard")
	game.cancel_interaction(); game.cancel_interaction()
	check(game.ghost == null and game.placement_outline == null and game.selected_id == -2, "repeated cancel leaves no preview or stale selection")
	snapshot_unchanged(before,revision,undos,"build preview and repeated cancel")

func test_disk_roundtrip() -> void:
	var before: Dictionary = game.state()
	var path := "user://interaction_polish_%d.json" % OS.get_process_id()
	check(game.write_save(path), "writes actual polished-scene save")
	var on_disk: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	check(on_disk.schema == 13 and on_disk.model_version == 22, "polish preserves current schema13 and physical model22")
	check(not on_disk.has("drag_active") and not on_disk.has("hovered_id") and not on_disk.has("link_preview"), "transient interaction state is never serialized")
	check(game.read_save(path), "reloads actual save through validated controller path")
	check(JSON.parse_string(JSON.stringify(game.state())) == JSON.parse_string(JSON.stringify(before)), "actual file roundtrip preserves complete scene and inventory")
	check(game.paused and game.speed == 1 and game.accumulator == 0, "reload remains safely paused")
	DirAccess.remove_absolute(path)

func interior_pixel(interior, point: Vector2) -> Vector2:
	return interior.camera.unproject_position(Vector3(point.x,0,point.y)) * interior.view_container.size / Vector2(interior.viewport.size)

func interior_button(interior, point: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new(); event.button_index = MOUSE_BUTTON_LEFT; event.pressed = pressed; event.position = point
	interior.view_container.gui_input.emit(event)

func interior_motion(interior, point: Vector2) -> void:
	var event := InputEventMouseMotion.new(); event.position = point; event.button_mask = MOUSE_BUTTON_MASK_LEFT
	interior.view_container.gui_input.emit(event)

func test_station_navigation() -> void:
	game.station_interior.free()
	var interior = load("res://scripts/station_interior.gd").new()
	game.station_interior = interior; game.add_child(interior); interior.setup(game)
	game.select_device(SITE); game.focus_selected()
	var base_camera := game.camera.transform; var base_target := game.target
	var base_yaw := game.yaw; var base_pitch := game.pitch; var base_distance := game.distance
	var before := frozen(); var revision := game.scene_revision; var undos := game.undo_states.size()
	game.open_station(SITE); await process_frame; await process_frame
	check(interior.visible and root.disable_3d, "actual station entry opens isolated interior and suspends base draw")
	interior._select(STORE)
	for view in [[145.0,30.0,6.2],[-35.0,22.0,4.2],[45.0,55.0,5.0]]:
		interior.set_camera_view(view[0],view[1],view[2]); interior.refresh()
	snapshot_unchanged(before,revision,undos,"interior selection, refresh and three camera angles")
	interior.reset_camera(); await process_frame
	var visual: Node3D = interior.equipment_nodes[STORE]
	var bounds: AABB = visual.get_meta("pick_bounds")
	var source: Vector2 = interior.camera.unproject_position(visual.to_global(bounds.get_center())) * interior.view_container.size / Vector2(interior.viewport.size)
	check(interior.device_at_view(source) == STORE, "actual interior body pick identifies store at metric scale")
	var origin := Vector2(float(game.device(STORE).interior_x),float(game.device(STORE).interior_z))
	var grab: Vector2 = interior.floor_at(source)
	var destination := Vector2(-1.4,1.2)
	check(game.can_place_internal(SITE,"thermal_store",destination,STORE).is_empty(), "interior drag fixture destination passes real layout guard")
	var destination_pixel := interior_pixel(interior,grab + destination - origin)
	interior.set_interaction_mode("move"); interior_button(interior,source,true); interior_motion(interior,destination_pixel)
	check(interior._move_drag_active and is_instance_valid(interior.preview) and interior.preview.preview_valid, "interior drag shows valid transient preview")
	snapshot_unchanged(before,revision,undos,"interior live drag")
	var esc := InputEventKey.new(); esc.keycode = KEY_ESCAPE; esc.pressed = true
	interior.window_input.emit(esc)
	check(interior.visible and interior.interaction_mode == "select" and interior.preview == null and not interior._move_drag_active, "interior Escape cancels drag without exiting")
	snapshot_unchanged(before,revision,undos,"interior cancelled drag")
	interior.set_interaction_mode("move"); interior_button(interior,source,true)
	var occupied := Vector2(float(game.device(BOILER).interior_x),float(game.device(BOILER).interior_z))
	var occupied_pixel := interior_pixel(interior,grab + occupied - origin)
	interior_motion(interior,occupied_pixel)
	check(is_instance_valid(interior.preview) and not interior.preview.preview_valid, "interior occupied destination visibly rejects move")
	interior_button(interior,occupied_pixel,false)
	check(not interior._move_drag_active and interior.preview == null, "interior illegal release clears transient preview")
	snapshot_unchanged(before,revision,undos,"interior illegal release")
	interior.set_interaction_mode("move"); interior_button(interior,source,true); interior_motion(interior,destination_pixel); interior_button(interior,destination_pixel,false)
	check(Vector2(game.device(STORE).interior_x,game.device(STORE).interior_z).is_equal_approx(destination), "interior drag commits correct grab-offset destination")
	check(game.scene_revision == revision + 1 and game.undo_states.size() == undos + 1, "interior drag adds exactly one real host undo")
	check(game.elapsed_s == 123.5 and game.device(STORE).state.energy_mwhth == 0.625 and game.device(BATTERY).state.energy_mwh == 0.25, "interior layout commit preserves both inventories and simulation time")
	game.undo(); check(frozen() == before, "one undo restores full interior layout and inventory")
	game.open_station(SITE); await process_frame
	interior._select(STORE); interior.start_build("electric_boiler")
	interior.window_input.emit(esc)
	check(interior.visible and interior.interaction_mode == "select", "first Escape cancels interior tool")
	interior.window_input.emit(esc)
	check(not interior.visible and not root.disable_3d and game.selected_id == SITE, "second Escape returns to base and reselects facility")
	check(game.camera.transform.is_equal_approx(base_camera) and game.target == base_target and game.yaw == base_yaw and game.pitch == base_pitch and game.distance == base_distance, "return preserves exact base camera, target, distance and angles")
	check(frozen() == before, "interior navigation and staged Escape never alter saved state")
