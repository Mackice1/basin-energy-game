extends SceneTree
## Real dispatch reports, not synthetic presentation samples, drive phase readouts.
const Fixtures=preload("res://tests/test_phase_hydrogen_physics.gd")
const C=preload("res://scripts/device_catalog.gd")
const M=preload("res://scripts/energy_model.gd")
const PanelUI=preload("res://scripts/optimization_panel.gd")
const Chart=preload("res://scripts/device_runtime_chart.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures.append(message);push_error("PHASE2B_DISPATCH_UI "+message)
func near(a:Variant,b:float,message:String):check((a is int or a is float) and absf(float(a)-b)<1e-8,message)
func _initialize():call_deferred("run")
func run():
	var fixtures:=Fixtures.new();var panel:=PanelUI.new();root.add_child(panel);var chart:=Chart.new()
	for kind in C.Materials.PHASE_KINDS:
		var fixture:Dictionary=fixtures.fixture(kind)
		var coefficients:Dictionary=C.Materials.phase_coefficients(kind)
		var reports:Array=[];var time:=0.0
		var power:float=(50.0+float(coefficients.charge_kwh_per_kg))/1000.0
		var report:Dictionary=M.dispatch(fixture.devices,fixture.links,{}, {"1":{"mw":power}},3600.0)
		check(report.valid,"actual charge report valid "+kind)
		if not report.valid:continue
		var charge:Dictionary=chart._extract(fixture.devices[4],report.devices["5"])
		check(not charge.is_empty() and charge.unit=="kg/s","actual report accepted by chart "+kind)
		near(charge.values[0],report.devices["5"].hydrogen_in_kg_s,"chart reflects actual charge kg/s")
		near(charge.soc,report.devices["5"].next_inventory_kg/C.inventory_capacity(kind,fixture.devices[4].params)*100.0,"actual phase SOC from derived capacity")
		var row:Dictionary=report.duplicate(true);row.dt_h=1.0;row.time_s=time;row.export_mw=report.delivered_mw;row.energy_mwh=0.0;row.soc=0.0;reports.append(row);time+=3600
		fixtures.advance(fixture,report);fixture.devices[7].state.energy_mwh=0.1;fixture.devices[6].params.demand_mw=1.0
		report=M.dispatch(fixture.devices,fixture.links,{}, {"1":{"mw":0.0}},1800.0)
		check(report.valid,"actual battery-powered discharge report valid "+kind)
		if not report.valid:continue
		var discharge:Dictionary=chart._extract(fixture.devices[4],report.devices["5"])
		check(discharge.values[1]>0.0 and discharge.values[0]==0.0,"actual discharge chart uses kg/s, not auxiliary MW")
		near(discharge.soc,report.devices["5"].next_inventory_kg/C.inventory_capacity(kind,fixture.devices[4].params)*100.0,"actual discharge SOC")
		row=report.duplicate(true);row.dt_h=.5;row.time_s=time;row.export_mw=report.delivered_mw;row.energy_mwh=0.0;row.soc=0.0;reports.append(row)
		var result:Dictionary={"status":"optimal","steps":reports};var before:Dictionary=result.duplicate(true)
		panel.set_material_context(fixture.devices);panel.show_result(result,result)
		check(panel._detail.text.contains("液氢储罐站" if kind=="hydrogen_liquid_store" else "LaNi5 固态储氢站"),"real device name, not generic energy store")
		check(panel._material_summary.text.contains("液态/固态储氢用电") and panel._material_summary.text.contains("环境吸热"),"auxiliary electricity and environmental heat separate")
		check(panel._material_summary.text.contains("参考态账本，非可用电量/热库存"),"signed phase enthalpy never labelled as useful energy")
		check(panel._material_summary.text.contains("液氢库存") and panel._material_summary.text.contains("LaNi5 结合氢库存"),"phase-resolved kg inventory retained")
		near(panel._material_total(reports,"phase_store_electric_mw"),reports[0].material.phase_store_electric_mw+reports[1].material.phase_store_electric_mw*.5,"MW integration uses actual duration hours")
		near(panel._material_total(reports,"environment_heat_in_mwth"),reports[0].material.environment_heat_in_mwth+reports[1].material.environment_heat_in_mwth*.5,"environmental MWth distinct integral")
		near(panel._material_total(reports,"phase_enthalpy_mwh"),reports[-1].material.phase_enthalpy_mwh,"phase enthalpy inventory is last snapshot")
		near(panel._material_total(reports,"phase_enthalpy_change_mwh"),reports[0].material.phase_enthalpy_change_mwh+reports[1].material.phase_enthalpy_change_mwh,"phase changes sum once without integration")
		near(panel._material_total(reports,"hydrogen_leaked_kg"),reports[0].material.hydrogen_leaked_kg+reports[1].material.hydrogen_leaked_kg,"leak kg not integrated again")
		panel._select_step(1)
		if kind=="hydrogen_metal_hydride_store":check(panel._detail.text.contains("固定宿主干质量"),"immutable host shown separately from hydrogen")
		check(result==before,"presentation never changes dispatch reports")
		var incomplete:Array=reports.duplicate(true);incomplete[1].material.erase("phase_enthalpy_mwh")
		check(panel._material_total(incomplete,"phase_enthalpy_mwh")==null,"missing phase inventory not fabricated")
	panel.free();chart.free();fixtures.free();await process_frame
	print("HYDROGEN_DISPATCH_PHASE2B_UI checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
