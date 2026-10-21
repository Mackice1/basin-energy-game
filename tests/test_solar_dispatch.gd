extends SceneTree
const Model = preload("res://scripts/energy_model.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
const Solar = preload("res://scripts/solar_thermal.gd")
var checks: int = 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("SOLAR_FAIL: " + label)
func near(a: float, b: float, label: String) -> void:
	check(absf(a-b) < 1e-8, label + " " + str(a) + " != " + str(b))
func dev(id: int, kind: String, params: Dictionary = {}) -> Dictionary:
	return {"id": id, "kind": kind, "params": params}
func el(a: int, b: int, aux: bool = false) -> Dictionary:
	var result: Dictionary = {"from": a, "to": b, "capacity_mw": 10.0, "loss_fraction": 0.0}
	if aux: result.merge({"from_port": "out", "to_port": "ac_in", "carrier": "electricity_ac", "unit": "MW"})
	return result
func hl(a: int, b: int, source: String = "heat_out", target: String = "hot_in") -> Dictionary:
	return {"from": a, "to": b, "from_port": source, "to_port": target, "carrier": "heat_water", "unit": "MWth", "grade_id": Catalog.SECONDARY_GRADE if source == "warm_out" else Catalog.PRIMARY_GRADE, "capacity_mwth": 10.0, "loss_fraction": 0.0}
func ds() -> Array:
	return [dev(1,"wind"),dev(2,"station",{"loss_fraction":0.0}),dev(3,"solar_thermal"),dev(4,"heat_exchanger"),dev(5,"heat_demand",{"demand_mwth":1.0})]
func ls() -> Array:
	return [el(1,2),el(2,3,true),hl(3,4),hl(4,5,"warm_out","heat_in")]
func weather() -> Dictionary:
	return {"irradiance_wm2":800.0,"air_temp_c":25.0,"irradiance_kind":"teaching_equivalent_poa"}
func run_case(devices: Array, links: Array, w: Dictionary, power: float = 1.0, dt: float = 3600.0) -> Dictionary:
	var r: Dictionary = Model.dispatch(devices,links,w,{"1":{"mw":power}},dt)
	check(r.valid,"valid runtime " + str(r.errors) + str(r.warnings))
	check(Model.audit_dispatch(devices,links,r,{},w).is_empty(),"replay audit")
	near(r.balance_error_mw,0,"electric balance")
	near(r.thermal.balance_error_mwth,0,"heat balance")
	near(r.energy_balance_error_mwh,0,"electric inventory")
	near(r.thermal.energy_balance_error_mwhth,0,"heat inventory")
	return r
func _initialize() -> void:
	var w: Dictionary = weather()
	var physics: Dictionary = Solar.evaluate({},w)
	near(physics.available_mwth,30.3*(.785*800-1.42*50-.005*2500)/1e6,"absorber curve")
	near(physics.incident_mw,30.3*800/1e6,"incident")
	near(physics.incident_mw,physics.optical_rejection_mw+physics.thermal_loss_mw+physics.available_mwth,"optical thermal separation")
	var d: Array = ds()
	var l: Array = ls()
	var r: Dictionary = run_case(d,l,w)
	near(r.solar.useful_mwth,physics.available_mwth,"full collector output")
	near(r.solar.auxiliary_electric_mw,r.solar.useful_mwth*.02,"aux per useful heat")
	for key in Solar.FIELDS:
		var tamper: Dictionary = r.duplicate(true)
		tamper.devices["3"][key] += .1
		check(not Model.audit_dispatch(d,l,tamper,{},w).is_empty(),"tamper device " + key)
		tamper = r.duplicate(true)
		tamper.solar[key] += .1
		check(not Model.audit_dispatch(d,l,tamper,{},w).is_empty(),"tamper aggregate " + key)
	check(not Model.audit_dispatch(d,l,r).is_empty(),"original weather required")
	var alternate: Dictionary = w.duplicate(true)
	alternate.irradiance_wm2 = 100.0
	check(not Model.audit_dispatch(d,l,r,{},alternate).is_empty(),"weather independently recomputed")
	for irradiance in [0.0,10.0,100.0,800.0,1200.0]:
		for temp in [-30.0,25.0,75.0,100.0]:
			var sample: Dictionary = {"irradiance_wm2":irradiance,"air_temp_c":temp}
			r = run_case(d,l,sample)
			check(r.solar.available_mwth <= r.solar.incident_mw,"never exceeds incident")
			if irradiance == 0.0: near(r.solar.useful_mwth,0,"night no heat")
	r = run_case(d,l,w,0)
	near(r.solar.useful_mwth,0,"no auxiliary no heat")
	near(r.solar.curtailed_mwth,r.solar.available_mwth,"no aux all potential curtailed")
	r = run_case(d,l,w,.0001)
	near(r.solar.useful_mwth,.005,"aux limited")
	d[4].params.demand_mwth=.001
	r = run_case(d,l,w)
	near(r.thermal.served_mwth,.001,"finite demand")
	near(r.solar.useful_mwth,.001/.98,"HX counted")
	d[4].params.demand_mwth=0.0
	r = run_case(d,l,w)
	near(r.solar.auxiliary_electric_mw,0,"zero demand pump off")
	r = run_case(ds(),[l[0],l[2],l[3]],w)
	near(r.solar.useful_mwth,0,"unwired pump off")
	r = run_case(ds(),[l[0],l[1]],w)
	near(r.solar.auxiliary_electric_mw,0,"unwired heat pump off")
	# Finite storage, no discharge cycling, no battery-to-heat speculative charge.
	d=ds();l=ls();d[4].params.demand_mwth=0.0
	d.append(dev(6,"thermal_store",{"capacity_mwhth":1.0,"initial_soc":.999}))
	l.append(hl(3,6,"heat_out","heat_in"))
	r=run_case(d,l,w)
	check(r.solar.useful_mwth < r.solar.available_mwth,"nearly full store finite")
	d[5].params.initial_soc=1.0;d[5].params.self_discharge_per_h=0.0
	r=run_case(d,l,w)
	near(r.solar.auxiliary_electric_mw,0,"full store pump off")
	d[5].params.initial_soc=0.0
	r=run_case(d,l,w,1.0,0.0)
	near(r.solar.auxiliary_electric_mw,0,"paused store pump off")
	# Battery supports demand but never collection solely for heat storage.
	d=ds();d[0]=dev(1,"battery");l=ls()
	r=run_case(d,l,w,0.0)
	near(r.solar.useful_mwth,r.solar.available_mwth,"battery auxiliary serves heat demand")
	d[4].params.demand_mwth=0.0;d.append(dev(6,"thermal_store",{"initial_soc":0.0}));l.append(hl(3,6,"heat_out","heat_in"))
	r=run_case(d,l,w,0.0)
	near(r.solar.useful_mwth,0,"battery auxiliary cannot charge heat store")
	# Solar merit order ahead of electric boilers without altering no-solar policy.
	d=ds();l=ls();d[4].params.demand_mwth=.001;d.append(dev(6,"electric_boiler"));l += [el(2,6,true),hl(6,4)]
	r=run_case(d,l,w)
	near(r.boiler_electric_mw,0,"solar before electric boiler")
	var snapshot: Dictionary = Model.optimization_snapshot(ds(),ls(),w,{},3600)
	check(snapshot.valid,"valid solar snapshot")
	var found: bool = false
	for device in snapshot.devices:
		if device.kind=="solar_thermal":
			found=true
			near(device.available_mwth,physics.available_mwth,"snapshot bound")
	check(found,"snapshot contains collector")
	check(Solar.validate_energy(Solar.initial_energy()).is_empty(),"empty history valid")
	check(not Solar.evaluate({}, {"irradiance_wm2":800,"irradiance_kind":"dni"}).valid,"DNI rejected")
	check(not Solar.evaluate({}, {"irradiance_wm2":NAN}).valid,"NaN rejected")
	check(not Solar.evaluate({}, {"irradiance_wm2":800.0,"is_day":0}).valid,"nonboolean day flag rejected")
	near(Solar.evaluate({}, {"irradiance_wm2":800.0,"is_day":false}).available_mwth,0,"night flag gates irradiance")
	# Scarce shared electric/heat resource rows, multiple collectors and priorities.
	for iteration in 80:
		d=ds();l=ls()
		d.append(dev(6,"solar_thermal",{"absorber_area_m2":30.3+float(iteration)}))
		l += [el(2,6,true),hl(6,4)]
		d[1].params.capacity_mw=.0001+float(iteration)*.00001
		d[4].params.demand_mwth=.0005+float(iteration)*.0002
		l[2].capacity_mwth=.003
		r=run_case(d,l,w,.0002+float(iteration)*.00001)
		check(r.devices["2"].input_mw <= d[1].params.capacity_mw+1e-9,"shared station cap")
		check(r.lines[2].sent_mwth <= .003+1e-9,"heat line cap")
		for id in ["3","6"]:
			check(r.devices[id].useful_mwth <= r.devices[id].available_mwth+1e-9,"collector never double spends")
	print("SOLAR_DISPATCH_TESTS: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
