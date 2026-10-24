extends SceneTree
const Workflow=preload("res://scripts/example_base_workflow.gd")
const Model=preload("res://scripts/energy_model.gd")
const Catalog=preload("res://scripts/device_catalog.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize():
	var f:=Workflow.fixture()
	check(f.devices.size()==8 and f.links.size()==9,"complete small base")
	var imports:=Workflow.real_imports()
	check(imports.size()==3,"live historical import records")
	for series in imports:check(Workflow.Series.validate_series(series).is_empty(),"validated historical series")
	var prior:=f.duplicate(true)
	for line in f.links:check(Catalog.validate_link(f.devices,[],line).is_empty(),"typed link valid "+str(line))
	var r:=Model.dispatch(f.devices,f.links,Workflow.weather_at(43200),{},1.0)
	check(r.valid,"live dispatch valid "+str(r.get("errors")))
	check(Model.audit_dispatch(f.devices,f.links,r).is_empty(),"original model independent audit")
	check(r.material.hydrogen_produced_kg_s>=0,"actual hydrogen rate nonnegative")
	check(r.charge_mw>0,"actually charges battery")
	check(r.delivered_mw>=0,"actual export nonnegative; no synthetic guarantee")
	check(not Workflow.explain(r,f.devices).is_empty(),"truthful runtime explanation")
	var timing:=Time.get_ticks_msec()
	var comparison:=Workflow.compare_capacity(f.devices,f.links)
	print("COMPARE_MS ",Time.get_ticks_msec()-timing)
	check(comparison.valid,"comparison valid "+str(comparison.get("error","")))
	if comparison.valid:
		for c in comparison.cases:
			print("CASE ",JSON.stringify(c))
			check(c.generated_mwh>0 and c.served_mwh>0 and c.hydrogen_produced_kg>0,"real positive operation")
			check(c.max_balance_error_mw<1e-7,"power balance closes")
			check(c.water_used_kg>0 and c.water_final_kg>=0,"finite water accounted")
			check(c.battery_final_mwh>=0 and c.battery_final_mwh<=c.battery_capacity_mwh,"finite battery")
		check(absf(comparison.cases[0].unserved_mwh-comparison.cases[2].unserved_mwh)<1e-7,"historical first day does not invent shortage benefit")
		check(comparison.cases[0].exported_mwh>comparison.cases[2].exported_mwh and comparison.cases[0].battery_final_mwh<comparison.cases[2].battery_final_mwh,"capacity changes actual allocation and final inventory")
		check(not comparison.cost_modeled,"no invented cost")
	check(f==prior,"no live mutation")
	var job:=Workflow.begin_comparison(f.devices,f.links)
	if not job.valid:
		check(false,"batch job cannot initialize "+str(job));quit(1);return
	var t0:=Time.get_ticks_msec()
	Workflow.step_comparison(job,8)
	print("BATCH8_MS ",Time.get_ticks_msec()-t0)
	check(job.valid and not job.done and job.jobs[0].t==2400.0,"bounded UI batch")
	check(f==prior,"cancel/drop partial job leaves live scene untouched")
	while not job.done:Workflow.step_comparison(job,8)
	check(job.result==comparison,"batched and synchronous results identical")
	var bad:=f.duplicate(true);bad.devices[4].params.capacity_mwh=20.0
	check(not Workflow.compare_capacity(bad.devices,bad.links).valid,"reject unsupported doubled capacity")
	check(not Workflow.compare_capacity([],[]).valid,"reject empty comparison")
	check(not Workflow.compare_capacity(f.devices,f.links,0).valid,"reject zero step")
	var fine:=Workflow.simulate(f.devices,f.links,1.0,60.0)
	check(fine.valid,"60second convergence run valid")
	if fine.valid and comparison.valid:
		for key in ["served_mwh","unserved_mwh","exported_mwh","curtailed_mwh","hydrogen_produced_kg","water_used_kg"]:
			var delta:float=absf(fine[key]-comparison.cases[1][key])
			print("STEP_CHECK ",key," delta=",delta)
			check(delta<=maxf(0.01,0.01*absf(fine[key])),"300s vs60s historical-case difference <=1% "+key)
	print("EXAMPLE_WORKFLOW checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
