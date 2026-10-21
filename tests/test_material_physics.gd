extends SceneTree
const Model = preload("res://scripts/energy_model.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
const Materials = preload("res://scripts/material_dispatch.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("MATERIAL_FAIL: "+label)
func near(a: float,b: float,label: String,tol: float=1e-7) -> void:
	check(is_finite(a) and absf(a-b)<=tol,label+" %s != %s" % [a,b])
func node(id: int,kind: String,p: Dictionary={}) -> Dictionary:
	return {"id":id,"kind":kind,"params":p,"state":Catalog.initial_state(kind,p)}
func fixture() -> Dictionary:
	var ds: Array = [node(1,"pv"),node(2,"station",{"capacity_mw":10.0,"loss_fraction":0.0}),node(3,"water_supply_boundary"),node(4,"electrolyzer_station"),node(5,"hydrogen_gas_store",{"leak_per_h":0.0}),node(6,"fuel_cell_station"),node(7,"load",{"demand_mw":0.0})]
	var ls: Array = [{"from":1,"to":2,"capacity_mw":10.0,"loss_fraction":0.0},{"from":2,"to":4,"from_port":"out","to_port":"ac_in","carrier":"electricity_ac","unit":"MW","capacity_mw":10.0,"loss_fraction":0.0},{"from":2,"to":5,"from_port":"out","to_port":"ac_in","carrier":"electricity_ac","unit":"MW","capacity_mw":10.0,"loss_fraction":0.0},{"from":6,"to":2,"from_port":"ac_out","to_port":"in","carrier":"electricity_ac","unit":"MW","capacity_mw":10.0,"loss_fraction":0.0},{"from":2,"to":7,"capacity_mw":10.0,"loss_fraction":0.0}]
	for spec in [[3,4,"water_out","water_in"],[4,5,"h2_out","h2_in"],[5,6,"h2_out","h2_in"]]:
		var port: Dictionary=Catalog.port(ds[spec[0]-1].kind,spec[2])
		var l: Dictionary={"from":spec[0],"to":spec[1],"from_port":spec[2],"to_port":spec[3],"mass_flow_capacity_kg_s":1.0,"loss_fraction":0.0}
		for k in ["carrier","unit","species_id","phase_id","grade_id"]:l[k]=port[k]
		ls.append(l)
	return {"devices":ds,"links":ls}
func run_case(f: Dictionary,power: float=1.0,dt: float=3600.0) -> Dictionary:
	var r: Dictionary=Model.dispatch(f.devices,f.links,{}, {"1":{"mw":power}},dt)
	check(r.valid,"valid "+str(r.errors)+str(r.warnings))
	if r.valid:
		for k in ["mass_balance_error_kg","hydrogen_element_error_kg","oxygen_element_error_kg","enthalpy_balance_error_mw"]:near(r.material[k],0,k,1e-6)
		near(r.balance_error_mw,0,"AC residual")
		check(Model.audit_dispatch(f.devices,f.links,r).is_empty(),"independent original audit "+str(Model.audit_dispatch(f.devices,f.links,r)))
	return r
func _initialize() -> void:
	var f: Dictionary=fixture()
	var before: Dictionary=f.duplicate(true)
	var r: Dictionary=run_case(f)
	check(f==before,"dispatch pure")
	var c: Dictionary=Catalog.Materials.coefficients()
	near(r.material.hydrogen_produced_kg_s,1.0/(3.6*53.0),"combined actual AC bottleneck")
	near(r.next_states["5"].material_inventory_kg.H2,3600.0/(3.6*53.0),"kg not MWh")
	near(r.material.electrolyzer_electric_mw+r.material.compression_electric_mw,1.0,"joint electric consumption")
	near(r.material.water_withdrawn_kg_s,r.material.hydrogen_produced_kg_s*c.water_per_h2,"water stoichiometry")
	var ledger: Dictionary=Materials.accumulate_energy(Materials.initial_energy_v1(),r,3600)
	check(not ledger.is_empty() and Materials.validate_energy(ledger).is_empty(),"cumulative dimensioned ledger")
	for d in f.devices:
		if r.next_states.has(str(d.id)):d.state=r.next_states[str(d.id)].duplicate(true)
	f.devices[6].params.demand_mw=1.0
	var out: Dictionary=run_case(f,0.0)
	near(out.material.hydrogen_consumed_kg_s,1.0/(3.6*53.0),"finite gas depletion")
	near(out.material.fuel_cell_output_mw,out.material.hydrogen_consumed_kg_s*3.6*c.lhv_kwh_per_kg*0.5,"FC net LHV conversion")
	near(out.next_states["5"].material_inventory_kg.H2,0.0,"empty after discharge")
	near(out.available_mw,0.0,"FC not renewable availability")
	near(out.material.water_released_kg_s,out.material.hydrogen_consumed_kg_s*c.water_per_h2,"FC water boundary")
	ledger=Materials.accumulate_energy(ledger,out,3600)
	check(not ledger.is_empty(),"cycle cumulative enthalpy")
	for scenario in ["water","power","full","compressor","pipe","demand","zero"]:
		f=fixture()
		var power: float=1.0
		var dt: float=3600.0
		if scenario=="water":f.devices[2].state.material_inventory_kg.H2O=0.0
		if scenario=="power":power=0.0
		if scenario=="full":f.devices[4].state.material_inventory_kg.H2=1000.0
		if scenario=="compressor":f.links[2].capacity_mw=0.0
		if scenario=="pipe":f.links.remove_at(6)
		if scenario=="demand":f.devices[6].params.demand_mw=1.0
		if scenario=="zero":dt=0.0
		r=run_case(f,power,dt)
		near(r.material.hydrogen_produced_kg_s,0.0,"stops "+scenario)
		near(r.material.electrolyzer_electric_mw+r.material.compression_electric_mw,0.0,"no half transaction "+scenario)
	f=fixture();r=run_case(f)
	for field in Materials.FIELDS:
		var bad: Dictionary=r.duplicate(true);bad.material[field]+=1.0
		check(not Model.audit_dispatch(f.devices,f.links,bad).is_empty(),"tamper aggregate "+field)
	for field in ["species_id","phase_id","grade_id","unit"]:
		var bad: Dictionary=r.duplicate(true);bad.lines[5][field]="wrong"
		check(not Model.audit_dispatch(f.devices,f.links,bad).is_empty(),"tamper edge "+field)
	var bad: Dictionary=r.duplicate(true);bad.next_states.erase("3")
	check(not Model.audit_dispatch(f.devices,f.links,bad).is_empty(),"missing finite resource state rejected")
	f=fixture();f.devices[4].params.leak_per_h=0.1;f.devices[4].state.material_inventory_kg.H2=100.0
	r=run_case(f,0.0)
	near(r.material.hydrogen_leaked_kg,100.0*(1.0-exp(-0.1)),"leak actual kg")
	near(r.material.hydrogen_consumed_kg_s,0.0,"zero demand no FC hydrogen consumption")
	shared_and_random_tests()
	print("MATERIAL_PHYSICS: %d checks, %d failures" %[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)

func typed_line(ds: Array,a: int,b: int,ap: String,bp: String) -> Dictionary:
	var kind: String = ""
	for d in ds:
		if int(d.id)==a: kind=d.kind
	var port: Dictionary=Catalog.port(kind,ap)
	var l: Dictionary={"from":a,"to":b,"from_port":ap,"to_port":bp,"loss_fraction":0.0}
	for k in ["carrier","unit","grade_id","species_id","phase_id"]:
		if port.has(k):l[k]=port[k]
	l["capacity_mw" if port.unit=="MW" else "capacity_mwth" if port.unit=="MWth" else "mass_flow_capacity_kg_s"]=10.0
	return l

func shared_and_random_tests() -> void:
	var f: Dictionary=fixture()
	f.devices.append(node(8,"electrolyzer_station"));f.devices.append(node(9,"hydrogen_gas_store",{"leak_per_h":0.0}))
	for spec in [[2,8,"out","ac_in"],[2,9,"out","ac_in"],[3,8,"water_out","water_in"],[8,9,"h2_out","h2_in"]]:f.links.append(typed_line(f.devices,spec[0],spec[1],spec[2],spec[3]))
	f.devices[2].state.material_inventory_kg.H2O=30.0
	var r: Dictionary=run_case(f)
	near(r.material.water_withdrawn_kg_s*3600.0,30.0,"shared source stock deducted once")
	near(r.next_states["3"].material_inventory_kg.H2O,0.0,"shared source exhausted")
	f.devices[2].state.material_inventory_kg.H2O=10000.0;f.devices[2].params.max_outflow_kg_s=0.001
	r=run_case(f)
	near(r.material.water_withdrawn_kg_s,0.001,"shared source aggregate port cap")
	f=fixture();f.devices[1].params.capacity_mw=0.2
	r=run_case(f)
	near(r.material.hydrogen_produced_kg_s,0.2/(3.6*53.0),"shared station sums electro+compression")
	f=fixture();f.links[0].capacity_mw=0.1
	r=run_case(f)
	near(r.material.hydrogen_produced_kg_s,0.1/(3.6*53.0),"shared incoming cable sums both uses")
	f=fixture();f.devices.append(node(8,"pv"));f.devices.append(node(9,"station",{"capacity_mw":2.0,"loss_fraction":0.0}))
	f.links[2].from=9
	f.links.append(typed_line(f.devices,8,9,"out","in"))
	r=Model.dispatch(f.devices,f.links,{}, {"1":{"mw":1.0},"8":{"mw":0.0}},3600)
	check(r.valid,"two-bus absent compressor source report")
	near(r.material.electrolyzer_electric_mw,0.0,"rollback leaves remote electro power unused")
	near(r.material.hydrogen_produced_kg_s,0.0,"no remote compressor power no product")
	r=Model.dispatch(f.devices,f.links,{}, {"1":{"mw":1.0},"8":{"mw":0.01}},3600)
	check(r.valid,"two-bus limited compressor source report")
	near(r.material.compression_electric_mw,0.01,"remote compressor actual AC cap")
	near(r.material.hydrogen_produced_kg_s,0.01/(3.6*3.0),"remote utility jointly limits chain")
	f=fixture();f.devices.append(node(8,"battery",{"initial_soc":1.0}));f.links.append(typed_line(f.devices,8,2,"ac","in"))
	r=run_case(f,0.0)
	near(r.material.hydrogen_produced_kg_s,0.0,"battery cannot silently electrolyze")
	f=fixture();f.devices[4].state.material_inventory_kg.H2=100.0
	f.links.append({"from":2,"to":-1,"capacity_mw":4.0,"loss_fraction":0.0})
	r=run_case(f,0.0)
	near(r.material.fuel_cell_output_mw,0.0,"FC no export without load")
	for thermal_kind in ["electric_boiler","fuel_boiler"]:
		f=fixture();f.devices.append(node(8,thermal_kind));f.devices.append(node(9,"heat_exchanger"));f.devices.append(node(10,"heat_demand",{"demand_mwth":0.1}))
		for spec in [[2,8,"out","ac_in"],[8,9,"heat_out","hot_in"],[9,10,"warm_out","heat_in"]]:f.links.append(typed_line(f.devices,spec[0],spec[1],spec[2],spec[3]))
		var direct: Dictionary={"1":{"mw":1.0},"_fuel_supply":{"enabled":true,"max_input_mw":0.5}}
		r=Model.dispatch(f.devices,f.links,{},direct,3600)
		check(r.valid,"mixed old "+thermal_kind+" "+str(r.errors))
		near(r.material.enthalpy_balance_error_mw,0.0,"mixed chemistry remains closed")
		check(Model.audit_dispatch(f.devices,f.links,r,r.get("fuel_supply",{})).is_empty(),"mixed independent "+thermal_kind)
	var rng:=RandomNumberGenerator.new();rng.seed=992317
	for i in 180:
		f=fixture()
		f.devices[1].params.capacity_mw=rng.randf_range(0.05,4.0)
		f.devices[1].params.loss_fraction=rng.randf_range(0,0.2)
		f.devices[2].state.material_inventory_kg.H2O=rng.randf_range(0,10000)
		f.devices[2].params.max_outflow_kg_s=rng.randf_range(0,0.1)
		f.devices[4].params.leak_per_h=rng.randf_range(0,0.05)
		f.devices[4].state.material_inventory_kg.H2=rng.randf_range(0,1000)
		f.devices[6].params.demand_mw=rng.randf_range(0,2)
		for l in f.links:
			if l.has("capacity_mw"):l.loss_fraction=rng.randf_range(0,0.2)
		r=run_case(f,rng.randf_range(0,1),rng.randf_range(0.01,100000))
		check(not (r.material.hydrogen_charged_kg_s>1e-10 and r.material.hydrogen_discharged_kg_s>1e-10),"random store mode exclusive")
		check(r.material.heat_rejected_mwth>=-1e-9,"random no external free heat")
		var ledger: Dictionary=Materials.accumulate_energy(Materials.initial_energy_v1(),r,r.dt_s)
		check(not ledger.is_empty(),"random cumulative dimensional audit")
