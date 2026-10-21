extends SceneTree
const M=preload("res://scripts/energy_model.gd")
const C=M.Catalog
const MC=C.Materials
const D=M.Dispatch.Materials
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("CHEMICAL_FAIL: "+label)
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
func fixture(kind:String,store:String="hydrogen_gas_store")->Dictionary:
	var cc:Dictionary=MC.chemical_coefficients(kind)
	var ds:Array=[node(1,"pv"),node(2,"station",{"capacity_mw":10.0,"loss_fraction":0.0}),node(3,store,{"leak_per_h":0.0} if store=="hydrogen_gas_store" else {}),node(4,cc.feed_kind),node(5,kind),node(6,"load",{"demand_mw":0.0})]
	ds[2].state.material_inventory_kg.H2=10.0
	var ls:Array=[]
	for x in [[1,2,"out","in"],[2,3,"out","ac_in"],[2,5,"out","ac_in"],[2,6,"out","in"],[3,5,"h2_out","h2_in"],[4,5,"n2_out" if cc.feed=="N2" else "co2_out","n2_in" if cc.feed=="N2" else "co2_in"]]:ls.append(edge(ds,x[0],x[1],x[2],x[3]))
	return {"devices":ds,"links":ls}
func run(f:Dictionary,power:float,dt:float)->Dictionary:
	var before:Dictionary=f.duplicate(true)
	var report:Dictionary=M.dispatch(f.devices,f.links,{}, {"1":{"mw":power}},dt)
	check(before==f,"pure transaction")
	check(report.valid,"valid "+str(report.errors)+str(report.warnings))
	if not report.valid:return report
	var errors:Array=M.audit_dispatch(f.devices,f.links,report)
	check(errors.is_empty(),"independent audit "+str(errors))
	near(report.balance_error_mw,0,"actual AC balance",1e-6)
	for k in ["mass_balance_error_kg","hydrogen_element_error_kg","carbon_element_error_kg","nitrogen_element_error_kg","oxygen_element_error_kg","enthalpy_balance_error_mw"]:near(report.material[k],0,k,1e-6)
	return report
func advance(f:Dictionary,r:Dictionary)->void:
	for d in f.devices:
		if r.next_states.has(str(d.id)):d.state=r.next_states[str(d.id)].duplicate(true)
func _initialize()->void:
	check(C.phase2b_implemented_kinds().size()==35 and C.implemented_kinds().size()==39,"frozen35 and current39")
	for kind in MC.CHEMICAL_KINDS:
		check(M.validate(kind,{}).is_empty(),"valid defaults "+kind)
		check(C.model_profile(kind)==MC.CHEMICAL_PROFILE_ID and C.model_profile_version(kind)==3,"explicit profile3")
		for k in C.defaults(kind):
			for bad in [-1.0,NAN,INF]:check(not M.validate(kind,{k:bad}).is_empty(),"reject parameter "+k)
	for kind in MC.SYNTHESIS_KINDS:
		var cc:Dictionary=MC.chemical_coefficients(kind)
		near(cc.hydrogen_per_product+cc.feed_per_product,1.0+cc.water_per_product,"molecular mass closes")
		check(cc.reaction_enthalpy_kwh_per_kg<0,"exothermic not power")
		check(not M.validate(kind,{"initial_inventory_kg":1.0}).is_empty(),"products start empty")
		for store in MC.HYDROGEN_STORE_KINDS:
			var f:Dictionary=fixture(kind,store)
			var ledger:Dictionary=D.initial_energy(f.devices)
			var phase_aux:float=MC.phase_coefficients(store).discharge_kwh_per_kg*cc.hydrogen_per_product if store in MC.PHASE_KINDS else 0.0
			var r:Dictionary=run(f,(cc.electric_kwh_per_kg+phase_aux)/1000.0,3600.0)
			if not r.valid:continue
			near(r.next_states["5"].material_inventory_kg[cc.product],1.0,"analytic1kg "+kind+store)
			near(r.devices["5"].electric_input_mw,cc.electric_kwh_per_kg/1000.0,"actual process AC")
			near(r.devices["5"].heat_rejected_mwth,cc.heat_rejected_kwh_per_kg/1000.0,"actual reject includes reaction")
			near(r.material.chemical_hydrogen_consumed_kg_s*3600,cc.hydrogen_per_product,"H2 stoichiometry")
			near(r.material.chemical_water_released_kg_s*3600,cc.water_per_product,"liquid water release")
			ledger=D.accumulate_energy(ledger,r,3600)
			check(not ledger.is_empty(),"reference ledger accepts analytic chemistry")
			var after:Dictionary=f.duplicate(true);advance(after,r)
			check(D.validate_energy(ledger,after.devices).is_empty(),"actual world ledger matches")
			for key in D.CHEMICAL_FIELDS:
				var bad:Dictionary=r.duplicate(true);bad.material[key]+=1.0
				check(not M.audit_dispatch(f.devices,f.links,bad).is_empty(),"reject aggregate "+key)
			for key in D.CHEMICAL_DETAIL_FIELDS:
				var bad:Dictionary=r.duplicate(true);bad.devices["5"][key]+=1.0
				check(not M.audit_dispatch(f.devices,f.links,bad).is_empty(),"reject detail "+key)
		for scenario in ["feed","hydrogen","power","heater","cooler","full","h2_pipe","feed_pipe","zero"]:
			var f:Dictionary=fixture(kind)
			var power:float=.2;var dt:float=3600.0
			if scenario=="feed":f.devices[3].state.material_inventory_kg[cc.feed]=0.0
			if scenario=="hydrogen":f.devices[2].state.material_inventory_kg.H2=0.0
			if scenario=="power":power=0.0
			if scenario=="heater":f.devices[4].params.heater_electric_mw=0.0
			if scenario=="cooler":f.devices[4].params.heat_rejection_mwth=0.0
			if scenario=="full":f.devices[4].state.material_inventory_kg[cc.product]=C.inventory_capacity(kind)
			if scenario=="h2_pipe":f.links[4].mass_flow_capacity_kg_s=0.0
			if scenario=="feed_pipe":f.links[5].mass_flow_capacity_kg_s=0.0
			if scenario=="zero":dt=0.0
			var r:Dictionary=run(f,power,dt)
			if r.valid:
				near(r.devices["5"].product_produced_kg_s,0,"atomic blocked "+scenario)
				near(r.material.chemical_electric_mw,0,"no half AC "+scenario)
	randomized_shared_cases()
	print("CHEMICAL_PROCESS_PHYSICS: %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)

func randomized_shared_cases()->void:
	var rng:=RandomNumberGenerator.new();rng.seed=202610213
	for i in 150:
		var kind:String=MC.SYNTHESIS_KINDS[i%2]
		var store:String=MC.HYDROGEN_STORE_KINDS[i%3]
		var cc:Dictionary=MC.chemical_coefficients(kind)
		var f:Dictionary=fixture(kind,store)
		f.devices[2].state.material_inventory_kg.H2=rng.randf_range(0,C.inventory_capacity(store))
		f.devices[3].state.material_inventory_kg[cc.feed]=rng.randf_range(0,1000)
		f.devices[4].state.material_inventory_kg[cc.product]=rng.randf_range(0,C.inventory_capacity(kind))
		f.devices[5].params.demand_mw=rng.randf_range(0,.2)
		f.devices.append(node(7,"fuel_cell_station"))
		f.links.append(edge(f.devices,3,7,"h2_out","h2_in"))
		f.links.append(edge(f.devices,7,2,"ac_out","in"))
		f.devices[1].params.loss_fraction=rng.randf_range(0,.1)
		f.devices[1].params.capacity_mw=rng.randf_range(.01,.6)
		for line in f.links:
			if line.carrier=="electricity_ac":line.capacity_mw=rng.randf_range(.001,.3);line.loss_fraction=rng.randf_range(0,.1)
		var ledger:Dictionary=D.initial_energy(f.devices)
		var dt:float=pow(10.0,rng.randf_range(-1,4.5))
		var report:Dictionary=run(f,rng.randf_range(0,.3),dt)
		if not report.valid:continue
		ledger=D.accumulate_energy(ledger,report,dt)
		check(not ledger.is_empty(),"shared FC/product reference ledger "+str(i))
		near(report.material.hydrogen_discharged_kg_s,report.material.hydrogen_consumed_kg_s+report.material.chemical_hydrogen_consumed_kg_s,"one H2 budget FC+product")
		advance(f,report)
		check(D.validate_energy(ledger,f.devices).is_empty(),"post-shared world state "+str(i))
