extends SceneTree
const M=preload("res://scripts/energy_model.gd")
const C=M.Catalog
const D=M.Dispatch.Materials
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("CHEM_CROSS_FAIL: "+label)
func _initialize()->void:
	var fs:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://evidence/phase2c_stage/solver/solver_fixtures.json"))
	if not fs is Array:check(false,"missing realGLPK fixture");quit(1);return
	for f in fs:
		var request:Dictionary=f.request;var result:Dictionary=f.result;var name:String=f.name
		if result.get("status")=="infeasible":
			check(result.get("optimal")==false,"explicit infeasibility "+name)
			check(not M.Dispatch.audit_optimization_result(request,result).is_empty(),"not usable as solution "+name)
			continue
		var errors:Array=M.Dispatch.audit_optimization_result(request,result)
		check(errors.is_empty(),"original "+name+" "+str(errors))
		for field in D.CHEMICAL_FIELDS:
			var bad:Dictionary=result.duplicate(true);bad.steps[0].material[field]+=1.0
			check(not M.Dispatch.audit_optimization_result(request,bad).is_empty(),"reject aggregate "+name+field)
		for field in ["chemical_electric_mwh","ammonia_produced_kg","methanol_produced_kg","nitrogen_withdrawn_kg","co2_withdrawn_kg","chemical_hydrogen_consumed_kg","chemical_water_released_kg"]:
			var bad:Dictionary=result.duplicate(true);bad.totals.material[field]+=1.0
			check(not M.Dispatch.audit_optimization_result(request,bad).is_empty(),"reject cumulative "+name+field)
		for n in request.devices:
			if not n.kind in C.Materials.CHEMICAL_KINDS:continue
			var id:String=str(int(n.id))
			for field in D.CHEMICAL_DETAIL_FIELDS+["inventory_before_kg","next_inventory_kg","electric_input_mw","heat_rejected_mwth","water_released_kg_s"]:
				var bad:Dictionary=result.duplicate(true);bad.steps[0].devices[id][field]+=1.0
				check(not M.Dispatch.audit_optimization_result(request,bad).is_empty(),"reject device "+name+field)
			var bad:Dictionary=result.duplicate(true);bad.steps[0].next_states[id].material_inventory_kg[C.Materials.species(n.kind)]+=1
			check(not M.Dispatch.audit_optimization_result(request,bad).is_empty(),"reject inventory "+name+n.kind)
		for schema in [8,9,10,11]:
			var req:Dictionary=request.duplicate(true);var bad:Dictionary=result.duplicate(true);req.schema_version=schema;bad.schema_version=schema
			check(not M.Dispatch.audit_optimization_result(req,bad).is_empty(),"reject oldschema "+name+str(schema))
		var forged:Dictionary=result.duplicate(true);forged.steps[0].material.inventory_by_reference_kg.NH3_gas_25c+=1
		check(not M.Dispatch.audit_optimization_result(request,forged).is_empty(),"reject reference phase map "+name)
	print("CHEMICAL_PROCESS_CROSSLANGUAGE: %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
