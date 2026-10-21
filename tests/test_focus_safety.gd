extends SceneTree
## Default-scene focus coverage: actual rendered bounds and terrain, with the
## immediate focus contract retained. No tween, model step or geometry change.
## Custom extreme hub heights need separate height-aware framing work.

const Visual = preload("res://scripts/equipment_visual.gd")
const Facade = preload("res://scripts/station_facade.gd")

class Fixture:
	extends "res://scripts/world_game.gd"
	func _ready() -> void:
		cfg = JSON.parse_string(FileAccess.get_file_as_string("res://config/map.json"))
		height_image = Image.create_from_data(1024, 1024, false, Image.FORMAT_RF, FileAccess.get_file_as_bytes("res://generated/height.raw"))
		dimension_profile = "metric_v1"
		for kind in KINDS: templates[kind] = model.defaults(kind)
		add_child(camera); add_child(lod_camera)
		camera.current = true
		camera.far = 1000.0
		set_process(false)
		set_process_input(false)
		set_process_unhandled_input(false)
	func tell(_message: String) -> void: pass

var checks := 0
var failures: Array[String] = []

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures.append(description)
		push_error("FOCUS_SAFETY: " + description)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var game := Fixture.new()
	root.add_child(game)
	var viewport_rect := game.camera.get_viewport().get_visible_rect()
	for imported in [false, true]:
		for kind in ["wind", "pv", "station", "battery", "thermal_station"]:
			var params: Dictionary = game.Catalog.defaults(kind) if kind != "thermal_station" else {}
			var visual: Node3D
			if kind == "thermal_station":
				visual = Facade.new(); root.add_child(visual)
				visual.setup({"name":"Focus fixture", "visual_dimension_profile":"metric_v1"}, imported)
				game.devices = []
				game.stations = [{"id":1000000, "name":"Focus fixture", "x":0.0, "z":0.0}]
				game.selected_id = 1000000
			else:
				var visual_params := params.duplicate(true)
				visual_params.visual_dimension_profile = "metric_v1"
				visual = Visual.create(kind, visual_params, imported); root.add_child(visual)
				game.stations = []
				game.devices = [{"id":0, "kind":kind, "x":0.0, "z":0.0, "params":params, "state":game.Catalog.initial_state(kind, params)}]
				game.selected_id = 0
			visual.position = Vector3(0.0, game.height_at(0.0, 0.0) + 0.15, 0.0)
			var surfaces: Array = visual.surfaces.duplicate()
			var original_transforms: Array[Transform3D] = []
			for surface in surfaces: original_transforms.append(surface.transform)
			var before := var_to_bytes(game.state())
			for lens in [45.0, 75.0]:
				for heading in [-0.22, 0.0, PI * 0.5, PI]:
					game.camera.fov = lens; game.yaw = heading
					game.focus_selected()
					var label := "%s/%s/fov%s/yaw%.2f" % [kind, "GLB" if imported else "fallback", lens, heading]
					check(game.target.is_finite() and game.camera.transform.is_finite(), label + " immediate focus is finite")
					check(game.camera.projection == Camera3D.PROJECTION_PERSPECTIVE and game.distance >= game.MIN_CAMERA_DISTANCE, label + " uses safe perspective distance")
					var inverse: Transform3D = game.camera.global_transform.affine_inverse()
					var safe_depth := true
					var inside_view := true
					for surface: MeshInstance3D in surfaces:
						if surface == visual.selection_ring: continue
						var box: AABB = surface.mesh.get_aabb()
						for corner in range(8):
							var point: Vector3 = surface.global_transform * box.get_endpoint(corner)
							var depth: float = -(inverse * point).z
							safe_depth = safe_depth and depth > game.camera.near and depth < game.camera.far
							inside_view = inside_view and viewport_rect.has_point(game.camera.unproject_position(point))
					check(safe_depth, label + " all rendered bounds clear near and far planes")
					check(inside_view, label + " all rendered bounds fit the viewport")
					check(var_to_bytes(game.state()) == before, label + " focus preserves serialized state")
			for index in surfaces.size(): check(surfaces[index].transform == original_transforms[index], kind + " focus never rescales geometry")
			visual.free()
	for point in [Vector2.ZERO, Vector2(-70,-42), Vector2(60,50), Vector2(-95,65)]:
		for heading in [0.0, PI * 0.5, PI]:
			game.target = Vector3(point.x, -100.0, point.y)
			game.yaw = heading; game.pitch = -1.0; game.distance = 0.001
			game.update_camera()
			check(game.target.y >= game.height_at(point.x, point.y), "target clears actual synthetic terrain")
			check(game.camera.position.y >= game.height_at(game.camera.position.x, game.camera.position.z) + game.CAMERA_GROUND_CLEARANCE - 0.00001, "close orbit origin clears actual synthetic terrain")
			check(-(game.camera.global_transform.affine_inverse() * game.target).z > game.camera.near, "near plane cannot clip the close orbit target")
	for key in ["terrain", "infrastructure", "overlay", "labels", "selection", "equipment", "cables", "confirmation", "param_dialog", "param_errors", "param_target", "data_dialog", "data_list", "line_dialog", "line_capacity", "line_loss", "line_choice"]:
		var node = game.get(key)
		if is_instance_valid(node) and node.get_parent() == null: node.free()
	game.free()
	print("FOCUS_SAFETY checks=", checks, " failures=", failures.size(), " scope=default-metric-geometry/actual-terrain/immediate-focus")
	quit(0 if failures.is_empty() else 1)
