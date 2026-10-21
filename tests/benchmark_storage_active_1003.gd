extends SceneTree
## Warmed per-technology ACTIVE charge/discharge CPU smoke benchmark.
## Existing lithium is a same-build reference, NOT an untouched baseline build.
## No scene tree visuals, frame rendering, GLB work, FPS or VRAM claims.
const C = preload("res://scripts/device_catalog.gd")
const M = preload("res://scripts/energy_model.gd")
const WARMUP_CALLS := 50
const MEASURED_CALLS := 250
const STEP_SECONDS := 60.0
var failures: Array[String] = []
func dev(id: int, kind: String, overrides: Dictionary = {}) -> Dictionary:
	var p: Dictionary=C.defaults(kind); p.merge(overrides,true)
	var d: Dictionary={"id":id,"kind":kind,"params":p}
	if C.is_storage(kind): d.state=C.initial_state(kind,p)
	if C.is_thermal(kind): d.model_profile=C.model_profile(kind)
	return d
func cable(a: int,b: int,tp: String="in") -> Dictionary:
	return {"from":a,"to":b,"from_port":"out","to_port":tp,"carrier":C.CARRIER,"unit":"MW","capacity_mw":20.0,"loss_fraction":0.0}
func heat(a: int,b: int,fp: String="heat_out",tp: String="hot_in") -> Dictionary:
	return {"from":a,"to":b,"from_port":fp,"to_port":tp,"carrier":C.THERMAL_CARRIER,"grade_id":C.SECONDARY_GRADE if fp=="warm_out" else C.PRIMARY_GRADE,"unit":"MWth","capacity_mwth":20.0,"loss_fraction":0.0}
func fixture(kind: String) -> Dictionary:
	if kind=="solid_thermal_store":
		return {"devices":[dev(1,"wind"),dev(2,"station",{"capacity_mw":20.0,"loss_fraction":0.0}),dev(3,"electric_boiler"),dev(4,kind),dev(5,"heat_exchanger"),dev(6,"heat_demand",{"demand_mwth":5.0})],
			"links":[cable(1,2),cable(2,3,"ac_in"),heat(3,4,"heat_out","heat_in"),heat(4,5),heat(5,6,"warm_out","heat_in")],"storage_index":3,"load_index":5}
	return {"devices":[dev(1,"wind"),dev(2,"station",{"capacity_mw":20.0,"loss_fraction":0.0}),dev(3,kind),dev(4,"load",{"demand_mw":5.0})],
		"links":[cable(1,2),cable(2,3,"ac"),cable(2,4)],"storage_index":2,"load_index":3}
func bench(kind: String, charging: bool) -> Dictionary:
	var f:=fixture(kind)
	var thermal: bool=kind=="solid_thermal_store"
	var unit: String="mwhth" if thermal else "mwh"
	var power: String="mwth" if thermal else "mw"
	var storage: Dictionary=f.devices[f.storage_index]
	f.devices[f.load_index].params["demand_"+power]=0.0 if charging else 5.0
	var direct: Dictionary={"1":{"mw":5.0 if charging else 0.0}}
	var initial: float=0.0 if charging else float(storage.params["capacity_"+unit])*0.5
	var samples:=PackedFloat64Array(); samples.resize(MEASURED_CALLS)
	var active_count:=0
	var min_power:=INF
	var memory_before:=0
	var last: Dictionary={}
	for i in WARMUP_CALLS+MEASURED_CALLS:
		# Reset outside timed work so EVERY call exercises actual conversion.
		# These are repeated bounded one-step trials, not a long-horizon run.
		storage.state["energy_"+unit]=initial
		if i==WARMUP_CALLS: memory_before=OS.get_static_memory_usage()
		var started:=Time.get_ticks_usec()
		last=M.dispatch(f.devices,f.links,{},direct,STEP_SECONDS)
		var duration: float=float(Time.get_ticks_usec()-started)/1000.0
		if not last.valid:
			failures.append(kind+": invalid dispatch "+str(last.errors)+str(last.warnings))
			return {"kind":kind,"phase":"charge" if charging else "discharge","error":failures[-1]}
		var d: Dictionary=last.devices[str(int(storage.id))]
		var activity: float=float(d[("charge_" if charging else "discharge_")+power])
		if activity<=1e-9:
			failures.append(kind+": expected active conversion did not occur")
			return {"kind":kind,"error":failures[-1]}
		if i>=WARMUP_CALLS:
			samples[i-WARMUP_CALLS]=duration
			active_count+=1
			min_power=minf(min_power,activity)
	var memory_after:=OS.get_static_memory_usage()
	var audit: Array=M.audit_dispatch(f.devices,f.links,last)
	if not audit.is_empty(): failures.append(kind+": independent audit "+str(audit))
	samples.sort()
	var mean:=0.0
	for value in samples: mean+=value/MEASURED_CALLS
	return {"kind":kind,"phase":"charge" if charging else "discharge","devices":f.devices.size(),"warmup_calls":WARMUP_CALLS,"measured_calls":MEASURED_CALLS,"active_measured_calls":active_count,"minimum_active_power":min_power,"power_unit":"MWth" if thermal else "MW AC","mean_ms":mean,"p50_ms":samples[int(ceil(MEASURED_CALLS*0.50))-1],"p95_ms":samples[int(ceil(MEASURED_CALLS*0.95))-1],"max_ms":samples[-1],"static_memory_after_warmup_bytes":memory_before,"static_memory_after_measured_bytes":memory_after,"independent_last_step_audit_errors":audit}
func _initialize() -> void:
	var cases: Array=[]
	for kind in ["battery"]+C.NEW_STORAGE_KINDS:
		for charging in [true,false]: cases.append(bench(kind,charging))
	var summary: Dictionary={"mode":"headless warmed active one-step dispatch CPU smoke; no rendering or visual creation","same_build_reference":"battery is legacy lithium implementation in this development build, not an untouched baseline build","method":"50 untimed warmups then 250 measured calls per kind/mode; original inventory reset outside timer to empty for charge or half-full for discharge; 60 simulated seconds per call; built-in runtime audit included, external independent audit outside timer","limitations":"No FPS, GPU, VRAM, peak-memory, leak, scaling, or baseline performance-regression claim. Static memory samples are diagnostic allocator snapshots, not retained-memory/leak proof. Thermal and electrical fixtures have different device counts.","cases":cases,"failures":failures,"all_active":failures.is_empty()}
	DirAccess.make_dir_recursive_absolute("res://evidence/storage_1003")
	var file:=FileAccess.open("res://evidence/storage_1003/headless_active_per_kind.json",FileAccess.WRITE)
	if file==null: printerr("Could not write benchmark result");quit(1);return
	file.store_string(JSON.stringify(summary,"  "));file.close()
	print(JSON.stringify(summary))
	quit(0 if failures.is_empty() else 1)
