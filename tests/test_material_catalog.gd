extends SceneTree
const C=preload("res://scripts/device_catalog.gd")
const MC=preload("res://scripts/material_catalog.gd")
const M=preload("res://scripts/energy_model.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok: failures.append(label);printerr("MATERIAL_CATALOG_FAIL: "+label)
func _initialize()->void:
	check(C.legacy_implemented_kinds().size()==27,"frozen27 kinds")
	check(C.phase2a_implemented_kinds().size()==31,"four new complete facilities")
	var c:Dictionary=MC.coefficients()
	check(abs(c.water_per_h2-1.0-c.oxygen_per_h2)<1e-12,"consistent atomic masses")
	check(c.hhv_kwh_per_kg>c.lhv_kwh_per_kg,"liquid-water enthalpy distinct LHV")
	for kind in MC.LEGACY_KINDS:
		check(C.implemented_kinds().count(kind)==1,"unique "+kind)
		check(not C.is_storage(kind),"kg is not MWh storage "+kind)
		check(M.validate(kind,{}).is_empty(),"valid defaults "+kind)
		check(C.validate_state(kind,{},C.initial_state(kind)).is_empty(),"valid typed state "+kind)
		check(C.model_profile(kind)==MC.PROFILE_ID,"material profile "+kind)
		for value in [-1.0,INF,NAN]:
			for key in MC.defaults(kind):
				check(not M.validate(kind,{key:value}).is_empty(),"bad finite/nonnegative "+kind+key)
		check(not M.validate(kind,{"magic_efficiency":1}).is_empty(),"unknown param rejected "+kind)
		for p in C.ports(kind):
			check(p.carrier=="electricity_ac" or (p.unit=="kg/s" and p.carrier in MC.CARRIERS and p.has("species_id") and p.has("phase_id") and p.has("grade_id")),"typed material port")
	for kind in ["water_supply_boundary","hydrogen_gas_store"]:
		var state:Dictionary=C.initial_state(kind)
		for value in [-1.0,INF,NAN,1e12]:
			var bad:Dictionary=state.duplicate(true);bad.material_inventory_kg[MC.species(kind)]=value
			check(not C.validate_state(kind,{},bad).is_empty(),"bad stock "+kind)
		var bad:Dictionary=state.duplicate(true);bad.material_inventory_kg["CO2"]=0.0
		check(not C.validate_state(kind,{},bad).is_empty(),"wrong species "+kind)
		check(not C.validate_state(kind,{}, {"energy_mwh":1.0}).is_empty(),"energy masquerade rejected")
		check(not C.validate_state(kind,{},null).is_empty(),"null state rejected")
	check(not M.validate("electrolyzer_station",{"electricity_kwh_per_kg":c.lhv_kwh_per_kg}).is_empty(),"no hidden liquid-water heat input")
	check(M.validate("electrolyzer_station",{"electricity_kwh_per_kg":c.hhv_kwh_per_kg}).is_empty(),"thermoneutral net boundary allowed")
	check(not M.validate("hydrogen_gas_store",{"compression_kwh_per_kg":0.0}).is_empty(),"no free compression")
	var ds:Array=[{"id":1,"kind":"water_supply_boundary"},{"id":2,"kind":"electrolyzer_station"},{"id":3,"kind":"hydrogen_gas_store"},{"id":4,"kind":"fuel_cell_station"}]
	var pipes: Array=[]
	for spec in [[1,2,"water_out","water_in"],[2,3,"h2_out","h2_in"],[3,4,"h2_out","h2_in"]]:
		var port:Dictionary=C.port(ds[spec[0]-1].kind,spec[2])
		var line:Dictionary={"from":spec[0],"to":spec[1],"from_port":spec[2],"to_port":spec[3],"mass_flow_capacity_kg_s":1.0,"loss_fraction":0.0}
		for key in ["carrier","unit","species_id","phase_id","grade_id"]:line[key]=port[key]
		pipes.append(line)
		check(C.validate_link(ds,[],line).is_empty(),"allowed one stage material edge")
		check(not C.validate_link(ds,[line],line).is_empty(),"duplicate material ports rejected")
		for key in ["carrier","unit","species_id","phase_id","grade_id"]:
			var bad:Dictionary=line.duplicate(true);bad[key]="wrong"
			check(not C.validate_link(ds,[],bad).is_empty(),"wrong typed edge "+key)
			bad=line.duplicate(true);bad.erase(key)
			check(not C.validate_link(ds,[],bad).is_empty(),"missing typed edge "+key)
		for key in ["capacity_mw","capacity_mwth","voltage_level"]:
			var bad:Dictionary=line.duplicate(true);bad[key]=1.0 if key!="voltage_level" else "AC_BUS"
			check(not C.validate_link(ds,[],bad).is_empty(),"mixed units rejected")
		var bad:Dictionary=line.duplicate(true);bad.loss_fraction=0.1
		check(not C.validate_link(ds,[],bad).is_empty(),"pipe cannot invent leak")
		bad=line.duplicate(true);bad.from=spec[1];bad.to=spec[0]
		check(not C.validate_link(ds,[],bad).is_empty(),"reverse route rejected")
	var snapshot:Dictionary=M.optimization_snapshot(ds,pipes,{},{},1.0)
	check(snapshot.valid and snapshot.schema_version==8,"material optimization export is valid schema8")
	check(snapshot.initial_states.size()==2 and snapshot.initial_states.has("1") and snapshot.initial_states.has("3"),"snapshot retains finite material initial stocks")
	check(snapshot.units.material_flow=="kg/s" and snapshot.units.material_inventory=="kg","snapshot kg units")
	for edge in snapshot.edges:
		check(edge.unit=="kg/s" and edge.has("species_id") and edge.has("phase_id") and not edge.has("capacity_mw"),"snapshot typed mass edges")
	for d in snapshot.devices:
		check(d.model_profile==MC.PROFILE_ID and d.model_profile_version==1,"snapshot freezes process profile")
	print("MATERIAL_CATALOG: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
