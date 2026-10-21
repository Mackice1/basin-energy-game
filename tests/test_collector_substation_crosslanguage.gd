extends SceneTree
const M=preload("res://scripts/energy_model.gd")
const C=M.Catalog
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("COLLECTOR_CROSS_FAIL: "+label)
func _initialize()->void:
	for name in ["collector_shared_capacity","collector_co2_full_cycle","collector_material_cycle","collector_material_co2"]:
		var prefix:String="res://evidence/collector_stage/solver/"+name
		var request:Variant=JSON.parse_string(FileAccess.get_file_as_string(prefix+"_request.json"));var result:Variant=JSON.parse_string(FileAccess.get_file_as_string(prefix+"_result.json"))
		if not request is Dictionary or not result is Dictionary:check(false,"missing actual GLPK fixture "+name);continue
		var errors:Array=M.Dispatch.audit_optimization_result(request,result)
		check(errors.is_empty(),"original "+name+" "+str(errors))
		for i in request.devices.size():
			if request.devices[i].kind!=C.COLLECTOR_KIND:continue
			var id:String=str(int(request.devices[i].id))
			for field in ["capacity_mw","loss_fraction","input_mw","received_mw","output_mw","sent_mw","loss_mw","model_profile","model_profile_version","energy_mwh"]:
				var bad:Dictionary=result.duplicate(true);bad.steps[0].devices[id][field]="wrong" if field=="model_profile" else float(bad.steps[0].devices[id].get(field,0.0))+1.0
				check(not M.Dispatch.audit_optimization_result(request,bad).is_empty(),"reject collector field "+name+field)
			for mode in ["profile","version","state","capacity"]:
				var original:Dictionary=request.duplicate(true)
				match mode:
					"profile":original.devices[i].model_profile="wrong"
					"version":original.devices[i].model_profile_version=2
					"state":original.devices[i].state={"energy_mwh":1.0}
					"capacity":original.devices[i].params.capacity_mw=201.0
				check(not M.Dispatch.audit_optimization_result(original,result).is_empty(),"reject original contract "+mode)
		for schema in [7,8,9]:
			var old_request:Dictionary=request.duplicate(true);var old_result:Dictionary=result.duplicate(true)
			old_request.schema_version=schema;old_result.schema_version=schema
			check(not M.Dispatch.audit_optimization_result(old_request,old_result).is_empty(),"reject old schema "+str(schema))
		for mode in ["extra_stock","time","duration","line_capacity"]:
			var bad:Dictionary=result.duplicate(true)
			match mode:
				"extra_stock":bad.steps[0].next_states["999"]={"energy_mwh":1.0}
				"time":bad.steps[0].time_s+=1.0
				"duration":bad.steps[0].dt_s+=1.0
				"line_capacity":bad.steps[0].lines[0].capacity_mw+=1.0
			check(not M.Dispatch.audit_optimization_result(request,bad).is_empty(),"reject result contract "+mode)
	print("COLLECTOR_SUBSTATION_CROSSLANGUAGE: %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
