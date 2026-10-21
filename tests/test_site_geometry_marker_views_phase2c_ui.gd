extends SceneTree
const Interior=preload("res://scripts/station_interior.gd")
const Inspector=preload("res://scripts/device_inspector.gd")
const InteriorHost=preload("res://tests/test_station_interior.gd")
const InspectorHost=preload("res://tests/test_device_inspector_v23.gd")
const C=preload("res://scripts/device_catalog.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures.append(message);push_error("SITE_MARKER_UI "+message)
func _initialize():call_deferred("run")
func settle():
 for i in 3:await process_frame
func device(id:int,profile:bool)->Dictionary:
 var p:Dictionary=C.defaults("thermal_store");p.capacity_mwhth=.2
 var item:Dictionary={"id":id,"kind":"thermal_store","parent_station_id":0,"interior_x":-.8 if id==1 else .8,"interior_z":0.0,"params":p,"state":C.initial_state("thermal_store",p)}
 if profile:item.site_geometry_profile="reference_size_v1"
 return item
func run():
 root.size=Vector2i(1180,812);root.gui_embed_subwindows=true
 var host:=InteriorHost.Host.new();host.dimension_profile="metric_v1";host.devices=[device(1,false),device(2,true)];root.add_child(host)
 var before:=var_to_bytes(host.devices)
 var interior:=Interior.new();host.add_child(interior);interior.setup(host)
 check(interior._visual_params(host.devices[0].params,host.devices[0]).visual_site_geometry_profile=="","actual legacy member explicitly passes empty geometry marker")
 check(interior._visual_params(host.devices[1].params,host.devices[1]).visual_site_geometry_profile=="reference_size_v1","actual marked member passes reference profile")
 check(interior._visual_params(host.templates.thermal_store).visual_site_geometry_profile=="reference_size_v1","construction default uses new reference geometry")
 check(interior.open_station(0),"real internal page opens");await settle()
 for item in host.devices:
  check(interior._visual_signatures[item.id]==item.kind+JSON.stringify(interior._visual_params(item.params,item)),"member visual signature includes actual profile")
  check(interior.equipment_nodes[item.id].position==Vector3(item.interior_x,0,item.interior_z),"member coordinates unchanged")
 var old_id:int=interior.equipment_nodes[1].get_instance_id()
 host.devices[0].site_geometry_profile="reference_size_v1";interior._sync_equipment(host.devices)
 check(interior.equipment_nodes[1].get_instance_id()!=old_id,"profile-only change invalidates internal model cache")
 host.devices[0].erase("site_geometry_profile");interior._sync_equipment(host.devices)
 interior.selected_id=1;interior.set_interaction_mode("move");await settle()
 var view_point:Vector2=interior.camera.unproject_position(Vector3(.1,0,1.0))*interior.view_container.size/Vector2(interior.viewport.size)
 interior._update_preview(view_point)
 check(is_instance_valid(interior.preview),"real movement ghost created")
 if is_instance_valid(interior.preview):check(interior.preview.get_meta("preview_signature")=="thermal_store"+JSON.stringify(interior._visual_params(host.devices[0].params,host.devices[0])),"move ghost retains missing legacy marker instead of construction default")
 interior.set_interaction_mode("select");interior.start_build("thermal_store");await settle();interior._update_preview(view_point)
 check(is_instance_valid(interior.preview),"real new construction ghost created")
 if is_instance_valid(interior.preview):check(interior.preview.get_meta("preview_signature")=="thermal_store"+JSON.stringify(interior._visual_params(host.templates.thermal_store)),"new ghost uses reference size marker")
 interior.close_station();check(var_to_bytes(host.devices)==before,"view switching and previews never migrate actual devices")
 interior.free();host.free()
 var detail_host:=InspectorHost.Host.new();root.add_child(detail_host);detail_host.devices=[device(1,false),device(2,true)]
 var inspector:=Inspector.new();detail_host.add_child(inspector);inspector.setup(detail_host)
 before=var_to_bytes(detail_host.devices)
 for item in detail_host.devices:
  var params:Dictionary=inspector._device_visual_params(item)
  check(params.visual_site_geometry_profile==item.get("site_geometry_profile",""),"inspector forwards exact actual marker")
  check(params.visual_dimension_profile=="metric_v1","one-argument host visual_params compatibility")
  check(inspector.open_device(item.id),"detail opens");await settle()
  check(inspector._signature==str([item.kind,params]),"detail model signature includes explicit marker")
 inspector.open_device(1);var model_id:int=inspector.model_node.get_instance_id()
 detail_host.devices[0].site_geometry_profile="reference_size_v1";inspector.refresh()
 check(inspector.model_node.get_instance_id()!=model_id,"profile-only change rebuilds detail model")
 detail_host.devices[0].erase("site_geometry_profile");inspector.refresh()
 check(inspector._device_visual_params(detail_host.devices[0]).visual_site_geometry_profile=="","restore unmarked device does not silently become new")
 check(var_to_bytes(detail_host.devices)==before,"inspection cannot write geometry marker or inventory")
 inspector.free();detail_host.free();await settle()
 print("SITE_GEOMETRY_MARKER_VIEWS_PHASE2C_UI checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
