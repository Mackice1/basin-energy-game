extends SceneTree
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
  push_error("INSPECTOR_V23_FAIL " + message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 root.size = Vector2i(1440, 900)
 var host := Host.new()
 root.add_child(host)
 var inspector := Inspector.new()
 host.add_child(inspector)
 inspector.setup(host)
 var id := 0
 for kind in Catalog.implemented_kinds():
  host.devices.append({"id":id, "kind":kind, "params":Catalog.defaults(kind), "state":{"energy_mwh":0.25}})
  host.result.get_or_add("devices", {})[str(id)] = {"generated_mw":1.25, "connected":false}
  id += 1
 var before: Array = [host.devices, host.links, host.result].duplicate(true)
 for profile in ["metric_v1", "legacy_illustrative"]:
  host.dimension_profile = profile
  for device in host.devices:
   check(inspector.open_device(int(device.id)), profile + " opens " + device.kind)
   await process_frame
   inspector.reset_camera()
   check(is_instance_valid(inspector.model_node), "actual model " + device.kind)
   check(inspector.model_node.get("device_kind") == device.kind, "correct visual kind " + device.kind)
   check(inspector.camera_distance > inspector.model_radius, "framed outside bounds " + device.kind)
   check(inspector.camera.position.is_finite(), "finite camera " + device.kind)
   var bounds_parts: Array[AABB] = inspector._bounds(inspector.model_node)
   var bounds: AABB = bounds_parts[0]
   for part in bounds_parts: bounds = bounds.merge(part)
   var canvas := Rect2(Vector2.ZERO, Vector2(inspector.viewport.size))
   for corner in 8:
    var point: Vector3 = bounds.get_endpoint(corner)
    check(not inspector.camera.is_position_behind(point), "framing keeps geometry in front " + device.kind)
    check(canvas.has_point(inspector.camera.unproject_position(point)), "projected corner inside viewport " + device.kind)
   check(inspector.texts["边界"].text.contains("未建模"), "model boundary " + device.kind)
   check(inspector.texts["参数"].text.contains("设备当前参数"), "parameters " + device.kind)
   check(inspector.texts["运行"].text.contains("1.25"), "authoritative result " + device.kind)
   inspector.close_device()
 inspector.open_device(0)
 host.result.devices["0"].generated_mw = 9.75
 inspector.refresh()
 check(inspector.texts["运行"].text.contains("9.75"), "live report changes")
 host.links.append({"from":0,"to":2,"from_port":"out","to_port":"in","capacity_mw":3.0})
 inspector.refresh()
 check(inspector.texts["连接"].text.contains(Inspector.NAMES.station + " #2"), "actual neighbor and link")
 var old_model = inspector.model_node
 host.devices[0].params.rotor_diameter_m = 150.0
 inspector.refresh()
 check(inspector.model_node != old_model, "changed dimensions rebuild actual visual")
 host.devices[0].params.rotor_diameter_m = Catalog.defaults("wind").rotor_diameter_m
 inspector.refresh()
 var preserved_report: Dictionary = host.result.devices["0"]
 host.result.devices.erase("0")
 inspector.refresh()
 check(inspector.texts["运行"].text.contains("尚无本设备计算结果"), "absent result is not fabricated zero")
 host.result.devices["0"] = preserved_report
 var wheel := InputEventMouseButton.new()
 wheel.pressed = true
 wheel.button_index = MOUSE_BUTTON_WHEEL_UP
 var distance: float = inspector.camera_distance
 inspector._view_input(wheel)
 check(inspector.camera_distance < distance, "wheel zooms")
 var saved: Dictionary = host.devices.pop_front()
 inspector.refresh()
 check(inspector.model_node == null and inspector.title_label.text.contains("已移除"), "deleted clears stale visual")
 host.devices.push_front(saved)
 inspector.refresh()
 check(is_instance_valid(inspector.model_node), "undo restoration rebuilds visual")
 var press := InputEventMouseButton.new()
 press.button_index = MOUSE_BUTTON_RIGHT
 press.pressed = true
 inspector._view_input(press)
 var motion := InputEventMouseMotion.new()
 motion.relative = Vector2(40, 10)
 var yaw: float = inspector.camera_yaw
 inspector._view_input(motion)
 check(inspector.camera_yaw != yaw, "right-drag orbits")
 press.pressed = false
 inspector._window_input(press)
 check(not inspector._orbit, "release ends orbit")
 press.pressed = true
 press.button_index = MOUSE_BUTTON_LEFT
 inspector._view_input(press)
 var target: Vector3 = inspector.camera_target
 inspector._view_input(motion)
 check(inspector.camera_target != target, "left-drag pans")
 var escape := InputEventKey.new()
 escape.keycode = KEY_ESCAPE
 escape.pressed = true
 inspector._window_input(escape)
 check(not inspector.visible and not inspector._pan, "Escape closes and releases camera")
 check(not inspector.open_device(99999), "invalid id rejected")
 host.result.devices["0"].generated_mw = 1.25
 host.links.clear()
 check(host.devices == before[0] and host.links == before[1] and host.result == before[2], "inspection never mutates authoritative simulation")
 host.free()
 await process_frame
 print("DEVICE_INSPECTOR_V23 checks=", checks, " failures=", failures.size())
 quit(0 if failures.is_empty() else 1)
