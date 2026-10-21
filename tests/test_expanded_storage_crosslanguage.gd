extends SceneTree
## Audit real GLPK reports using Godot's independent original-input physics.
## Only report field aliases are mapped; no allocation or flow recomputation.
const M = preload("res://scripts/energy_model.gd")
const C = preload("res://scripts/device_catalog.gd")
const D = preload("res://scripts/network_dispatch.gd")
const H = preload("res://scripts/thermal_dispatch.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("STORAGE_CROSSLANG_FAIL: " + label)
func _initialize() -> void:
	var records: Array = []
	for kind in C.NEW_STORAGE_KINDS:
		var prefix: String = "res://evidence/expanded_storage/validation/" + kind
		var request: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(prefix + "_request.json"))
		var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(prefix + "_result.json"))
		check(result.success and result.solver_invoked and result.status == "optimal","real GLPK optimal " + kind)
		var devices: Array = request.devices.duplicate(true)
		for d in devices:
			var p: Dictionary = C.defaults(d.kind); p.merge(d.params,true); d.params=p
			if C.is_storage(d.kind) and not d.has("state"): d.state=C.initial_state(d.kind,d.params)
		for line in request.links: line.from=int(line.from);line.to=int(line.to)
		for index in result.steps.size():
			var step: Dictionary = request.steps[index]
			var direct: Dictionary = {}
			for id in step.available_mw: direct[id]={"mw":step.available_mw[id]}
			for d in devices:
				if d.kind=="load": d.params.demand_mw=step.demand_mw[str(int(d.id))]
				elif d.kind=="heat_demand": d.params.demand_mwth=step.heat_demand_mwth[str(int(d.id))]
			var prepared: Dictionary = D._prepare(devices,request.links,{},direct,float(step.dt_h)*3600.0,M.generation,M.validate)
			H.prepare(prepared)
			var candidate: Dictionary = result.steps[index]
			var report: Dictionary = prepared.report.duplicate(true)
			for key in candidate:
				if not key in ["devices","lines","fuel"]: report[key]=candidate[key]
			for key in candidate.get("fuel",{}): check(absf(float(candidate.fuel[key]))<1e-9,"absent fuel zero " + kind + "/" + key)
			for id in candidate.devices:
				report.devices[id].merge(candidate.devices[id],true)
				var d: Dictionary = report.devices[id]
				if C.is_storage(d.kind):
					var unit: String = "mwhth" if C.is_thermal_storage(d.kind) else "mwh"
					check(absf(float(d["energy_"+unit])-float(d["next_energy_"+unit]))<1e-9,"Python post-step alias " + kind)
					d["energy_"+unit]=d["energy_before_"+unit]
					d["storage_balance_error_"+unit]=0.0
				if d.kind=="electric_boiler":
					d.electric_input_mw=d.boiler_electric_mw
					d.heat_output_mwth=d.boiler_heat_mwth
					d.conversion_loss_mw=d.boiler_conversion_loss_mw
			for i in candidate.lines.size():
				report.lines[i].merge(candidate.lines[i],true)
				for key in ["index","from","to","flow_from","flow_to","direction"]:
					if report.lines[i].has(key): report.lines[i][key]=int(report.lines[i][key])
			var errors: Array = M.audit_dispatch(devices,request.links,report)
			check(errors.is_empty(),kind+" step "+str(index)+" independent Godot audit "+str(errors))
			var bad := report.duplicate(true)
			var field: String="energy_mwhth" if kind=="solid_thermal_store" else "energy_mwh"
			bad.next_states["3"][field]+=0.01
			check(not M.audit_dispatch(devices,request.links,bad).is_empty(),"forged optimized inventory rejected")
			records.append({"kind":kind,"step":index,"audit_errors":errors,"next_state":report.next_states["3"]})
			for d in devices:
				var id:=str(int(d.id))
				if report.next_states.has(id): d.state=report.next_states[id].duplicate(true)
	var file:=FileAccess.open("res://evidence/expanded_storage/validation/godot_crosslanguage_audit.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":records,"adapter":"Original inputs supply presentation defaults; Python post-step energy alias maps to Godot pre-step alias; boiler report field names mapped. No allocation; all candidate flows, efficiencies, inventory and loss terms retained."},"  ")); file.close()
	print("EXPANDED_STORAGE_CROSSLANGUAGE: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
