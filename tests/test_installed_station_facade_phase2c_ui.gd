extends SceneTree
const Facade=preload("res://scripts/station_facade.gd")
const C=preload("res://scripts/device_catalog.gd")
const Visual=preload("res://scripts/equipment_visual.gd")
const Spatial=preload("res://scripts/spatial_dimensions.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures.append(message);push_error("INSTALLED_FACADE "+message)
func _initialize():call_deferred("run")
func member(kind:String,id:int,at:Vector2,p:Dictionary={})->Dictionary:
 var params:Dictionary=C.defaults(kind).merged(p,true)
 return {"id":id,"kind":kind,"parent_station_id":100,"interior_x":at.x,"interior_z":at.y,"params":params,"state":C.initial_state(kind,params)}
func signature(visual:Node3D)->Array:
 var result:Array=[]
 for surface in visual.surfaces:
  if surface==visual.selection_ring:continue
  var local:Transform3D=visual.global_transform.affine_inverse()*surface.global_transform
  result.append([surface.mesh.get_aabb(),local])
 return result
func same_signature(a:Array,b:Array)->bool:
 if a.size()!=b.size():return false
 for index in a.size():
  if not a[index][0].is_equal_approx(b[index][0]) or not a[index][1].is_equal_approx(b[index][1]):return false
 return true
func names_count(node:Node,pattern:String)->int:return node.find_children(pattern,"Node",true,false).size()
func run():
 var facade:=Facade.new();root.add_child(facade);facade.position=Vector3(10,2,-8)
 for prefer in [false,true]:
  var members:Array=[member("electric_boiler",1,Vector2(-1.4,-1.1)),member("thermal_store",2,Vector2(.8,.5),{"capacity_mwhth":.2}),member("heat_exchanger",3,Vector2(-.8,1.4))]
  var data:Dictionary={"id":100,"name":"实际安装热站","kind":"thermal_station","visual_dimension_profile":"metric_v1","installed_devices":members,"has_primary_storage_boundary":true}
  var original:=var_to_bytes(data);facade.setup(data,prefer)
  check(not facade.has_node("BlenderAsset") and not facade.has_node("PlantBuilding") and names_count(facade,"TankSilhouette*")==0,"no fixed fake building/tanks in metric mode")
  check(facade.get_meta("visual_backend")=="metric_installed_equipment","explicit installed geometry backend")
  check(facade.get_node("FacilityFoundation").mesh.size==Vector3(8,.05,6),"80x60m exact site boundary")
  check(facade.get_node("Courtyard").mesh.size==Vector3(4.8,.008,4.8),"48x48m exact inner placement area")
  check(facade.installed_device_nodes.size()==3 and facade.get_meta("installed_device_ids")==[1,2,3],"each real ID exactly once")
  check(is_equal_approx(facade.footprint_radius,Spatial.profile("thermal_station").clearance_radius_world),"siting radius unchanged")
  for item in members:
   var child:Node3D=facade.installed_device_nodes[item.id]
   var vp:Dictionary=item.params.duplicate(true);vp.visual_dimension_profile="metric_v1";vp.visual_site_geometry_profile=str(item.get("site_geometry_profile",""))
   var reference:Node3D=Visual.create(item.kind,vp,prefer);root.add_child(reference)
   check(child.scale==Vector3.ONE and child.get_parent().scale==Vector3.ONE,"no arbitrary member rescaling "+item.kind)
   check(child.position==Vector3(item.interior_x,0,item.interior_z),"same interior world coordinates "+item.kind)
   check(child.global_position==facade.global_position+Vector3(item.interior_x,0,item.interior_z),"global station placement composed once")
   check(same_signature(signature(child),signature(reference)),"identical same-params mesh bounds and local transforms "+item.kind)
   check(child.named_port_locals==reference.named_port_locals,"same physical device port positions "+item.kind)
   check(not child.selection_ring.visible,"one facility selection ring only")
   for surface in child.surfaces:check(surface in facade.surfaces,"real child surface included in whole-site picker")
   reference.free()
  for port in ["ac_in","heat_out"]:
   var expected:Vector3=Visual._vector3(Visual.thermal_asset_definition("thermal_station").ports[port])
   check(facade.named_port_locals[port]==expected,"mapped outer boundary unchanged "+port)
  facade.set_selected(true);check(facade.selection_ring.visible,"whole-site selected ring preserved")
  facade.set_preview(false)
  for surface in facade.surfaces:check(surface.material_override==facade.preview_bad,"preview tint covers actual member meshes")
  facade.clear_preview()
  for index in facade.surfaces.size():check(facade.surfaces[index].material_override==facade.base_materials[index],"restores authored member materials")
  check(var_to_bytes(data)==original,"geometry never mutates state params positions or IDs")
  var first_count:int=facade.surfaces.size();facade.setup(data,prefer)
  check(facade.installed_device_nodes.size()==3 and facade.surfaces.size()==first_count,"rebuild not duplicate members")
  var changed:=data.duplicate(true);changed.installed_devices.remove_at(1);changed.installed_devices[0].interior_x=1.2;facade.setup(changed,prefer)
  check(not facade.installed_device_nodes.has(2) and is_equal_approx(facade.installed_device_nodes[1].position.x,1.2),"deleted and moved members reflect new snapshot")
  facade.setup({"kind":"thermal_station","visual_dimension_profile":"metric_v1","installed_devices":[]},prefer)
  check(facade.installed_device_nodes.is_empty() and names_count(facade,"TankSilhouette*")==0,"empty site has no imaginary storage")
  var tower_members:Array=[member("solar_tower_receiver",10,Vector2(0,-.4)),member("molten_salt_store",11,Vector2(4.0,4.0)),member("salt_steam_generator",12,Vector2(-4.0,4.0)),member("steam_turbine",13,Vector2(-4.5,3.0))]
  var tower:Dictionary={"id":100,"kind":"tower_station","visual_dimension_profile":"metric_v1","installed_devices":tower_members}
  var tower_before:=var_to_bytes(tower);facade.setup(tower,prefer)
  check(names_count(facade,"ReceiverTower25m")==1,"tower appears once")
  check(names_count(facade,"MirrorSurface*")==100,"100 real mirrors appear once")
  check(names_count(facade,"TowerControlCabinet")==1,"installed receiver controller appears once")
  check(names_count(facade,"HotSaltTank")==1 and names_count(facade,"ColdSaltTank")==1,"only actual installed salt pair")
  check(facade.installed_device_nodes.size()==4,"all actual tower members shown")
  check(facade.named_ports.size()==4 and facade.get_meta("capacity_added")==0,"mapped carrier ports and zero extra capacity preserved")
  facade.set_tower_tracking(35.0,120.0)
  check(var_to_bytes(tower)==tower_before,"tracking/geometry never mutate installed state")
  facade.setup({"kind":"tower_station_preview","visual_dimension_profile":"metric_v1","installed_devices":tower_members},prefer)
  check(facade.installed_device_nodes.is_empty() and facade.named_ports.is_empty(),"uncommissioned preview creates no operational devices or ports")
  check(names_count(facade,"ReceiverTower25m")==1 and names_count(facade,"MirrorSurface*")==100,"preview still one tower/mirror scene")
 facade.setup({"kind":"thermal_station","visual_dimension_profile":"legacy_illustrative","installed_devices":[member("thermal_store",2,Vector2.ZERO)]},false)
 check(facade.has_node("TankSilhouette1") and facade.installed_device_nodes.is_empty(),"legacy icon layout remains unchanged until explicit migration")
 check(facade.get_meta("legacy_scale_migration_required") and facade.get_node("LegacyScaleNotice").text.contains("非真实尺寸"),"legacy clearly marked not actual metric equipment")
 facade.setup({"id":100,"kind":"thermal_station","visual_dimension_profile":"metric_v1","installed_devices":[member("electric_boiler",1,Vector2.ZERO),member("electric_boiler",1,Vector2.ONE),{"id":3,"kind":"bogus"}]},false)
 check(facade.installed_device_nodes.size()==1,"duplicate IDs and unknown kinds cannot duplicate geometry")
 check(not facade.has_meta("legacy_scale_migration_required"),"rebuild clears legacy migration label metadata")
 facade.free();await process_frame
 print("INSTALLED_STATION_FACADE_PHASE2C_UI checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
