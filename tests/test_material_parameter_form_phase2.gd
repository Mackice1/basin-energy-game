extends SceneTree
const Form = preload("res://scripts/parameter_form.gd")
const C = preload("res://scripts/device_catalog.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures.append(message);push_error(message)
func _initialize():call_deferred("run")
func run():
	var form=Form.new();root.add_child(form)
	for kind in C.Materials.LEGACY_KINDS:
		var defaults:Dictionary=C.defaults(kind)
		form.set_parameters(kind,defaults,false)
		check(form._fields.size()==defaults.size(),"every actual parameter has labeled control "+kind)
		check(form.get_parameters()==defaults,"default parameter identity "+kind)
		check(form.get_validation_errors().is_empty(),"default valid "+kind)
		if defaults.has("initial_inventory_kg"):
			check(not form._fields.initial_inventory_kg.editable,"installed initial kg readonly "+kind)
			check(form._fields.initial_inventory_kg.get_meta("construction_only"),"construction marker "+kind)
			form.set_parameters(kind,defaults,true)
			check(form._fields.initial_inventory_kg.editable,"new facility initial condition editable "+kind)
	form.free()
	print("MATERIAL_PARAMETER_FORM_PHASE2 checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
