extends SceneTree
const M=preload("res://scripts/energy_model.gd")
const C=M.Catalog
const MC=C.Materials
const D=M.Dispatch.Materials
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("PHASE_H2_FAIL: "+label)
func near(a:float,b:float,label:String,tol:float=1e-7)->void:check(is_finite(a) and absf(a-b)<=tol,label+" "+str(a)+" != "+str(b))
func node(id:int,kind:String,p:Dictionary={})->Dictionary:return {"id":id,"kind":kind,"params":p,"state":C.initial_state(kind,p)}
func edge(ds:Array,a:int,b:int,ap:String,bp:String)->Dictionary:
	var port:Dictionary={}
	for n in ds:
		if n.id==a:port=C.port(n.kind,ap)
	var l:Dictionary={"from":a,"to":b,"from_port":ap,"to_port":bp,"loss_fraction":0.0}
	for k in ["carrier","unit","species_id","phase_id","grade_id"]:
		if port.has(k):l[k]=port[k]
	l["capacity_mw" if port.unit=="MW" else "mass_flow_capacity_kg_s"]=10.0
	return l
func fixture(kind:String)->Dictionary:
	var ds:Array=[node(1,"pv"),node(2,"station",{"capacity_mw":10.0,"loss_fraction":0.0}),node(3,"water_supply_boundary"),node(4,"electrolyzer_station"),node(5,kind),node(6,"fuel_cell_station"),node(7,"load",{"demand_mw":0.0}),node(8,"battery",{"capacity_mwh":1.0,"initial_soc":0.0,"charge_mw":0.0,"discharge_mw":1.0,"charge_efficiency":1.0,"discharge_efficiency":1.0,"self_discharge_per_h":0.0})]
	var ls:Array=[]
	for x in [[1,2,"out","in"],[2,4,"out","ac_in"],[2,5,"out","ac_in"],[6,2,"ac_out","in"],[2,7,"out","in"],[8,2,"ac","in"],[3,4,"water_out","water_in"],[4,5,"h2_out","h2_in"],[5,6,"h2_out","h2_in"]]:ls.append(edge(ds,x[0],x[1],x[2],x[3]))
	return {"devices":ds,"links":ls}
func run(f:Dictionary,power:float,dt:float)->Dictionary:
	var before:Dictionary=f.duplicate(true)
	var r:Dictionary=M.dispatch(f.devices,f.links,{}, {"1":{"mw":power}},dt)
	check(f==before,"pure dispatch")
	check(r.valid,"valid "+str(r.errors)+str(r.warnings))
	if not r.valid:return r
	var errors:Array=M.audit_dispatch(f.devices,f.links,r)
	check(errors.is_empty(),"independent audit "+str(errors))
	near(r.balance_error_mw,0,"AC balance",1e-6)
	for k in ["mass_balance_error_kg","hydrogen_element_error_kg","oxygen_element_error_kg","enthalpy_balance_error_mw"]:near(r.material[k],0,k,1e-6)
	return r
func advance(f:Dictionary,r:Dictionary)->void:
	for d in f.devices:
		if r.next_states.has(str(d.id)):d.state=r.next_states[str(d.id)].duplicate(true)
func _initialize()->void:
	for kind in MC.PHASE_KINDS:
		check(M.validate(kind,{}).is_empty(),"valid catalog "+kind)
		check(not M.validate(kind,{"initial_inventory_kg":1.0}).is_empty(),"new build cannot preload "+kind)
		near(C.inventory_capacity(kind),1000.0 if kind=="hydrogen_liquid_store" else 120.0,"derived capacity")
		var p:Dictionary=C.defaults(kind)
		for key in p:
			var bad:Dictionary=p.duplicate();bad[key]=NAN
			check(not M.validate(kind,bad).is_empty(),"nonfinite "+key)
		var f:Dictionary=fixture(kind)
		var pc:Dictionary=MC.phase_coefficients(kind)
		var ledger:Dictionary=D.initial_energy(f.devices)
		var r:Dictionary=run(f,(50.0+pc.charge_kwh_per_kg)/1000.0,3600.0)
		if not r.valid:continue
		near(r.next_states["5"].material_inventory_kg.H2,1.0,"one kg charge")
		near(r.devices["5"].electric_input_mw,pc.charge_kwh_per_kg/1000.0,"charge AC")
		near(r.devices["5"].heat_rejected_mwth,(pc.charge_kwh_per_kg-pc.enthalpy_kwh_per_kg)/1000.0,"charge reject")
		near(r.devices["5"].phase_enthalpy_mwh,pc.enthalpy_kwh_per_kg/1000.0,"signed phase enthalpy")
		ledger=D.accumulate_energy(ledger,r,3600)
		check(not ledger.is_empty(),"charge ledger "+kind)
		advance(f,r)
		f.devices[7].state.energy_mwh=.1
		# Actual finite battery supplies phase auxiliaries while FC supplies load.
		f.devices[6].params.demand_mw=1.0
		var out:Dictionary=run(f,0.0,3600.0)
		check(out.devices["5"].hydrogen_out_kg_s>0.0,"battery-enabled night discharge")
		near(out.devices["5"].electric_input_mw,out.devices["5"].hydrogen_out_kg_s*3.6*pc.discharge_kwh_per_kg,"actual desorption/vaporizer AC")
		near(out.next_states["5"].material_inventory_kg.H2,0.0,"stock exhausted")
		ledger=D.accumulate_energy(ledger,out,3600)
		check(not ledger.is_empty(),"full phase cycle ledger")
		var after:Dictionary=f.duplicate(true);advance(after,out)
		check(D.validate_energy(ledger,after.devices).is_empty(),"world-matched phase cycle ledger")
		for field in D.PHASE_DETAIL_FIELDS:
			var forged:Dictionary=out.duplicate(true);forged.devices["5"][field]+=1
			check(not M.audit_dispatch(f.devices,f.links,forged).is_empty(),"reject phase field "+field)
		for field in D.PHASE_FIELDS:
			var forged:Dictionary=out.duplicate(true);forged.material[field]+=1
			check(not M.audit_dispatch(f.devices,f.links,forged).is_empty(),"reject aggregate "+field)
		for scenario in ["empty","no_water","power","aux_cable","full","cooling","ambient","zero","host"]:
			f=fixture(kind)
			var power:float=1.0;var dt:float=3600.0
			if scenario=="no_water":f.devices[2].state.material_inventory_kg.H2O=0.0
			if scenario=="power":power=0.0
			if scenario=="full":f.devices[4].state.material_inventory_kg.H2=C.inventory_capacity(kind)
			if scenario=="cooling":f.devices[4].params.heat_rejection_mwth=0.0
			if scenario in ["empty","aux_cable","ambient"]:
				power=0.0;f.devices[6].params.demand_mw=1.0
				if scenario!="empty":f.devices[4].state.material_inventory_kg.H2=1.0
			if scenario=="aux_cable":f.links[2].capacity_mw=0.0
			if scenario=="ambient" and kind=="hydrogen_liquid_store":f.devices[4].params.ambient_vaporizer_mwth=0.0
			if scenario=="zero":dt=0.0
			if scenario=="host" and kind=="hydrogen_metal_hydride_store":
				f.devices[4].state.host_dry_mass_kg-=1.0
				check(not M.dispatch(f.devices,f.links,{}, {},1.0).valid,"host immutable");continue
			r=run(f,power,dt)
			if not r.valid:continue
			if scenario in ["empty","aux_cable","ambient"]:near(r.material.hydrogen_consumed_kg_s,0,"blocked discharge "+scenario)
			if scenario in ["no_water","power","cooling","zero"]:near(r.material.hydrogen_produced_kg_s,0,"blocked production "+scenario)
		# Passive LH2 loss persists disconnected; signed phase inventory does not become electricity.
		f=fixture(kind);f.devices[4].state.material_inventory_kg.H2=100.0
		r=run(f,0.0,86400)
		near(r.material.hydrogen_leaked_kg,.1 if kind=="hydrogen_liquid_store" else 0.0,"teaching daily passive loss",1e-8)
		near(r.material.phase_store_electric_mw,0,"idle no fictional standby")
		near(r.material.environment_heat_in_mwth,.1*1.24/24000.0 if kind=="hydrogen_liquid_store" else 0,"boiloff finalgas warming")
	randomized_cases()
	print("PHASE_HYDROGEN_PHYSICS: %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)

func randomized_cases()->void:
	var rng:=RandomNumberGenerator.new();rng.seed=202610212
	for i in 240:
		var kind:String=MC.PHASE_KINDS[i%2]
		var f:Dictionary=fixture(kind)
		f.devices[2].state.material_inventory_kg.H2O=rng.randf_range(0.0,10000.0)
		f.devices[4].state.material_inventory_kg.H2=rng.randf_range(0.0,C.inventory_capacity(kind))
		f.devices[6].params.demand_mw=rng.randf_range(0.0,1.0)
		f.devices[7].state.energy_mwh=rng.randf_range(0.0,1.0)
		f.devices[1].params.capacity_mw=rng.randf_range(0.02,4.0)
		f.devices[1].params.loss_fraction=rng.randf_range(0.0,.1)
		for line in f.links:
			if line.carrier=="electricity_ac":line.capacity_mw=rng.randf_range(.001,1.0);line.loss_fraction=rng.randf_range(0.0,.1)
		var ledger:Dictionary=D.initial_energy(f.devices)
		var dt:float=pow(10.0,rng.randf_range(-1.0,5.0))
		var r:Dictionary=run(f,rng.randf_range(0.0,1.0),dt)
		if not r.valid:continue
		var out:Dictionary=D.accumulate_energy(ledger,r,dt)
		check(not out.is_empty(),"random reference ledger "+str(i))
		var original:Dictionary=f.duplicate(true)
		advance(f,r)
		check(D.validate_energy(out,f.devices).is_empty(),"random actual inventory audit "+str(i))
		check(r.devices["5"].hydrogen_in_kg_s<=1e-10 or r.devices["5"].hydrogen_out_kg_s<=1e-10,"random exclusive mode")
		for field in ["energy_mwh","soc","useful_heat_output_mwth"]:
			var forged:Dictionary=r.duplicate(true);forged.devices["5"][field]=1.0

			check(not M.audit_dispatch(original.devices,original.links,forged).is_empty(),"no additional phase SOC "+field)
