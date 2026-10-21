extends SceneTree
const Base=preload("res://tests/test_material_world_phase2.gd")
const F=preload("res://tests/test_phase_hydrogen_physics.gd")
const C=preload("res://scripts/device_catalog.gd")
const D=preload("res://scripts/material_dispatch.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func fixture()->Dictionary:
	var f=F.new()
	var ds:Array=[f.node(1,"pv"),f.node(2,"station",{"capacity_mw":10.0,"loss_fraction":0.0}),f.node(3,"hydrogen_gas_store",{"initial_inventory_kg":10.0}),f.node(4,"nitrogen_supply_boundary"),f.node(5,"co2_supply_boundary"),f.node(6,"ammonia_synthesis_station"),f.node(7,"methanol_synthesis_station")]
	var ls:Array=[]
	for x in [[1,2,"out","in"],[2,6,"out","ac_in"],[2,7,"out","ac_in"],[3,6,"h2_out","h2_in"],[3,7,"h2_out","h2_in"],[4,6,"n2_out","n2_in"],[5,7,"co2_out","co2_in"]]:ls.append(f.edge(ds,x[0],x[1],x[2],x[3]))
	f.free();return {"devices":ds,"links":ls}
func _initialize():call_deferred("run")
func run():
	var spec:Dictionary=fixture()
	var w=Base.World.new();root.add_child(w)
	w.dimension_profile="metric_v1";w.devices=spec.devices;w.links=spec.links;w.next_id=8
	for k in w.KINDS:w.templates[k]=C.defaults(k)
	for d in w.devices:
		d.x=-55.0 if d.id==1 else 5.0+float(d.id%3)*22.0;d.z=-35.0 if d.id==1 else float(int(d.id/3))*25.0-35.0
		d.params=C.defaults(d.kind).merged(d.params,true)
		if C.is_material(d.kind):d.model_profile=C.model_profile(d.kind);d.model_profile_version=C.model_profile_version(d.kind)
	w.material_energy=D.initial_energy(w.devices)
	check(w.connection_candidate(4,6).get("carrier")=="material_n2_gas","actual nitrogen connection metadata")
	check(w.connection_candidate(5,7).get("species_id")=="CO2","actual carbon connection metadata")
	check(w.connection_candidate(5,6).is_empty(),"wrong feed cannot connect")
	check(w.advance(10.0),"real world chemical synthesis")
	check(w.device(6).state.material_inventory_kg.NH3>0,"actual NH3 product")
	check(w.device(7).state.material_inventory_kg.CH3OH>0,"actual methanol product")
	check(w.device(3).state.material_inventory_kg.H2<10.0,"finite stored hydrogen consumed")
	check(w.device(4).state.material_inventory_kg.N2<1000.0,"finite nitrogen consumed")
	check(w.device(5).state.material_inventory_kg.CO2<1000.0,"finite carbon feed consumed")
	check(w.material_energy.chemical_electric_mwh>0,"chemical AC cumulative")
	check(D.validate_energy(w.material_energy,w.devices).is_empty(),"whole reference mass element enthalpy ledger")
	var saved:Dictionary=JSON.parse_string(JSON.stringify(w.state()))
	check(w.SaveValidator.validate(saved).is_empty(),"chemical JSON save: "+w.SaveValidator.validate(saved))
	w.restore(saved)
	check(w.material_energy==saved.material_energy,"restore no material reimport")
	for id in [4,5,6,7]:
		var before:Dictionary=w.state().duplicate(true)
		check(not w._commit_remove_device(id),"nonempty feed/product cannot vanish "+str(id))
		check(w.state()==before,"rejected removal atomic "+str(id))
	var product_before:float=w.device(7).state.material_inventory_kg.CH3OH
	w.supplied_power=0
	check(w.advance(10.0),"no power stable valid step")
	check(w.device(7).state.material_inventory_kg.CH3OH==product_before,"no free product without electric heat")
	var poisoned:Dictionary=w.state().duplicate(true)
	poisoned.devices[6].state.material_inventory_kg.CH3OH+=1.0
	check(not w.SaveValidator.validate(poisoned).is_empty(),"forged product inventory rejected")
	var harness=Base.new();harness.cleanup(w);harness.free();await process_frame
	print("CHEMICAL_WORLD_PHASE2C checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
