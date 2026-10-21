extends SceneTree
const Env=preload("res://scripts/environment_visual.gd")
var checks:=0
var failures:Array[String]=[]
class Ground extends Node3D:
 var cfg={"seed":241014,"world_size":[400,400],"grid_export_mw":4,"gas_capacity_m3_hour":90000,"water_supply_m3_day":4800,"coal_capacity_t_day":8000}
 func height_at(x:float,z:float)->float:return sin(x*.025)*1.5+cos(z*.04)*.4
 func stream_x(z:float)->float:return -28+z*.20+sin(z*.065)*7
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func run():
 var map:=Ground.new();root.add_child(map);var cfg_before:=var_to_bytes(map.cfg)
 var start:=Time.get_ticks_usec()
 var bg:=Env.build_surround(map);var plants:=Env.build_scatter(map);var resources:=Env.build_resources(map,map)
 var build_usec:=Time.get_ticks_usec()-start
 check(bg.get_meta("buildable")==false and not bg.get_meta("changes_height_field"),"Backdrop is not buildable terrain")
 check(bg.get_meta("triangles")==1024,"Bounded single-batch horizon")
 check(bg.get_meta("inner_half_extents")==Vector2(200,200),"Backdrop starts after the expanded real ground, not the texture allocation")
 var seam_points:Dictionary={}
 for v in bg.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
  check(absf(v.x)>=199.9999 or absf(v.z)>=199.9999,"Horizon never overlays existing terrain")
  if absf(v.x)<=200.0001 and absf(v.z)<=200.0001:
   seam_points[Vector2(v.x,v.z)]=true
   check(absf(v.y-map.height_at(v.x,v.z))<.0001,"Seam has no vertical gap at visible terrain edge")
 check(seam_points.size()==Env.SECTORS,"Every inner sector joins the visible terrain, leaving no pale background apron")
 for p in [Vector2(200,0),Vector2(0,200),Vector2(-200,0),Vector2(0,-200)]:
  var nearest:=INF
  for q in seam_points:nearest=minf(nearest,q.distance_to(p))
  check(nearest<.001,"Rectangular apron reaches cardinal terrain boundary "+str(p))
 for n in map.find_children("*","CollisionObject3D",true,false):check(false,"No collision object "+n.name)
 var triangles:=1024;var instances:=0
 for n in plants.find_children("*","MultiMeshInstance3D",true,false):
  var mm:MultiMesh=n.multimesh;instances+=mm.instance_count
  var a=mm.mesh.surface_get_arrays(0);var vertices:PackedVector3Array=a[Mesh.ARRAY_VERTEX]
  triangles+=vertices.size()/3*mm.instance_count
  for i in mm.instance_count:
   var tf:=mm.get_instance_transform(i);var p:=Vector2(tf.origin.x,tf.origin.z)
   check(Env.clear_of_routes(p),"Scatter avoids roads, pipelines and resource labels")
   check(tf.origin.is_finite() and tf.basis.determinant()>0,"Finite varied transforms")
   var closest:=INF
   for v in vertices:
    var q:Vector3=tf*v
    closest=minf(closest,q.y-map.height_at(q.x,q.z))
   check(closest<.025,"Every rock or plant contacts terrain, not hovering")
 check(instances<=1812 and instances>1500,"Sparse capped scatter count")
 for span in [300.,235.,179.,80.,8.,200.]:
  Env.set_detail(plants,span)
  check(plants.get_node("NearPlantDetail").visible==(span<180.),"Plant LOD follows world camera span")
 check(resources.get_meta("resource_production_added")==0 and resources.get_meta("logical_ports_added")==0,"Resource pictures add no production or ports")
 check(resources.get_child_count()==3,"Three external resource boundaries only")
 for kind in Env.RESOURCE_POINTS:
  var n=resources.get_node("External_"+kind)
  check(n.get_meta("boundary_anchor")==Env.RESOURCE_POINTS[kind],"Original resource interface anchor")
  check(n.get_meta("not_constructed_devices") if n.has_meta("not_constructed_devices") else resources.get_meta("not_constructed_devices"),"Not a purchased or simulated facility")
  triangles+=n.get_child(0).mesh.surface_get_array_len(0)/3
 check(triangles<65000,"Bounded close-view triangle budget")
 check(var_to_bytes(map.cfg)==cfg_before,"Exact source quotas and map bounds unchanged")
 var repeat:=Ground.new();root.add_child(repeat);var again:=Env.build_scatter(repeat)
 var a=plants.find_children("*","MultiMeshInstance3D",true,false);var b=again.find_children("*","MultiMeshInstance3D",true,false)
 for i in a.size():check(a[i].multimesh.buffer==b[i].multimesh.buffer,"Deterministic scatter repeat")
 print("ENVIRONMENT_PHASE2 checks=",checks," failures=",failures.size()," instances=",instances," total_close_triangles=",triangles," build_usec=",build_usec)
 map.free();repeat.free();quit(0 if failures.is_empty() else 1)
