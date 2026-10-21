extends SceneTree
const Catalog = preload("res://scripts/device_catalog.gd")
const Spatial = preload("res://scripts/spatial_dimensions.gd")
const Visual = preload("res://scripts/equipment_visual.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, what: String) -> void:
 checks += 1
 if not ok: failures.append(what); push_error(what)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var stages := {"water_supply_boundary":["FiniteSectionalWaterReservoir","WaterMeterAndPumpSkid"],"electrolyzer_station":["PEMElectrolyzerEnclosure","RectifierPowerSupplyEnclosure","ElectrolyzerThermalControl"],"hydrogen_gas_store":["VerticalCompositeHydrogenCylinderRack","HydrogenCompressorAndValveSkid","GasDeliveryRegulationAndMetering"],"fuel_cell_station":["FuelCellCabinetBank","FuelCellDryCoolingBank","FuelCellInverterAndACSwitchgear"]}
 for kind in Visual.MATERIAL_KINDS:
  var p := Catalog.defaults(kind)
  var before := var_to_bytes(p)
  var d := Spatial.profile(kind,p)
  var cheap := Spatial.profile(kind,p,false)
  check(d.valid and cheap.valid,kind+" valid metric profile")
  check(d.module_count == 1,kind+" one default aggregate module")
  check(d.land_area_m2 > d.body_area_m2,kind+" margin not double counted")
  check(d.body_dimensions_m == cheap.body_dimensions_m and d.land_area_m2 == cheap.land_area_m2,kind+" cheap persistence query identical")
  check(d.module_origins_m.size()==1 and cheap.module_origins_m.is_empty(),kind+" origin query bounded")
  var v := Visual.create(kind,p)
  root.add_child(v)
  check(v.get_meta("visual_dimension_profile")=="metric_v1",kind+" metric without opt in")
  check(v.get_meta("representation")=="material_process_"+kind,kind+" no placeholder/reused battery")
  check(v.get_meta("capacity_added")==0.0 and not v.get_meta("geometry_is_capacity_proof"),kind+" display is not capacity")
  check(not v.get_meta("pressure_is_simulated"),kind+" no invented pressure transient")
  check(v.find_child("Placeholder",true,false)==null,kind+" no placeholder")
  for name in stages[kind]: check(v.find_child(name,true,false)!=null,kind+" independent component "+name)
  check(v.named_ports.size()==Catalog.ports(kind).size(),kind+" exact port count")
  for spec in Catalog.ports(kind):
   check(v.has_named_port(spec.id),kind+" named port "+spec.id)
   var port: Node3D = v.named_ports[spec.id]
   for key in ["carrier","direction","unit","species_id","phase_id","grade_id","voltage_level"]:
    if spec.has(key): check(port.get_meta(key)==spec[key],kind+" port "+spec.id+" "+key)
   check(v.get_named_port_position(spec.id).is_finite(),kind+" finite port")
   var a: Vector3 = v.named_port_locals[spec.id]*10.0
   check(absf(a.x)<d.land_dimensions_m.x*.5 and absf(a.z)<d.land_dimensions_m.z*.5,kind+" port inside installation")
  var body: MeshInstance3D = v.find_child("MaterialFacilityGeometry",true,false)
  check(body != null and body.mesh.get_surface_count()<=12,kind+" material batching budget")
  var b: AABB = body.mesh.get_aabb()
  check(b.position.y >= -.00001,kind+" ground contact")
  check(b.end.y <= d.body_dimensions_m.y*.1+.001,kind+" height matches profile")
  check(b.size.x <= d.body_dimensions_m.x*.1+.001 and b.size.z <= d.body_dimensions_m.z*.1+.001,kind+" module envelope")
  check(v.surfaces.size()<=20,kind+" surface node budget")
  check(var_to_bytes(p)==before,kind+" rendering does not mutate parameters")
  var p2 := p.duplicate(true)
  p2[d.rating_parameter] = float(p2[d.rating_parameter])*2.01
  check(not Spatial.profile(kind,p2,false).valid,kind+" reference profile rejects unsupported enlargement")
  var historical_default:=Spatial.profile(kind,p,false,"flow_process_v2","")
  var d2 := Spatial.profile(kind,p2,false,"flow_process_v2","")
  check(d2.module_count==3 and d2.unit_dimensions_m==historical_default.unit_dimensions_m,kind+" historical replicate never stretches")
  check(d2.land_area_m2>historical_default.land_area_m2,kind+" historical capacity takes more land")
  p2[d.rating_parameter]=NAN
  check(not Spatial.profile(kind,p2,false).valid,kind+" reject nonfinite geometry")
  v.free()
 var huge := Catalog.defaults("hydrogen_gas_store")
 huge.capacity_kg = 1000000000.0
 check(not Spatial.profile("hydrogen_gas_store",huge,false).valid,"new reference cannot pretend billion-kg site is supported")
 var full := Spatial.profile("hydrogen_gas_store",huge,false,"flow_process_v2","")
 check(full.valid and full.module_count==1000000 and full.module_origins_m.is_empty(),"massive site cheap reject path retains dimensions")
 var large := Catalog.defaults("water_supply_boundary")
 large.capacity_kg=500000
 large.visual_site_geometry_profile=""
 var lod := Visual.create("water_supply_boundary",large)
 check(lod.get_meta("module_count")==50 and lod.get_meta("display_module_count")==32 and lod.get_meta("representative_lod"),"LOD explicit bounded without capacity shrink")
 lod.free()
 print("MATERIAL_VISUAL_PHASE2_RESULT ", "PASS" if failures.is_empty() else "FAIL", " checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
