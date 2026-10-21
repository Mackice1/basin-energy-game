extends SceneTree
const V=preload("res://scripts/equipment_visual.gd")
const S=preload("res://scripts/spatial_dimensions.gd")
const C=preload("res://scripts/device_catalog.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,msg:String)->void:
 checks+=1
 if not ok:failures.append(msg);push_error(msg)
func _initialize():call_deferred("run")
func run():
 for kind in V.CHEMICAL_KINDS:
  var p:Dictionary={"capacity_kg":200.0 if kind=="ammonia_synthesis_station" else 1000.0}
  var d:=S.profile(kind,p)
  var before:=var_to_bytes(p)
  check(d.valid and d.module_count==1 and d.module_origins_m[0]==Vector3.ZERO,kind+" one full centered site")
  var small:=p.duplicate();small.capacity_kg=1.0
  check(S.profile(kind,small).land_dimensions_m==d.land_dimensions_m,kind+" finite capacity reduction does not shrink facility")
  var large:=p.duplicate();large.capacity_kg+=1
  check(not S.profile(kind,large).valid,kind+" hard capacity ceiling")
  var start:=Time.get_ticks_usec();var v:=V.create(kind,p);var usec:=Time.get_ticks_usec()-start
  root.add_child(v)
  check(v.get_meta("representation")=="complete_"+kind,kind+" own complete architecture")
  for key in ["geometry_is_capacity_proof","pressure_is_simulated","temperature_is_dynamic","has_free_material_source"]:check(not v.get_meta(key),kind+" honest boundary "+key)
  var g:MeshInstance3D=v.find_child("ChemicalFacilityGeometry",true,false);var b:=g.mesh.get_aabb()
  check(b.size.x<=d.body_dimensions_m.x*.1+.001 and b.size.z<=d.body_dimensions_m.z*.1+.001 and b.end.y<=d.body_dimensions_m.y*.1+.001 and b.position.y>=-.001,kind+" metric envelope "+str(b))
  check(g.mesh.get_surface_count()<=12,kind+" batching")
  var tris:=0
  for i in g.mesh.get_surface_count():
   var indices:PackedInt32Array=g.mesh.surface_get_arrays(i)[Mesh.ARRAY_INDEX];tris+=indices.size()/3
  check(tris<80000,kind+" bounded triangle budget")
  var expected:Dictionary={"nitrogen_supply_boundary":["FinitePreparedNitrogenBottleBundles","NitrogenRegulationAndMetering"],"co2_supply_boundary":["FiniteCO2FlexibleGasBuffer","CO2GasOutletMeterAndIsolation"],"ammonia_synthesis_station":["AmmoniaProductionHall","AmmoniaSynthesisRecycleAndSeparation","FiniteAmmoniaGasProductBuffer","FiniteElectricHeatingAndHeatRejection"],"methanol_synthesis_station":["MethanolProductionHall","MethanolSynthesisAndDistillation","FiniteMethanolLiquidProductBuffer","FiniteElectricHeatingAndHeatRejection"]}
  for stage in expected[kind]:check(v.find_child(stage,true,false)!=null,kind+" distinct stage "+stage)
  var specs:Array=C.ports(kind)
  check(specs.size()==(1 if kind in ["nitrogen_supply_boundary","co2_supply_boundary"] else 3),kind+" real catalog contract landed")
  if not specs.is_empty():
   check(v.named_ports.size()==specs.size(),kind+" only catalog ports")
   for spec in specs:
    for key in ["direction","carrier","unit"]:check(v.named_ports[spec.id].get_meta(key)==spec[key],kind+" "+spec.id+" "+key)
    if spec.carrier!="electricity_ac":
     for key in ["species_id","phase_id","grade_id"]:check(v.named_ports[spec.id].get_meta(key)==spec[key],kind+" material "+key)
     var caption:Label3D=v.named_ports[spec.id].get_node("PortLabel")
     var expected_formula:String={"N2":"N₂","CO2":"CO₂","H2":"H₂"}[str(spec.species_id)]
     check(expected_formula in caption.text,kind+" material caption names correct species")
     if spec.species_id!="H2":check(not "H₂" in caption.text,kind+" non-hydrogen port never mislabeled hydrogen")
  else:print("CHEMICAL_PORT_CONTRACT_PENDING ",kind)
  check(var_to_bytes(p)==before,kind+" display leaves physical input unchanged")
  print("CHEMICAL_GEOMETRY ",kind," triangles=",tris," surfaces=",g.mesh.get_surface_count()," usec=",usec," land=",d.land_dimensions_m," ports=",v.named_port_locals)
  v.free()
 print("CHEMICAL_VISUAL_RESULT ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
