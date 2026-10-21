extends SceneTree
const C = preload("res://scripts/device_catalog.gd")
const Fixtures = preload("res://tests/test_phase_hydrogen_physics.gd")
const WorldTest = preload("res://tests/test_material_world_phase2.gd")
const Controller = preload("res://scripts/optimization_controller.gd")
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String):
	checks+=1
	if not ok:failures.append(message);push_error(message)
func _initialize():call_deferred("run")
func run():
	for phase_kind in C.Materials.PHASE_KINDS:
		await check_kind(phase_kind)
	print("PHASE_HYDROGEN_OPTIMIZATION_WORLD checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
func check_kind(phase_kind:String):
	var source=Fixtures.new();var spec:Dictionary=source.fixture(phase_kind);source.free()
	var world=WorldTest.World.new();root.add_child(world)
	world.devices=spec.devices;world.links=spec.links;world.next_id=9
	for kind in world.KINDS:world.templates[kind]=C.defaults(kind)
	for d in world.devices:
		d.x=float(d.id)*10-40;d.z=0.0;d.params=C.defaults(d.kind).merged(d.params,true)
		if C.is_material(d.kind):d.model_profile=C.model_profile(d.kind);d.model_profile_version=C.model_profile_version(d.kind)
	world.material_energy=world.Materials.initial_energy(world.devices)
	var service=Controller.new();root.add_child(service);service.setup(world)
	var before:=JSON.stringify(world.state())
	var options:Dictionary={"horizon_hours":1.0,"step_minutes":60.0,"load_multiplier":1.0,"strict_supply":false,"timeout_s":15,"terminal_hydrogen_kg":{"5":0.0}}
	var snapshot:Dictionary=service.snapshot(options)
	check(not snapshot.has("error"),"material snapshot accepted: "+str(snapshot.get("error","")))
	check(snapshot.get("schema_version")==11,"snapshot uses schema11")
	check(snapshot.options.terminal_hydrogen_kg=={"5":0.0},"explicit target retained")
	var baseline:Dictionary=service.make_baseline(snapshot)
	check(not baseline.has("error") and baseline.steps.size()==1,"material baseline valid")
	check(baseline.steps[0].has("material"),"baseline never falls back to electric only")
	for value in [{"05":0},{"4":0},{"5":1001},{"5":-1},{"5":"1"},[],null]:
		var bad:=options.duplicate(true);bad.terminal_hydrogen_kg=value
		check(service.snapshot(bad).has("error"),"invalid target refused "+str(value))
	service.open()
	check(service.panel.get_options().has("terminal_hydrogen_kg"),"controller configures material UI")
	service.panel.hide();service.start(options)
	var deadline:=Time.get_ticks_msec()+25000
	while service.pid>0 and Time.get_ticks_msec()<deadline:await create_timer(0.02).timeout
	check(service.pid<0,"solver completes")
	check(not service.last_result.is_empty(),"real GLPK result survives independent Godot audit")
	check(JSON.stringify(world.state())==before,"optimization cannot mutate live material state or ledger")
	service.free()
	var helper=WorldTest.new();helper.cleanup(world);helper.free()
