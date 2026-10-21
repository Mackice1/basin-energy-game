extends SceneTree
const Model = preload("res://scripts/energy_model.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool,label: String) -> void:
	checks += 1
	if not ok: failures.append(label);printerr("MATERIAL_CROSSLANGUAGE_FAIL: "+label)
func _initialize() -> void:
	var args: PackedStringArray=OS.get_cmdline_user_args()
	var path: String=args[0] if args.size()>0 else "res://evidence/material_phase2/solver_fixture.json"
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary: printerr("MATERIAL_CROSSLANGUAGE: fixture missing");quit(1);return
	var request: Dictionary=data.get("snapshot",data.get("request",{}))
	var errors: Array[String]=Model.Dispatch.audit_optimization_result(request,data.result)
	check(errors.is_empty(),"original actual GLPK result: "+str(errors))
	var result: Dictionary=data.result
	for key in result.steps[0].material:
		var bad: Dictionary=result.duplicate(true);bad.steps[0].material[key]+=0.1
		check(not Model.Dispatch.audit_optimization_result(request,bad).is_empty(),"aggregate forged "+key)
	for key in result.totals.material:
		var bad: Dictionary=result.duplicate(true);bad.totals.material[key]+=1.0
		check(not Model.Dispatch.audit_optimization_result(request,bad).is_empty(),"total forged "+key)
	for id in result.steps[0].devices:
		if not Model.Catalog.is_material(result.steps[0].devices[id].kind):continue
		for key in Model.Dispatch.Materials.DETAIL_FIELDS:
			var bad: Dictionary=result.duplicate(true);bad.steps[0].devices[id][key]+=0.1
			check(not Model.Dispatch.audit_optimization_result(request,bad).is_empty(),"material detail forged "+id+key)
	for i in result.steps[0].lines.size():
		for key in ["carrier","from_port","to_port","unit"]:
			var bad: Dictionary=result.duplicate(true);bad.steps[0].lines[i][key]="forged"
			check(not Model.Dispatch.audit_optimization_result(request,bad).is_empty(),"edge identity forged "+str(i)+key)
	for mode in ["missing_stock","new_stock","initial_stock","duration","time","missing_material","missing_species","missing_flow","invalid_flow_endpoint","device_kind","missing_totals"]:
		var bad: Dictionary=result.duplicate(true)
		match mode:
			"missing_stock":bad.steps[0].next_states.erase("3")
			"new_stock":bad.steps[0].next_states["3"].material_inventory_kg.H2O+=1.0
			"initial_stock":bad.initial_states["3"].material_inventory_kg.H2O+=1.0
			"duration":bad.steps[0].dt_s+=1.0
			"time":bad.steps[0].time_s+=1.0
			"missing_material":bad.steps[0].erase("material")
			"missing_species":bad.steps[0].lines[-1].erase("species_id")
			"missing_flow":bad.steps[0].lines[-1].erase("sent_kg_s")
			"invalid_flow_endpoint":bad.steps[0].lines[0].flow_from=9999
			"device_kind":bad.steps[0].devices["4"].kind="pv"
			"missing_totals":bad.totals.erase("material")
		check(not Model.Dispatch.audit_optimization_result(request,bad).is_empty(),"rejected "+mode)
	for field in ["model_profile","model_profile_version"]:
		var bad_request: Dictionary=request.duplicate(true)
		bad_request.devices[3][field]="wrong" if field=="model_profile" else 2
		check(not Model.Dispatch.audit_optimization_result(bad_request,result).is_empty(),"original process contract rejected "+field)
	var stress_path: String="res://evidence/material_phase2/solver_stress_fixtures.json"
	if FileAccess.file_exists(stress_path):
		var stress: Variant=JSON.parse_string(FileAccess.get_file_as_string(stress_path))
		if stress is Array:
			for i in stress.size():
				var x: Dictionary=stress[i]
				var audit: Array=Model.Dispatch.audit_optimization_result(x.get("request",x.get("snapshot",{})),x.result)
				check(audit.is_empty(),"mixed/tiny actual GLPK "+str(i)+" "+str(audit))
				var original_request:Dictionary=x.get("request",x.get("snapshot",{}))
				if x.result.steps.any(func(step):return step.get("unserved_mw",0.0)>1e-4 or step.get("thermal",{}).get("unserved_mwth",0.0)>1e-4):
					var strict:Dictionary=original_request.duplicate(true);strict.options.strict_supply=true
					check(not Model.Dispatch.audit_optimization_result(strict,x.result).is_empty(),"original strict supply contract "+str(i))
				for d in original_request.devices:
					if not Model.Catalog.is_storage(d.kind):continue
					var heat:bool=Model.Catalog.is_thermal_storage(d.kind)
					var p:Dictionary=Model.Catalog.defaults(d.kind).merged(d.get("params",{}),true)
					var final_energy:float=x.result.final_states[str(int(d.id))]["energy_mwhth" if heat else "energy_mwh"]
					if final_energy>=p["capacity_mwhth" if heat else "capacity_mwh"]-1e-4:continue
					var floor_request:Dictionary=original_request.duplicate(true);floor_request.options["terminal_heat_soc_fraction" if heat else "terminal_soc_fraction"]=1.0
					check(not Model.Dispatch.audit_optimization_result(floor_request,x.result).is_empty(),"original terminal energy floor "+str(i))
	print("MATERIAL_CROSSLANGUAGE: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
