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
 var p:=Catalog.defaults("co2_liquid_cycle_store")
 var before:=var_to_bytes(p)
 var d:=Spatial.profile("co2_liquid_cycle_store",p)
 check(d.valid,"CO2 default supported despite float32 spatial limits")
 check(d.module_count==1 and d.land_dimensions_m==Vector3(752,0,752),"752m square original site")
 check(absf(d.land_area_m2-565504)<1,"Area never compressed to CAES footprint")
 check(absf(d.published_site_area_m2-565333.333333)<.01,"848mu independently recorded")
 var lower:=p.duplicate(true);lower.capacity_mwh=1.;lower.charge_mw=1.;lower.discharge_mw=1.
 check(Spatial.profile("co2_liquid_cycle_store",lower).land_dimensions_m==d.land_dimensions_m,"Low rating does not shrink whole plant")
 var bad:=p.duplicate(true);bad.capacity_mwh=800
 check(not Spatial.profile("co2_liquid_cycle_store",bad,false).valid,"No unbounded multi-site interpolation")
 bad.capacity_mwh=794.24001
 check(not Spatial.profile("co2_liquid_cycle_store",bad,false).valid,"Exact fractional capacity ceiling retained")
 var start:=Time.get_ticks_usec()
 var v:=Visual.create("co2_liquid_cycle_store",p)
 var build_usec:=Time.get_ticks_usec()-start
 root.add_child(v)
 check(v.get_meta("representation")=="complete_closed_co2_gas_liquid_cycle","Distinct CO2 facility")
 check(v.get_meta("gas_holder_count")==5 and v.get_meta("liquid_storage_unit_count")==141 and v.get_meta("thermal_storage_unit_count")==97,"Published equipment counts")
 for key in ["pressure_is_simulated","working_fluid_mass_calibrated","soc_is_gas_volume","geometry_is_capacity_proof"]:check(not v.get_meta(key),"Honest CO2 boundary "+key)
 for node in ["CO2LowPressureGasHolderDistrict","CO2LiquidStorageDistrict","CO2InternalThermalStorageDistrict","CO2CompressionExpansionProcessCore","CO2HeatExchangeAndLiquefactionTrain","CO2ClosedLoopPipeGallery"]:check(v.find_child(node,true,false)!=null,"Complete process district "+node)
 check(v.find_child("CO2LowPressureGasHolderDistrict",true,false).get_child_count()==6,"Five holders plus one annotation")
 check(v.find_child("AbovegroundAirVesselBank",true,false)==null,"Not CAES air-bank reuse")
 check(v.named_ports.size()==1 and v.has_named_port("ac"),"One aggregate port")
 var anchor:Node3D=v.named_ports.ac
 for key in ["carrier","unit","direction","voltage_level"]:check(anchor.get_meta(key)==Catalog.ports("co2_liquid_cycle_store")[0][key],"Port contract "+key)
 check(absf(v.named_port_locals.ac.z)*10<376,"AC within site boundary")
 var geom:MeshInstance3D=v.find_child("CO2CompleteSiteGeometry",true,false)
 var bound:=geom.mesh.get_aabb()
 check(bound.size.x<=74.81 and bound.size.z<=74.81 and bound.end.y<=5.5,"All districts inside declared physical envelope")
 var triangles:=0
 for surface in geom.mesh.get_surface_count():
  var indices:PackedInt32Array=geom.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
  triangles+=indices.size()/3 if not indices.is_empty() else geom.mesh.surface_get_array_len(surface)/3
 check(triangles<140000,"Entire 5/141/97 site bounded mesh budget")
 check(geom.mesh.get_surface_count()<=12,"Material batching")
 check(var_to_bytes(p)==before,"No parameters changed by geometry")
 # Actual placement predicate, original terrain, no scene startup or save access.
 var w:=World.new()
 w.height_image=Image.create_from_data(1024,1024,false,Image.FORMAT_RF,FileAccess.get_file_as_bytes("res://generated/height.raw"))
 w.cfg=JSON.parse_string(FileAccess.get_file_as_string("res://config/map.json"));w.noise.seed=int(w.cfg.seed);w.noise.frequency=.045;w.noise.fractal_octaves=4
 w.dimension_profile="metric_v1";w.devices=[];w.stations=[]
 check(w.can_place("co2_liquid_cycle_store",Vector2(0,-11)).is_empty(),"Unmodified map has legal center (0,-11) when clear")
 var beyond_edge:=Vector2(Domain.HALF_EXTENTS.x-float(d.clearance_radius_world)+.01,0)
 check(not Domain.contains(beyond_edge,float(d.clearance_radius_world)),"Whole CO2 site exceeds current domain edge")
 check(w.can_place("co2_liquid_cycle_store",beyond_edge).contains("边界"),"Expanded map still rejects a whole site crossing its boundary")
 w.devices=[{"id":1,"kind":"load","x":0.,"z":-11.,"params":Catalog.defaults("load"),"site_geometry_profile":"reference_size_v1"}]
 check(w.can_place("co2_liquid_cycle_store",Vector2(0,-11)).contains("重叠"),"Existing reference-layout device blocks overlapping site")
 w.devices[0].erase("site_geometry_profile")
 check(w.can_place("co2_liquid_cycle_store",Vector2(0,-11)).contains("旧比例"),"Legacy compatibility explicitly blocks new construction before overlap tests")
 var orphans:Array[Node]=[]
 for property in w.get_property_list():
  if not (property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE):continue
  var value:Variant=w.get(property.name)
  if value is Node and value!=w and value.get_parent()==null and not value in orphans:orphans.append(value)
 w.free()
 for n in orphans:
  if is_instance_valid(n):n.free()
 v.free()
 print("CO2_VISUAL_PHASE2_RESULT ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size()," triangles=",triangles," build_usec=",build_usec)
 quit(0 if failures.is_empty() else 1)
