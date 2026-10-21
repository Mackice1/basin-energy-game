extends SceneTree
const Base=preload("res://tests/test_material_world_phase2.gd")
const F=preload("res://tests/test_phase_hydrogen_physics.gd")
const C=preload("res://scripts/device_catalog.gd")
const D=preload("res://scripts/material_dispatch.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func run():
	for kind in C.Materials.PHASE_KINDS:
		var fixture=F.new();var spec:Dictionary=fixture.fixture(kind);fixture.free()
		var w=Base.World.new();root.add_child(w)
		w.dimension_profile="metric_v1";w.devices=spec.devices;w.links=spec.links;w.next_id=9
		for k in w.KINDS:w.templates[k]=C.defaults(k)
		for d in w.devices:
			d.x=-55.0 if d.id==1 else 5.0+float(d.id%3)*22.0;d.z=-35.0 if d.id==1 else float(int(d.id/3))*25.0-35.0
			d.params=C.defaults(d.kind).merged(d.params,true)
			if C.is_material(d.kind):d.model_profile=C.model_profile(d.kind);d.model_profile_version=C.model_profile_version(d.kind)
		w.device(8).params.initial_soc=.1;w.device(8).state=C.initial_state("battery",w.device(8).params)
		w.material_energy=D.initial_energy(w.devices)
		check(w.advance(10.0),kind+" real world charge")
		check(w.device(5).state.material_inventory_kg.H2>0,kind+" commits inventory")
		check(w.material_energy.phase_store_electric_mwh>0,kind+" phase AC accumulated")
		var saved:Dictionary=JSON.parse_string(JSON.stringify(w.state()))
		check(w.SaveValidator.validate(saved).is_empty(),kind+" save JSON: "+w.SaveValidator.validate(saved))
		w.restore(saved)
		check(w.material_energy==saved.material_energy,kind+" restore no reimport")
		check(D.validate_energy(w.material_energy,w.devices).is_empty(),kind+" restored stock ledger")
		var old:Dictionary=w.state().duplicate(true)
		check(not w._commit_remove_device(5),kind+" nonempty demolition refused")
		check(w.state()==old,kind+" rejected removal atomic")
		w.supplied_power=0;w.device(7).params.demand_mw=1.0
		check(w.advance(30.0),kind+" night discharge with finite battery")
		check(w.material_energy.fuel_cell_output_mwh>0,kind+" actual FC output")
		check(w.device(8).state.energy_mwh<.1,kind+" consumes finite auxiliary battery")
		check(D.validate_energy(w.material_energy,w.devices).is_empty(),kind+" discharge ledger")
		check(w.device(5).state.material_inventory_kg.H2==0,kind+" drained exactly")
		check(w._commit_remove_device(5),kind+" empty demolition succeeds")
		check(D.validate_energy(w.material_energy,w.devices).is_empty(),kind+" host export ledger")
		w.undo()
		check(not w.device(5).is_empty(),kind+" undo restores device")
		check(D.validate_energy(w.material_energy,w.devices).is_empty(),kind+" undo restores exact stock host")
		var harness=Base.new();harness.cleanup(w);harness.free();await process_frame
	print("PHASE_HYDROGEN_WORLD checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
