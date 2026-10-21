extends SceneTree
## Real feedback and picking methods on synthetic sloped terrain. No Terrain3D,
## native windows, save writes, or changes to the energy model.
class FeedbackController:
	extends "res://scripts/world_game.gd"
	var cursor := Vector2.ZERO
	var over_ui := false
	var last_notice := ""
	func _ready():
		cfg = {"max_build_slope_degrees": 8.0}
		for kind in ["wind", "pv", "station"]: templates[kind] = model.defaults(kind)
		add_child(equipment); add_child(cables); add_child(camera); add_child(labels)
		camera.position = Vector3(0, 18, 30)
		camera.look_at(Vector3(0, 5, 0))
		camera.current = true
		booted = true
		set_process(false)
	func exclusion(_x: float, _z: float) -> String: return ""
	func slope_at(_x: float, _z: float) -> float: return 3.0
	func height_at(x: float, z: float) -> float: return x * 0.03 + z * 0.02
	func pick_ground(_position: Vector2) -> Vector2: return cursor
	func pointer_over_ui(_position: Vector2, _padding: Vector2 = Vector2.ZERO) -> bool: return over_ui
	func modal_visible() -> bool: return false
	func update_status(): pass
	func refresh(): pass
	func tell(message: String): last_notice = message

var game: FeedbackController
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("CONSTRUCTION_FEEDBACK: " + label)
func _initialize(): call_deferred("_run")
func tick(point: Vector2) -> void:
	game.cursor = point
	game._process(0.0)
func solved() -> Dictionary:
	return game.model.solve(game.devices, game.links, {"wind_speed_mps":12.0,"irradiance_wm2":800.0,"temperature_c":25.0})
func _run():
	root.size = Vector2i(1600, 1000)
	game = FeedbackController.new()
	root.add_child(game)
	game.devices = [
		{"id":0,"kind":"wind","x":0.0,"z":0.0,"params":game.templates.wind.duplicate(true)},
		{"id":7,"kind":"station","x":30.0,"z":0.0,"params":game.templates.station.duplicate(true)}]
	game.links = [{"from":0,"to":7,"capacity_mw":8.0,"loss_fraction":0.02},{"from":7,"to":-1,"capacity_mw":4.0,"loss_fraction":0.02}]
	game.next_id = 8
	game.selected_id = 0
	game.rebuild_equipment()
	var before := game.state()
	var output := solved()
	game.set_mode("move")
	check(game.ghost != null and game.ghost.device_kind == "wind", "move creates selected device ghost")
	tick(Vector2.ZERO)
	check(game.ghost.preview_valid, "move ignores original device occupancy")
	check(game.can_place("wind", Vector2.ZERO) != "", "build still rejects original occupancy")
	tick(Vector2(-20, 8))
	check(game.ghost.preview_valid, "valid destination is green")
	check(game.ghost.position.is_equal_approx(Vector3(-20,game.height_at(-20,8)+0.005,8)), "ghost follows sampled ground height")
	check(game.state() == before and solved() == output, "live valid feedback leaves model and state unchanged")
	var arrays: Array = game.placement_outline.mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	check(vertices.size() == 64 * 6, "outline contains 64 solid ribbon segments")
	for vertex in vertices:
		check(is_equal_approx(vertex.y,game.height_at(vertex.x,vertex.z)+0.30), "outline vertex conforms to terrain")
	var outline = game.placement_outline.mesh
	tick(Vector2(-20,8))
	check(game.placement_outline.mesh == outline, "unchanged outline reuses geometry")
	game.set_mode("select")
	check(game.ghost == null and game.placement_outline == null, "cancel clears all feedback")
	check(game.state() == before and game.undo_states.is_empty(), "valid move cancellation is atomic")
	game.set_mode("move")
	tick(Vector2(30,0))
	check(not game.ghost.preview_valid, "occupied destination is invalid")
	check(not game.move_selected(Vector2(30,0)), "invalid move cannot commit")
	check(game.state() == before and game.undo_states.is_empty(), "invalid move rejection leaves state unchanged")
	game.over_ui = true
	tick(Vector2(-20,8))
	check(not game.ghost.visible and not game.placement_outline.visible, "HUD hover suppresses ghost and footprint")
	game.over_ui = false
	game.set_mode("select")
	check(game.state() == before, "invalid move cancellation preserves state")
	game.set_mode("move")
	game.select_device(7)
	check(game.mode == "select" and game.ghost == null, "changing selection cancels stale move preview")
	game.selected_id = -2
	game.set_mode("move")
	check(game.mode == "select" and game.ghost == null, "move without selection falls back safely")
	game.start_build("pv")
	tick(Vector2(-25,0))
	check(game.mode == "select" and game.ghost == null and game.last_notice.contains("旧比例"), "legacy layout rejects new PV construction without a preview")
	game.set_mode("link")
	check(game.ghost == null and game.placement_outline == null and game.pending_link == -2, "link transition clears construction feedback")
	check(game.state() == before and solved() == output, "all feedback transitions preserve physics")
	game.set_mode("select")
	var body_point := game.camera.unproject_position(Vector3(0, 6, 0))
	check(body_point.distance_to(game.camera.unproject_position(game.endpoint(0))) > 42, "body pick fixture is outside port hit radius")
	check(game.nearest(body_point) == 0, "visible turbine body is clickable")
	game.set_mode("link")
	check(game.nearest(body_point) == 0, "link mode accepts visible equipment body as endpoint")
	game.selected_id = 0
	game.set_mode("move")
	check(game.move_selected(Vector2(-20,8)), "valid move commits")
	check(game.mode == "select" and game.ghost == null and game.undo_states.size() == 1, "commit exits preview and records one undo")
	game.undo()
	check(game.state() == before, "committed move remains fully undoable")
	# Separate, explicit reference-layout fixture; do not migrate the legacy move
	# case implicitly or compare its snapshot against different geometry markers.
	game.dimension_profile = "metric_v1"
	for item in game.devices: item.site_geometry_profile = "reference_size_v1"
	game.rebuild_equipment()
	before = game.state()
	output = solved()
	game.start_build("pv")
	tick(Vector2(-25, 0))
	check(game.ghost != null and game.ghost.device_kind == "pv" and game.ghost.preview_valid, "reference layout creates the correct valid PV preview")
	game.set_mode("link")
	check(game.ghost == null and game.placement_outline == null and game.pending_link == -2, "reference build-to-link transition clears all construction feedback")
	check(game.state() == before and solved() == output, "reference preview and cancellation preserve its own snapshot and physics")
	game.set_mode("select")
	for key in ["lod_camera","terrain","infrastructure","selection","overlay","confirmation","param_dialog","param_errors","param_target","data_dialog","data_list","line_dialog","line_capacity","line_loss","line_choice"]:
		var node = game.get(key)
		if is_instance_valid(node) and node.get_parent() == null: node.free()
	game.free()
	await process_frame
	print("CONSTRUCTION_FEEDBACK_TEST checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
