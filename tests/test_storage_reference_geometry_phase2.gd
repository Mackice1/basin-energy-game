extends SceneTree
const V=preload("res://scripts/equipment_visual.gd")
const S=preload("res://scripts/spatial_dimensions.gd")
const C=preload("res://scripts/device_catalog.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,msg:String)->void:
 checks+=1
 if not ok:failures.append(msg);push_error(msg)
func _initialize():call_deferred("run")
func run():
 for kind in ["battery_sodium","battery_flow","liquid_air_store","solid_thermal_store"]:
  for profile in (["flow_icon_v1","flow_process_v2"] if kind=="battery_flow" else ["flow_process_v2"]):
   var p:=C.defaults(kind);p.visual_geometry_profile=profile
   # These are the original single-module photo-reference schemes, not current defaults.
   var site_marker:String="reference_size_v1" if kind=="liquid_air_store" else ""
   p.visual_site_geometry_profile=site_marker
   if kind=="battery_sodium":p.capacity_mwh=5.0;p.charge_mw=2.5;p.discharge_mw=2.5
   elif kind=="battery_flow":p.capacity_mwh=10.0;p.charge_mw=2.0;p.discharge_mw=2.0
   elif kind=="solid_thermal_store":p.capacity_mwhth=4.0;p.charge_mwth=2.0;p.discharge_mwth=2.0
   var saved:=var_to_bytes(p)
   var d:=S.profile(kind,p,true,profile,site_marker)
   var start:=Time.get_ticks_usec();var v:=V.create(kind,p);var us:=Time.get_ticks_usec()-start
   root.add_child(v)
   check(d.valid and d.module_count==1,kind+" exact historical complete-site scheme")
   check(v.named_ports.size()==C.ports(kind).size(),kind+" exact catalog ports")
   for port in C.ports(kind):
    check(v.has_named_port(port.id),kind+" port "+port.id)
    for key in ["carrier","direction","unit"]:check(v.named_ports[port.id].get_meta(key)==port[key],kind+" "+key)
   var g:MeshInstance3D=v.find_child("StorageFacilityGeometry",true,false);var b:=g.mesh.get_aabb()
   check(b.size.x<=d.body_dimensions_m.x*.1+.001 and b.size.z<=d.body_dimensions_m.z*.1+.001 and b.end.y<=d.body_dimensions_m.y*.1+.001,kind+" measured geometry stays in declared metric envelope "+str(b))
   check(g.mesh.get_surface_count()<=12,kind+" batched surfaces")
   var tris:=0
   for i in g.mesh.get_surface_count():
    var indices:PackedInt32Array=g.mesh.surface_get_arrays(i)[Mesh.ARRAY_INDEX];tris+=indices.size()/3
   check(tris<60000,kind+" triangle budget")
   if kind=="battery_flow":
    var legacy:bool=profile=="flow_icon_v1"
    check(d.land_dimensions_m==(Vector3(18,0,14) if legacy else Vector3(42,0,19)),"flow version occupancy")
    check(v.get_meta("legacy_icon_geometry")==legacy,"flow compatibility visibly explicit")
    check(v.get_meta("geometry_profile")==profile,"flow profile propagated")
    check(v.find_children("FlowProcessUnit*","Node3D",true,false).size()==(0 if legacy else 6),"flow old icon vs six real-size process units")
    check(is_equal_approx(V.footprint(kind,p),d.clearance_radius_world),"flow visual footprint exact same profile")
   else:check(v.get_meta("storage_reference_revision")=="primary_photos_20261021",kind+" photo revision")
   check(var_to_bytes(p)==saved,kind+" no parameter mutation")
   print("REFERENCE_GEOMETRY ",kind," ",profile," triangles=",tris," materials=",g.mesh.get_surface_count()," usec=",us," land=",d.land_dimensions_m)
   v.free()
 # Current defaults and derating retain their full finite-reference installation.
 for kind in ["battery_sodium","battery_flow","liquid_air_store","solid_thermal_store"]:
  var p:=C.defaults(kind)
  var d:=S.profile(kind,p)
  var expected_modules:int=1 if kind=="liquid_air_store" else 3 if kind=="battery_sodium" else 2
  check(d.valid and d.site_geometry_profile=="reference_size_v1" and d.module_count==expected_modules,kind+" actual current default accepted")
  var thermal:bool=kind=="solid_thermal_store"
  var capacity_key:String="capacity_mwhth" if thermal else "capacity_mwh"
  var charge_key:String="charge_mwth" if thermal else "charge_mw"
  var discharge_key:String="discharge_mwth" if thermal else "discharge_mw"
  var lower:=p.duplicate(true)
  for key in [capacity_key,charge_key,discharge_key]:lower[key]=float(lower[key])*0.5
  var lower_bytes:=var_to_bytes(lower)
  var derated:=S.profile(kind,lower)
  check(derated.valid and derated.module_count==d.module_count and derated.unit_dimensions_m==d.unit_dimensions_m and derated.body_dimensions_m==d.body_dimensions_m and derated.land_dimensions_m==d.land_dimensions_m,kind+" reference derating keeps complete installed geometry")
  for params in [p,lower]:
   var saved:=var_to_bytes(params)
   var v:=V.create(kind,params)
   root.add_child(v)
   check(v.get_meta("site_geometry_profile")=="reference_size_v1" and v.get_meta("module_count")==expected_modules,kind+" default and derated visuals retain current full hardware")
   check(v.named_ports.size()==C.ports(kind).size(),kind+" reference aggregate catalog ports")
   for port in C.ports(kind):check(v.has_named_port(port.id),kind+" reference named port "+port.id)
   check(is_equal_approx(V.footprint(kind,params),d.clearance_radius_world),kind+" reference visual footprint matches full installation")
   check(var_to_bytes(params)==saved,kind+" reference visual does not alter simulation parameters")
   v.free()
  check(var_to_bytes(lower)==lower_bytes,kind+" reference spatial derating is non-mutating")
  # The current implementation supports no larger capacity/power than this facility.
  for key in [capacity_key,charge_key,discharge_key]:
   var oversized:=p.duplicate(true);oversized[key]=float(p[key])+0.001
   check(not S.profile(kind,oversized).valid,kind+" rejects unsupported reference "+key)
 check(not S.profile("battery_flow",{},false,"bad_profile").valid,"unknown geometry rejected")
 print("STORAGE_REFERENCE_GEOMETRY_RESULT ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
