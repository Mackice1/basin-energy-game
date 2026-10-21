extends SceneTree
## Uses the actual new process dispatcher, including supply limits and final buffers.
const Fixtures=preload("res://tests/test_chemical_process_physics.gd")
const C=preload("res://scripts/device_catalog.gd")
const M=preload("res://scripts/energy_model.gd")
const PanelUI=preload("res://scripts/optimization_panel.gd")
const Chart=preload("res://scripts/device_runtime_chart.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures.append(message);push_error("PHASE2C_DISPATCH_UI "+message)
func near(a:Variant,b:float,message:String):check((a is int or a is float) and absf(float(a)-b)<1e-8,message)
func _initialize():call_deferred("run")
func run():
	var fixture_builder:=Fixtures.new();var panel:=PanelUI.new();root.add_child(panel);var chart:=Chart.new()
	for kind in C.Materials.SYNTHESIS_KINDS:
		var fixture:Dictionary=fixture_builder.fixture(kind);var coefficients:Dictionary=C.Materials.chemical_coefficients(kind)
		var reports:Array=[]
		for seconds in [3600.0,1800.0]:
			var report:Dictionary=M.dispatch(fixture.devices,fixture.links,{}, {"1":{"mw":float(coefficients.electric_kwh_per_kg)/1000.0}},seconds)
			check(report.valid,"actual chemical report valid "+kind);if not report.valid:continue
			check(M.audit_dispatch(fixture.devices,fixture.links,report).is_empty(),"independent core report audit")
			for index in [3,4]:
				var device:Dictionary=fixture.devices[index];var data:Dictionary=report.devices[str(device.id)];var output:Dictionary=chart._extract(device,data)
				check(not output.is_empty() and output.unit=="kg/s","real feed/product accepted "+str(device.kind))
				var field:="product_produced_kg_s" if index==4 else ("nitrogen_out_kg_s" if coefficients.feed=="N2" else "co2_out_kg_s")
				near(output.values[0],data[field],"chart matches actual mass flow not electric MW")
				near(output.soc,float(data.next_inventory_kg)/C.inventory_capacity(device.kind,device.params)*100.0,"chart real last inventory percentage")
			var row:Dictionary=report.duplicate(true);row.dt_h=seconds/3600.0;row.time_s=0.0 if reports.is_empty() else 3600.0;row.export_mw=report.delivered_mw;row.energy_mwh=0.0;row.soc=0.0;reports.append(row)
			fixture_builder.advance(fixture,report)
		check(reports.size()==2,"both actual periods available")
		if reports.size()!=2:continue
		var result:Dictionary={"status":"optimal","steps":reports};var original:=result.duplicate(true)
		panel.set_material_context(fixture.devices);panel.show_result(result,result)
		check(panel._detail.text.contains("NH3(g)" if kind=="ammonia_synthesis_station" else "CH3OH(l)"),"correct product phase label")
		check(panel._material_summary.text.contains("化工用电") and panel._material_summary.text.contains("环境排热"),"electric MW separated from thermal MWth")
		check(panel._material_summary.text.contains("不重复累计") and panel._material_summary.text.contains("碳元素差") and panel._material_summary.text.contains("氮元素差"),"new species and subset accounting explicit")
		check(panel._comparison_note.text.contains("基线不强制期末氢目标，也不强制期末化工产品目标"),"baseline target limitation clear")
		for spec in PanelUI.CHEMICAL_RATES:
			near(panel._material_total(reports,spec[0]),reports[0].material[spec[0]]*3600.0+reports[1].material[spec[0]]*1800.0,"actual kg/s integrated using seconds "+str(spec[0]))
		for spec in PanelUI.CHEMICAL_STOCKS:near(panel._material_total(reports,spec[0]),reports[-1].material[spec[0]],"inventory only final snapshot "+str(spec[0]))
		near(panel._material_total(reports,"chemical_electric_mw"),reports[0].material.chemical_electric_mw+reports[1].material.chemical_electric_mw*.5,"chemical MW integrates hours")
		near(panel._material_total(reports,"hydrogen_leaked_kg"),reports[0].material.hydrogen_leaked_kg+reports[1].material.hydrogen_leaked_kg,"leaked kg not integrated twice")
		panel._select_step(1);check(panel._detail.text.contains("产品生成") and panel._detail.text.contains("有限 N2(g)" if coefficients.feed=="N2" else "有限 CO2(g)"),"source and product detail actual fields shown")
		check(result==original,"UI never mutates dispatch transaction")
		var incomplete:Array=reports.duplicate(true);incomplete[-1].material.erase("ammonia_inventory_kg")
		check(panel._material_total(incomplete,"ammonia_inventory_kg")==null,"missing snapshot not replaced by earlier/zero stock")
		fixture.devices[4].state.material_inventory_kg[coefficients.product]=C.inventory_capacity(kind,fixture.devices[4].params)
		var full:Dictionary=M.dispatch(fixture.devices,fixture.links,{}, {"1":{"mw":1.0}},3600.0)
		check(full.valid,"full-product dispatch valid")
		if full.valid:
			var stopped:Dictionary=chart._extract(fixture.devices[4],full.devices["5"])
			near(stopped.values[0],0.0,"full product buffer actual zero production")
			near(stopped.soc,100.0,"full buffer no automatic clearing")
	panel.free();chart.free();fixture_builder.free();await process_frame
	print("CHEMICAL_DISPATCH_PHASE2C_UI checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
