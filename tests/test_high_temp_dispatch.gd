extends SceneTree
const Model = preload("res://scripts/energy_model.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
const High = preload("res://scripts/high_temp_thermal.gd")
var checks: int = 0
var failures: Array[String] = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
		printerr("HIGH_TEMP_FAIL: " + label)
func near(a: float, b: float, label: String) -> void:
	check(absf(a-b)<1e-8, label + " " + str(a) + " != " + str(b))
func dev(id: int, kind: String, params: Dictionary = {}) -> Dictionary: return {"id": id, "kind": kind, "params": params}
func el(a: int, b: int, aux: bool = false) -> Dictionary:
	var r: Dictionary = {"from": a, "to": b, "capacity_mw": 10.0, "loss_fraction": 0.0}
	if aux: r.merge({"from_port": "out", "to_port": "ac_in", "carrier": "electricity_ac", "unit": "MW"})
	return r
func hl(a: int, b: int, carrier: String, grade: String, source: String = "heat_out", target: String = "hot_in") -> Dictionary:
	return {"from": a, "to": b, "from_port": source, "to_port": target, "carrier": carrier, "unit": "MWth", "grade_id": grade, "capacity_mwth": 10.0, "loss_fraction": 0.0}
func ds() -> Array: return [dev(1,"wind"),dev(2,"station",{"loss_fraction":0.0}),dev(3,"parabolic_trough"),dev(4,"oil_water_exchanger"),dev(5,"heat_exchanger"),dev(6,"heat_demand",{"demand_mwth":1.0})]
func ls() -> Array: return [el(1,2),el(2,3,true),el(2,4,true),hl(3,4,"heat_oil","oil_300_200"),hl(4,5,"heat_water",Catalog.PRIMARY_GRADE,"warm_out"),hl(5,6,"heat_water",Catalog.SECONDARY_GRADE,"warm_out","heat_in")]
func weather() -> Dictionary: return {"dni_wm2":800.0,"solar_altitude_deg":90.0,"solar_azimuth_deg":180.0,"air_temp_c":20.0,"is_day":true}
func run_case(d: Array, l: Array, w: Dictionary, power: float = 1.0, dt: float = 3600.0) -> Dictionary:
	var r: Dictionary = Model.dispatch(d,l,w,{"1":{"mw":power}},dt)
	check(r.valid,"valid runtime " + str(r.errors) + str(r.warnings))
	check(Model.audit_dispatch(d,l,r,{},w).is_empty(),"replay " + str(Model.audit_dispatch(d,l,r,{},w)))
	for x in [r.balance_error_mw,r.thermal.balance_error_mwth,r.high_temp.balance_error_mwth,r.high_temp.energy_balance_error_mwhth,r.thermal.energy_balance_error_mwhth,r.cross_carrier_balance_error_mw]: near(x,0,"balance")
	return r
func _initialize() -> void:
	var w: Dictionary = weather()
	near(High.evaluate({},w).available_mwth,.0392189208,"source reference")
	var d: Array = ds()
	var l: Array = ls()
	var r: Dictionary = run_case(d,l,w)
	near(r.high_temp.useful_mwth,.0392189208,"collected")
	near(r.thermal.served_mwth,.0392189208*.98*.98,"both exchangers")
	near(r.high_temp.auxiliary_electric_mw,.0392189208*.03,"both auxiliaries")
	for key in High.empty():
		var tamper: Dictionary = r.duplicate(true)
		tamper.high_temp[key] += .1
		check(not Model.audit_dispatch(d,l,tamper,{},w).is_empty(),"tamper aggregate " + key)
	for key in ["dni_wm2","cos_incidence","incident_mw","available_mwth","useful_mwth","auxiliary_electric_mw"]:
		var tamper: Dictionary = r.duplicate(true)
		tamper.devices["3"][key] += .1
		check(not Model.audit_dispatch(d,l,tamper,{},w).is_empty(),"tamper source " + key)
	for field in ["from_port", "to_port", "grade_id", "carrier"]:
		var tamper: Dictionary = r.duplicate(true)
		tamper.lines[3][field] = "incorrect"
		check(not Model.audit_dispatch(d,l,tamper,{},w).is_empty(),"edge metadata tamper " + field)
	check(not Model.audit_dispatch(d,l,r).is_empty(),"original weather required")
	for key in ["dni_wm2","solar_altitude_deg","solar_azimuth_deg","air_temp_c"]:
		var bad: Dictionary = w.duplicate(true)
		bad.erase(key)
		check(not Model.dispatch(d,l,bad,{"1":{"mw":1.0}},3600).valid,"missing " + key)
		bad=w.duplicate(true);bad[key]=NAN
		check(not High.evaluate({},bad).valid,"nonfinite " + key)
	for dni in [-1.0,2001.0]:
		var bad: Dictionary=w.duplicate(true);bad.dni_wm2=dni
		check(not High.evaluate({},bad).valid,"invalid DNI")
	for key in ["is_day","solar_altitude_deg"]:
		var night: Dictionary=w.duplicate(true);night[key]=false if key=="is_day" else 0.0
		r=run_case(d,l,night)
		near(r.high_temp.useful_mwth,0,"night no source")
	r=run_case(d,l,w,0)
	near(r.high_temp.useful_mwth,0,"no AC")
	for remove in [1,2]:
		var links: Array=l.duplicate(true);links.remove_at(remove)
		r=run_case(d,links,w)
		near(r.high_temp.useful_mwth,0,"missing one auxiliary atomic")
		near(r.high_temp.auxiliary_electric_mw,0,"no stranded auxiliary")
	# High inventory charges with collection auxiliary and cannot be water inventory.
	d.append(dev(7,"high_temp_store",{"initial_soc":0.0}));l.append(hl(3,7,"heat_oil","oil_300_200","heat_out","heat_in"))
	d[5].params.demand_mwth=0.0
	r=run_case(d,l,w)
	near(r.high_temp.charge_mwth,r.high_temp.useful_mwth,"oil charge")
	near(r.thermal.energy_mwhth,0,"independent water inventory")
	near(r.high_temp.energy_mwhth,r.high_temp.charge_mwth*.98,"oil charging efficiency")
	d[6].params.initial_soc=1.0;d[6].params.self_discharge_per_h=0.0
	r=run_case(d,l,w)
	near(r.high_temp.useful_mwth,0,"full store")
	# Isolated night storage delivery still requires independent oil circulation AC.
	d[5].params.demand_mwth=1.0;l.append(hl(7,4,"heat_oil","oil_300_200"))
	var night: Dictionary=w.duplicate(true);night.is_day=false
	r=run_case(d,l,night)
	near(r.high_temp.discharge_mwth,.1,"stored heat bounded rate")
	near(r.high_temp.oil_auxiliary_electric_mw,.001,"storage circulation")
	near(r.high_temp.energy_mwhth,.2-.1/.98,"finite stored enthalpy")
	r=run_case(d,l,night,0)
	near(r.high_temp.discharge_mwth,0,"no AC no stored discharge")
	r=run_case(d,l,w,1,0)
	near(r.high_temp.charge_mwth+r.high_temp.discharge_mwth,0,"pause inventory freeze")
	# Port grade reversals/mixing are invalid.
	var badlink: Dictionary=hl(3,5,"heat_oil","oil_300_200")
	check(not Catalog.validate_link(d,[],badlink).is_empty(),"no oil directly into water HX")
	badlink=hl(5,7,"heat_water",Catalog.SECONDARY_GRADE,"warm_out","heat_in")
	check(not Catalog.validate_link(d,[],badlink).is_empty(),"no secondary upgrades")
	for i in 35:
		d=ds();l=ls();d[1].params.capacity_mw=.0001+float(i)*.00002
		d[3].params.capacity_mwth=.002+float(i)*.001
		l[4].capacity_mwth=.003+float(i)*.0004
		r=run_case(d,l,w)
		check(r.devices["2"].input_mw <= float(d[1].params.capacity_mw)+1e-9,"shared electric bottleneck")
		check(r.devices["4"].input_mwth<=float(d[3].params.capacity_mwth)+1e-9,"oilHX cap")
		check(r.lines[4].sent_mwth <= float(l[4].capacity_mwth)+1e-9,"middle water line cap")
	# Shared upstream row must pay both pumps, not grant each its full capacity.
	d=ds();l=ls();l[0].capacity_mw=.0003
	r=run_case(d,l,w)
	near(r.high_temp.useful_mwth,.01,"shared upstream both pumps sum")
	near(r.devices["3"].auxiliary_electric_mw,.0002,"collector share")
	near(r.devices["4"].auxiliary_electric_mw,.0001,"exchanger share")
	# No solar needed for inventory, but exchanger AC cable is mandatory at night.
	d.append(dev(7,"high_temp_store",{"initial_soc":1.0}));l.append(hl(7,4,"heat_oil","oil_300_200"));l.remove_at(2)
	r=run_case(d,l,night)
	near(r.high_temp.discharge_mwth,0,"night disconnected oilHX pump")
	near(r.thermal.served_mwth,0,"night no hidden circulating source")
	# Existing water solar/boilers share the same final exchanger resource row.
	d=ds();l=ls();d[4].params.capacity_mwth=.06
	d.append(dev(7,"solar_thermal"));d.append(dev(8,"electric_boiler"))
	l += [el(2,7,true),el(2,8,true),hl(7,5,"heat_water",Catalog.PRIMARY_GRADE),hl(8,5,"heat_water",Catalog.PRIMARY_GRADE)]
	var mixed: Dictionary=w.duplicate(true);mixed.irradiance_wm2=800.0
	r=run_case(d,l,mixed)
	near(r.devices["5"].input_mwth,.06,"shared final HX all source types")
	near(r.thermal.served_mwth,.06*.98,"mixed delivery")
	# An independent stored oil circuit remains valid without any trough/weather.
	d=ds();l=ls();d[2]=dev(3,"high_temp_store",{"initial_soc":1.0});l.remove_at(1)
	r=run_case(d,l,{})
	near(r.high_temp.discharge_mwth,.1,"oil store standalone")
	var malformed: Dictionary=r.duplicate(true);malformed.devices["4"].auxiliary_electric_mw=0.0
	check(not Model.audit_dispatch(d,l,malformed,{},{}).is_empty(),"oil pump tamper rejected")
	check(High.validate_energy(High.initial_energy()).is_empty(),"empty cumulative valid")
	var snap: Dictionary=Model.optimization_snapshot(ds(),ls(),w,{},3600)
	check(snap.valid,"snapshot valid")
	check(snap.forecasts.weather==w,"snapshot original weather")
	check(snap.constraints.thermal_paths.size()==1,"multiedge path")
	print("HIGH_TEMP_DISPATCH_TESTS: %d checks, %d failures" % [checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
