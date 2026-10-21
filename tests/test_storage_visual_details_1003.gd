extends SceneTree
## Isolated headless presentation checks: no user saves and no desktop window.
const Catalog = preload("res://scripts/device_catalog.gd")
const Visual = preload("res://scripts/equipment_visual.gd")
const Spatial = preload("res://scripts/spatial_dimensions.gd")
const Inspector = preload("res://scripts/device_inspector.gd")
const Form = preload("res://scripts/parameter_form.gd")
const TestHost = preload("res://tests/test_device_inspector_v23.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String) -> void:
 checks += 1
 if not ok:
  failures.append(message)
  push_error("STORAGE_VISUAL_1003 " + message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 root.size = Vector2i(1024, 768)
 var host := TestHost.Host.new()
 root.add_child(host)
 var inspector := Inspector.new()
 host.add_child(inspector)
 inspector.setup(host)
 var form := Form.new()
 host.add_child(form)
 var names: Array[String] = []
 for kind in Catalog.NEW_STORAGE_KINDS:
  var params: Dictionary = Catalog.defaults(kind)
  var thermal: bool = Catalog.is_thermal_storage(kind)
  var energy_key := "energy_mwhth" if thermal else "energy_mwh"
  var capacity_key := "capacity_mwhth" if thermal else "capacity_mwh"
  var charge_key := "charge_mwth" if thermal else "charge_mw"
  var discharge_key := "discharge_mwth" if thermal else "discharge_mw"
  var state := {energy_key: float(params[capacity_key]) * .25}
  var id: int = host.devices.size()
  var current_device := {"id":id, "kind":kind, "params":params, "state":state, "site_geometry_profile":"reference_size_v1"}
  if kind=="battery_flow":current_device.geometry_profile="flow_process_v2"
  host.devices.append(current_device)
  host.result.get_or_add("devices", {})[str(id)] = {charge_key:.02, discharge_key:0.0}
  var before := var_to_bytes([host.devices, host.links, host.result])
  check(inspector.open_device(id), kind + " opens detail")
  await process_frame
  inspector.reset_camera()
  check(inspector.texts["运行"].text.contains("SOC 25.00%"), kind + " derives SOC from saved inventory")
  check(inspector.texts["运行"].text.contains("本步实际：充 0.0200"), kind + " uses actual report, not nameplate")
  check(inspector.texts["运行"].text.contains("连续自损"), kind + " explicit self loss")
  check(inspector.texts["边界"].text.contains("未建模"), kind + " honest model limits")
  check(inspector.texts["连接"].text.contains("尚未连接任何线路"), kind + " no invented topology")
  var visual: Node3D = inspector.model_node
  var representation := str(visual.get_meta("representation", ""))
  check(not representation.is_empty() and not representation in names, kind + " distinguishable representation")
  names.append(representation)
  check(not visual.get_meta("pressure_is_simulated", true), kind + " no pressure simulation claim")
  check(visual.get_meta("capacity_added", -1) == 0.0, kind + " display adds no capacity")
  check(visual.get_meta("display_module_count", 0) == visual.get_meta("module_count", -1), kind + " default displays full facility")
  check(visual.get("named_ports").size() == Catalog.ports(kind).size(), kind + " exact port count")
  for port in Catalog.ports(kind):
   check(visual.has_named_port(str(port.id)), kind + " physical port " + str(port.id))
   var anchor: Node3D = visual.get("named_ports")[port.id]
   check(anchor.get_meta("direction") == port.direction, kind + " port direction matches catalog")
   check(anchor.get_meta("carrier") == port.carrier, kind + " port carrier matches catalog")
  if thermal:
   check(not visual.has_named_port("ac"), "solid storage does not pretend to generate power")
   check(inspector.texts["运行"].text.contains("不直接发电"), "thermal-only boundary visible")
  if kind == "hydrogen_storage_system":
   for stage in ["ElectrolyzerAndCompressionStage", "HydrogenStorageVesselBank", "FuelCellAndInverterStage"]:
    check(visual.find_child(stage, true, false) != null, "hydrogen visible stage " + stage)
   check(inspector.texts["运行"].text.contains("MWh(LHV)"), "hydrogen LHV inventory unit")
  if kind == "caes_aboveground":
   for stage in ["AbovegroundAirVesselBank", "ElectricDrivenAirCompressor", "AirExpanderGenerator"]:
    check(visual.find_child(stage, true, false) != null, "CAES visible stage " + stage)
  var dimensions: Dictionary = Spatial.profile(kind, params)
  check(dimensions.valid, kind + " current reference metric profile valid")
  check(visual.get_meta("site_geometry_profile")=="reference_size_v1", kind + " detail uses actual current reference geometry")
  check(visual.get_meta("land_dimensions_m")==dimensions.land_dimensions_m, kind + " current detail and placement use same complete site")
  check(dimensions.land_area_m2 > dimensions.body_area_m2, kind + " installation allowance distinct from footprint")
  var larger := params.duplicate(true)
  larger[capacity_key] = float(params[capacity_key]) * 5.0
  check(not Spatial.profile(kind, larger, false).valid, kind + " current unsupported expansion is rejected")
  var derated:=params.duplicate(true);derated[capacity_key]=float(params[capacity_key])*.25
  var low:=Spatial.profile(kind,derated,false)
  check(low.valid and low.module_count==dimensions.module_count and low.body_dimensions_m==dimensions.body_dimensions_m and low.land_dimensions_m==dimensions.land_dimensions_m, kind + " derating retains all installed hardware")
  # The old module-scaling contract is retained only for historical geometry,
  # not as permission to construct oversized current reference facilities.
  var historical:=Spatial.profile(kind,params,false,"flow_process_v2","")
  var historical_larger:=Spatial.profile(kind,larger,false,"flow_process_v2","")
  check(historical.valid and historical_larger.valid and historical_larger.land_area_m2>historical.land_area_m2, kind + " historical capacity increases full-module land usage")
  form.set_parameters(kind, params, false)
  check(form._fields.size() == params.size(), kind + " all parameters have fields")
  check(form.get_validation_errors().is_empty(), kind + " default form valid")
  check(not form._fields.initial_soc.editable, kind + " initial SOC locked for existing facility")
  form._fields.initial_soc.text = "1"
  check(form.get_parameters().initial_soc == params.initial_soc, kind + " initial SOC not reset by editing")
  form._fields[capacity_key].text = "not a number"
  check(not form.get_validation_errors().is_empty(), kind + " invalid capacity is rejected")
  check(Form.GROUPS[kind].size() == 3, kind + " grouped capacity/loss/initialization")
  for field in form._fields.values():
   check(field.get_theme_font_size("font_size") >= 18, kind + " readable numeric type")
   check(field.custom_minimum_size.x >= 125 and field.custom_minimum_size.y >= 40, kind + " touch target size")
  var escape := InputEventKey.new()
  escape.keycode = KEY_ESCAPE; escape.pressed = true; escape.echo = true
  inspector._window_input(escape)
  check(inspector.visible, kind + " held Esc does not close next layer")
  escape.echo = false
  inspector._window_input(escape)
  check(not inspector.visible, kind + " Esc closes one inspector layer")
  check(before == var_to_bytes([host.devices, host.links, host.result]), kind + " inspection/form/Esc leave state unchanged")
 var large := Catalog.defaults("caes_aboveground")
 large.capacity_mwh = 100.0
 check(not Spatial.profile("caes_aboveground",large,false).valid,"current CAES refuses historical 100MWh geometry stress rating")
 large.visual_site_geometry_profile=""
 var lod := Visual.create("caes_aboveground", large)
 check(lod.get_meta("site_geometry_profile")=="","CAES stress LOD explicitly remains historical geometry")
 check(lod.get_meta("module_count") == 400, "large installation keeps exact physical count")
 check(lod.get_meta("display_module_count") == 48 and lod.get_meta("representative_lod"), "large facility has explicit bounded visual LOD")
 check(lod.get("surfaces").size() < 20, "large facility uses batched meshes")
 lod.free()
 host.free()
 await process_frame
 print("STORAGE_VISUAL_DETAILS_1003 checks=", checks, " failures=", failures.size())
 quit(0 if failures.is_empty() else 1)
