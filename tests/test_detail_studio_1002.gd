extends SceneTree
const Inspector = preload("res://scripts/device_inspector.gd")
const TestHost = preload("res://tests/test_device_inspector_v23.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
const Visual = preload("res://scripts/equipment_visual.gd")
var checks := 0
func verify(ok: bool, message: String):
 checks += 1
 assert(ok, message)
func _initialize(): call_deferred("run")
func run():
 var host = TestHost.Host.new()
 root.add_child(host)
 var inspector = Inspector.new()
 host.add_child(inspector); inspector.setup(host)
 for kind in Catalog.implemented_kinds():
  host.devices.append({"id":host.devices.size(),"kind":kind,"params":Catalog.defaults(kind),"state":{}})
 var baseline = var_to_bytes([host.devices,host.links,host.result])
 for resolution in [Vector2i(1440,900),Vector2i(1024,768)]:
  root.size = resolution
  for item in host.devices:
   inspector.open_device(item.id)
   await process_frame
   inspector.reset_camera()
   verify(inspector.studio_environment.background_color == Color("87989f"), "tower-style background for " + item.kind)
   verify(inspector.studio_light.shadow_enabled, "real shadows for " + item.kind)
   verify(inspector.studio_ground.get_parent() == inspector.scene_root, "ground excluded from model subtree")
   verify(inspector.studio_ground.position.y < inspector.model_bounds.position.y, "ground below equipment")
   verify(inspector.studio_ground.scale.x > inspector.model_bounds.size.x, "ground width covers equipment")
   verify(inspector.studio_ground.scale.z > inspector.model_bounds.size.z, "ground depth covers equipment")
   verify(inspector.model_bounds.size.length() < inspector.studio_ground.scale.length(), "ground not in fit bounds")
   if item.kind in ["pv","station"]:
    verify(inspector.model_node.get_meta("representative_only"), "explicit representative metadata")
    verify(inspector.model_label.text.contains("非全"), "representative label is visible")
   if item.kind == "pv":
    verify(inspector.model_node.get_meta("sample_module_count") == 3, "three representative modules")
    verify(inspector.model_node.get_child_count() < 20, "batched PV display meshes")
    verify(inspector.camera_yaw == 145.0, "front face is default view")
   inspector.close_device()
 verify(baseline == var_to_bytes([host.devices,host.links,host.result]), "no representative count or scenery modifies simulation")
 var main_pv = Visual.create("pv",host.visual_params(Catalog.defaults("pv")),true)
 verify(not main_pv.has_meta("representative_only"), "main PV remains complete real field visual")
 main_pv.free()
 verify(ProjectSettings.get_setting("application/config/version") == "1.0.0.2", "single-source version")
 host.free()
 print("DETAIL_STUDIO_1002 checks=",checks," failures=0")
 quit()
