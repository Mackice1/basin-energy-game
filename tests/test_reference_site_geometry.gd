extends SceneTree
const Spatial=preload("res://scripts/spatial_dimensions.gd")
const Visual=preload("res://scripts/equipment_visual.gd")
const Catalog=preload("res://scripts/device_catalog.gd")
const Support=preload("res://scripts/site_layout_support.gd")
var checks=0
var failures=[]
func check(ok:bool,why:String)->void:
 checks+=1
 if not ok: failures.append(why);push_error(why)
func _initialize()->void:call_deferred("run")
func run()->void:
 for kind in ["thermal_store","solid_thermal_store","hydrogen_gas_store","hydrogen_storage_system","nitrogen_supply_boundary","ammonia_synthesis_station"]:
  var p=Catalog.defaults(kind)
  var before=var_to_bytes(p)
  var d=Spatial.profile(kind,p)
  var proof=Support.required_geometry(kind,p)
  check(d.valid,kind+" dimensions valid")
  if not d.valid:continue
  check(d.actual_net_volume_m3>=d.required_net_volume_m3,kind+" net volume sufficient")
  check(abs(d.actual_net_volume_m3-proof.hardware_internal_volume_m3)<1e-6,kind+" one shared net geometry")
  check(d.reference_volume_check_pass,kind+" volume pass metadata")
  var v=Visual.create(kind,p,true)
  root.add_child(v)
  check(v.get_meta("site_geometry_profile")=="reference_size_v1",kind+" new default marker")
  check(v.get_meta("actual_net_volume_m3")==d.actual_net_volume_m3,kind+" visual volume metadata")
  check(not v.get_meta("pressure_vessel_certified"),kind+" no pressure certificate")
  check(var_to_bytes(p)==before,kind+" params not mutated")
  check(v.named_ports.size()==Catalog.ports(kind).size(),kind+" unchanged ports")
  var meshes=v.find_children("*","MeshInstance3D",true,false)
  var bounds=AABB();var first=true
  for mesh in meshes:
   if mesh.name=="SelectionRing" or mesh.get_parent().name.begins_with("Port_"):continue
   var local=v.global_transform.affine_inverse()*mesh.global_transform
   var b=local*mesh.mesh.get_aabb()
   bounds=b if first else bounds.merge(b);first=false
  print(kind," net=",d.actual_net_volume_m3," minimum=",d.required_net_volume_m3," body=",d.body_dimensions_m," rendered=",bounds)
  check(bounds.position.y>=-0.002,kind+" above ground")
  check(bounds.end.y<=d.body_dimensions_m.y*.1+.04,kind+" authored height fits")
  check(bounds.size.x<=d.body_dimensions_m.x*.1+.04,kind+" authored width fits")
  check(bounds.size.z<=d.land_dimensions_m.z*.1+.04,kind+" ports fit installation")
  var low=p.duplicate(true);low[d.rating_parameter]=float(low[d.rating_parameter])*.1
  var lowd=Spatial.profile(kind,low)
  check(lowd.valid and lowd.body_dimensions_m==d.body_dimensions_m and lowd.module_count==d.module_count,kind+" derating preserves shell/modules")
  var old=Spatial.profile(kind,p,true,"flow_process_v2","")
  var oldp=p.duplicate(true);oldp.visual_site_geometry_profile="";oldp.visual_dimension_profile="metric_v1"
  var oldv=Visual.create(kind,oldp,false);root.add_child(oldv)
  check(old.valid and oldv.get_meta("site_geometry_profile")=="",kind+" old marker preserved")
  check(not oldv.has_meta("actual_net_volume_m3"),kind+" old geometry not falsely certified")
  if kind in ["thermal_store","solid_thermal_store","hydrogen_gas_store"]:check(old.body_dimensions_m!=d.body_dimensions_m,kind+" old occupied size unchanged")
  v.free();oldv.free()
 for kind in ["pv","battery","station","high_temp_store","molten_salt_store","solar_thermal","parabolic_trough","electrolyzer_station"]:
  var p=Catalog.defaults(kind);var low=p.duplicate(true)
  for key in Support.parameter_limits(kind):
   if not key in ["rotor_diameter_m","hub_height_m"]:low[key]=float(low[key])*.1
  var d=Spatial.profile(kind,p,false);var ld=Spatial.profile(kind,low,false)
  check(d.valid and ld.valid and d.body_dimensions_m==ld.body_dimensions_m and d.module_count==ld.module_count,kind+" installed geometry floor")
 print("REFERENCE_SITE_GEOMETRY ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures)
 quit(0 if failures.is_empty() else 1)
