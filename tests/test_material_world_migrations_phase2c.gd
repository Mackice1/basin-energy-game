extends SceneTree
const Base=preload("res://tests/test_material_world_phase2.gd")
const F=preload("res://tests/test_material_physics.gd")
const C=preload("res://scripts/device_catalog.gd")
const V2=preload("res://scripts/material_ledger_v2.gd")
const D=preload("res://scripts/material_dispatch.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func run():
	for schema in [14,16,17,18]:
		var f=F.new();var spec:Dictionary=f.fixture();f.free()
		var w=Base.World.new();root.add_child(w);w.dimension_profile="metric_v1";w.devices=spec.devices;w.links=spec.links;w.next_id=8
		for kind in w.KINDS:w.templates[kind]=C.defaults(kind)
		for d in w.devices:
			d.x=-55.0 if d.id==1 else 5.0+float(d.id%3)*22.0;d.z=-35.0 if d.id==1 else float(int(d.id/3))*25.0-35.0
			d.params=C.defaults(d.kind).merged(d.params,true)
			if C.is_material(d.kind):d.model_profile=C.model_profile(d.kind);d.model_profile_version=1
		w.device(5).params.initial_inventory_kg=10.0;w.device(5).state=C.initial_state("hydrogen_gas_store",w.device(5).params)
		var saved:Dictionary=w.state();saved.schema=schema;saved.model_version=23 if schema==14 else 25 if schema==16 else 26
		var allowed:Array=w.SaveValidator.SCHEMA13_KINDS+w.SaveValidator.MATERIAL_KINDS
		if schema>=15:allowed.append("co2_liquid_cycle_store")
		if schema>=16:allowed.append("collector_substation")
		if schema>=17:allowed.append_array(w.SaveValidator.MATERIAL_2B_KINDS)
		for kind in saved.templates.keys():
			if kind not in allowed:saved.templates.erase(kind)
		saved.material_energy=D.initial_energy_v1() if schema<17 else V2.initial_energy(w.devices)
		saved=JSON.parse_string(JSON.stringify(saved))
		check(w.SaveValidator.validate(saved).is_empty(),"historical schema "+str(schema)+": "+w.SaveValidator.validate(saved))
		w.restore(saved)
		check(w.material_energy.get("ledger_version")==3,"migrated v3 "+str(schema))
		check(w.device(5).state.material_inventory_kg.H2==10.0,"no duplicate initial H2 "+str(schema))
		check(D.validate_energy(w.material_energy,w.devices).is_empty(),"migrated stock exact "+str(schema))
		if schema>=17:
			for field in saved.material_energy:
				if field not in ["ledger_version","ledger_profile"]:check(w.material_energy[field]==saved.material_energy[field],"preserved v2 field "+field)
		var current:Dictionary=JSON.parse_string(JSON.stringify(w.state()))
		check(w.SaveValidator.validate(current).is_empty(),"current migrated JSON "+str(schema))
		w.restore(current)
		check(w.material_energy==current.material_energy,"reload no second migration "+str(schema))
		check(w.advance(1.0),"migrated world runs "+str(schema))
		var harness=Base.new();harness.cleanup(w);harness.free();await process_frame
	print("MATERIAL_WORLD_MIGRATIONS_PHASE2C checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
