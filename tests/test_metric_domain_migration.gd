extends SceneTree
const Domain=preload("res://scripts/map_domain.gd")
const Validator=preload("res://scripts/save_validator.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func run():
 var w=load("res://main.tscn").instantiate();root.add_child(w);await process_frame
 w.devices.clear();w.stations.clear();w.links.clear();w.dimension_profile="metric_v1";w.rebuild_equipment();w.refresh()
 check(Domain.METERS_PER_UNIT==10.0 and Domain.WORLD_SIZE==Vector2(400,400),"fixed four kilometre domain at ten metres per unit")
 check(Domain.contains(Vector2(190,190),10) and not Domain.contains(Vector2(190.01,190),10),"full footprint, not only centre, inside boundary")
 var current:Dictionary=w.state()
 check(current.schema==20,"expanded-domain saves versioned")
 var flow:Dictionary={"id":1,"kind":"battery_flow","x":170.0,"z":170.0,"params":w.Catalog.defaults("battery_flow"),"state":w.Catalog.initial_state("battery_flow",w.Catalog.defaults("battery_flow"))}
 current.devices=[flow];current.next_id=2
 check(Validator.validate(current).is_empty(),"new domain accepts expanded location")
 var old:Dictionary=current.duplicate(true);old.schema=19
 check(not Validator.validate(old).is_empty(),"historical schema retains historical bounds")
 flow.x=0.0;flow.z=0.0
 w.devices=[flow];w.next_id=2;w.rebuild_equipment()
 var preserved:Dictionary=w.state().duplicate(true)
 var review:Dictionary=w.metric_migration_preview()
 check(review.changes.size()>0,"old flow has explicit migration change")
 check(w.devices==preserved.devices,"preview never mutates installed scene")
 check(review.candidate.devices[0].geometry_profile==Validator.FLOW_PROCESS_GEOMETRY,"candidate upgrades process geometry only")
 check(review.candidate.devices[0].params==flow.params and review.candidate.devices[0].state==flow.state,"preview preserves capacity and energy")
 check(review.candidate.devices[0].x==0.0 and review.candidate.devices[0].z==0.0,"preview preserves coordinates")
 var duplicate:Dictionary=flow.duplicate(true);duplicate.id=2;duplicate.x=0.1
 w.devices.append(duplicate);w.next_id=3
 var colliding:Dictionary=w.metric_migration_preview()
 check(not colliding.can_apply and not colliding.issues.is_empty(),"new real footprints block collision rather than auto-moving")
 check(not w.apply_metric_migration(colliding),"blocked preview cannot apply")
 check(w.devices.size()==2 and w.devices[1].x==0.1,"blocked migration retains every old object")
 w.scene_revision+=1
 check(not w.apply_metric_migration(review),"stale review rejected")
 w.devices=[flow.duplicate(true)];w.devices[0].x=170.0;w.devices[0].z=170.0;w.next_id=2
 var original:Dictionary=w.state().duplicate(true)
 var approved:Dictionary=w.metric_migration_preview()
 check(approved.can_apply,"isolated exterior-site migration is applicable: "+str(approved.issues))
 check(w.apply_metric_migration(approved),"approved migration applies after original backup")
 check(w.devices[0].site_geometry_profile=="reference_size_v1" and w.is_reference_layout(),"successful migration enters explicit reference mode")
 var backups:=DirAccess.get_files_at("user://migration_backups")
 check(backups.size()>0,"recoverable original backup file exists")
 var found_original:=false
 for file in backups:
  var raw=JSON.parse_string(FileAccess.get_file_as_string("user://migration_backups/"+file))
  if raw is Dictionary and raw.devices.size()==1 and not raw.devices[0].has("site_geometry_profile") and float(raw.devices[0].x)==170.0:found_original=true
 check(found_original,"backup preserves old geometry and original position")
 w.undo()
 check(w.devices==original.devices and not w.is_reference_layout(),"one undo restores exact old objects and explicit compatibility mode")
 w.queue_free();await process_frame;await process_frame
 print("METRIC_DOMAIN_MIGRATION checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
