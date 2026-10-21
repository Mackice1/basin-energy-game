extends SceneTree
## Photo-reference and geometry contract. Runs headlessly, without user saves.
const Visual = preload("res://scripts/equipment_visual.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
const Spatial = preload("res://scripts/spatial_dimensions.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok: failures.append(label); push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 for params in [Catalog.defaults("caes_aboveground"), {"capacity_mwh":1.0,"charge_mw":.2,"discharge_mw":.2}, {"capacity_mwh":10.0,"charge_mw":2.0,"discharge_mw":2.0}]:
  var before: Dictionary = params.duplicate(true)
  var shape: Dictionary = Spatial.profile("caes_aboveground", params)
  var item := Visual.create("caes_aboveground", params)
  root.add_child(item)
  check(params == before, "visual never mutates parameters")
  check(shape.unit_dimensions_m == Vector3(24,6,18), "existing module dimensions unchanged")
  check(item.get_meta("body_dimensions_m") == shape.body_dimensions_m, "existing site dimensions unchanged")
  check(item.get_meta("caes_visual_revision") == "photo_referenced_surface_plant_v2", "reference-backed visual revision")
  check(item.get_meta("caes_reference_ids").size() == 4, "traceable photo mapping")
  check(item.get_meta("caes_storage_location") == "aboveground_pressure_vessels_only", "no cavern geometry implied")
  check(not item.get_meta("caes_geometry_is_capacity_proof"), "photo sizes are not energy guarantees")
  check(not item.get_meta("caes_thermal_vessels_are_air_storage"), "thermal spheres not mistaken for air store")
  check(not item.get_meta("pressure_is_simulated") and item.get_meta("capacity_added") == 0.0, "presentation changes no physics")
  var modules := item.find_children("StorageModule*", "Node3D", false, false)
  check(modules.size() == shape.module_count, "accepted CAES limits render complete module count")
  for module in modules:
   for stage in ["CompressorExpanderMachineHall","ElectricDrivenAirCompressor","AirExpanderGenerator","ThermalRecoveryAndStorageArea","InsulatedHeatExchangerTrain","AbovegroundAirVesselBank","ElevatedProcessPipeGallery"]:
    check(module.find_child(stage,true,false) != null, "distinct process stage " + stage)
   var bank: Node = module.get_node("AbovegroundAirVesselBank")
   check(bank.get_child_count() == 4, "four individually structured air receivers")
   for receiver in bank.get_children():
    check(receiver.get_meta("shell_form") == "cylinder_with_shallow_dished_heads", "receiver is not generic capsule or sphere")
   var heat: Node = module.get_node("ThermalRecoveryAndStorageArea")
   check(heat.get_meta("role") == "internal_compression_heat_recovery_not_air_inventory", "distinct heat role")
  var mesh: MeshInstance3D = item.get_node("StorageFacilityGeometry")
  var bounds: AABB = mesh.mesh.get_aabb()
  var body: Vector3 = shape.body_dimensions_m * .1
  check(bounds.position.y >= -0.00001 and bounds.end.y <= body.y + .00001, "geometry remains above ground and inside height")
  check(bounds.position.x >= -body.x*.5-.00001 and bounds.end.x <= body.x*.5+.00001, "geometry fits unchanged width")
  check(bounds.position.z >= -body.z*.5-.00001 and bounds.end.z <= body.z*.5+.00001, "geometry fits unchanged depth")
  check(item.named_ports.keys() == ["ac"], "exactly one authoritative aggregate AC terminal")
  check(item.named_ports.ac.get_meta("direction") == "bidirectional", "AC direction unchanged")
  var expected: Vector3 = Vector3(-shape.body_dimensions_m.x*.5+.5,.65,-shape.body_dimensions_m.z*.5-.35)*.1
  check(item.named_port_locals.ac.is_equal_approx(expected), "existing cable anchor remains exact")
  check(item.surfaces.size() < 20, "material batching retained")
  for label in ["CAESMachineHallLabel","CAESHeatRecoveryLabel","CAESAbovegroundAirLabel"]:
   check(item.find_children(label,"Label3D",true,false).size() == 1, "one uncluttered identification " + label)
  item.free()
 print("CAES_REFERENCE_VISUAL_1003 checks=",checks," failures=",failures.size())
 quit(0 if failures.is_empty() else 1)
