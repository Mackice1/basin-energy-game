extends SceneTree
## Read real GLPK candidates through a report-format-only adapter, then apply
## Godot's independent original-topology/physics audit. No runtime allocation.
const Model = preload("res://scripts/energy_model.gd")
const Dispatch = preload("res://scripts/network_dispatch.gd")
const Thermal = preload("res://scripts/thermal_dispatch.gd")
const Tower = preload("res://scripts/solar_tower_thermal.gd")
const Rankine = preload("res://scripts/rankine_cycle.gd")
var failures: Array[String] = []
var checks: int = 0
func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures.append(label);printerr("CROSSLANG_FAIL: "+label)
func _initialize() -> void:
	var records: Array = []
	for period in ["day","night"]:
		var prefix: String = "res://evidence/tower_stage/validation/crosslang_"+period
		var request: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(prefix+"_input.json"))
		var result: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(prefix+"_output.json"))
		check(result.success and result.status=="optimal","real GLPK candidate "+period)
		var step: Dictionary = request.steps[0]
		var direct: Dictionary = {}
		for id in step.available_mw: direct[id]={"mw":step.available_mw[id]}
		for line in request.links:
			line.from=int(line.from);line.to=int(line.to)
		var devices: Array = request.devices.duplicate(true)
		for d in devices:
			if d.kind=="load": d.params.demand_mw=step.demand_mw[str(int(d.id))]
		var prepared: Dictionary = Dispatch._prepare(devices,request.links,step.weather,direct,float(step.dt_h)*3600.0,Model.generation,Model.validate)
		Thermal.prepare(prepared);Tower.prepare(prepared);Rankine.prepare(prepared)
		check(prepared.report.errors.is_empty() and prepared.report.warnings.is_empty(),"original topology valid "+period)
		var candidate: Dictionary = result.steps[0]
		var report: Dictionary = prepared.report.duplicate(true)
		for key in candidate:
			if key not in ["devices","lines","fuel"]: report[key]=candidate[key]
		# Python always includes a zero fuel summary even without fuel equipment.
		# This is a shape difference only; reject any nonzero discarded value.
		for key in candidate.get("fuel",{}): check(absf(float(candidate.fuel[key]))<1e-10,"absent fuel is zero "+key)
		for id in candidate.devices:
			report.devices[id].merge(candidate.devices[id],true)
			var d: Dictionary = report.devices[id]
			if d.has("auxiliary_electric_mw"):
				d.auxiliary_electric_loss_mw = d.pump_motor_loss_mw if d.kind=="feedwater_pump" else d.auxiliary_electric_mw
			if d.kind=="molten_salt_store":
				# Python energy_mwhth is post-step; Godot uses it for pre-step.
				check(absf(float(d.energy_mwhth)-float(d.next_energy_mwhth))<1e-10,"Python storage endpoint alias "+period)
				d.energy_mwhth=d.energy_before_mwhth
				d.storage_balance_error_mwhth=0.0
		for i in candidate.lines.size():
			report.lines[i].merge(candidate.lines[i],true)
			for key in ["index","from","to","flow_from","flow_to","direction"]: report.lines[i][key]=int(report.lines[i][key])
		report.cross_carrier_balance_error_mw=float(report.balance_error_mw)+float(report.thermal.balance_error_mwth)+float(report.tower.balance_error_mwth)+float(report.rankine.balance_error_mw)
		var errors: Array = Model.audit_dispatch(devices,request.links,report,{},step.weather)
		check(errors.is_empty(),period+" Godot original-physics audit "+str(errors))
		var bad: Dictionary = report.duplicate(true)
		bad.tower.rankine_salt_input_mwth+=.01
		check(not Model.audit_dispatch(devices,request.links,bad,{},step.weather).is_empty(),period+" cross-language aggregate tampering rejected")
		bad=report.duplicate(true);bad.lines[8 if period=="day" else 10].sent_mwth+=.01
		check(not Model.audit_dispatch(devices,request.links,bad,{},step.weather).is_empty(),period+" cross-language salt transport tampering rejected")
		records.append({"case":period,"audit_errors":errors,"gross_electric_mw":report.rankine.gross_electric_mw,"salt_input_mwth":report.rankine.salt_input_mwth,"oil_input_mwth":report.rankine.oil_input_mwth,"energy_mwhth":report.tower.energy_mwhth})
	var file: FileAccess = FileAccess.open("res://evidence/tower_stage/validation/crosslang_godot_audit.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":records,"adapter":"No dispatch allocation. Original input metadata supplies missing runtime presentation fields; Python endpoint storage energy is mapped to Godot pre-step alias. All candidate flows, next_states and physical totals retained."},"  "));file.close()
	print("TOWER_CROSSLANGUAGE_REPLAY: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
