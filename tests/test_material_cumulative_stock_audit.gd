extends SceneTree
const M=preload("res://scripts/energy_model.gd")
func _initialize()->void:
	var f:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://evidence/phase2b_stage/solver/legacy_paired_gas_cumulative_forgery.json"))
	if not f is Dictionary:printerr("Missing real GLPK paired-stock fixture");quit(1);return
	var errors:Array=M.Dispatch.audit_optimization_result(f.request,f.result)
	if not errors.is_empty():printerr("Clean paired original rejected: "+str(errors));quit(1);return
	var bad:Array=M.Dispatch.audit_optimization_result(f.request,f.forged_result)
	if bad.is_empty():printerr("Cumulative1kg transfer between identical-phase stores was accepted");quit(1);return
	print("MATERIAL_CUMULATIVE_STOCK_AUDIT: 2 checks, 0 failures; rejection: "+str(bad))
	quit(0)
