extends SceneTree
## Headless native-control acceptance, never opens the desktop or edits a save.
const Form=preload("res://scripts/parameter_form.gd")
const Bulk=preload("res://scripts/bulk_parameter_editor.gd")
const PanelUI=preload("res://scripts/optimization_panel.gd")
const RuntimeChart=preload("res://scripts/device_runtime_chart.gd")
const C=preload("res://scripts/device_catalog.gd")
const Previous=preload("res://tests/test_hydrogen_storage_phase2b_ui.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures.append(message);push_error("PHASE2C_UI "+message)
func near(a:Variant,b:float,message:String):check((a is float or a is int) and absf(float(a)-b)<1e-8,message)
func _initialize():call_deferred("run")
func settle():
	for i in 4:await process_frame
func item(kind:String,id:int)->Dictionary:
	var p:Dictionary=C.defaults(kind)
	return {"id":id,"kind":kind,"x":float(id)*30.0,"z":0.0,"params":p,"state":C.initial_state(kind,p)}
func run():
	root.gui_embed_subwindows=true;root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1180,812)
	var form:=Form.new();var theme:=Theme.new();theme.default_font=load("res://assets/InterfaceCJK.ttc");form.theme=theme;form.size=Vector2(1140,552);root.add_child(form);await settle()
	var maximums:Dictionary=C.Materials.chemical_profile().maximums
	for kind in C.Materials.CHEMICAL_KINDS:
		var p:Dictionary=C.defaults(kind);var original:=p.duplicate(true)
		for construction in [true,false]:
			form.set_parameters(kind,p,construction)
			check(form._fields.size()==p.size(),kind+" every accepted parameter labelled")
			check(form.get_parameters()==p and form.get_validation_errors().is_empty(),kind+" exact valid defaults")
			check(form._fields.initial_inventory_kg.editable==(construction and kind in C.Materials.FEED_KINDS),kind+" initial stock construction-only or fixed zero")
			form._fields.initial_inventory_kg.text="5"
			near(form.get_parameters().initial_inventory_kg,5.0 if construction and kind in C.Materials.FEED_KINDS else p.initial_inventory_kg,kind+" injected inventory text guarded")
			for key in ["phase_id","technology","reaction_enthalpy","heater_efficiency","product_species"]:check(not form._fields.has(key),kind+" no fixed-profile switch "+key)
		for key in p:
			if key=="initial_inventory_kg":continue
			form.set_parameters(kind,p,true);var invalid:=float(maximums[kind][key])+1.0;form._fields[key].text=str(invalid)
			check(not form.get_validation_errors().is_empty(),"hardcap rejected "+kind+key)
			near(form.get_parameters()[key],invalid,"invalid value is not silently clamped")
			form._fields[key].text="NaN";check(not form.get_validation_errors().is_empty(),"nonfinite draft rejected")
		if kind in C.Materials.FEED_KINDS:
			form.set_parameters(kind,p,true);form._fields.initial_inventory_kg.text="1001";check(not form.get_validation_errors().is_empty(),"feed initial cannot exceed capacity")
		for resolution in [Vector2i(1180,812),Vector2i(640,480)]:
			root.size=resolution;form.position=Vector2(20,100);form.size=Vector2(resolution.x-40,resolution.y-260);form.set_parameters(kind,p,false);await settle()
			check(form.size.x<=resolution.x-40 and form.size.y<=resolution.y-260,"form within bounds "+kind+str(resolution))
			for editor in form._fields.values():
				form._scroll.ensure_control_visible(editor);await settle()
				var viewport:=form._scroll.get_global_rect();viewport.size.x-=form._scroll.get_v_scroll_bar().size.x if form._scroll.get_v_scroll_bar().visible else 0.0;viewport.size.y-=form._scroll.get_h_scroll_bar().size.y if form._scroll.get_h_scroll_bar().visible else 0.0
				check(viewport.grow(1.0).encloses(editor.get_global_rect()),"numeric field reachable "+kind+str(resolution))
				check(editor.get_theme_font_size("font_size")==18 and editor.size.x>=125 and editor.size.y>=40,"readable field hierarchy")
		check(p==original,"source params unchanged")
	form.free();root.size=Vector2i(1180,812)
	var host:=Previous.Host.new();root.add_child(host)
	for index in C.Materials.CHEMICAL_KINDS.size():host.devices.append(item(C.Materials.CHEMICAL_KINDS[index],index+1))
	var before:Array=host.devices.duplicate(true)
	var bulk:=Bulk.new();root.add_child(bulk);bulk.setup(host)
	for kind in C.Materials.CHEMICAL_KINDS:
		bulk.select_kind(kind);bulk.select_all();bulk.show();bulk.size=Vector2i(620,450);await settle()
		check(not bulk._fields.has("initial_inventory_kg"),"no initial feed/product batch field")
		check(bulk.get_patch().patch=={},"selection creates no draft")
		var key:="max_outflow_kg_s" if kind in C.Materials.FEED_KINDS else "max_product_kg_s"
		bulk._fields[key].text="0.005";bulk._fields[key].text_changed.emit("0.005")
		check(bulk.get_patch().patch=={key:0.005},"batch only explicit numeric field")
		bulk.set_selected_ids([]);bulk.select_all();check(bulk.get_patch().patch=={},"selection clears chemical draft")
		for editor in bulk._fields.values():check(editor.get_global_rect().end.x<bulk.size.x,"batch numeric field fits narrow window")
	bulk.cancel();bulk.free();check(host.devices==before,"batch UI never mutates real inventory")
	var panel:=PanelUI.new();root.add_child(panel);var legacy:=panel.get_options().duplicate(true)
	check(not legacy.has("terminal_product_kg"),"old options exact compatibility")
	var context:Array=[item("hydrogen_gas_store",11),item("ammonia_synthesis_station",31),item("methanol_synthesis_station",57),item("nitrogen_supply_boundary",62)]
	var original:Array=context.duplicate(true);panel.set_material_context(context)
	check(panel._product_controls.keys()==["31","57"] and panel._material_controls.keys()==["11"],"only products eligible with separate H2 targets")
	check(panel.get_options().terminal_product_kg=={},"new targets default disabled")
	panel.configure({"terminal_hydrogen_kg":{"11":9.0},"terminal_product_kg":{"31":25.0,"57":100.0}})
	check(panel.get_options().terminal_product_kg=={"31":25.0,"57":100.0} and panel.get_options().terminal_hydrogen_kg=={"11":9.0},"independent products and hydrogen lower bounds")
	near(panel._product_controls["31"].amount.max_value,C.inventory_capacity(context[1].kind,context[1].params),"ammonia cap from shared helper")
	var shrink:=context.duplicate(true);shrink[1].params.capacity_kg=20.0;panel.set_material_context(shrink)
	check(panel.get_options().terminal_product_kg=={"57":100.0},"over-capacity target disabled not clamped")
	check(panel._product_target_note.text.contains("#31") and panel._product_target_note.text.contains("未截断"),"invalid target visibly warned")
	shrink.remove_at(2);panel.set_material_context(shrink)
	check(panel.get_options().terminal_product_kg=={} and panel._product_target_note.text.contains("#57"),"deleted target explicit invalidation")
	panel.set_material_context(context)
	for invalid in [{"31":NAN},{"31":INF},{"31":-1.0},{"31":201.0},{"404":1.0},{"11":1.0},{31:1.0},{"031":1.0}]:
		panel.configure({"terminal_product_kg":invalid});check(panel.get_options().terminal_product_kg=={} and not panel._product_invalidated_targets.is_empty(),"invalid target rejected "+str(invalid))
	panel.configure({"terminal_product_kg":{"31":0.0}});check(panel.get_options().terminal_product_kg=={"31":0.0},"explicit zero lower bound retained")
	panel.set_busy(true);check(not panel._product_controls["31"].amount.editable and panel._product_controls["31"].enabled.disabled,"busy locks product controls");panel.set_busy(false)
	panel.open();await settle()
	for resolution in [Vector2i(1000,740),Vector2i(700,580)]:
		panel.size=resolution;panel._tabs.current_tab=panel._material_tab_index;await settle()
		var scroll:ScrollContainer=panel._tabs.get_child(panel._material_tab_index)
		check(not scroll.get_h_scroll_bar().visible,"target cards fit "+str(resolution))
		for controls in panel._product_controls.values():
			scroll.ensure_control_visible(controls.amount);await settle();check(controls.amount.get_global_rect().end.x<panel.size.x,"product kg field and unit retained")
		check(panel._run.get_global_rect().end.y<=panel.size.y,"fixed action contained")
	check(panel._product_target_note.text.contains("实时/固定策略基线不保证") and panel._product_target_note.text.contains("不可行"),"target limitations explicit")
	check(context==original,"target edits never modify realtime inventory")
	panel.set_material_context([]);check(panel.get_options()==legacy,"empty context returns old options")
	panel.free()
	var pending:=PanelUI.new();root.add_child(pending);pending.configure({"terminal_product_kg":{"31":4.0}});pending.set_material_context(context)
	check(pending.get_options().terminal_product_kg=={"31":4.0},"configure before context preserves target")
	pending.free()
	var chart:=RuntimeChart.new();host.add_child(chart);chart.setup(host)
	for kind in C.Materials.CHEMICAL_KINDS:
		var device:=item(kind,97);var capacity:=C.inventory_capacity(kind,device.params)
		var field:="nitrogen_out_kg_s" if kind=="nitrogen_supply_boundary" else ("co2_out_kg_s" if kind=="co2_supply_boundary" else "product_produced_kg_s")
		var report:Dictionary={field:0.0025,"next_inventory_kg":capacity*.25}
		var output:Dictionary=chart._extract(device,report)
		check(output.values==[.0025] and output.unit=="kg/s","actual chemical mass flow "+kind);near(output.soc,25.0,"separate inventory percentage")
		check(output.labels[0].contains(C.Materials.species(kind)),"species labels explicit "+kind)
		for absent in [field,"next_inventory_kg"]:
			var missing:=report.duplicate(true);missing.erase(absent);check(chart._extract(device,missing).is_empty(),"missing data does not fabricate point")
		var invalid:=report.duplicate(true);invalid[field]=NAN;check(chart._extract(device,invalid).is_empty(),"nonfinite flow omitted")
		chart.reset_history();host.devices=[device];host.selected_id=97;host.paused=false;chart.capture_step({"devices":{"97":report}},1.0,1000)
		check(chart.sample_count==1 and chart.has_soc,"committed actual sample accepted")
		host.paused=true;chart.capture_step({"devices":{"97":report}},2.0,1300);check(chart.sample_count==1 and not chart.visible,"paused no chart or new sample")
		chart.reset_history();host.paused=false;chart.capture_step({"devices":{}},3.0,1500);check(chart.sample_count==0 and not chart.visible,"no report no chart")
	chart.free();host.free();await settle()
	print("CHEMICAL_PHASE2C_UI checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
