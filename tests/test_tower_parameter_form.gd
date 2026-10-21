extends SceneTree
const Form = preload("res://scripts/parameter_form.gd")
const C = preload("res://scripts/device_catalog.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var form:=Form.new();root.add_child(form)
	for kind in C.TOWER_KINDS:
		var defaults: Dictionary=C.defaults(kind)
		form.set_parameters(kind,defaults,true)
		check(form.get_parameters()==defaults,"defaults exact roundtrip "+kind)
		check(form._fields.size()==defaults.size(),"all tower parameters visible "+kind)
		check(form.get_validation_errors().is_empty(),"valid tower defaults "+kind)
		for key in defaults:check(form._fields.has(key),"editor exists "+key)
	form.set_parameters("solar_tower_receiver",C.defaults("solar_tower_receiver"),true)
	for key in ["mirror_area_m2","supply_temp_c","return_temp_c"]:check(not form._fields[key].editable,"fixed physical value read-only "+key)
	form._fields.mirror_area_m2.text="3200"
	check(not form.get_validation_errors().is_empty(),"programmatic area tampering still rejected")
	form.set_parameters("molten_salt_store",C.defaults("molten_salt_store"),false)
	check(not form._fields.initial_soc.editable,"running storage initial SOC read-only")
	form.set_parameters("molten_salt_store",C.defaults("molten_salt_store"),true)
	check(form._fields.initial_soc.editable,"new storage initial SOC configurable")
	form.set_parameters("salt_steam_generator",C.defaults("salt_steam_generator"),true)
	check(not form._fields.transfer_efficiency.editable,"fixed steam cycle efficiency read-only")
	form.queue_free();await process_frame
	print("TOWER_PARAMETER_FORM: ",checks," checks, ",failures.size()," failures")
	quit(0 if failures.is_empty() else 1)
