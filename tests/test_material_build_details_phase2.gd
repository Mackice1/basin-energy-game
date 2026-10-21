extends SceneTree
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures.append(message);push_error(message)
func _initialize():call_deferred("run")
func run():
	var world=load("res://main.tscn").instantiate();root.add_child(world);await process_frame
	world.dimension_profile="metric_v1";world.devices=[];world.links=[];world.stations=[];world.next_id=0;world.elapsed_s=0.0
	world.energy=world.ENERGY_ZERO.duplicate(true);world.material_energy=world.Materials.initial_energy()
	world.rebuild_equipment();world.refresh()
	for kind in world.MATERIAL_KINDS:
		var placed:=false
		for x in range(-65,66,13):
			for z in range(-65,66,13):
				if world.can_place(kind,Vector2(x,z)).is_empty():
					placed=world.add_equipment(kind,Vector2(x,z),false);break
			if placed:break
		check(placed,"real map legal placement "+kind)
		if not placed:continue
		var id:int=world.selected_id
		check(world.nodes.has(str(id)),"actual visual created "+kind)
		var visual=world.nodes[str(id)]
		for port in world.Catalog.ports(kind):check(visual.has_named_port(port.id),"actual named port "+kind+"/"+port.id)
		check(world.device_inspector.open_device(id),"actual secondary page opens "+kind)
		await process_frame
		check(world.device_inspector.texts["参数"].text.contains("当前参数"),"live parameter page "+kind)
		check(world.device_inspector.texts["边界"].text.contains("物种"),"explicit material boundary "+kind)
		world.device_inspector.close_device()
	var saved:Dictionary=world.state()
	check(world.validate_state(saved).is_empty(),"all four actual placed facilities save validates: "+world.validate_state(saved))
	var bytes:=JSON.stringify(saved)
	world.restore(JSON.parse_string(bytes))
	check(world.devices==JSON.parse_string(bytes).devices and world.links==JSON.parse_string(bytes).links,"actual restore preserves IDs positions states and links")
	check(world.material_energy==JSON.parse_string(bytes).material_energy,"actual restore preserves material ledger")
	world.queue_free();await process_frame;await process_frame
	print("MATERIAL_BUILD_DETAILS_PHASE2 checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
