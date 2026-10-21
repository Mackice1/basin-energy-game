extends SceneTree
const CurrentWorldVersion = preload("res://scripts/world_game.gd")
const C = preload("res://scripts/device_catalog.gd")
const Fixtures = preload("res://tests/test_material_physics.gd")
const Materials = preload("res://scripts/material_dispatch.gd")
class World:
	extends "res://scripts/world_game.gd"
	var supplied_power := 1.0
	func _ready(): pass
	func update_status(): pass
	func tell(_message: String): pass
	func rebuild_equipment(): pass
	func rebuild_cables(): pass
	func set_mode(value: String): mode=value
	func solve_at(_time: float) -> Dictionary:
		return Model.dispatch(devices, links, {}, {"1":{"mw":supplied_power}}, dispatch_dt_s)
var checks := 0
var failures: Array[String] = []
func check(ok: bool, text: String):
	checks += 1
	if not ok: failures.append(text); push_error(text)
func _initialize(): call_deferred("run")
func run():
	var f = Fixtures.new(); var spec: Dictionary=f.fixture();f.free()
	var world := World.new();root.add_child(world)
	world.dimension_profile="metric_v1";world.devices=spec.devices;world.links=spec.links;world.next_id=8
	for kind in world.KINDS:world.templates[kind]=C.defaults(kind)
	for d in world.devices:
		d.x=-55.0 if d.id==1 else 5.0+float(d.id%3)*22.0;d.z=-35.0 if d.id==1 else float(int(d.id/3))*25.0-35.0
		d.params=C.defaults(d.kind).merged(d.params,true)
		if C.is_material(d.kind):d.model_profile=C.model_profile(d.kind);d.model_profile_version=1
	world.material_energy=Materials.initial_energy(world.devices)
	check(world.advance(10.0), "actual world advances hydrogen production")
	check(world.device(5).state.material_inventory_kg.H2>0, "world commits gas kg inventory")
	check(world.device(3).state.material_inventory_kg.H2O<10000, "world commits finite water draw")
	check(Materials.validate_energy(world.material_energy).is_empty(), "world material cumulative ledger valid")
	check(world.material_energy.hydrogen_produced_kg>0, "world actual cumulative production")
	check(absf(world.energy.generated-world.material_energy.electrolyzer_electric_mwh-world.material_energy.compression_electric_mwh)<1e-9, "world AC input reconciles material draw")
	var snapshot: Dictionary=world.state()
	check(snapshot.schema==CurrentWorldVersion.CURRENT_SAVE_SCHEMA and snapshot.model_version==CurrentWorldVersion.CURRENT_MODEL_VERSION, "world emits material schema")
	check(snapshot.material_energy==world.material_energy, "save includes material history")
	check(world.SaveValidator.validate(snapshot).is_empty(), "actual material world save validates: "+world.SaveValidator.validate(snapshot))
	check(world.SaveValidator.validate(JSON.parse_string(JSON.stringify(snapshot))).is_empty(), "actual kg inventories JSON roundtrip: "+world.SaveValidator.validate(JSON.parse_string(JSON.stringify(snapshot))))
	var before: Dictionary=snapshot.duplicate(true)
	world.refresh()
	check(world.state()==before, "preview refresh cannot consume water or produce hydrogen")
	var pipe: Dictionary=world.connection_candidate(3,4)
	check(pipe.get("carrier")=="material_water" and pipe.get("unit")=="kg/s", "click connection makes water pipe")
	check(pipe.get("species_id")=="H2O" and pipe.get("phase_id")=="liquid" and not pipe.has("capacity_mwth"), "water pipe explicit species and phase")
	pipe=world.connection_candidate(4,5)
	check(pipe.get("carrier")=="material_h2_gas" and pipe.get("grade_id")=="h2_gas_supply", "click connection makes supply H2 pipe")
	pipe=world.connection_candidate(5,6)
	check(pipe.get("grade_id")=="h2_gas_delivery", "delivery grade remains distinct")
	check(world.connection_candidate(3,5).is_empty(), "water cannot enter gas store")
	world.supplied_power=0.0;world.device(7).params.demand_mw=1.0
	check(world.advance(10.0), "world advances finite fuel cell output")
	check(world.material_energy.fuel_cell_output_mwh>0, "actual fuel cell output accumulated")
	check(Materials.validate_energy(world.material_energy).is_empty(), "charge discharge whole ledger reconciles")
	world.selected_id=3
	var count_before:int=world.devices.size()
	world.remove_selected()
	check(world.devices.size()==count_before,"water stock cannot silently vanish through demolition")
	world.material_energy.hydrogen_produced_kg+=1.0
	var rejected_state:Dictionary=world.state().duplicate(true)
	check(not world.advance(1.0),"invalid material ledger blocks next commit")
	check(world.state()==rejected_state,"failed ledger transaction changes no energy inventory clock")
	cleanup(world);await process_frame
	print("MATERIAL_WORLD_PHASE2 checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func cleanup(controller):
	for key in ["camera","lod_camera","terrain","labels","infrastructure","selection","overlay","equipment","cables","confirmation","param_dialog","param_errors","param_target","data_dialog","data_list","line_dialog","line_capacity","line_loss","line_choice"]:
		var node=controller.get(key)
		if is_instance_valid(node) and node.get_parent()==null:node.free()
	controller.free()
