extends SceneTree
## CPU and object-memory smoke benchmark; explicitly NOT rendered FPS/VRAM.
const C=preload("res://scripts/device_catalog.gd")
const M=preload("res://scripts/energy_model.gd")
const V=preload("res://scripts/equipment_visual.gd")
func _initialize():
	var ds:Array=[];var ls:Array=[]
	for spec in [[1,"wind"],[2,"station"],[3,"load"],[4,"battery_sodium"],[5,"battery_flow"],[6,"caes_aboveground"],[7,"liquid_air_store"],[8,"hydrogen_storage_system"]]:
		var p:Dictionary=C.defaults(spec[1]);var d:Dictionary={"id":spec[0],"kind":spec[1],"params":p}
		if C.is_storage(d.kind):d.state=C.initial_state(d.kind,p)
		ds.append(d)
	ds[1].params.capacity_mw=20.0
	for pair in [[1,2,"out","in"],[2,3,"out","in"],[2,4,"out","ac"],[2,5,"out","ac"],[2,6,"out","ac"],[2,7,"out","ac"],[2,8,"out","ac"]]:
		ls.append({"from":pair[0],"to":pair[1],"from_port":pair[2],"to_port":pair[3],"carrier":C.CARRIER,"unit":"MW","capacity_mw":20.0,"loss_fraction":0.01})
	var samples:Array[float]=[]
	var memory_before:=OS.get_static_memory_usage()
	for i in 500:
		var start:=Time.get_ticks_usec()
		var result:Dictionary=M.dispatch(ds,ls,{}, {"1":{"mw":5.0 if i%100<50 else 0.0}},1.0)
		if not result.valid:push_error(str(result.errors));quit(1);return
		for d in ds:
			if result.next_states.has(str(d.id)):d.state=result.next_states[str(d.id)].duplicate(true)
		samples.append(float(Time.get_ticks_usec()-start)/1000.0)
	samples.sort()
	var mean:=0.0
	for sample in samples:mean+=sample/float(samples.size())
	var visuals:Array=[];var visual_start:=Time.get_ticks_usec()
	for kind in C.NEW_STORAGE_KINDS:
		var p:Dictionary=C.defaults(kind);p.visual_dimension_profile="metric_v1"
		var node=V.create(kind,p,false)
		visuals.append({"kind":kind,"nodes":count_nodes(node)})
		node.free()
	var summary:Dictionary={"mode":"headless CPU/object-memory only; not rendered FPS/VRAM","dispatch_devices":ds.size(),"dispatch_steps":samples.size(),"dispatch_mean_ms":mean,"dispatch_p50_ms":samples[250],"dispatch_p95_ms":samples[475],"dispatch_max_ms":samples[-1],"static_memory_before_bytes":memory_before,"static_memory_after_bytes":OS.get_static_memory_usage(),"six_visual_create_free_ms":float(Time.get_ticks_usec()-visual_start)/1000.0,"visuals":visuals}
	var f=FileAccess.open("res://evidence/storage_1003/headless_performance.json",FileAccess.WRITE);f.store_string(JSON.stringify(summary,"\t"));f.close()
	print(JSON.stringify(summary));quit()
func count_nodes(node:Node)->int:
	var total:=1
	for child in node.get_children():total+=count_nodes(child)
	return total
