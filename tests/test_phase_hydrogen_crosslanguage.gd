extends SceneTree
const M=preload("res://scripts/energy_model.gd")
const C=M.Catalog
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("PHASE_CROSS_FAIL: "+label)
func _initialize()->void:
	var fixtures:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://evidence/phase2b_stage/solver/solver_fixtures.json"))
	if not fixtures is Array:check(false,"missing realGLPK fixture");quit(1);return
	for f in fixtures:
		var request:Dictionary=f.request;var result:Dictionary=f.result;var name:String=f.name
		var original:Array=M.Dispatch.audit_optimization_result(request,result)
		check(original.is_empty(),"original "+name+" "+str(original))
		for d in request.devices:
			if not d.kind in C.Materials.PHASE_KINDS:continue
			var id:String=str(int(d.id))
			for field in ["phase_enthalpy_before_mwh","phase_enthalpy_mwh","phase_enthalpy_change_mwh","environment_heat_in_mwth","electric_input_mw","heat_rejected_mwth","inventory_before_kg","inventory_after_leak_kg","next_inventory_kg","leaked_kg","energy_mwh","soc","useful_heat_output_mwth"]:
				var bad:Dictionary=result.duplicate(true);bad.steps[0].devices[id][field]=float(bad.steps[0].devices[id].get(field,0.0))+1.0
				check(not M.Dispatch.audit_optimization_result(request,bad).is_empty(),"reject phase device "+name+" "+field)
			for field in ["model_profile","reference_id"]:
				var bad:Dictionary=result.duplicate(true);bad.steps[0].devices[id][field]="wrong"
				check(not M.Dispatch.audit_optimization_result(request,bad).is_empty(),"reject identity "+name+" "+field)
			var stock:Dictionary=result.duplicate(true);stock.steps[0].next_states[id].material_inventory_kg.H2+=1.0
			check(not M.Dispatch.audit_optimization_result(request,stock).is_empty(),"reject next stock "+name)
			if d.kind=="hydrogen_metal_hydride_store":
				var host:Dictionary=result.duplicate(true);host.steps[0].next_states[id].host_dry_mass_kg-=1.0
				check(not M.Dispatch.audit_optimization_result(request,host).is_empty(),"reject host mass "+name)
		for schema in [8,9,10]:
			var req:Dictionary=request.duplicate(true);var bad:Dictionary=result.duplicate(true);req.schema_version=schema;bad.schema_version=schema
			check(not M.Dispatch.audit_optimization_result(req,bad).is_empty(),"reject oldschema "+name+str(schema))
		for field in ["phase_store_electric_mwh","environment_heat_in_mwhth"]:
			var bad:Dictionary=result.duplicate(true);bad.totals.material[field]+=1.0
			check(not M.Dispatch.audit_optimization_result(request,bad).is_empty(),"reject totals "+name+field)
		for field in ["phase_store_electric_mw","environment_heat_in_mwth","phase_enthalpy_mwh","phase_enthalpy_change_mwh"]:
			var bad:Dictionary=result.duplicate(true);bad.steps[0].material[field]+=1.0
			check(not M.Dispatch.audit_optimization_result(request,bad).is_empty(),"reject aggregate "+name+field)
		var phase:Dictionary=result.duplicate(true);phase.steps[0].material.inventory_by_reference_kg.H2_liquid_20k+=1.0
		check(not M.Dispatch.audit_optimization_result(request,phase).is_empty(),"reject phase map "+name)
	print("PHASE_HYDROGEN_CROSSLANGUAGE: %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
