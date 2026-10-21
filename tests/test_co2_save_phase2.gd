extends SceneTree
const V=preload("res://scripts/save_validator.gd")
const C=preload("res://scripts/device_catalog.gd")
const Old=preload("res://tests/test_material_save_phase2.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures.append(message);push_error(message)
func blank()->Dictionary:
	var old=Old.new();var s:Dictionary=old.blank();old.free()
	s.schema=15;s.model_version=24;s.templates.co2_liquid_cycle_store=C.defaults("co2_liquid_cycle_store")
	return s
func _initialize():
	var s:=blank()
	check(V.validate(s).is_empty(),"schema15 blank valid: "+V.validate(s))
	check(V.validate(JSON.parse_string(JSON.stringify(s))).is_empty(),"schema15 roundtrip")
	var prior:=s.duplicate(true);prior.schema=14;prior.model_version=23
	check(not V.validate(prior).is_empty(),"schema14 cannot silently accept new CO2 template")
	prior.templates.erase("co2_liquid_cycle_store")
	check(V.validate(prior).is_empty(),"frozen schema14 31-kind contract retained")
	for value in [-1,794.241,100000,NAN,INF,"794.24",true]:
		var bad:=s.duplicate(true);bad.templates.co2_liquid_cycle_store.capacity_mwh=value
		check(not V.validate(bad).is_empty(),"invalid single-station capacity rejected")
	print("CO2_SAVE_PHASE2 checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
