extends SceneTree
const Facade = preload("res://scripts/station_facade.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, text: String):
 checks += 1
 if not ok:failures.append(text);push_error(text)
func _initialize():call_deferred("run")
func run():
 var facade := Facade.new();root.add_child(facade)
 for prefer_assets in [false,true]:
  var settings := {"kind":"tower_station","visual_dimension_profile":"metric_v1"}
  var before := settings.duplicate(true)
  facade.setup(settings,prefer_assets)
  check(facade.named_ports.size()==4 and facade.get_meta("energy_port_count")==4,"commissioned tower exposes two AC and two salt boundary markers")
  for id in ["ac_in","ac_out","heat_in","heat_out"]:
   check(facade.has_named_port(id),"tower explicit anchor "+id)
   check(facade.get_port_position(id).is_equal_approx(facade.named_ports[id].global_position),"anchor matches marker "+id)
  for id in ["heat_in","heat_out"]:
   var port:Node3D=facade.named_ports[id]
   check(port.get_meta("carrier")=="heat_salt" and port.get_meta("grade_id")=="salt_565_290" and port.get_meta("unit")=="MWth","salt port physical meaning "+id)
   check(port.get_meta("direction")==("input" if id=="heat_in" else "output"),"salt direction "+id)
   check(port.get_node("PortLabel").text.contains("565/290"),"salt grade label "+id)
   check(port.has_node("SupplyFlange") and port.has_node("ReturnFlange"),"paired salt service flanges "+id)
   check(facade.get_port_position(id).distance_to(facade.get_port_position("ac_in"))>1,"salt anchor not AC anchor")
  check(facade.get_meta("capacity_added")==0 and settings==before,"facade never adds simulation state")
  facade.setup({"kind":"tower_station_preview","visual_dimension_profile":"metric_v1"},prefer_assets)
  check(facade.named_ports.is_empty() and facade.get_meta("energy_port_count")==0,"preview remains entirely unconnected")
  facade.setup({"kind":"thermal_station","visual_dimension_profile":"metric_v1","has_primary_storage_boundary":true},prefer_assets)
  check(facade.named_ports.size()==4,"thermal station adds primary pair only")
  check(facade.named_ports.heat_out.get_meta("grade_id")=="hw_secondary_70_40","existing secondary output is preserved")
  for id in ["heat_primary_in","heat_primary_out"]:
   check(facade.has_named_port(id),"thermal primary anchor "+id)
   check(facade.named_ports[id].get_meta("grade_id")=="hw_primary_90_60","primary heat not mislabeled secondary")
   check(facade.get_port_position(id).distance_to(facade.get_port_position("heat_out"))>.5,"separate primary/secondary boundary")
  facade.setup({"kind":"thermal_station","visual_dimension_profile":"metric_v1"},prefer_assets)
  check(facade.named_ports.size()==2,"existing facade default API remains two ports")
 facade.free();await process_frame
 print("STORAGE_FACADE_PORTS_1003 checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
