extends SceneTree
const Visual=preload("res://scripts/equipment_visual.gd")
const Spatial=preload("res://scripts/spatial_dimensions.gd")
const Catalog=preload("res://scripts/device_catalog.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures.append(label);push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
 for kind in ["hydrogen_liquid_store","hydrogen_metal_hydride_store"]:
  var liquid:bool=kind=="hydrogen_liquid_store"
  var p:Dictionary={"capacity_kg":1000.0} if liquid else {"dry_host_mass_kg":10000.0}
  var snapshot:=var_to_bytes(p)
  var d:=Spatial.profile(kind,p)
  check(d.valid,kind+" fixed-site profile valid")
  check(d.module_count==1 and d.module_origins_m[0]==Vector3.ZERO,kind+" one complete centered site")
  check(d.land_dimensions_m==(Vector3(44,0,32) if liquid else Vector3(24,0,18)),kind+" exact authorized teaching occupancy")
  var low:=p.duplicate(true);low.charge_kg_s=0;low.discharge_kg_s=0
  if liquid:low.capacity_kg=1.0
  check(Spatial.profile(kind,low).land_dimensions_m==d.land_dimensions_m,kind+" zero throughput never shrinks facility")
  var invalid:=p.duplicate(true)
  if liquid:invalid.capacity_kg=1000.01
  else:invalid.dry_host_mass_kg=10001
  check(not Spatial.profile(kind,invalid).valid,kind+" upper physical contract bounded")
  if not liquid:
   invalid.dry_host_mass_kg=1000
   var smaller:=Spatial.profile(kind,invalid)
   check(smaller.valid and smaller.dry_host_mass_kg==1000 and smaller.derived_hydrogen_capacity_kg==12,"Small new-build dry host derives exact usable hydrogen")
   check(smaller.land_dimensions_m==d.land_dimensions_m,"Reduced host fill retains complete thermal-management site")
   invalid.dry_host_mass_kg=0
   check(not Spatial.profile(kind,invalid).valid,"Zero dry host rejected")
   check(d.derived_hydrogen_capacity_kg==120,"Fixed 10t host implies 120kg capacity")
  var start:=Time.get_ticks_usec()
  var v:=Visual.create(kind,p)
  var usec:=Time.get_ticks_usec()-start
  root.add_child(v)
  check(v.get_meta("representation")=="complete_"+kind,kind+" distinct complete facility")
  check(v.get_meta("internal_inventory_phase")==d.material_phase,kind+" internal phase explicit")
  check(v.get_meta("external_hydrogen_phase")=="gas",kind+" external gas phase unchanged")
  for key in ["geometry_is_capacity_proof","pressure_is_simulated","temperature_is_dynamic","soc_is_liquid_level"]:check(not v.get_meta(key),kind+" no false dynamic "+key)
  check(v.named_ports.size()==3 and v.has_named_port("ac_in") and v.has_named_port("h2_in") and v.has_named_port("h2_out"),kind+" exactly three true ports")
  var specs:Array=Catalog.ports(kind)
  check(specs.size()==3,kind+" complete actual v2 catalog contract")
  for spec in specs:
   for key in ["carrier","unit","direction"]:check(v.named_ports[spec.id].get_meta(key)==spec[key],kind+" catalog port "+spec.id+" "+key)
   if spec.carrier!="electricity_ac":
    for key in ["species_id","phase_id","grade_id"]:check(v.named_ports[spec.id].get_meta(key)==spec[key],kind+" gas contract "+key)
  for local in v.named_port_locals.values():check(absf(local.x)<d.land_dimensions_m.x*.05 and absf(local.z)<d.land_dimensions_m.z*.05,kind+" port within installation boundary")
  var districts:Array=["LH2VacuumInsulatedStorage","LH2LiquefierColdBox","LH2CompressionAndRefrigerationHall","LH2LiquefactionCompressorSkids","LH2FiniteAmbientVaporizer","LH2InsulatedTransferAndWarmGasHeaders","LH2BoiloffVentMast"] if liquid else ["LaNi5WeatherEnclosedBedModule","LaNi5JacketedTubularBedRack","LaNi5ElectricHeatingAndCirculation","LaNi5AbsorptionHeatRejection","LaNi5ClosedThermalManagementLoop"]
  for district in districts:check(v.find_child(district,true,false)!=null,kind+" process role "+district)
  check(v.find_child("CompositePressureCylinder",true,false)==null,kind+" not a copy of compressed gas rack")
  var geom:MeshInstance3D=v.find_child("HydrogenPhaseFacilityGeometry",true,false)
  var b:=geom.mesh.get_aabb()
  check(b.size.x<=d.body_dimensions_m.x*.1+.001 and b.size.z<=d.body_dimensions_m.z*.1+.001 and b.end.y<=d.body_dimensions_m.y*.1+.001,kind+" all components remain within actual metric envelope")
  var tris:=0
  for surface in geom.mesh.get_surface_count():
   var indices:PackedInt32Array=geom.mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
   tris+=indices.size()/3 if not indices.is_empty() else geom.mesh.surface_get_array_len(surface)/3
  check(tris<100000,kind+" bounded mesh budget")
  check(geom.mesh.get_surface_count()<=12,kind+" material batching")
  check(var_to_bytes(p)==snapshot,kind+" geometry does not mutate state/parameters")
  print("PHASE_GEOMETRY ",kind," triangles=",tris," surfaces=",geom.mesh.get_surface_count()," build_usec=",usec," ports=",v.named_port_locals," aabb=",b)
  v.free()
 print("HYDROGEN_PHASE_VISUAL_RESULT ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
