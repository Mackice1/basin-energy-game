extends SceneTree
const C=preload("res://scripts/device_catalog.gd")
const V=preload("res://scripts/save_validator.gd")
const S=preload("res://scripts/solar_thermal.gd")
const H=preload("res://scripts/high_temp_thermal.gd")
const F=preload("res://scripts/fuel_supply.gd")
const P=preload("res://scripts/series_import.gd")
const Climate=preload("res://scripts/climate_model.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func device(id:int,kind:String)->Dictionary:
	return {"id":id,"kind":kind,"params":C.defaults(kind),"state":C.initial_state(kind)}
func edge(a:int,b:int,ap:String,bp:String,carrier:String,grade:String)->Dictionary:
	return {"from":a,"to":b,"from_port":ap,"to_port":bp,"carrier":carrier,"grade_id":grade,"unit":"MWth","capacity_mwth":1.0,"loss_fraction":0.0}
func blank()->Dictionary:
	var s:Dictionary={"schema":10,"model_version":19,"rebuild":true,"devices":[],"links":[],"imports":[],"templates":{},"next_id":0,"elapsed_s":0.0,"physical_lines":true,"energy":{},"thermal_energy":{},"solar_energy":S.initial_energy(),"high_temp_energy":H.initial_energy(),"fuel_energy":F.initial_energy(),"fuel_supply":F.defaults(),"stations":[],"next_station_id":1000000,"dimension_profile":"metric_v1"}
	for kind in V.HIGH_TEMP_KINDS:s.templates[kind]=C.defaults(kind)
	for key in V.CURRENT_ENERGY_KEYS:s.energy[key]=0.0
	for key in V.THERMAL_ENERGY_KEYS:s.thermal_energy[key]=0.0
	return s
func _initialize()->void:
	for kind in C.HIGH_TEMP_KINDS:
		check(C.implemented_kinds().count(kind)==1,"exactly one "+kind)
		check(C.is_high_temp(kind) and C.is_thermal(kind),"high-grade thermal kind")
		check(C.model_profile(kind)=="high_temp_stage1_v1","explicit high-temp profile")
		check(C.validate_thermal(kind,{}).is_empty(),"defaults validate "+kind)
		for key in C.defaults(kind):
			for bad in [NAN,INF,"1",true,null]:check(not C.validate_thermal(kind,{key:bad}).is_empty(),"reject invalid "+kind+"/"+key)
	check(C.temperature_grade(C.OIL_GRADE).medium=="Therminol66","separate medium")
	check(C.initial_state("high_temp_store").energy_mwhth==0,"empty usable high-temp state")
	check(C.validate_state("high_temp_store",{}, {"energy_mwhth":.2}).is_empty(),"full high store")
	check(not C.validate_state("high_temp_store",{}, {"energy_mwhth":.201}).is_empty(),"no invented inventory")
	var ds:Array=[device(0,"parabolic_trough"),device(1,"high_temp_store"),device(2,"oil_water_exchanger"),device(3,"heat_exchanger"),device(4,"thermal_store"),device(5,"heat_demand"),device(6,"station")]
	var links:Array=[edge(0,1,"heat_out","heat_in",C.OIL_CARRIER,C.OIL_GRADE),edge(0,2,"heat_out","hot_in",C.OIL_CARRIER,C.OIL_GRADE),edge(1,2,"heat_out","hot_in",C.OIL_CARRIER,C.OIL_GRADE),edge(2,3,"warm_out","hot_in",C.THERMAL_CARRIER,C.PRIMARY_GRADE),edge(3,5,"warm_out","heat_in",C.THERMAL_CARRIER,C.SECONDARY_GRADE)]
	check(C.validate_topology(ds,links).is_empty(),"two distinct media chain")
	for bad in [edge(0,3,"heat_out","hot_in",C.OIL_CARRIER,C.OIL_GRADE),edge(4,2,"heat_out","hot_in",C.THERMAL_CARRIER,C.PRIMARY_GRADE),edge(2,1,"warm_out","heat_in",C.THERMAL_CARRIER,C.PRIMARY_GRADE),edge(0,4,"heat_out","heat_in",C.OIL_CARRIER,C.OIL_GRADE)]:check(not C.validate_link(ds,[],bad).is_empty(),"reject cross medium/upgrade "+str(bad))
	for target in [0,2]:check(C.validate_link(ds,[],{"from":6,"to":target,"from_port":"out","to_port":"ac_in","carrier":"electricity_ac","unit":"MW","capacity_mw":1.0,"loss_fraction":0.0}).is_empty(),"explicit independent aux AC "+str(target))
	var state:=blank()
	check(V.validate(state).is_empty(),"schema10 accepts zero ledgers: "+V.validate(state))
	var bad:=state.duplicate(true);bad.erase("rankine_energy"); bad.templates.erase("steam_generator"); bad.templates.erase("steam_turbine"); bad.templates.erase("steam_condenser"); bad.templates.erase("feedwater_pump"); bad.erase("high_temp_energy");check(not V.validate(bad).is_empty(),"missing history refused")
	for key in state.high_temp_energy:
		bad=state.duplicate(true);bad.high_temp_energy[key]=-1;check(not V.validate(bad).is_empty(),"negative high-temp ledger "+key)
	bad=state.duplicate(true);bad.schema=9;bad.model_version=18;bad.erase("rankine_energy"); bad.templates.erase("steam_generator"); bad.templates.erase("steam_turbine"); bad.templates.erase("steam_condenser"); bad.templates.erase("feedwater_pump"); bad.erase("high_temp_energy")
	for kind in C.HIGH_TEMP_KINDS:bad.templates.erase(kind)
	check(V.validate(bad).is_empty(),"V18 zero scene still accepted")
	var mapping:Dictionary={"time_column":"t","value_column":"DNI","time_unit":"s","value_unit":"W/m2","field":"dni_wm2","target_device":""}
	var dni:=P.parse("t,DNI\n0,800\n60,0",mapping)
	check(dni.ok and P.validate_series(dni.series).is_empty(),"explicit globalDNI saved/reparsed")
	mapping.target_device="0";check(not P.parse("t,DNI\n0,800\n60,0",mapping).ok,"DNI cannot bind device")
	mapping.target_device=""
	for name in ["POA","GHI","DHI","global_horizontal","水平总辐照"]:
		mapping.value_column=name;check(not P.parse("t,"+name+"\n0,800\n60,0",mapping).ok,"non-DNI cannot masquerade "+name)
	var w:Dictionary={"solar_altitude_deg":60.0,"is_day":true,"cloud_cover":.2,"irradiance_wm2":0.0}
	var reference:=Climate.teaching_dni(w);w.irradiance_wm2=2000
	check(Climate.teaching_dni(w)==reference,"teaching DNI independent of POA")
	w.is_day=false;check(Climate.teaching_dni(w)==0,"teaching night DNI zero")
	print("HIGH_TEMP_CATALOG: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
