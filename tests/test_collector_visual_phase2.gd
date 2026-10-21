extends SceneTree
const Visual=preload("res://scripts/equipment_visual.gd")
const Spatial=preload("res://scripts/spatial_dimensions.gd")
const Catalog=preload("res://scripts/device_catalog.gd")
const World=preload("res://scripts/world_game.gd")
const Domain=preload("res://scripts/map_domain.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 var p:=Catalog.defaults("collector_substation")
 var before:=var_to_bytes(p)
 check(p.capacity_mw==200 and p.loss_fraction==.01,"Independent teaching aggregate capacity/loss")
 var d:=Spatial.profile("collector_substation",p)
 check(d.valid,"Collector spatial profile")
 check(d.module_count==1 and d.columns==1 and d.rows==1 and d.module_origins_m[0]==Vector3.ZERO,"One complete centered site, not repeated compact units")
 check(d.body_dimensions_m==Vector3(96,16,98),"Fixed yard envelope")
 check(d.land_dimensions_m==Vector3(100,0,102) and d.land_area_m2==10200,"Declared 1.02ha original teaching rectangle")
 check(absf(d.clearance_radius_world-sqrt(50*50+51*51)*.1)<.00001,"Uncompressed physical occupancy")
 var lower:=p.duplicate(true);lower.capacity_mw=1
 check(Spatial.profile("collector_substation",lower).land_dimensions_m==d.land_dimensions_m,"Derating does not shrink entire station")
 var bad:=p.duplicate(true);bad.capacity_mw=200.01
 check(not Spatial.profile("collector_substation",bad).valid,"No unsupported capacity expansion")
 var start:=Time.get_ticks_usec()
 var v:=Visual.create("collector_substation",p)
 var usec:=Time.get_ticks_usec()-start
 root.add_child(v)
 check(v.get_meta("representation")=="complete_collector_ais_substation","Independent full station appearance")
 check(v.get_meta("display_module_count")==1 and v.get_meta("transformer_display_count")==2,"Two explicit transformer districts within one aggregate node")
 for key in ["geometry_is_capacity_proof","numeric_voltage_is_simulated","electrical_topology_is_simulated","has_pv_inverters"]:check(not v.get_meta(key),"Honest simulation boundary "+key)
 for name in ["CollectorAccessAndServiceRoads","CollectorAISBusbarAndBayYard","CollectorOverheadBusbarStructures","CollectorControlAndProtectionBuildings","CollectorPerimeterPalisadeAndEntryGate","CollectorLightningProtectionMasts","CollectorTransformerThreePhaseJumpers","CollectorThreePhaseBusTakeoffs","CollectorControlCableTrenches"]:check(v.find_child(name,true,false)!=null,"Complete district "+name)
 check(v.find_children("CollectorPowerTransformer*","Node3D",true,false).size()==2,"Two large original transformer groups")
 check(v.find_children("AISBay*","Node3D",true,false).size()==4,"Four distinct three-phase AIS bays")
 check(v.find_child("CompactMVTransformerSwitchgear",true,false)==null,"No magnified old cabinet")
 check(v.named_ports.size()==2 and v.has_named_port("in") and v.has_named_port("out"),"Exactly two real aggregate ports")
 for port in Catalog.ports("collector_substation"):
  for key in ["carrier","unit","direction","voltage_level"]:check(v.named_ports[port.id].get_meta(key)==port[key],"Exact logical port "+str(port.id)+" "+key)
 check(v.named_port_locals["in"].is_equal_approx(Vector3(-1.4,.065,5.0)) and v.named_port_locals["out"].is_equal_approx(Vector3(1.4,.065,5.0)),"Separated in/out physical anchors inside site")
 var geom:MeshInstance3D=v.find_child("CollectorSubstationGeometry",true,false)
 var b:=geom.mesh.get_aabb()
 check(b.size.x<=9.601 and b.size.z<=9.801 and b.end.y<=1.6 and b.position.y>=-.001,"All physical components fit stated metric envelope")
 var triangles:=0
 for surface in geom.mesh.get_surface_count():
  var indices:PackedInt32Array=geom.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
  triangles+=indices.size()/3 if not indices.is_empty() else geom.mesh.surface_get_array_len(surface)/3
 check(triangles<100000,"Bounded AIS mesh budget")
 check(geom.mesh.get_surface_count()<=12,"Static material batching")
 check(var_to_bytes(p)==before,"Visuals do not modify rating, losses or ports")
 var old:=Spatial.profile("station",Catalog.defaults("station"))
 check(old.module_count==2 and old.land_dimensions_m.is_equal_approx(Vector3(19.626,0,9.538)),"Old compact station footprint unchanged")
 var w:=World.new()
 w.height_image=Image.create_from_data(1024,1024,false,Image.FORMAT_RF,FileAccess.get_file_as_bytes("res://generated/height.raw"))
 w.cfg=JSON.parse_string(FileAccess.get_file_as_string("res://config/map.json"));w.noise.seed=int(w.cfg.seed);w.noise.frequency=.045;w.noise.fractal_octaves=4
 w.dimension_profile="metric_v1";w.devices=[];w.stations=[]
 var legal:Vector2;var found:=false
 for x in range(-40,41,5):
  for z in range(-40,41,5):
   if w.can_place("collector_substation",Vector2(x,z)).is_empty():legal=Vector2(x,z);found=true;break
  if found:break
 check(found,"Actual unmodified terrain has a legal collector center")
 var beyond_edge:=Vector2(Domain.HALF_EXTENTS.x-float(d.clearance_radius_world)+.01,0)
 check(not Domain.contains(beyond_edge,float(d.clearance_radius_world)),"Whole collector site exceeds current domain edge")
 check(w.can_place("collector_substation",beyond_edge).contains("边界"),"Expanded map still rejects a whole site crossing its boundary")
 if found:
  w.devices=[{"id":1,"kind":"load","x":legal.x,"z":legal.y,"params":Catalog.defaults("load"),"site_geometry_profile":"reference_size_v1"}]
  check(w.can_place("collector_substation",legal).contains("重叠"),"Existing reference-layout devices still block overlap")
  w.devices[0].erase("site_geometry_profile")
  check(w.can_place("collector_substation",legal).contains("旧比例"),"Legacy compatibility explicitly blocks new construction")
 var orphans:Array[Node]=[]
 for property in w.get_property_list():
  if not (property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):continue
  var value:Variant=w.get(property.name)
  if value is Node and value!=w and value.get_parent()==null and not value in orphans:orphans.append(value)
 w.free()
 for n in orphans:
  if is_instance_valid(n):n.free()
 v.free()
 print("COLLECTOR_VISUAL_PHASE2_RESULT ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size()," triangles=",triangles," build_usec=",usec," legal_center=",legal)
 quit(0 if failures.is_empty() else 1)
