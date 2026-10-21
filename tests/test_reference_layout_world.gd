extends SceneTree
const Support=preload("res://scripts/site_layout_support.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func run():
 var w=load("res://main.tscn").instantiate();root.add_child(w);await process_frame
 w.devices.clear();w.stations.clear();w.links.clear();w.dimension_profile="metric_v1";w.rebuild_equipment();w.refresh()
 for kind in w.KINDS:
  var params:Dictionary=w.Catalog.defaults(kind)
  check(w.layout_support_errors(kind,params).is_empty(),"current reference defaults supported: "+kind)
  var bounds:Dictionary=Support.parameter_limits(kind)
  for key in bounds:
   var invalid:Dictionary=params.duplicate(true);invalid[key]=float(bounds[key].max)+maxf(1.0,absf(float(bounds[key].max))*.1)
   check(not w.layout_support_errors(kind,invalid).is_empty(),"shared world upper bound: "+kind+"/"+key)
 var flow_params:Dictionary=w.Catalog.defaults("battery_flow")
 w.devices=[{"id":800,"kind":"battery_flow","x":0.0,"z":0.0,"params":flow_params,"state":w.Catalog.initial_state("battery_flow",flow_params),"site_geometry_profile":"reference_size_v1","geometry_profile":"flow_icon_v1"}]
 check(not w.reference_layout_errors().is_empty() and not w.advance(.1),"reference marker cannot run legacy flow icon geometry")
 check(w.optimization_controller.snapshot({"horizon_hours":1.0,"step_minutes":60.0}).has("error"),"legacy flow icon with reference marker rejected by optimization before stripping geometry")
 w.devices[0].geometry_profile="flow_process_v2"
 check(w.reference_layout_errors().is_empty(),"actual reference flow process passes all geometric guards")
 w.devices=[]
 var too_efficient:Dictionary=w.Catalog.defaults("caes_aboveground");too_efficient.discharge_efficiency=.99
 check(str(w.layout_support_errors("caes_aboveground",too_efficient)).contains("净返电"),"coupled capacity-efficiency failure gives useful net-energy correction, not generic scalar range")
 check(w.add_equipment("battery",Vector2(170,170)),"new reference battery places in expanded domain")
 var id:int=w.selected_id
 check(w.device(id).site_geometry_profile=="reference_size_v1" and w.is_reference_layout(),"new device receives explicit as-built profile")
 var before:Dictionary=w.state().duplicate(true)
 var outcome:Dictionary=w.apply_bulk_parameters("battery",[id],{"capacity_mwh":99999.0})
 check(not outcome.ok and w.devices==before.devices,"bulk over-envelope rejected atomically without silent clamp")
 check(w.advance(.25),"supported real layout operates")
 var mixed:Dictionary=w.device(id).duplicate(true);mixed.id=999;mixed.erase("site_geometry_profile");w.devices.append(mixed)
 check(not w.layout_mode_error().is_empty() and not w.advance(.25),"partial marker cannot downgrade strict real scene into compatibility operation")
 var mixed_snapshot:Dictionary=w.optimization_controller.snapshot({"horizon_hours":1.0,"step_minutes":60.0})
 check(mixed_snapshot.has("error"),"mixed profile optimizer fails exactly like realtime")
 w.devices.pop_back()
 w.device(id).params.capacity_mwh=99999.0
 check(not w.advance(.25),"unsupported marked layout cannot run as physically supported")
 var snapshot:Dictionary=w.optimization_controller.snapshot({"horizon_hours":1.0,"step_minutes":60.0})
 check(snapshot.has("error") and str(snapshot.error).contains("规格"),"optimizer shares real layout guard")
 w.device(id).erase("site_geometry_profile")
 check(not w.is_reference_layout(),"unmarked device is explicit old compatibility mode")
 w.update_status()
 check(w.hud_clock.text.contains("旧比例"),"legacy mode is permanently visible in top HUD, not only a hidden sidebar")
 check(w.advance(.25),"legacy teaching operation preserved without rewriting ratings")
 check(w.device(id).params.capacity_mwh==99999.0,"compatibility does not clamp stored rating")
 check(not w.can_place("battery",Vector2(-170,170)).is_empty(),"compatibility cannot silently mix new reference construction")
 var review:Dictionary=w.metric_migration_preview()
 check(not review.can_apply and str(review.issues).contains("capacity_mwh"),"migration names exact unsupported field and preserves original")
 check(w.device(id).params.capacity_mwh==99999.0 and not w.device(id).has("site_geometry_profile"),"failed migration has no mutation")
 var original:Dictionary=w.state().duplicate(true)
 var undo_count:int=w.undo_states.size()
 w.new_reference_scene()
 check(w.is_reference_layout() and w.devices.is_empty() and w.stations.is_empty() and w.links.is_empty(),"explicit empty new scene is true-scale and contains no old objects")
 check(w.elapsed_s==0.0 and w.paused and w.selected_id==-2,"new empty scene resets runtime and selection, starts paused")
 check(w.undo_states.size()==undo_count+1 and w.undo_states.back()==original,"new scene retains complete original scene as undo checkpoint")
 check(w.can_place("battery",Vector2(170,170)).is_empty(),"empty scene has immediately usable true-scale build path")
 w.undo()
 check(w.devices==original.devices and w.links==original.links and w.material_energy==original.material_energy,"new scene undo restores exact devices, links and material inventory ledger")
 check(w.dimension_profile==original.dimension_profile and w.elapsed_s==original.elapsed_s,"new scene undo restores previous scale and simulation clock")
 w.queue_free();await process_frame;await process_frame
 print("REFERENCE_LAYOUT_WORLD checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
