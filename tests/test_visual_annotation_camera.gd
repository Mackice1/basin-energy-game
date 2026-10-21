extends SceneTree
## Visual-only interaction vocabulary, bounded text and terrain-safe cameras.

const Visual = preload("res://scripts/equipment_visual.gd")
const Facade = preload("res://scripts/station_facade.gd")

class MapFixture:
	extends "res://scripts/map.gd"
	func _ready() -> void:
		add_child(camera)
		add_child(lod_camera)
		camera.current = true
		set_process(false)
	func height_at(_x: float, z: float) -> float:
		return 20.0 if z > 3.0 else 2.0

var checks := 0
var failures: Array[String] = []

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures.append(description)
		push_error(description)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1440, 900)
	var map := MapFixture.new()
	root.add_child(map)
	map.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	map.camera.fov = 45.0
	map.distance = 0.01
	map.pitch = -4.0
	map.yaw = 0.0
	map.update_camera()
	check(is_equal_approx(map.distance, 8.0), "metric focus can reach eight-unit close range without crossing minimum")
	check(is_equal_approx(map.pitch, map.MIN_CAMERA_PITCH), "orbit cannot cross below safe minimum pitch")
	check(map.target.y >= map.height_at(map.target.x, map.target.z), "look target stays above local terrain")
	check(map.camera.position.y >= map.height_at(map.camera.position.x, map.camera.position.z) + map.CAMERA_GROUND_CLEARANCE - 0.00001, "perspective origin clears rising terrain behind target")
	map.distance = INF
	map.pitch = NAN
	map.yaw = INF
	map.target = Vector3(NAN, 0, 0)
	map.update_camera()
	check(map.camera.transform.is_finite() and map.target.is_finite(), "nonfinite camera inputs recover to finite transform")
	map.target = Vector3(500, -90, -200)
	map.distance = 9999
	map.update_camera()
	check(map.target.x == 100.0 and map.target.z == -70.0, "panning target stays within inspectable map")
	check(map.distance == map.MAX_CAMERA_DISTANCE, "zoom out is bounded")
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	map.distance = 8.0
	map._unhandled_input(wheel)
	check(map.distance == 8.0, "wheel zoom respects same close focus bound")
	map.set_view(0)
	check(map.pitch == map.MAX_CAMERA_PITCH, "overhead preset survives same camera clamp")
	for field in [LineEdit.new(), TextEdit.new(), SpinBox.new()]:
		root.add_child(field)
		var editor: Control = field.get_line_edit() if field is SpinBox else field
		editor.grab_focus()
		check(map.camera_keyboard_blocked(), "text and numeric entry blocks polled camera movement")
		editor.release_focus()
		field.free()
	check(not map.camera_keyboard_blocked(), "camera keyboard control resumes after entry focus clears")

	var label := Label3D.new()
	label.font_size = 40
	root.add_child(label)
	for projection in [Camera3D.PROJECTION_ORTHOGONAL, Camera3D.PROJECTION_PERSPECTIVE]:
		map.camera.projection = projection
		for zoom in [8.0, 60.0, 235.0]:
			map.distance = zoom
			map.update_camera()
			Visual.fit_screen_label(label, map.camera, 22.0)
			var projection_factor := 1.0 if projection == Camera3D.PROJECTION_ORTHOGONAL else absf(map.camera.get_camera_projection().y.y)
			var screen_height: float = label.pixel_size * label.font_size * root.get_visible_rect().size.y * 0.5 * projection_factor
			check(is_equal_approx(screen_height, 22.0), "label nominal screen height stays bounded across projection and zoom")
			check(label.fixed_size and label.is_scale_disabled(), "screen text ignores mesh parent scale")
	label.free()

	for imported in [false, true]:
		var equipment = Visual.create("thermal_store", {"visual_dimension_profile": "metric_v1", "capacity_mwhth": 12.0}, imported)
		root.add_child(equipment)
		_check_visual(equipment, "equipment " + ("GLB" if imported else "fallback"))
		for suppressed in equipment.find_children("*", "Label3D", true, false):
			if suppressed.get_meta("annotation_suppressed", false):
				check(not suppressed.visible, "duplicate module annotation remains suppressed")
		equipment.free()
		var facade := Facade.new()
		root.add_child(facade)
		facade.setup({"name": "电热储能站", "visual_dimension_profile": "metric_v1"}, imported)
		_check_visual(facade, "facade " + ("GLB" if imported else "fallback"))
		for tag in facade.annotation_labels:
			check(not tag.no_depth_test, "facade annotations respect terrain and model depth")
		facade.free()

	for orphan in [map.terrain, map.labels, map.infrastructure, map.selection, map.overlay]:
		orphan.free()
	map.free()
	print("VISUAL_ANNOTATION_CAMERA_TEST checks=", checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _check_visual(visual: Node3D, title: String) -> void:
	var transforms: Array[Transform3D] = []
	var meshes: Array[Mesh] = []
	for surface in visual.surfaces:
		transforms.append(surface.transform)
		meshes.append(surface.mesh)
	var footprint: float = visual.get_meta("footprint_radius")
	var ports: Dictionary = visual.named_port_locals.duplicate(true)
	check(not visual.selection_ring.visible, title + ": no idle selection overlay")
	for tag in visual.annotation_labels:
		check(not tag.visible, title + ": idle annotation hidden")
	visual.set_interaction_hint(true, false, false)
	check(visual.selection_ring.visible and not visual.selected, title + ": hover hint does not select")
	check(visual.selection_ring.material_override == visual.hint_materials.hover, title + ": pale hover ring")
	visual.set_interaction_hint(true, true, false)
	check(visual.selection_ring.material_override == visual.hint_materials.compatible, title + ": compatible target is cyan")
	visual.set_interaction_hint(true, true, true)
	check(visual.selection_ring.material_override == visual.hint_materials.source, title + ": source has priority over target")
	visual.set_highlight(true)
	check(visual.selection_ring.material_override == visual.hint_materials.selected, title + ": selected gold has highest priority")
	visual.set_annotation_visibility(true, false)
	for tag in visual.annotation_labels:
		check(tag.visible == (tag.name != "PortLabel"), title + ": details exclude port clutter")
	visual.set_annotation_visibility(false, true)
	for tag in visual.annotation_labels:
		check(tag.visible == (tag.name == "PortLabel"), title + ": connection mode can show ports alone")
	visual.set_annotation_visibility(true, true)
	for valid in [false, true]:
		visual.set_preview(valid)
		check(not visual.selection_ring.visible and visual.selected, title + ": preview retains selection without hint ring")
		for tag in visual.annotation_labels:
			check(not tag.visible, title + ": preview masks all intrinsic annotations")
	visual.clear_preview()
	check(visual.selection_ring.material_override == visual.hint_materials.selected, title + ": clear preview restores selected ring")
	for tag in visual.annotation_labels:
		check(tag.visible, title + ": clear preview restores requested annotations")
	visual.set_highlight(false)
	visual.set_interaction_hint(false, false, false)
	visual.set_annotation_visibility(false)
	check(not visual.selection_ring.visible, title + ": clearing interaction removes ring")
	check(visual.selection_ring.material_override == visual.hint_materials.selected, title + ": idle ring material returns to authored baseline")
	check(visual.get_meta("footprint_radius") == footprint and visual.named_port_locals == ports, title + ": hints never change siting or physical endpoints")
	for index in visual.surfaces.size():
		check(visual.surfaces[index].transform == transforms[index] and visual.surfaces[index].mesh == meshes[index], title + ": hints never resize or replace real geometry")
