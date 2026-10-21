extends SceneTree
const C=preload("res://scripts/device_catalog.gd")
const M=preload("res://scripts/energy_model.gd")
const H2=preload("res://tests/test_material_physics.gd")
const CO2=preload("res://tests/test_co2_storage_physics.gd")
const Tower=preload("res://tests/test_tower_runtime.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("COLLECTOR_FAIL: "+label)
func near(a:float,b:float,label:String,tol:float=1e-6)->void:check(is_finite(a) and abs(a-b)<=tol,label+" "+str(a)+" != "+str(b))
func node(id:int,kind:String,p:Dictionary={})->Dictionary:return {"id":id,"kind":kind,"params":p,"state":C.initial_state(kind,p)}
func line(a:int,b:int)->Dictionary:return {"from":a,"to":b,"capacity_mw":500.0,"loss_fraction":0.0}
func fixture()->Dictionary:
	return {"devices":[node(1,"pv",{"dc_capacity_mw":144.0,"inverter_capacity_mw":120.0}),node(2,"pv",{"dc_capacity_mw":144.0,"inverter_capacity_mw":120.0}),node(3,C.COLLECTOR_KIND),node(4,"load",{"demand_mw":250.0})],"links":[line(1,3),line(2,3),line(3,4)]}
func audited(f:Dictionary,direct:Dictionary,dt:float=3600.0,w:Dictionary={})->Dictionary:
	var r:Dictionary=M.dispatch(f.devices,f.links,w,direct,dt)
	check(r.valid,"valid dispatch "+str(r.errors)+str(r.warnings))
	if r.valid:
		check(M.audit_dispatch(f.devices,f.links,r,{},w).is_empty(),"independent physical audit")
		near(r.balance_error_mw,0,"AC balance")
	return r
func _initialize()->void:
	check(C.legacy_implemented_kinds().size()==27 and C.phase2a_implemented_kinds().size()==31 and C.co2_stage_implemented_kinds().size()==32 and C.collector_stage_implemented_kinds().size()==33,"frozen version kind lists")
	check(C.is_electric_station("station") and C.is_electric_station(C.COLLECTOR_KIND) and not C.is_electric_station("electric_thermal_station"),"station role helper")
	check(C.dispatch_role(C.COLLECTOR_KIND)=="station" and C.model_profile(C.COLLECTOR_KIND)==C.COLLECTOR_PROFILE,"role not saved kind")
	check(C.ports(C.COLLECTOR_KIND)==C.ports("station"),"compatible AC in/out")
	near(C.defaults("station").capacity_mw,4,"legacy default unchanged")
	check(M.validate("station",{"capacity_mw":10000.0}).is_empty(),"legacy capacity contract unchanged")
	near(C.defaults(C.COLLECTOR_KIND).capacity_mw,200,"collector default")
	check(M.validate(C.COLLECTOR_KIND,{}).is_empty(),"valid collector defaults")
	for v in [0.0,-1.0,200.0001,INF,NAN]:check(not M.validate(C.COLLECTOR_KIND,{"capacity_mw":v}).is_empty(),"collector positive hard capacity")
	for v in [-.01,1.0,INF,NAN]:check(not M.validate(C.COLLECTOR_KIND,{"loss_fraction":v}).is_empty(),"collector loss bounds")
	check(not C.validate_state(C.COLLECTOR_KIND,{}, {"energy_mwh":1.0}).is_empty(),"no collector energy inventory")
	var f:Dictionary=fixture();var original:Dictionary=f.duplicate(true)
	var r:Dictionary=audited(f,{"1":{"mw":120.0},"2":{"mw":120.0}})
	check(f==original,"pure dispatch")
	near(r.devices["3"].input_mw,200,"shared station throughput")
	near(r.served_mw,198,"net load after station loss")
	near(r.loss_mw,2,"station loss once")
	near(r.curtailed_mw,40,"finite shared station headroom")
	check(r.devices["3"].kind==C.COLLECTOR_KIND and r.devices["3"].model_profile==C.COLLECTOR_PROFILE,"explicit facility identity")
	check(r.next_states.is_empty(),"collector no persistent state")
	for field in ["capacity_mw","loss_fraction","input_mw","received_mw","output_mw","sent_mw","loss_mw","model_profile","model_profile_version","energy_mwh"]:
		var bad:Dictionary=r.duplicate(true);bad.devices["3"][field]="wrong" if field=="model_profile" else float(bad.devices["3"].get(field,0.0))+1.0
		check(not M.audit_dispatch(f.devices,f.links,bad).is_empty(),"forged collector "+field)
	f.devices.append(node(5,"station"));f.devices.append(node(6,C.COLLECTOR_KIND))
	for edge in [line(3,5),line(5,3),line(3,6)]:check("不能直接级联" in C.validate_link(f.devices,[],edge),"explicit no station cascade")
	f=fixture();f.devices[2].kind="station"
	r=audited(f,{"1":{"mw":120.0},"2":{"mw":120.0}});near(r.served_mw,3.96,"same paths preserve legacy4MW")
	f=fixture();f.devices[2].model_profile="wrong"
	r=M.dispatch(f.devices,f.links,{}, {"1":{"mw":120.0}},1);check(not r.valid,"wrong runtime profile rejected")
	var h=H2.new();f=h.fixture();h.free();f.devices[1].kind=C.COLLECTOR_KIND;f.devices[1].params=C.defaults(C.COLLECTOR_KIND)
	r=audited(f,{"1":{"mw":1.0}})
	near(r.material.electrolyzer_electric_mw+r.material.compression_electric_mw,.99,"collector actual utility loss applied before transaction")
	check(r.material.hydrogen_produced_kg_s>0,"collector serves atomic H2 process")
	for d in f.devices:
		if r.next_states.has(str(d.id)):d.state=r.next_states[str(d.id)].duplicate(true)
	f.devices[6].params.demand_mw=1.0;r=audited(f,{"1":{"mw":0.0}})
	check(r.material.fuel_cell_output_mw>0 and r.served_mw>0,"fuel cell serves actual load through collector")
	near(r.served_mw,r.material.fuel_cell_output_mw*.99,"FC collector loss")
	var co2=CO2.new();f=co2.fixture();co2.free();f.devices[1].kind=C.COLLECTOR_KIND;f.devices[1].params=C.defaults(C.COLLECTOR_KIND)
	r=audited(f,{"1":{"mw":146.0/.99}},6.8*3600)
	near(r.next_states["3"].energy_mwh,794.24,"large CO2 charge through collector")
	f.devices[2].state=r.next_states["3"].duplicate(true);f.devices[3].params.demand_mw=99.0
	r=audited(f,{"1":{"mw":0.0}},6.14*3600)
	near(r.served_mw,99.0,"large CO2 discharge through collector")
	near(r.next_states["3"].energy_mwh,0,"CO2 finite stock used once")
	var tower=Tower.new();var ds:Array=tower.ds();var ls:Array=tower.ls();var w:Dictionary=tower.weather(false)
	for d in ds:
		if d.kind=="station":d.kind=C.COLLECTOR_KIND;d.params=C.defaults(C.COLLECTOR_KIND)
	r=audited({"devices":ds,"links":ls},{"1":{"mw":.01}},3600,w);check(r.rankine.gross_electric_mw>0,"collector tower/Rankine auxiliary provenance");tower.free()
	var snapshot:Dictionary=M.optimization_snapshot(f.devices,f.links,{}, {},1)
	check(snapshot.valid and snapshot.schema_version==10,"schema10 snapshot")
	check(snapshot.devices[1].kind==C.COLLECTOR_KIND and snapshot.devices[1].model_profile==C.COLLECTOR_PROFILE,"snapshot collector profile")
	var legacy:Dictionary=M.solve([node(1,"pv"),node(2,C.COLLECTOR_KIND)],[line(1,2),line(2,-1)],{}, {"1":{"mw":1.0}})
	check(legacy.errors.is_empty() and legacy.warnings.is_empty(),"legacy export solve understands station role")
	near(legacy.delivered_mw,.99,"legacy solve collector loss")
	var rng:=RandomNumberGenerator.new();rng.seed=902166
	for i in 80:
		f=fixture();f.devices[2].params={"capacity_mw":rng.randf_range(.01,200.0),"loss_fraction":rng.randf_range(0,.2)};f.devices[3].params.demand_mw=rng.randf_range(0,300)
		for edge in f.links:edge.capacity_mw=rng.randf_range(0,300);edge.loss_fraction=rng.randf_range(0,.1)
		r=audited(f,{"1":{"mw":rng.randf_range(0,120)},"2":{"mw":rng.randf_range(0,120)}})
		check(r.devices["3"].input_mw<=f.devices[2].params.capacity_mw+1e-7,"random shared station cap")
	print("COLLECTOR_SUBSTATION_PHYSICS: %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
