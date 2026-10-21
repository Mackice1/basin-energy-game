extends SceneTree
const C=preload("res://scripts/device_catalog.gd")
const S=preload("res://scripts/site_layout_support.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;printerr("FAIL "+label)
func _initialize():
 var d={"id":1,"kind":"battery_flow","params":C.defaults("battery_flow"),"site_geometry_profile":S.SITE_GEOMETRY_PROFILE,"state":{"energy_mwh":2.5},"x":1.25,"z":-2.5}
 check(S.assess_device(d).operable,"omitted field retains new direct-call default")
 var cases:Array=[]
 for profile in ["flow_process_v2","flow_icon_v1","unknown",null,true]:
  var item=d.duplicate(true);item.geometry_profile=profile
  var before=var_to_bytes(item)
  var legal:bool=profile is String and str(profile)=="flow_process_v2"
  var assessed=S.assess_device(item)
  check(assessed.operable==legal,"explicit geometry must match new support")
  if not legal:check(assessed.issues[0].code=="incompatible_geometry_profile","specific marker error")
  check(var_to_bytes(item)==before,"no silent geometry migration")
  cases.append({"device":item,"result":assessed})
 var old=d.duplicate(true);old.erase("site_geometry_profile");old.geometry_profile="flow_icon_v1"
 var before=var_to_bytes(old)
 check(S.validate_for_model([old]).operable and not S.validate_for_model([old]).applied,"old marker-free world still runs")
 check(S.assess_device(old).supported and S.assess_device(old).needs_migration,"old icon retained until explicit migration")
 check(var_to_bytes(old)==before,"legacy positions stock and geometry unchanged")
 print("FLOW_MARKER_CASES ",JSON.stringify(cases,"",false,true))
 print("REFERENCE_GEOMETRY_MARKER checks=",checks," failures=",failures)
 quit(0 if failures==0 else 1)
