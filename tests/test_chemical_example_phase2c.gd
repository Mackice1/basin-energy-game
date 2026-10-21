extends SceneTree
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func run():
	var w=load("res://main.tscn").instantiate();root.add_child(w);await process_frame
	var before:Dictionary=w.state().duplicate(true)
	w.chemical_example()
	check(w.devices.size()==12,"actual complete example places twelve facilities")
	check(w.links.size()==20,"complete typed topology twenty links")
	var pipe_labels:=0
	for tag in w.cables.get_children():
		if tag is Label3D:
			pipe_labels+=1
			var projection_factor:float=absf(w.camera.get_camera_projection().y.y) if w.camera.projection!=Camera3D.PROJECTION_ORTHOGONAL else 1.0
			var pixels:float=tag.pixel_size*tag.font_size*root.get_visible_rect().size.y*projection_factor/2.0
			check(absf(pixels-18.0)<0.01,"material pipe label bounded to eighteen screen pixels")
	check(pipe_labels>0,"actual selected synthesis has material pipe labels")
	check(w.validate_state(w.state()).is_empty(),"actual terrain and save validate: "+w.validate_state(w.state()))
	check(w.advance(30.0),"real weather actual world runs")
	check(w.material_energy.ammonia_produced_kg>0,"real example produces ammonia")
	check(w.material_energy.methanol_produced_kg>0,"real example produces methanol")
	check(w.Materials.validate_energy(w.material_energy,w.devices).is_empty(),"example complete reference ledger")
	w.undo()
	check(w.devices==before.devices and w.links==before.links,"example one undo restores original scene")
	w.queue_free();await process_frame;await process_frame
	print("CHEMICAL_EXAMPLE_PHASE2C checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
