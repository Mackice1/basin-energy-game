extends SceneTree
const C=preload("res://scripts/device_catalog.gd")
const V=preload("res://scripts/save_validator.gd")
const R=preload("res://scripts/rankine_cycle.gd")
const Old=preload("res://tests/test_high_temp_catalog.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize():
 var old=Old.new();var s:Dictionary=old.blank();old.free()
 check(V.validate(s).is_empty(),"old V19 schema10 stillvalid")
 s.schema=11;s.model_version=20;s.rankine_energy=R.initial_energy()
 for k in C.RANKINE_KINDS:s.templates[k]=C.defaults(k)
 check(V.validate(s).is_empty(),"empty schema11 valid "+V.validate(s))
 s.stations=[{"id":1000000,"name":"塔式教学预览 · 未投运","x":0.0,"z":0.0,"kind":"tower_station_preview"}];s.next_station_id=1000001
 check(V.validate(s).is_empty(),"metric tower preview valid "+V.validate(s))
 var bad:Dictionary=s.duplicate(true);bad.stations[0].x=90.0
 check(not V.validate(bad).is_empty(),"full160m facade cannot cross mapboundary")
 bad=s.duplicate(true);bad.dimension_profile="legacy_illustrative"
 check(not V.validate(bad).is_empty(),"tower cannot shrink into legacy scale")
 bad=s.duplicate(true);bad.stations[0].kind="tower_operating"
 check(not V.validate(bad).is_empty(),"unknown commissioned tower rejected")
 bad=s.duplicate(true);bad.stations[0].capacity_mw=100
 check(not V.validate(bad).is_empty(),"preview cannot store fake nameplate")
 bad=s.duplicate(true);bad.stations.append({"id":1000001,"name":"other","x":14.0,"z":0.0});bad.next_station_id=1000002
 check(not V.validate(bad).is_empty(),"real preview land prevents overlapping oldsite")
 bad=s.duplicate(true);bad.devices=[{"id":0,"kind":"steam_generator","params":C.defaults("steam_generator"),"state":{},"model_profile":"rankine_stage1_v1","model_profile_version":1,"x":0.0,"z":0.0,"parent_station_id":1000000,"interior_x":0.0,"interior_z":0.0}];bad.next_id=1
 check(not V.validate(bad).is_empty(),"uncommissioned preview forbids operating internals")
 bad=s.duplicate(true);bad.links=[{"from":1000000,"to":-1,"capacity_mw":100,"loss_fraction":0}]
 check(not V.validate(bad).is_empty(),"facility has no energy network node")
 bad=s.duplicate(true);bad.rankine_energy.gross_electric_mwh=1
 check(not V.validate(bad).is_empty(),"unbacked electricity history rejected")
 for field in ["circulated_mass_kg","steam_heat_mwhth","pump_hydraulic_mwh"]:
  bad=s.duplicate(true);bad.rankine_energy[field]=1
  check(not V.validate(bad).is_empty(),"fixed enthalpy history binds "+field)
 check(V.validate(JSON.parse_string(JSON.stringify(s))).is_empty(),"preview andledger JSONroundtrip")
 print("RANKINE_SAVE_PREVIEW checks=",checks," failures=",failures)
 quit(0 if failures==0 else 1)
