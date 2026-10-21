extends SceneTree
const C=preload("res://scripts/device_catalog.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;push_error(label)
func d(id:int,k:String)->Dictionary:return {"id":id,"kind":k,"params":C.defaults(k)}
func m(a:int,b:int,ap:String,bp:String,g:String)->Dictionary:return {"from":a,"to":b,"from_port":ap,"to_port":bp,"carrier":"water_steam","unit":"kg/s","grade_id":g,"mass_flow_capacity_kg_s":0.05,"loss_fraction":0.0}
func _initialize():
 for k in C.RANKINE_KINDS:
  check(C.validate_thermal(k,{}).is_empty(),k+" defaults")
  check(C.model_profile(k)=="rankine_stage1_v1",k+" fixed model")
  for key in C.defaults(k):
   for bad in [NAN,INF,"1",null,true]:
    check(not C.validate_thermal(k,{key:bad}).is_empty(),k+" invalid "+key)
  check(not C.validate_thermal(k,{"imaginary":1}).is_empty(),"unknown param")
  check(not C.validate_state(k,{}, {"energy_mwh":1}).is_empty(),"no fictitious inventory")
 var ds=[d(0,"steam_generator"),d(1,"steam_turbine"),d(2,"steam_condenser"),d(3,"feedwater_pump"),d(4,"parabolic_trough"),d(5,"station")]
 var ls=[m(0,1,"steam_out","steam_in","rankine_live_v1"),m(1,2,"exhaust_out","exhaust_in","rankine_exhaust_v1"),m(2,3,"condensate_out","condensate_in","rankine_condensate_v1"),m(3,0,"feed_out","feed_in","rankine_feedwater_v1")]
 check(C.validate_topology(ds,ls).is_empty(),"full closed mass loop legal")
 for line in ls:
  check(not C.validate_link(ds,ls,line).is_empty(),"duplicate massport rejected")
  for key in ["capacity_mw","capacity_mwth","voltage_level"]:
   var bad:Dictionary=line.duplicate();bad[key]=1
   check(not C.validate_link(ds,[],bad).is_empty(),"ambiguous massunits rejected")
  for key in ["unit","grade_id","carrier","from_port","to_port"]:
   var bad:Dictionary=line.duplicate();bad[key]="wrong"
   check(not C.validate_link(ds,[],bad).is_empty(),"mass metadata required")
  var bad:Dictionary=line.duplicate();bad.loss_fraction=.1
  check(not C.validate_link(ds,[],bad).is_empty(),"closed mass cannot leak")
 var oil={"from":4,"to":0,"from_port":"heat_out","to_port":"oil_in","carrier":"heat_oil","unit":"MWth","grade_id":"oil_300_200","capacity_mwth":.1,"loss_fraction":0.0}
 check(C.validate_link(ds,[],oil).is_empty(),"oil input legal")
 check(C.validate_link(ds,[],{"from":1,"to":5,"from_port":"ac_out","to_port":"in","carrier":"electricity_ac","unit":"MW","capacity_mw":.1,"loss_fraction":0.0}).is_empty(),"turbine AC export legal")
 for id in [0,2,3]:check(C.validate_link(ds,[],{"from":5,"to":id,"from_port":"out","to_port":"ac_in","carrier":"electricity_ac","unit":"MW","capacity_mw":.1,"loss_fraction":0.0}).is_empty(),"external ACaux legal")
 print("RANKINE_CATALOG checks=",checks," failures=",failures)
 quit(0 if failures==0 else 1)
