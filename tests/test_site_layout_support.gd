extends SceneTree
const S=preload("res://scripts/site_layout_support.gd")
const C=preload("res://scripts/device_catalog.gd")
var checks=0
var failures=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:
  failures+=1
  printerr("FAIL "+label)
func device(kind:String)->Dictionary:
 return {"id":7,"kind":kind,"params":C.defaults(kind),"site_geometry_profile":S.SITE_GEOMETRY_PROFILE,"state":{"sentinel":12.34},"position":[1,2,3]}
func _initialize():
 check(S.supported_kinds().size()==39,"39 scoped kinds")
 for kind in C.implemented_kinds():
  var d=device(kind)
  var original=d.duplicate(true)
  var r=S.assess_device(d)
  check(r.supported and r.operable and not r.needs_migration,"default "+kind)
  check(r.applicable,"coverage "+kind)
  check(d==original,"pure "+kind)
  var old=d.duplicate(true);old.erase("site_geometry_profile")
  var old_result=S.assess_device(old)
  check(old_result.supported and old_result.needs_migration and not old_result.operable,"legacy preserved "+kind)
  check(old.params==d.params and old.state==d.state,"legacy ratings untouched "+kind)
  check(S.validate_for_model([old]).operable and not S.validate_for_model([old]).applied,"legacy model bypass "+kind)
  check(not S.validate_for_model([old],true).operable,"explicit reference "+kind)
  for key in S.parameter_limits(kind):
   var bounds=S.parameter_limits(kind)[key]
   var changed=d.duplicate(true)
   changed.params[key]=float(bounds.max)+maxf(0.00001,absf(float(bounds.max))*0.01)
   var over=S.assess_device(changed)
   check(not over.supported and over.needs_migration,"overbound "+kind+" "+key)
   check(changed.params[key]>float(bounds.max),"no clamp "+kind+" "+key)
   # The scalar eta upper limit is legal with a smaller capacity; the joint limit has its own test.
   if key=="discharge_efficiency" and kind in ["caes_aboveground","liquid_air_store"]:changed.params.capacity_mwh*=0.5
   changed.params[key]=bounds.max
   check(S.assess_device(changed).operable,"max inclusive "+kind+" "+key)
   changed.params[key]=bounds.min
   check(S.assess_device(changed).supported==not bool(bounds.min_exclusive),"min semantics "+kind+" "+key)
   for bad in [NAN,INF,-INF,true,"1",null]:
    changed.params[key]=bad
    check(not S.assess_device(changed).supported,"invalid type "+kind+" "+key)
   changed.params.erase(key)
   check(not S.assess_device(changed).supported,"missing key "+kind+" "+key)
  var g:Dictionary=r.required_geometry
  if g.has("hardware_capacity_sufficient"):
   check(g.hardware_capacity_sufficient,"hardware volume "+kind)
   var low=d.duplicate(true)
   low.params[g.capacity_key]*=0.1
   var lg=S.assess_device(low).required_geometry
   check(is_equal_approx(g.hardware_internal_volume_m3,lg.hardware_internal_volume_m3),"no shrink when derated "+kind)
   check(is_equal_approx(lg.required_effective_volume_m3,g.required_effective_volume_m3*.1),"requested volume scales "+kind)
  var detached=S.parameter_limits(kind)
  detached.clear()
  check(S.parameter_limits(kind)==r.supported_bounds,"bounds defensive copy "+kind)
 var h=S.assess_device(device("hydrogen_gas_store")).required_geometry
 check(absf(h.minimum_installed_effective_volume_m3-1000.0/14)<1e-10,"H2 net capacity")
 check(h.untracked_heel_kg==0,"no hidden heel")
 check(h.hardware.count==54 and h.hardware_internal_volume_m3>75,"H2 actual bottle cavities")
 var a=S.assess_device(device("ammonia_synthesis_station")).required_geometry
 check(absf(a.minimum_installed_effective_volume_m3-200.0/3.3)<1e-10,"NH3 gaseous volume")
 check(a.reference_pressure_bar_abs==5,"NH3 gas reference")
 var steel=S.assess_device(device("solid_thermal_store")).required_geometry
 check(absf(steel.minimum_installed_material_mass_kg-2133333.3333333335)<1e-6,"steel mass")
 check(absf(steel.minimum_installed_effective_volume_m3-271.76220806794055)<1e-9,"steel net volume")
 check(steel.hardware_effective_volume_m3==288,"steel material fraction")
 var water=S.assess_device(device("thermal_store")).required_geometry
 check(water.hardware_effective_volume_m3>water.minimum_installed_effective_volume_m3,"hot-water density/freeboard")
 var wind=device("wind");wind.params.rotor_diameter_m=60
 check(not S.assess_device(wind).supported,"cannot invent smaller wind rotor")
 var legacy=device("thermal_store");legacy.erase("site_geometry_profile");legacy.params.charge_mwth=10000.0
 check(S.validate_for_model([legacy]).operable,"old extreme preserved teaching run")
 check(not S.validate_for_model([legacy],true).operable,"old extreme cannot migrate")
 var mixed=[device("battery"),legacy]
 check(not S.validate_for_model(mixed).operable,"partial migration cannot bypass")
 legacy.site_geometry_profile=null
 check(not S.validate_for_model([legacy]).operable,"null marker cannot bypass")
 for invalid in [null,1,true,[],"bad"]:
  check(not S.assess_device(invalid).supported,"bad device")
 check(not S.assess_device({}).supported,"missing kind")
 check(not S.assess_device({"kind":"battery","params":null}).supported,"bad params")
 check(not S.assess_world(null).supported,"bad world")
 var unknown=S.assess_device({"kind":"future_unreviewed"})
 check(not unknown.applicable,"unknown not certified")
 var v=S.assess_world([device("battery"),device("hydrogen_gas_store")])
 check(v.operable and v.devices.size()==2,"world strict pass")
 print("site_layout_support: %d checks, %d failures" % [checks,failures])
 quit(1 if failures else 0)
