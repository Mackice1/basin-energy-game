extends SceneTree
const PanelUI=preload("res://scripts/optimization_panel.gd")
const Catalog=preload("res://scripts/device_catalog.gd")
const Model=preload("res://scripts/energy_model.gd")
const Materials=preload("res://scripts/material_dispatch.gd")
const Fixtures=preload("res://tests/test_material_physics.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures.append(message);push_error("MATERIAL_OPT_UI_FAIL "+message)
func near(a:Variant,b:float,message:String):check((a is float or a is int) and absf(float(a)-b)<1e-8,message)
func _initialize():call_deferred("run")
func settle():
	for i in 5:await process_frame
func run():
	var panel:=PanelUI.new();root.add_child(panel)
	var legacy:Dictionary=panel.get_options().duplicate(true)
	check(not legacy.has("terminal_hydrogen_kg"),"pure legacy option dictionary unchanged")
	var helper:=Fixtures.new();var fixture:Dictionary=helper.fixture();helper.free()
	for device in fixture.devices:device.params=Catalog.defaults(device.kind).merged(device.params,true)
	fixture.devices[4].params.leak_per_h=0.1;fixture.devices[4].state.material_inventory_kg.H2=100.0
	var context:Array=fixture.devices.duplicate(true)
	var extra:Dictionary=context[4].duplicate(true);extra.id=91;extra.params.capacity_kg=2000.0;context.append(extra)
	var before_context:Array=context.duplicate(true)
	panel.set_material_context(context)
	check(panel._material_controls.keys()==["5","91"],"only actual gas stores get stable-ID editors")
	check(panel.get_options().terminal_hydrogen_kg=={},"new targets disabled by default")
	check(not panel._tabs.is_tab_hidden(panel._material_tab_index),"material context shows material tab")
	panel._material_controls["5"].enabled.button_pressed=true
	panel._material_controls["5"].amount.get_line_edit().text="42.125"
	check(panel.get_options().terminal_hydrogen_kg=={"5":42.125},"single explicit per-store kg target commits entered text")
	check(context==before_context,"editing forecast targets never mutates source devices or inventory")
	panel.set_material_context(context)
	check(panel.get_options().terminal_hydrogen_kg=={"5":42.125},"same context preserves explicit target")
	panel.configure({"terminal_hydrogen_kg":{"5":10.0,"91":0.0}})
	check(panel.get_options().terminal_hydrogen_kg=={"5":10.0,"91":0.0},"configure supports zero and independent per-ID targets")
	panel.set_busy(true)
	check(panel._material_controls["5"].enabled.disabled and not panel._material_controls["5"].amount.editable,"busy disables hydrogen editing")
	panel.set_busy(false)
	panel._material_controls["91"].enabled.button_pressed=false
	check(not panel._material_controls["91"].amount.editable,"disabled target stays noneditable after busy")
	panel.set_material_context(fixture.devices)
	check(not panel._material_controls.has("91") and panel.get_options().terminal_hydrogen_kg=={"5":10.0},"deleted ID cannot remain in target options")
	var shrunk:Array=fixture.devices.duplicate(true);shrunk[4].params.capacity_kg=5.0
	panel.set_material_context(shrunk)
	check(panel.get_options().terminal_hydrogen_kg=={},"capacity shrink invalidates target rather than silently clamping it")
	panel.configure({"terminal_hydrogen_kg":{"5":NAN,"999":1.0}})
	check(panel.get_options().terminal_hydrogen_kg=={},"unknown and nonfinite targets cannot enter UI options")
	panel.set_material_context(fixture.devices)
	# Actual dispatch supplies all material report values; durations deliberately differ.
	var rows:Array=[];var t:=0.0;var expected_leak:=0.0;var expected_prod:=0.0;var expected_electric:=0.0;var expected_heat:=0.0
	for seconds in [900.0,1800.0,450.0]:
		var report:Dictionary=Model.dispatch(fixture.devices,fixture.links,{}, {"1":{"mw":1.0 if rows.is_empty() else 0.0}},seconds)
		check(report.valid,"real material dispatch valid")
		var row:Dictionary=report.duplicate(true);row.time_s=t;row.dt_h=seconds/3600.0;row.export_mw=report.delivered_mw;row.energy_mwh=0.0;row.soc=0.0
		rows.append(row);t+=seconds
		expected_leak+=report.material.hydrogen_leaked_kg;expected_prod+=report.material.hydrogen_produced_kg_s*seconds;expected_electric+=report.material.electrolyzer_electric_mw*seconds/3600.0;expected_heat+=report.material.heat_rejected_mwth*seconds/3600.0
		for device in fixture.devices:
			if report.next_states.has(str(device.id)):device.state=report.next_states[str(device.id)].duplicate(true)
		fixture.devices[6].params.demand_mw=0.25
	var result:Dictionary={"status":"optimal","steps":rows};var before_result:Dictionary=result.duplicate(true)
	panel.show_result(result,result)
	near(panel._material_total(rows,"hydrogen_leaked_kg"),expected_leak,"leak kg summed once, never multiplied by seconds or hours")
	near(panel._material_total(rows,"hydrogen_produced_kg_s"),expected_prod,"kg/s uses each actual duration in seconds")
	near(panel._material_total(rows,"electrolyzer_electric_mw"),expected_electric,"MW uses duration in hours")
	near(panel._material_total(rows,"heat_rejected_mwth"),expected_heat,"MWth remains independent heat integration")
	near(panel._material_total(rows,"hydrogen_inventory_kg"),rows[-1].material.hydrogen_inventory_kg,"inventory takes only final snapshot")
	near(panel._material_total(rows,"hydrogen_lhv_mwh"),rows[-1].material.hydrogen_lhv_mwh,"LHV inventory not accumulated as generated energy")
	check(panel._detail.text.contains("kg/s") and panel._detail.text.contains("MWh(LHV)（非电量）") and panel._detail.text.contains("本时段泄漏"),"details distinguish rate, stock and chemical indicator")
	check(panel._detail.text.contains("电解用电") and panel._detail.text.contains("环境排热") and panel._detail.text.contains("参考态焓差"),"electrical, thermal and conservation details retained")
	check(panel._detail.text.contains("电解制氢站 #4") and not panel._detail.text.contains("锅炉电输入"),"material devices get correct device-specific labels, not boiler labels")
	check(panel._comparison_note.text.contains("基线不强制期末氢目标"),"baseline terminal-target limitation explicit")
	check(panel._material_summary.text.contains("时段末氢库存"),"material tab displays actual selected report")
	panel._select_step(2)
	check(panel._material_summary.text.contains(panel._material_value(rows[2].material,"hydrogen_inventory_kg")),"step selection synchronizes material snapshot")
	check(result==before_result,"result and baseline data remain unchanged")
	var missing:Array=rows.duplicate(true);missing[1].material.erase("hydrogen_leaked_kg")
	check(panel._material_total(missing,"hydrogen_leaked_kg")==null,"missing material field yields unknown, not zero")
	missing[-1].material=null
	check(panel._material_total(missing,"hydrogen_inventory_kg")==null,"missing end snapshot safe")
	panel.show_result(result,{})
	var unknown_found:=false
	for index in range(0,panel._comparison.get_child_count(),4):
		if panel._comparison.get_child(index).text=="氢泄漏 / kg":unknown_found=panel._comparison.get_child(index+1).text=="—"
	check(unknown_found,"absent baseline does not fabricate material comparison")
	panel._material_controls["5"].enabled.button_pressed=true
	check(panel._steps.is_empty(),"changing hydrogen constraint invalidates earlier result")
	panel.show_result(result,result);panel.open();await settle()
	for size in [Vector2i(1000,740),Vector2i(700,580)]:
		panel.size=size;panel._tabs.current_tab=panel._material_tab_index;await settle()
		var scroll:ScrollContainer=panel._tabs.get_child(panel._material_tab_index)
		check(panel._run.get_global_rect().end.y<=panel.size.y and panel._run.get_global_rect().end.x<=panel.size.x,"fixed solve controls fit "+str(size))
		check(not scroll.get_h_scroll_bar().visible,"material settings fit width "+str(size))
		for controls in panel._material_controls.values():check(controls.amount.get_global_rect().end.x<panel.size.x,"kg target editor inside window")
		check(panel._tabs.size.y>=100,"tab scroll retains usable height")
	panel.set_material_context([])
	check(panel.get_options()==legacy and panel._material_controls.is_empty(),"returning to legacy scene removes material options and stale targets")
	check(panel._tabs.is_tab_hidden(panel._material_tab_index),"legacy context hides material controls")
	panel.configure({"terminal_hydrogen_kg":{"5":5.0}});panel.set_material_context(fixture.devices)
	check(panel.get_options().terminal_hydrogen_kg=={"5":5.0},"configure before context safely restores only matching installed target")
	panel._close();check(context==before_context and result==before_result,"close does not apply targets to realtime or result state")
	panel.set_material_context([{"id":77,"kind":"hydrogen_gas_store","params":{},"state":{"material_inventory_kg":{"H2":10.0}}}])
	check(panel._material_controls.has("77") and panel._material_controls["77"].amount.max_value==Catalog.defaults("hydrogen_gas_store").capacity_kg,"valid partial parameters use catalog capacity defaults")
	panel.set_material_context([{"id":78,"kind":"hydrogen_gas_store","params":{"capacity_kg":NAN}}])
	check(panel._material_controls.is_empty(),"invalid capacity cannot construct a NaN SpinBox")
	panel.free();await process_frame
	print("MATERIAL_OPTIMIZATION_PANEL_PHASE2 checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
