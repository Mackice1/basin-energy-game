extends SceneTree
## godot --headless --path . --script res://tests/test_full_domain_framing_ux.gd
## Real camera projection and responsive HUD, without launching the terrain GUI.
const Domain = preload("res://scripts/map_domain.gd")

class WorldFixture:
	extends "res://scripts/world_game.gd"
	func _ready():
		height_image = Image.create_from_data(1024, 1024, false, Image.FORMAT_RF, FileAccess.get_file_as_bytes("res://generated/height.raw"))
		cfg = JSON.parse_string(FileAccess.get_file_as_string("res://config/map.json"))
		for kind in KINDS: templates[kind] = model.defaults(kind)
		add_child(camera); add_child(lod_camera); add_child(equipment); add_child(cables)
		camera.current = true; camera.far = 2000.0
		make_ui(); booted = true; set_process(false)

var checks := 0
var failures: Array[String] = []
var game: WorldFixture

func _initialize(): call_deferred("run")
func check(ok: bool, description: String):
	checks += 1
	if not ok:
		failures.append(description)
		push_error("FULL_DOMAIN_FRAMING_UX: " + description)

func fit_check(context: String):
	var usable := game.overview_usable_rect()
	check(usable.size.x > 0.0 and usable.size.y > 0.0, context + " positive usable viewport")
	check(game.distance >= game.MIN_CAMERA_DISTANCE and game.distance <= game.MAX_CAMERA_DISTANCE, context + " orbit distance remains bounded")
	check(game.camera.position.is_finite() and game.target.is_finite(), context + " finite camera and target")
	check(game.pitch >= game.MIN_CAMERA_PITCH and game.pitch <= game.MAX_CAMERA_PITCH, context + " pitch remains bounded")
	check(Domain.contains(Vector2(game.target.x, game.target.z)), context + " target remains in domain")
	check(is_equal_approx(game.target.x, 0.0) and is_equal_approx(game.target.z, 0.0), context + " overview targets actual domain centre")
	var screen_min := Vector2(INF, INF)
	var screen_max := Vector2(-INF, -INF)
	# Independent 10-unit sampling is denser than the fitter's 20-unit grid.
	for x in range(-200, 201, 10):
		for z in range(-200, 201, 10):
			var world := Vector3(x, game.height_at(x, z), z)
			var screen := game.camera.unproject_position(world)
			check(not game.camera.is_position_behind(world) and usable.has_point(screen), context + " domain point visible " + str(Vector2(x, z)))
			check(-game.camera.to_local(world).z >= game.camera.near and -game.camera.to_local(world).z < game.camera.far, context + " point inside near/far")
			screen_min = screen_min.min(screen); screen_max = screen_max.max(screen)
	var fill := (screen_max - screen_min) / usable.size
	check(maxf(fill.x, fill.y) > 0.90 and maxf(fill.x, fill.y) < 1.0, context + " tight readable fit, not excessive blank margins")
	for p in [Vector2(-195, -195), Vector2(195, -195), Vector2(-195, 195), Vector2(195, 195), Vector2(0, 0)]:
		var screen := game.camera.unproject_position(Vector3(p.x, game.height_at(p.x, p.y), p.y))
		check(game.pick_ground(screen).distance_to(p) < 0.1, context + " screen offset preserves edge picking " + str(p))
	print("FULL_DOMAIN_FRAME ", context, " usable=", usable, " distance=", game.distance, " projection_span=", game.camera.size, " fill=", fill)

func run():
	root.content_scale_size = Vector2i.ZERO
	root.gui_embed_subwindows = true
	root.size = Vector2i(1440, 900)
	game = WorldFixture.new(); root.add_child(game)
	await process_frame; await process_frame
	# Physical records and transforms must remain exactly unchanged by framing.
	var params: Dictionary = game.model.defaults("battery")
	game.devices.append({"id": 77, "kind": "battery", "x": 145.0, "z": -132.0, "params": params, "state": {"energy_mwh": 0.25}})
	var physical := Node3D.new(); game.equipment.add_child(physical)
	physical.position = Vector3(145.0, game.height_at(145.0, -132.0), -132.0)
	var original_records := JSON.stringify([game.devices, game.links, game.elapsed_s, game.energy, game.dimension_profile])
	var original_transform := physical.transform
	for resolution in [Vector2i(1920, 1080), Vector2i(1440, 900), Vector2i(1024, 768), Vector2i(640, 480)]:
		root.size = resolution
		await process_frame; await process_frame; await process_frame
		game._layout_workspace()
		game.reset_camera()
		var context := str(resolution)
		fit_check(context)
		var usable := game.overview_usable_rect()
		check(usable.position.y >= game.hud_views.get_global_rect().end.y, context + " below header and view toolbar")
		check(usable.end.y <= game.hud_context.get_global_rect().position.y, context + " above context/build/footer bars")
		check(usable.end.x <= game.hud_dock.get_node("DockRail").get_global_rect().position.x, context + " left of navigation rail")
		var initial_span := game.camera.size
		var initial_offset := Vector2(game.camera.h_offset, game.camera.v_offset)
		game.distance *= 0.91; game.update_camera()
		check(is_equal_approx(game.camera.size, initial_span * 0.91), context + " first zoom after overview stays continuous")
		check(Vector2(game.camera.h_offset, game.camera.v_offset).is_equal_approx(initial_offset * 0.91), context + " zoom keeps consistent screen centring")
		game.selected_id = 77; game.focus_selected()
		check(game.camera.projection == Camera3D.PROJECTION_PERSPECTIVE and game.camera.h_offset == 0.0 and game.camera.v_offset == 0.0, context + " actual device focus clears overview correction")
		check(game.target.x == 145.0 and game.target.z == -132.0 and game.distance <= 235.0, context + " unchanged local device focus")
		game.reset_camera(); fit_check(context + " after focus")
		var pose := [game.target, game.camera.transform, game.distance, game.camera.size, game.camera.h_offset, game.camera.v_offset]
		game.reset_camera()
		check(pose == [game.target, game.camera.transform, game.distance, game.camera.size, game.camera.h_offset, game.camera.v_offset], context + " repeated overview idempotent")
		for mode in range(3):
			game.set_view(mode)
			check(game.distance == 235.0 and game.camera.size == 235.0, context + " preset retains readable local scale " + str(mode))
			check(game.camera.projection == (Camera3D.PROJECTION_PERSPECTIVE if mode == 2 else Camera3D.PROJECTION_ORTHOGONAL), context + " preset projection " + str(mode))
			check(game.camera.h_offset == 0.0 and game.camera.v_offset == 0.0, context + " preset has no stale offsets " + str(mode))
			game.reset_camera()
	# An untouched overview follows a resize after responsive layout, but a
	# focused device must never be recentered by the same resize callback.
	root.size = Vector2i(1920, 1080)
	await process_frame; await process_frame; await process_frame
	game.reset_camera()
	root.size = Vector2i(640, 480)
	await process_frame; await process_frame; await process_frame
	fit_check("automatic 1920x1080 -> 640x480")
	game.selected_id = 77; game.focus_selected()
	var focused_target := game.target
	root.size = Vector2i(1024, 768)
	await process_frame; await process_frame; await process_frame
	check(game.target == focused_target and game.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "resize does not hijack device focus")
	game.reset_camera()
	var closed_span := game.camera.size
	game.hud_dock.toggle_panel("templates")
	await process_frame; await process_frame
	fit_check("1024x768 automatically after opening scene panel")
	check(game.camera.size > closed_span, "opening sidebar automatically refits untouched overview without pressing R")
	check(game.overview_usable_rect().end.x <= game.hud_dock.panels.templates.get_global_rect().position.x, "overview avoids an opened side panel")
	game.hud_dock.close_panels()
	await process_frame; await process_frame
	fit_check("1024x768 automatically after closing scene panel")
	check(is_equal_approx(game.camera.size, closed_span), "closing sidebar automatically restores readable full-width overview")
	game.selected_id = 77; game.focus_selected()
	focused_target = game.target
	game.hud_dock.toggle_panel("templates")
	await process_frame; await process_frame
	check(game.target == focused_target and game.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "opening sidebar does not hijack device focus")
	game.hud_dock.close_panels(); game.reset_camera()
	game.pan_camera(Vector2(20.0, 10.0))
	var panned_pose := [game.target, game.camera.transform, game.distance, game.camera.size]
	game.hud_dock.toggle_panel("templates")
	await process_frame; await process_frame
	check(panned_pose == [game.target, game.camera.transform, game.distance, game.camera.size], "opening sidebar does not hijack a manually panned overview")
	check(original_records == JSON.stringify([game.devices, game.links, game.elapsed_s, game.energy, game.dimension_profile]), "all camera operations preserve equipment, state, units, links and elapsed time")
	check(physical.transform == original_transform, "all camera operations preserve physical device transform")
	game.target = Vector3(INF, NAN, INF); game.distance = INF; game.pitch = NAN; game.yaw = INF; game.update_camera()
	check(game.target.is_finite() and game.camera.position.is_finite(), "existing non-finite camera recovery preserved")
	game.distance = 9999.0; game.target = Vector3(9999, 0, -9999); game.update_camera()
	check(game.distance == 650.0 and game.target.x == 200.0 and game.target.z == -200.0, "existing distance and target limits unchanged")
	for key in ["terrain", "labels", "infrastructure", "selection", "overlay"]:
		var node = game.get(key)
		if is_instance_valid(node) and node.get_parent() == null: node.free()
	game.free()
	print("FULL_DOMAIN_FRAMING_UX checks=", checks, " failures=", failures.size(), " mode=headless real-camera/real-HUD")
	quit(0 if failures.is_empty() else 1)
