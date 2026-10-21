extends SceneTree

# The clean/forged pairs share original requests. Godot independently reconstructs
# the full schedule; Python's validation flags and errors are never trusted here.
const Model = preload("res://scripts/energy_model.gd")
const EVIDENCE = "res://evidence/phase2c_stage/solver/"
var checks := 0
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("CHEM_ADVERSARIAL_FAIL: " + label)

func _initialize() -> void:
	var controls: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVIDENCE + "clean_cumulative_controls.json"))
	var negatives: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVIDENCE + "forged_solver_fixtures.json"))
	check(controls is Array and controls.size() == 4, "four actual-GLPK cumulative controls available")
	check(negatives is Array and negatives.size() == 16, "sixteen independent result forgeries available")
	if not controls is Array or not negatives is Array:
		quit(1)
		return
	var original_requests: Dictionary = {}
	for fixture in controls:
		var errors: Array = Model.Dispatch.audit_optimization_result(fixture.request, fixture.result)
		check(errors.is_empty(), "clean " + fixture.name + ": " + str(errors))
		var species: String = String(fixture.name).trim_prefix("clean_cumulative_")
		original_requests[species] = fixture.request
	for fixture in negatives:
		var name: String = fixture.name
		if name.begins_with("forged_cumulative_balanced_"):
			var species: String = name.trim_prefix("forged_cumulative_balanced_")
			check(original_requests.has(species) and original_requests[species] == fixture.request,
				"same original request for clean/forged " + species)
		var errors: Array = Model.Dispatch.audit_optimization_result(fixture.request, fixture.result)
		check(not errors.is_empty(), "reject " + name)
		if not errors.is_empty():
			print("REJECTED ", name, ": ", errors[0])
	print("CHEMICAL_PROCESS_ADVERSARIAL_CROSSLANGUAGE: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)
