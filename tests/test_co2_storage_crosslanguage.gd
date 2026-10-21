extends SceneTree
const Model=preload("res://scripts/energy_model.gd")
const C=Model.Catalog
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures.append(label);printerr("CO2_CROSS_FAIL: "+label)
func _initialize()->void:
	for name in ["co2_full_cycle","co2_material_coexistence","co2_idle_decay","co2_material_tiny","co2_tiny_mode"]:
		var prefix:String="res://evidence/co2_stage/solver/"+name
		var request:Variant=JSON.parse_string(FileAccess.get_file_as_string(prefix+"_request.json"))
		var result:Variant=JSON.parse_string(FileAccess.get_file_as_string(prefix+"_result.json"))
		if not request is Dictionary or not result is Dictionary:check(false,"missing actual GLPK fixtures "+name);continue
		var errors:Array=Model.Dispatch.audit_optimization_result(request,result)
		check(errors.is_empty(),"original "+name+" "+str(errors))
		var index:int=-1
		for i in request.devices.size():
			if request.devices[i].kind==C.CO2_STORAGE_KIND:index=i
		check(index>=0,"CO2 fixture device")
		if index<0:continue
		var id:String=str(int(request.devices[index].id))
		for field in ["charge_mw","discharge_mw","next_energy_mwh","energy_mwh","charge_conversion_loss_mw","discharge_conversion_loss_mw","self_discharge_mwh","capacity_mwh","mode","model_profile","model_profile_version","inventory_basis","working_fluid","working_inventory_calibrated","co2_inventory_kg","heat_output_mwth","hydrogen_lhv_mwh"]:
			var bad:Dictionary=result.duplicate(true)
			if field=="working_inventory_calibrated":bad.steps[0].devices[id][field]=true
			elif field in ["mode","model_profile","inventory_basis","working_fluid"]:bad.steps[0].devices[id][field]="forged"
			else:bad.steps[0].devices[id][field]=float(bad.steps[0].devices[id].get(field,0.0))+1.0
			check(not Model.Dispatch.audit_optimization_result(request,bad).is_empty(),"reject field "+name+field)
		for field in ["model_profile","model_profile_version"]:
			var bad_request:Dictionary=request.duplicate(true);bad_request.devices[index][field]="wrong" if field=="model_profile" else 2
			check(not Model.Dispatch.audit_optimization_result(bad_request,result).is_empty(),"reject original profile "+field)
		for schema in [7,8]:
			var old:Dictionary=request.duplicate(true);old.schema_version=schema
			var old_result:Dictionary=result.duplicate(true);old_result.schema_version=schema
			check(not Model.Dispatch.audit_optimization_result(old,old_result).is_empty(),"old schema rejects CO2 "+str(schema))
		for mode in ["missing_state","new_state","initial_state","duration","terminal_floor"]:
			var bad_request:Dictionary=request.duplicate(true);var bad:Dictionary=result.duplicate(true)
			match mode:
				"missing_state":bad.steps[0].next_states.erase(id)
				"new_state":bad.steps[0].next_states[id].energy_mwh+=1.0
				"initial_state":bad.initial_states[id].energy_mwh+=1.0
				"duration":bad.steps[0].dt_s+=1.0
				"terminal_floor":bad_request.options.terminal_soc_fraction=1.0
			check(not Model.Dispatch.audit_optimization_result(bad_request,bad).is_empty(),"reject frozen contract "+name+mode)
	print("CO2_STORAGE_CROSSLANGUAGE: %d checks, %d failures"%[checks,failures.size()]);quit(0 if failures.is_empty() else 1)
