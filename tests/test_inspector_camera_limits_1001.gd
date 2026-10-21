extends SceneTree
## Run: godot --headless --path . --script res://tests/test_inspector_camera_limits_1001.gd
const Inspector = preload("res://scripts/device_inspector.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
class Host:
 extends Node
 var devices: Array = []
 var links: Array = []
 var result: Dictionary = {}
 var dimension_profile := "metric_v1"
 func device(id: int) -> Dictionary:
  for item in devices:
   if int(item.id) == id: return item
  return {}
 func visual_params(params: Dictionary) -> Dictionary:
  var value := params.duplicate(true)
  value.visual_dimension_profile = dimension_profile
  return value
var failures: Array[String] = []
var checks := 0
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok:
  failures.append(message)
  push_error("INSPECTOR_CAMERA_1001_FAIL " + message)
func _initialize() -> void: call_deferred("run")
func wheel(inspector: Window, button: MouseButton, count: int) -> void:
 var event := InputEventMouseButton.new()
 event.pressed = true
 event.button_index = button
 for step in count: inspector._view_input(event)
func drag(inspector: Window, button: MouseButton, relative: Vector2) -> void:
 var press := InputEventMouseButton.new()
 press.button_index = button
 press.pressed = true
 inspector._view_input(press)
 var motion := InputEventMouseMotion.new()
 motion.relative = relative
 inspector._view_input(motion)
 press.pressed = false
 inspector._window_input(press)
func check_camera(inspector: Window, context: String, close_up := false) -> void:
 check(inspector.camera.position.is_finite() and inspector.camera_target.is_finite(), context + " finite camera")
 check(inspector.camera_distance > 0.0, context + " positive distance")
 check(inspector.camera_distance <= inspector.max_zoom_out_distance * 1.0001, context + " zoom-out capped")
 check(is_equal_approx(inspector.max_zoom_out_distance, inspector.fit_distance * 1.6), context + " 1.6x fit cap")
 var center: Vector3 = inspector.model_center
 check(not inspector.camera.is_position_behind(center), context + " center in front")
 var screen: Vector2 = inspector.camera.unproject_position(center) / Vector2(inspector.viewport.size)
 # Tiny zoom distances incur single-precision transform cancellation; allow 3%.
 var margin := 0.17 if close_up else 0.199
 check(screen.is_finite() and screen.x >= margin and screen.x <= 1.0 - margin and screen.y >= margin and screen.y <= 1.0 - margin, context + " center inside middle 60% " + str(screen))
 var depth_error: float = absf((inspector.camera_target - center).dot(inspector.camera.basis.z))
 check(depth_error <= maxf(inspector.model_radius * 0.000002, inspector.camera_distance * 0.0001), context + " pan remains in center depth plane")
func check_fit(inspector: Window, context: String) -> void:
 var canvas := Rect2(Vector2(-1, -1), Vector2(inspector.viewport.size) + Vector2(2, 2))
 for corner in 8:
  var point: Vector3 = inspector.model_bounds.get_endpoint(corner)
  check(not inspector.camera.is_position_behind(point) and canvas.has_point(inspector.camera.unproject_position(point)), context + " reset fits AABB corner " + str(corner))
func run() -> void:
 var host := Host.new()
 root.add_child(host)
 var inspector := Inspector.new()
 host.add_child(inspector)
 inspector.setup(host)
 var kinds: Array = Catalog.implemented_kinds()
 check(kinds.size() == Catalog.implemented_kinds().size(), "all implemented equipment kinds covered")
 for kind in kinds:
  var id := host.devices.size()
  host.devices.append({"id":id, "kind":kind, "params":Catalog.defaults(kind), "state":{"energy_mwh":0.25}})
  host.result.get_or_add("devices", {})[str(id)] = {"generated_mw":1.25, "connected":false}
 host.links.append({"from":0,"to":2,"from_port":"out","to_port":"in","capacity_mw":3.0})
 var before: Array = [host.devices, host.links, host.result].duplicate(true)
 for resolution in [Vector2i(1440, 900), Vector2i(1024, 768)]:
  root.size = resolution
  for profile in ["metric_v1", "legacy_illustrative"]:
   host.dimension_profile = profile
   for device in host.devices:
    var context := "%s %s %s" % [str(resolution), profile, device.kind]
    check(inspector.open_device(int(device.id)), context + " opens")
    await process_frame
    await process_frame
    inspector.reset_camera()
    check_camera(inspector, context + " reset")
    check_fit(inspector, context)
    wheel(inspector, MOUSE_BUTTON_WHEEL_DOWN, 200)
    check(is_equal_approx(inspector.camera_distance, inspector.max_zoom_out_distance), context + " 200 down stops at cap")
    check_camera(inspector, context + " zoomed out")
    for step in 12:
     var direction := Vector2(1 if step % 2 == 0 else -1, 1 if step % 3 == 0 else -1)
     drag(inspector, MOUSE_BUTTON_LEFT if step % 2 == 0 else MOUSE_BUTTON_MIDDLE, direction * 100000.0)
     check_camera(inspector, context + " huge pan " + str(step))
     drag(inspector, MOUSE_BUTTON_RIGHT, direction * Vector2(1700, 1100))
     check_camera(inspector, context + " orbit after pan " + str(step))
    wheel(inspector, MOUSE_BUTTON_WHEEL_UP, 200)
    check(inspector.camera_distance < inspector.model_radius * 0.002, context + " zoom-in far past previous radius*0.25 floor")
    check_camera(inspector, context + " 200 up", true)
    for step in 4:
     drag(inspector, MOUSE_BUTTON_LEFT, Vector2(100000, -100000))
     check_camera(inspector, context + " close-up huge pan " + str(step), true)
     drag(inspector, MOUSE_BUTTON_RIGHT, Vector2(-1700, 1100))
     check_camera(inspector, context + " close-up orbit " + str(step), true)
    # Resizing an already panned/rotated/zoomed view must remain recoverable.
    inspector.size = Vector2i(680, 480)
    await process_frame
    await process_frame
    check_camera(inspector, context + " narrow resize", true)
    inspector.size = Vector2i(resolution * 0.94)
    await process_frame
    await process_frame
    check_camera(inspector, context + " restored resize", true)
    inspector.reset_camera()
    check_fit(inspector, context + " final reset")
    check(inspector.camera_target.is_equal_approx(inspector.model_center), context + " reset recenters")
    inspector.close_device()
    check(not inspector._pan and not inspector._orbit, context + " closing releases drags")
 check(host.devices == before[0] and host.links == before[1] and host.result == before[2], "camera actions never mutate authoritative devices, state, links, or results")
 host.free()
 await process_frame
 print("INSPECTOR_CAMERA_1001 checks=", checks, " failures=", failures.size())
 quit(0 if failures.is_empty() else 1)
