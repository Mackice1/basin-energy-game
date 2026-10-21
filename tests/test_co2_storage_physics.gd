extends SceneTree
const C=preload("res://scripts/device_catalog.gd")
const M=preload("res://scripts/energy_model.gd")
const TowerFixture=preload("res://tests/test_tower_runtime.gd")
const KIND="co2_liquid_cycle_store"
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("CO2_FAIL: "+label)
func near(a:float,b:float,label:String,tol:float=1e-6)->void:
	check(is_finite(a) and abs(a-b)<=tol,label+" "+str(a)+" != "+str(b))
func node(id:int,kind:String,p:Dictionary={})->Dictionary:
	return {"id":id,"kind":kind,"params":p,"state":C.initial_state(kind,p)}
func fixture()->Dictionary:
	return {"devices":[node(1,"pv",{"dc_capacity_mw":240.0,"inverter_capacity_mw":200.0}),node(2,"station",{"capacity_mw":500.0,"loss_fraction":0.0}),node(3,KIND),node(4,"load",{"demand_mw":0.0})],"links":[{"from":1,"to":2,"capacity_mw":500.0,"loss_fraction":0.0},{"from":2,"to":3,"capacity_mw":500.0,"loss_fraction":0.0},{"from":2,"to":4,"capacity_mw":500.0,"loss_fraction":0.0}]}
func run_case(f:Dictionary,power:float,dt:float)->Dictionary:
	var r:Dictionary=M.dispatch(f.devices,f.links,{}, {"1":{"mw":power}},dt)
	check(r.valid and r.commit_allowed,"valid "+str(r.errors)+str(r.warnings))
	if r.valid:
		check(M.audit_dispatch(f.devices,f.links,r).is_empty(),"independent runtime audit")
		near(r.balance_error_mw,0,"AC conservation")
		near(r.storage_balance_error_mwh,0,"finite SOC conservation")
	return r
func _initialize()->void:
	check(C.legacy_implemented_kinds().size()==27 and C.phase2a_implemented_kinds().size()==31 and C.co2_stage_implemented_kinds().size()==32,"versioned kind boundaries")
	check(C.is_electric_storage(KIND) and not C.is_material(KIND),"independent aggregate not material facility")
	check(M.validate(KIND,{}).is_empty(),"valid teaching defaults")
	var p:Dictionary=C.defaults(KIND)
	near(p.capacity_mwh,794.24,"internal equivalent capacity")
	near(p.charge_efficiency*p.discharge_efficiency,614.0/992.8,"teaching arithmetic ratio")
	check(C.ports(KIND).size()==1 and C.ports(KIND)[0].id=="ac" and C.ports(KIND)[0].direction=="bidirectional","only bidirectional AC")
	for pair in [["capacity_mwh",794.24001],["charge_mw",146.00001],["discharge_mw",100.00001]]:
		check(not M.validate(KIND,{pair[0]:pair[1]}).is_empty(),"single-facility bound "+pair[0])
	for value in [NAN,INF,-1.0]:
		for key in p:check(not M.validate(KIND,{key:value}).is_empty(),"finite bounded "+key)
	for field in ["co2_inventory_kg","external_heat_mwth","fuel_input_mw","hydrogen_mass_kg"]:
		check(not M.validate(KIND,{field:1.0}).is_empty(),"no extra resource "+field)
		check(not C.validate_state(KIND,{}, {"energy_mwh":0.0,field:1.0}).is_empty(),"no extra stock "+field)
	var f:Dictionary=fixture();var before:Dictionary=f.duplicate(true)
	var r:Dictionary=run_case(f,146.0,6.8*3600)
	check(f==before,"pure dispatch does not mutate input")
	near(r.charge_mw,146,"full charge terminal power")
	near(r.next_states["3"].energy_mwh,794.24,"full internal equivalent energy")
	near(r.charge_mw*r.dt_h,992.8,"input arithmetic not measured cycle")
	check(not r.has("material") and not r.devices["3"].has("hydrogen_mass_kg"),"no invented mass/LHV report")
	check(r.devices["3"].model_profile==C.CO2_STORAGE_PROFILE and r.devices["3"].working_inventory_calibrated==false,"closed uncalibrated CO2 metadata")
	var charge_loss:float=r.devices["3"].storage_conversion_loss_mw*r.dt_h
	f.devices[2].state=r.next_states["3"].duplicate(true);f.devices[3].params.demand_mw=100.0
	var out:Dictionary=run_case(f,0,6.14*3600)
	near(out.served_mw,100,"actual load served")
	near(out.served_mw*out.dt_h,614,"return arithmetic")
	near(out.next_states["3"].energy_mwh,0,"empty equivalent energy is not CO2 empty")
	near(charge_loss+out.devices["3"].storage_conversion_loss_mw*out.dt_h,992.8-614,"all conversion losses counted once")
	for field in ["model_profile","inventory_basis","working_fluid","working_inventory_calibrated","co2_inventory_kg","heat_output_mwth"]:
		var bad:Dictionary=out.duplicate(true);bad.devices["3"][field]=true if field=="working_inventory_calibrated" else 1.0 if field.ends_with("_kg") or field.ends_with("_mwth") else "forged"
		check(not M.audit_dispatch(f.devices,f.links,bad).is_empty(),"report forgery rejected "+field)
	f=fixture();r=run_case(f,0,3600);near(r.discharge_mw,0,"empty cannot produce power")
	f=fixture();f.devices[2].state.energy_mwh=794.24;r=run_case(f,146,3600);near(r.charge_mw,0,"full cannot consume charge")
	f.devices[2].params.self_discharge_per_h=.01;r=run_case(f,0,3600)
	near(r.next_states["3"].energy_mwh,794.24*exp(-.01),"standing equivalent energy loss")
	f=fixture();r=run_case(f,146,0);near(r.charge_mw,0,"paused no exchange")
	f=fixture();f.devices[2].state.energy_mwh=794.24;f.links.append({"from":2,"to":-1,"capacity_mw":500.0,"loss_fraction":0.0})
	r=run_case(f,0,3600);near(r.delivered_mw,0,"stored CO2 energy cannot export")
	f.devices.append(node(5,"battery",{"initial_soc":0.0}));f.links.append({"from":2,"to":5,"capacity_mw":500.0,"loss_fraction":0.0})
	r=run_case(f,0,3600);near(r.charge_mw,0,"no storage-to-storage transfer")
	var snapshot:Dictionary=M.optimization_snapshot(f.devices,f.links,{},{},1.0)
	check(snapshot.valid and snapshot.schema_version==9,"schema9 export")
	check(snapshot.initial_states.has("3") and snapshot.initial_states["3"].has("energy_mwh"),"snapshot E not kg")
	f=fixture();r=run_case(f,1e-8,3600)
	check(r.devices["3"].mode=="charge" and r.charge_mw>0,"positive tiny CO2 flow not rounded to idle")
	var wrong_mode:Dictionary=r.duplicate(true);wrong_mode.devices["3"].mode="idle"
	check(not M.audit_dispatch(f.devices,f.links,wrong_mode).is_empty(),"tiny CO2 mode forgery")
	var tower=TowerFixture.new();var ds:Array=tower.ds();var ls:Array=tower.ls()
	ds[0]=node(1,KIND,{"initial_soc":1.0});ls[0].from_port="ac"
	var w:Dictionary=tower.weather(false);r=M.dispatch(ds,ls,w,{},3600)
	check(r.valid,"CO2 auxiliary salt cycle valid "+str(r.errors)+str(r.warnings))
	check(r.rankine.gross_electric_mw>0,"CO2 supplies external tower auxiliaries")
	check(M.audit_dispatch(ds,ls,r,{},w).is_empty(),"CO2 mixed tower independent audit")
	tower.free()
	var rng:=RandomNumberGenerator.new();rng.seed=912344
	for i in 100:
		f=fixture();f.devices[2].state.energy_mwh=rng.randf_range(0,794.24);f.devices[2].params.self_discharge_per_h=rng.randf_range(0,.05);f.devices[3].params.demand_mw=rng.randf_range(0,150)
		f.devices[1].params.loss_fraction=rng.randf_range(0,.1)
		for link in f.links:link.capacity_mw=rng.randf_range(0,200);link.loss_fraction=rng.randf_range(0,.1)
		r=run_case(f,rng.randf_range(0,200),rng.randf_range(.01,100000))
		check(r.next_states["3"].energy_mwh>=0 and r.next_states["3"].energy_mwh<=794.24,"random finite bounded stock")
		check(not(r.devices["3"].charge_mw>1e-8 and r.devices["3"].discharge_mw>1e-8),"random exclusive mode")
	print("CO2_STORAGE_PHYSICS: %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
