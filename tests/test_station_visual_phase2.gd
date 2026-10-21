extends SceneTree
const Catalog=preload("res://scripts/device_catalog.gd")
const Spatial=preload("res://scripts/spatial_dimensions.gd")
const Visual=preload("res://scripts/equipment_visual.gd")
const Detail=preload("res://scripts/station_detail_sample.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func run():
 var p:=Catalog.defaults("station");p.visual_dimension_profile="metric_v1"
 check(p.capacity_mw==4.0 and p.loss_fraction==.01,"No ability upgrade")
 var d:=Spatial.profile("station",p)
 check(d.module_count==2 and d.unit_dimensions_m==Vector3(6.813,2.941,5.538),"Original two reference-sized modules")
 check(d.body_dimensions_m.is_equal_approx(Vector3(15.626,2.941,5.538)),"Original group dimensions")
 check(d.land_dimensions_m.is_equal_approx(Vector3(19.626,0,9.538)),"Original installation area")
 var v:=Visual.create("station",p);root.add_child(v)
 check(v.get_meta("representation")=="metric_mv_platform_group","Stable representation API")
 check(v.get_meta("display_module_count")==2 and not v.get_meta("representative_lod"),"Default shows both full modules")
 check(not v.get_meta("has_pv_inverters"),"No unmodeled inverter stage")
 check(v.find_children("CompactMVTransformerSwitchgear","Node3D",true,false).size()==2,"Common detailed construction in both modules")
 check(v.named_ports.size()==2 and v.has_named_port("in") and v.has_named_port("out"),"Exact existing logical ports")
 var expected:=Vector3(-d.body_dimensions_m.x*.5,.65,-d.body_dimensions_m.z*.5-.4)*.1
 check(v.port_local.is_equal_approx(expected),"Existing AC marker remains at same coordinate")
 check(v.named_port_locals["in"]==expected and v.named_port_locals["out"]==expected,"Existing aliases unchanged")
 var body:MeshInstance3D=v.find_child("MetricModuleGeometry",true,false)
 var b:=body.mesh.get_aabb()
 check(b.size.x<=d.body_dimensions_m.x*.1+.00001 and b.size.z<=d.body_dimensions_m.z*.1+.00001 and b.end.y<=d.body_dimensions_m.y*.1,"Detailed body fits unchanged spatial envelope")
 check(body.mesh.get_surface_count()==9,"Nine batched material surfaces")
 var detail:=Detail.new()
 check(detail.get_meta("representative_only") and detail.get_meta("identity")=="compact_mv_transformer_switchgear_not_hv_collector","Detail identity honest")
 check(detail.get_meta("triangle_count")<25000,"Single module bounded triangle budget")
 check(detail.get_meta("visible_roles").size()==7,"Platform, piers, fins, bushings, guard and cabinet roles")
 detail.free();v.free()
 # Current installations retain both original units when electrically derated.
 var derated:=p.duplicate(true);derated.capacity_mw=1.0
 var before:=var_to_bytes(derated);var low_d:=Spatial.profile("station",derated)
 check(low_d.valid and low_d.module_count==2 and low_d.body_dimensions_m==d.body_dimensions_m and low_d.land_dimensions_m==d.land_dimensions_m,"Current derating retains complete two-unit installation")
 var low_v:=Visual.create("station",derated);root.add_child(low_v)
 check(low_v.get_meta("site_geometry_profile")=="reference_size_v1" and low_v.get_meta("display_module_count")==2,"Current derated visual remains reference hardware")
 check(low_v.get_meta("land_dimensions_m")==d.land_dimensions_m and low_v.named_port_locals=={"in":expected,"out":expected},"Derated physical envelope and aggregate AC anchors stay fixed")
 check(var_to_bytes(derated)==before,"Geometry does not rewrite lower requested capacity")
 low_v.free()
 var maximum:=p.duplicate(true);maximum.capacity_mw=16.0
 var max_d:=Spatial.profile("station",maximum)
 check(max_d.valid and max_d.module_count==8,"Current supported upper limit retains eight full 2MW reference modules")
 var invalid:=p.duplicate(true);invalid.capacity_mw=16.01
 check(not Spatial.profile("station",invalid).valid,"Current capacity beyond finite 16MW support is rejected")
 # Preserve the old 1000MW geometry/LOD contract only for explicit historical
 # geometry, not as permission to construct such a current reference unit.
 var large:=p.duplicate(true);large.capacity_mw=1000;large.visual_site_geometry_profile=""
 check(not Spatial.profile("station",large).valid,"Historical huge rating is not accepted by current reference dimensions")
 var lod:=Visual.create("station",large)
 check(lod.get_meta("site_geometry_profile")=="","Large historical LOD never silently upgrades profile")
 check(lod.get_meta("module_count")==500 and lod.get_meta("display_module_count")==16 and lod.get_meta("representative_lod"),"Large station retains area/count with bounded visible samples")
 check(lod.get_meta("land_dimensions_m")==Spatial.profile("station",large,false,"flow_process_v2","").land_dimensions_m,"LOD never compresses site")
 lod.free()
 print("STATION_VISUAL_PHASE2_RESULT ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
