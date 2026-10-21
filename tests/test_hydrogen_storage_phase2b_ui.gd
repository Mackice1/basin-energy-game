extends SceneTree
## Native controls only; no display, map, saves, or physical simulation mutation.
const Form=preload("res://scripts/parameter_form.gd")
const Bulk=preload("res://scripts/bulk_parameter_editor.gd")
const PanelUI=preload("res://scripts/optimization_panel.gd")
const RuntimeChart=preload("res://scripts/device_runtime_chart.gd")
const C=preload("res://scripts/device_catalog.gd")
const M=preload("res://scripts/energy_model.gd")
const PHASE=["hydrogen_liquid_store","hydrogen_metal_hydride_store"]
class Host extends Node:
	var font_full:Font=load("res://assets/InterfaceCJK.ttc")
	var model=preload("res://scripts/energy_model.gd").new()
	var devices:Array=[]
	var paused:=false
	var selected_id:=-1
	var DEVICE_NAMES:Dictionary={}
	func device(id:int)->Dictionary:
		for d in devices:
			if d.id==id:return d
		return {}
	func modal_visible()->bool:return false
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures.append(message);push_error("PHASE2B_UI "+message)
func near(a:Variant,b:float,message:String):check((a is float or a is int) and absf(float(a)-b)<1e-8,message)
func _initialize():call_deferred("run")
func settle():
	for i in 4:await process_frame
func item(kind:String,id:int)->Dictionary:
	var p:Dictionary=C.defaults(kind)
	return {"id":id,"kind":kind,"x":float(id)*30.0,"z":0.0,"params":p,"state":C.Materials.initial_state(kind,p)}
func run():
	root.gui_embed_subwindows=true;root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1180,812)
	var form:=Form.new();var theme:=Theme.new();theme.default_font=load("res://assets/InterfaceCJK.ttc");form.theme=theme;form.size=Vector2(1140,552);root.add_child(form);await settle()
	var maximums:Dictionary=C.Materials.phase_profile().maximums
	for kind in PHASE:
		var p:Dictionary=C.defaults(kind);var before:Dictionary=p.duplicate(true)
		for construction in [true,false]:
			form.set_parameters(kind,p,construction)
			check(form._fields.size()==p.size(),kind+" every accepted field is labelled")
			check(form.get_parameters()==p and form.get_validation_errors().is_empty(),kind+" defaults exact and valid")
			check(not form._fields.initial_inventory_kg.editable,kind+" initial H2 fixed zero in both contexts")
			form._fields.initial_inventory_kg.text="99"
			check(form.get_parameters().initial_inventory_kg==0.0,kind+" injected initial H2 text ignored")
			for forbidden in ["phase_id","technology","leak_per_h","liquefaction_kwh_per_kg","capacity_mwh"]:check(not form._fields.has(forbidden),kind+" no profile/phase/energy shortcut "+forbidden)
			if kind=="hydrogen_metal_hydride_store":
				check(form._fields.dry_host_mass_kg.editable==construction,"host editable only during construction")
				check(not form._fields.has("capacity_kg"),"no independent metal capacity control")
				form._fields.dry_host_mass_kg.text="5000";form._fields.dry_host_mass_kg.text_changed.emit("5000")
				near(form.get_parameters().dry_host_mass_kg,5000.0 if construction else 10000.0,"host programmatic guard")
				near(form._derived_capacity.text.to_float(),C.inventory_capacity(kind,form.get_parameters()),"read-only derived capacity uses authoritative helper")
		check(p==before,"form never mutates source params "+kind)
		for key in p:
			if key=="initial_inventory_kg":continue
			form.set_parameters(kind,p,true)
			form._fields[key].text=str(float(maximums[kind][key])+1.0)
			check(not form.get_validation_errors().is_empty(),kind+" rejects hardcap overflow "+key)
			near(form.get_parameters()[key],float(maximums[kind][key])+1.0,"invalid draft not silently clamped "+key)
			form._fields[key].text="NaN";check(not form.get_validation_errors().is_empty(),"nonfinite draft rejected "+key)
		for resolution in [Vector2i(1180,812),Vector2i(640,480)]:
			root.size=resolution;form.position=Vector2(20,100);form.size=Vector2(resolution.x-40,resolution.y-260);form.set_parameters(kind,p,false);await settle()
			check(form.size.x<=resolution.x-40 and form.size.y<=resolution.y-260,"form contained "+kind+str(resolution)+" actual="+str(form.size)+" min="+str(form.get_combined_minimum_size()))
			for editor in form._fields.values():
				form._scroll.ensure_control_visible(editor);await settle()
				var viewport:=form._scroll.get_global_rect();viewport.size.x-=form._scroll.get_v_scroll_bar().size.x if form._scroll.get_v_scroll_bar().visible else 0.0;viewport.size.y-=form._scroll.get_h_scroll_bar().size.y if form._scroll.get_h_scroll_bar().visible else 0.0
				check(viewport.grow(1.0).encloses(editor.get_global_rect()),"field reachable "+str(editor.name)+str(resolution))
				check(editor.get_theme_font_size("font_size")==18 and editor.size.x>=125 and editor.size.y>=40,"readable input hierarchy and hit target")
	form.set_parameters("collector_substation",C.defaults("collector_substation"),false)
	check(form._fields.size()==C.defaults("collector_substation").size() and form.get_parameters()==C.defaults("collector_substation"),"collector parameters unchanged")
	form.free();root.size=Vector2i(1180,812)
	var host:=Host.new();root.add_child(host)
	for index in PHASE.size():host.devices.append(item(PHASE[index],index+1))
	var source:Array=host.devices.duplicate(true)
	var bulk:=Bulk.new();root.add_child(bulk);bulk.setup(host)
	for kind in PHASE:
		bulk.select_kind(kind);bulk.select_all();bulk.show();bulk.size=Vector2i(620,450);await settle()
		for editor in bulk._fields.values():check(editor.get_global_rect().end.x<bulk.size.x,"narrow batch editor stays accessible")
		check(not bulk._fields.has("initial_inventory_kg") and not bulk._enabled.has("initial_inventory_kg"),"batch excludes initial H2 "+kind)
		check(not bulk._fields.has("dry_host_mass_kg") and not bulk._enabled.has("dry_host_mass_kg"),"batch excludes fixed host "+kind)
		check(bulk.get_patch().patch=={},"selection does not create draft")
		bulk._fields.charge_kg_s.text="0.005";bulk._fields.charge_kg_s.text_changed.emit("0.005")
		check(bulk.get_patch().patch=={"charge_kg_s":0.005},"only explicit batch flow field")
		bulk.set_selected_ids([]);bulk.select_all();check(bulk.get_patch().patch=={},"changed selection clears prior draft")
	# Defense-in-depth even if an external test/client injects disabled fields.
	var injected:=CheckBox.new();injected.button_pressed=true;bulk._enabled.dry_host_mass_kg=injected
	check(not bulk.get_patch().ok,"injected host batch field safely rejected before lookup")
	bulk._enabled.erase("dry_host_mass_kg");injected.free();bulk.cancel()
	check(host.devices==source,"batch selection and cancellation preserve kg and host")
	bulk.free()
	var panel:=PanelUI.new();root.add_child(panel)
	var legacy:Dictionary=panel.get_options().duplicate(true)
	check(not legacy.has("terminal_hydrogen_kg"),"pure legacy options compatible")
	var context:Array=[item("hydrogen_gas_store",11),item(PHASE[0],31),item(PHASE[1],57)]
	context[2].params.dry_host_mass_kg=5000.0;context[2].state.host_dry_mass_kg=5000.0
	var original:Array=context.duplicate(true);panel.set_material_context(context)
	check(panel._material_controls.keys()==["11","31","57"],"all gas/liquid/LaNi5 installed IDs selectable")
	check(panel.get_options().terminal_hydrogen_kg=={},"all three target classes default disabled")
	near(panel._material_controls["57"].amount.max_value,C.inventory_capacity(PHASE[1],context[2].params),"target bound uses derived host capacity")
	panel.configure({"terminal_hydrogen_kg":{"11":10.0,"31":50.0,"57":30.0}})
	check(panel.get_options().terminal_hydrogen_kg=={"11":10.0,"31":50.0,"57":30.0},"targets preserve independent stable IDs in kg")
	check(context==original,"targets cannot mutate realtime stock/host")
	var shrink:Array=context.duplicate(true);shrink[1].params.capacity_kg=20.0
	panel.set_material_context(shrink)
	check(panel.get_options().terminal_hydrogen_kg=={"11":10.0,"57":30.0},"invalid capacity target disabled not clamped")
	check(panel._material_target_note.text.contains("#31") and panel._material_target_note.text.contains("未截断"),"capacity invalidation explicitly visible")
	shrink.remove_at(2);panel.set_material_context(shrink)
	check(not panel._material_controls.has("57") and panel._material_target_note.text.contains("#57"),"deleted target explicit and absent")
	panel.configure({"terminal_hydrogen_kg":{"31":NAN,"404":1.0}})
	check(panel.get_options().terminal_hydrogen_kg=={} and panel._material_invalidated_targets.size()==2,"nonfinite and unknown targets explicitly rejected")
	panel.set_material_context(context);panel.configure({"terminal_hydrogen_kg":{"57":0.0}})
	check(panel.get_options().terminal_hydrogen_kg=={"57":0.0},"explicit zero target remains meaningful")
	panel.set_busy(true);check(not panel._material_controls["57"].amount.editable,"busy blocks metal target editor");panel.set_busy(false)
	panel.open();await settle()
	for resolution in [Vector2i(1000,740),Vector2i(700,580)]:
		panel.size=resolution;panel._tabs.current_tab=panel._material_tab_index;await settle()
		var scroll:ScrollContainer=panel._tabs.get_child(panel._material_tab_index)
		check(not scroll.get_h_scroll_bar().visible,"target cards fit narrow native window "+str(resolution))
		check(panel._run.get_global_rect().end.y<=panel.size.y,"fixed solve action contained")
		for controls in panel._material_controls.values():check(controls.amount.get_global_rect().end.x<panel.size.x,"kg field and unit remain on row")
	panel.set_material_context([]);check(panel.get_options()==legacy,"empty scene returns exact legacy options")
	panel.free()
	var chart:=RuntimeChart.new();host.add_child(chart);chart.setup(host)
	chart.power_unit="kg/s";check(chart._series_number(1.0/3600.0).is_valid_float() and chart._series_number(1.0/3600.0).to_float()>0.0 and chart._series_number(0.0)=="0.000","small real flow label never rounds to false zero")
	for kind in PHASE:
		var device:=item(kind,97);var capacity:=C.inventory_capacity(kind,device.params)
		var report:Dictionary={"hydrogen_in_kg_s":0.0025,"hydrogen_out_kg_s":0.001,"next_inventory_kg":capacity*0.25}
		var before:Dictionary=device.duplicate(true);var output:Dictionary=chart._extract(device,report)
		check(output.values==[0.0025,0.001] and output.unit=="kg/s","actual low mass flows, not power "+kind)
		near(output.soc,25.0,"separate derived-capacity SOC "+kind)
		check(device==before,"chart extraction cannot alter state "+kind)
		for absent in ["hydrogen_in_kg_s","hydrogen_out_kg_s","next_inventory_kg"]:
			var incomplete:=report.duplicate(true);incomplete.erase(absent);check(chart._extract(device,incomplete).is_empty(),"missing series is not fabricated "+absent)
		var invalid:=report.duplicate(true);invalid.next_inventory_kg=NAN;check(chart._extract(device,invalid).is_empty(),"invalid inventory no chart")
		chart.reset_history();host.devices=[device];host.selected_id=97;host.paused=false
		chart.capture_step({"devices":{"97":report}},1.0,1000);check(chart.sample_count==1 and chart.has_soc,"committed material sample accepted")
		host.paused=true;chart.capture_step({"devices":{"97":report}},2.0,1300);check(chart.sample_count==1 and not chart.visible,"pause adds no point and hides")
		chart.reset_history();host.paused=false;chart.capture_step({"devices":{}},3.0,1500);check(chart.sample_count==0 and not chart.visible,"missing committed report has no graph")
	chart.free();host.free();await process_frame
	print("HYDROGEN_STORAGE_PHASE2B_UI checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
