extends SceneTree
const S=preload("res://scripts/site_layout_support.gd")
const C=preload("res://scripts/device_catalog.gd")
var checks:=0
var failures:=0
var cases:Array=[]
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL "+label)
func probe(device:Dictionary)->Dictionary:
 var before=var_to_bytes(device)
 var result=S.assess_device(device)
 check(var_to_bytes(device)==before,"pure assessment")
 cases.append({"device":device.duplicate(true),"result":result})
 return result
func _initialize():
 for kind in ["caes_aboveground","liquid_air_store"]:
  var d={"id":7,"kind":kind,"params":C.defaults(kind),"state":{"energy_mwh":0.123},"x":12.3,"z":-4.5,"site_geometry_profile":S.SITE_GEOMETRY_PROFILE}
  var result=probe(d)
  check(result.operable,"default "+kind)
  var g:Dictionary=result.required_geometry
  check(g.energy_screen_pass and not g.screen_is_performance_guarantee and not g.pressure_vessel_certified,"screen not certification")
  check(not g.pressure_is_simulated and not g.soc_is_pressure_or_liquid_level and g.external_heat_credit_mwh==0,"no dynamic state or free heat")
  if kind=="caes_aboveground":
   check(absf(g.hardware_internal_volume_m3-104.55220351146832)<1e-9,"four net cylinders")
   check(absf(g.ideal_isothermal_availability_mwh-0.42576314717198677)<1e-12,"separate reversible availability")
   check(absf(g.net_electric_screen_mwh-0.19972593183091922)<1e-12,"no-reheat adiabatic bound")
   check(absf(g.requested_net_electric_mwh-.175)<1e-12,"actual discharge efficiency applied")
  else:
   check(absf(g.hardware_internal_volume_m3-127.108838764243)<1e-8,"two net cryogenic cylinders")
   check(absf(g.hardware_effective_volume_m3-101.68707101139441)<1e-8,"fill excludes freeboard")
   check(absf(g.reference_maximum_liquid_mass_kg-88679.26088761684)<1e-6,"finite liquid mass screen")
   check(absf(g.requested_net_electric_mwh-5.2)<1e-12,"internal energy not AC energy")
   check(absf(g.required_liquid_mass_kg-62400.0)<1e-7,"default liquid requirement")
  var high=d.duplicate(true);high.params.discharge_efficiency=1.0
  var over=probe(high)
  check(not over.operable and over.needs_migration and over.issues[0].code=="energy_screen_exceeded","high eta cannot bypass volume "+kind)
  var small=high.duplicate(true);small.params.capacity_mwh*=.5
  check(probe(small).operable,"small capacity high eta valid "+kind)
  for offset in [-1e-9,0.0,1e-9]:
   var edge=high.duplicate(true);edge.params.capacity_mwh=g.net_electric_screen_mwh+offset
   check(probe(edge).operable==(offset<=0),"exact net bound both sides "+kind)
  var low=d.duplicate(true);low.params.capacity_mwh*=.25
  var lower=probe(low).required_geometry
  check(lower.hardware_internal_volume_m3==g.hardware_internal_volume_m3 and lower.net_electric_screen_mwh==g.net_electric_screen_mwh,"derating never shrinks hardware")
  check(absf(lower.required_effective_volume_m3-.25*g.required_effective_volume_m3)<1e-9,"required volume scales only")
  var legacy=high.duplicate(true);legacy.erase("site_geometry_profile")
  var before=var_to_bytes(legacy)
  check(S.validate_for_model([legacy]).operable and not S.validate_for_model([legacy]).applied,"legacy not retroactively constrained")
  check(not S.validate_for_model([legacy],true).operable,"migration reports unsupported pair")
  check(var_to_bytes(legacy)==before,"legacy state and rating not clamped")
  for invalid in [null,".7",NAN,INF,true]:
   var bad=d.duplicate(true);bad.params.discharge_efficiency=invalid
   check(not S.assess_device(bad).operable,"bad efficiency fail closed")
  var missing=d.duplicate(true);missing.params.erase("discharge_efficiency")
  check(not S.assess_device(missing).operable,"missing efficiency fail closed")
 print("AIR_SCREEN_CASES ",JSON.stringify(cases,"",false,true))
 print("AIR_STORAGE_GEOMETRY checks=",checks," failures=",failures)
 quit(0 if failures==0 else 1)
