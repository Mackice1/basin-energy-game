extends SceneTree
const Fixture=preload("res://tests/test_compact_build_bulk_ui_1003.gd")
var game
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,note:String):
	checks+=1
	if not ok:failures.append(note);push_error("FLYOUT_GESTURE_FAIL "+note)
func _initialize():call_deferred("run")
func settle():
	for i in 6:await process_frame
func mouse(point:Vector2,pressed:bool,shift:bool=false,ctrl:bool=false)->InputEventMouseButton:
	var e:=InputEventMouseButton.new();e.position=point;e.global_position=point;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;e.shift_pressed=shift;e.ctrl_pressed=ctrl;return e
func motion(point:Vector2)->InputEventMouseMotion:
	var e:=InputEventMouseMotion.new();e.position=point;e.global_position=point;e.button_mask=MOUSE_BUTTON_MASK_LEFT;return e
func escape(echo:bool=false):
	var e:=InputEventKey.new();e.keycode=KEY_ESCAPE;e.pressed=true;e.echo=echo;game._input(e)
func run():
	root.content_scale_size=Vector2i.ZERO;root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.size=Vector2i(1180,812)
	game=Fixture.UIController.new();root.add_child(game);await settle()
	check(not game.build_tray_open and not game.build_tray.visible,"idle equipment tray hidden")
	for resolution in [Vector2i(1180,812),Vector2i(1024,768),Vector2i(640,480)]:
		root.size=resolution;await settle();game._layout_workspace();await settle()
		var canvas:=Rect2(Vector2.ZERO,Vector2(resolution))
		check(game.hud_build.size.y<=60,"single row dock height "+str(resolution))
		check(canvas.encloses(game.header_run_group.get_global_rect()),"run group contained "+str(resolution))
		for tile in game.header_metric_tiles:check(tile.visible and canvas.encloses(tile.get_global_rect()),"all three header metrics fit "+str(resolution))
		for key in game.category_buttons:
			var b:Button=game.category_buttons[key]
			var needed:float=b.get_theme_font("font").get_string_size(b.text,HORIZONTAL_ALIGNMENT_LEFT,-1,b.get_theme_font_size("font_size")).x+26+b.get_theme_constant("h_separation")+b.get_theme_stylebox("normal").get_minimum_size().x
			check(b.size.x>=needed,"category full name "+b.text)
			check(canvas.encloses(b.get_global_rect()),"category contained "+b.text)
		game.toggle_build_category("storage");await create_timer(0.3).timeout;await settle()
		check(game.build_tray_open and is_equal_approx(game.build_tray.modulate.a,1),"tray fully fades in")
		check(canvas.encloses(game.build_tray.get_global_rect()),"tray fits viewport "+str(resolution))
		check(game.build_tray.get_global_rect().end.y<=game.hud_context.position.y,"tray stays above prompt controls")
		for kind in game.BUILD_CATEGORIES.storage.kinds:
			var b:Button=game.tool_buttons[kind]
			check(b.size.y>=90 and b.get_theme_constant("icon_max_width")>=48,"large device target "+kind)
			game.build_scroll.ensure_control_visible(b);await settle()
			check(game.build_scroll.get_global_rect().encloses(b.get_global_rect()),"full device card scroll reachable "+kind)
		var old_center:Vector2=game.build_tray.get_global_rect().get_center()
		game.toggle_build_category("storage");await create_timer(0.2).timeout
		check(not game.build_tray.visible and not game.build_tray_open,"same category toggles closed")
		check(not game.pointer_over_ui(old_center),"hidden tray has no input region")
	game.toggle_build_category("power");game.toggle_build_category("storage");game.toggle_build_category("heat");game.toggle_build_category("heat");await create_timer(0.3).timeout
	check(not game.build_tray.visible,"rapid interrupted transitions cannot leave ghost tray")
	game.build_category="storage";game.mode="link";game.toggle_build_category("storage");escape(true)
	check(game.build_tray_open and game.mode=="link","Esc echo does not close tray")
	escape();check(not game.build_tray_open and game.mode=="link","Esc closes tray before active map action")
	escape();check(game.mode=="link","closing animation cannot leak second rapid Esc")
	await create_timer(0.2).timeout;escape();check(game.mode=="select","subsequent Esc cancels underlying map action")
	game.dimension_profile="metric_v1";game.toggle_build_category("power");game.start_build("wind");check(not game.build_tray.visible and game.mode=="build","choosing equipment dismisses tray without canceling placement");escape()
	root.size=Vector2i(1180,812);await settle()
	game.devices=[]
	for index in 20:game.devices.append({"id":10+index*10,"kind":"wind","x":float(index)*30,"z":0.0,"params":game.model.defaults("wind")})
	game.devices.append({"id":999,"kind":"pv","x":0.0,"z":100.0,"params":game.model.defaults("pv")})
	game.open_bulk_parameters();var bulk=game.bulk_parameter_editor;bulk.size=Vector2i(1060,730);await settle();bulk.select_kind("wind");await settle()
	var gutter_start:Vector2=bulk._list_input_rect().position+Vector2(5,24)
	check(bulk._card_at(gutter_start)==-1 and bulk._device_grid.global_position.x-bulk._list_input_rect().position.x>=12,"persistent side gutter is wide enough to begin marquee")
	check(bulk.handle_list_input(mouse(gutter_start,true)),"marquee can start from side gutter beside first card")
	var gutter_end:Vector2=bulk._card_panels[20].get_global_rect().end-Vector2(2,2)
	bulk.handle_list_input(motion(gutter_end));bulk.handle_list_input(mouse(gutter_end,false));check(bulk.selected_ids==[10,20],"gutter-origin drag selects cards using actual scrolled layout")
	bulk.select_card(10);bulk.select_card(50,true);check(bulk.selected_ids==[10,20,30,40,50],"Shift first-to-fifth inclusive")
	bulk.select_card(50);bulk.select_card(20,true);check(bulk.selected_ids==[20,30,40,50],"reverse Shift range inclusive")
	bulk.select_card(90,false,true);check(bulk.selected_ids==[20,30,40,50,90],"modifier click toggles one independent stable ID")
	bulk._cards[20].button_pressed=false;check(bulk.selected_ids==[30,40,50,90],"checkbox still toggles arbitrary subset")
	check(bool(bulk._select_all_checkbox.get_meta("indeterminate")) and not bulk._select_all_checkbox.button_pressed,"partial selection has mixed all-checkbox")
	check(bulk._select_all_checkbox.get_parent().get_child(0).text=="已安装设备","select all belongs to list heading")
	bulk._fields.rated_mw.text="9";bulk._fields.rated_mw.text_changed.emit("9");check(not bulk.get_patch().patch.is_empty(),"field draft exists before select all")
	var before:Dictionary=game.state().duplicate(true)
	bulk._select_all_checkbox.button_pressed=true;check(bulk.selected_ids.size()==20 and not bool(bulk._select_all_checkbox.get_meta("indeterminate")),"all checkbox selects only filtered kind")
	check(bulk.get_patch().patch.is_empty() and bulk._error.text.contains("清空"),"select all clears draft explicitly without applying")
	check(game.state()==before,"select all never commits draft")
	bulk._select_all_checkbox.button_pressed=false;check(bulk.selected_ids.is_empty(),"checked all toggles clear")
	bulk.set_selected_ids([10]);bulk._fields.rated_mw.text="7";bulk._fields.rated_mw.text_changed.emit("7")
	var first:Rect2=bulk._card_panels[10].get_global_rect();var third:Rect2=bulk._card_panels[30].get_global_rect()
	var begin:=Vector2(first.position.x+4,first.end.y+4);var finish:=Vector2(third.end.x-4,third.end.y-2)
	check(bulk.handle_list_input(mouse(begin,true)),"blank list starts pending gesture")
	check(bulk._pointer_card_id==-1 and bulk.selected_ids==[10],"blank press never clicks a card")
	bulk.handle_list_input(motion(finish));check(bulk._drag_active and bulk.selected_ids==[10],"drag previews without mutating selection")
	bulk.handle_list_input(mouse(finish,false));check(bulk.selected_ids==[20,30],"box selects crossed cards once on release")
	check(bulk.get_patch().patch.is_empty() and bulk._error.text.contains("清空"),"box selection clears staged fields")
	var second:Rect2=bulk._card_panels[20].get_global_rect()
	var reverse_start:=Vector2(third.end.x-3,third.end.y+4);var reverse_end:=second.position+Vector2(3,2)
	bulk.handle_list_input(mouse(reverse_start,true));bulk.handle_list_input(motion(reverse_end));bulk.handle_list_input(mouse(reverse_end,false))
	check(bulk.selected_ids==[20,30],"reverse-direction rectangle selects same cards")
	bulk.set_selected_ids([10]);bulk._fields.rated_mw.text="7";bulk._fields.rated_mw.text_changed.emit("7")
	bulk.handle_list_input(mouse(begin,true));bulk.handle_list_input(motion(finish));game.handle_escape()
	check(bulk.visible and not bulk._pointer_pending and bulk.selected_ids==[10],"Esc cancels only active marquee")
	check(bulk.get_patch().patch.get("rated_mw")==7.0,"cancelled marquee retains original field draft")
	bulk._list_scroll.ensure_control_visible(bulk._card_panels[100]);await settle()
	var target:Rect2=bulk._card_panels[100].get_global_rect();var area:Rect2=bulk._list_input_rect()
	begin=Vector2(target.position.x+3,maxf(area.position.y+2,target.position.y-4));finish=target.end-Vector2(3,2)
	bulk.handle_list_input(mouse(begin,true));bulk.handle_list_input(motion(finish));bulk.handle_list_input(mouse(finish,false))
	check(bulk.selected_ids.has(100) and not bulk.selected_ids.has(10),"scrolled box maps to correct content IDs")
	bulk._list_scroll.scroll_vertical=0;await settle();first=bulk._card_panels[10].get_global_rect();area=bulk._list_input_rect();begin=Vector2(first.position.x+4,first.end.y+4);finish=area.end-Vector2(8,2)
	bulk.handle_list_input(mouse(begin,true));bulk.handle_list_input(motion(finish));var previous_scroll:int=bulk._list_scroll.scroll_vertical;bulk._process(0.2);await settle()
	check(bulk._list_scroll.scroll_vertical>previous_scroll,"marquee edge scroll advances content")
	bulk.handle_list_input(mouse(finish,false));check(not bulk._pointer_pending,"edge-scrolled drag ends cleanly")
	bulk._list_scroll.scroll_vertical=0;await settle()
	bulk.set_selected_ids([])
	var checkbox_point:Vector2=bulk._cards[10].get_global_rect().get_center()
	check(bulk.handle_list_input(mouse(checkbox_point,true)),"device checkbox pointer input has one gesture owner")
	bulk.handle_list_input(mouse(checkbox_point,false))
	check(bulk._cards[10].button_mask==0,"native mouse toggle cannot duplicate custom range selection")
	# Native embedded-window mouse routing is covered in test_bulk_native_pointer_1003.
	# Also verify the toggled signal and focused keyboard action remain usable.
	bulk._cards[10].button_pressed=true;await settle()
	check(bulk.selected_ids==[10],"native checkbox toggled signal preserves arbitrary selection")
	bulk._cards[20].grab_focus();var accept_event:=InputEventAction.new();accept_event.action="ui_accept";accept_event.pressed=true;bulk.push_input(accept_event,true);accept_event=InputEventAction.new();accept_event.action="ui_accept";accept_event.pressed=false;bulk.push_input(accept_event,true);await settle()
	check(bulk.selected_ids==[10,20],"focused checkbox keyboard acceptance remains usable")
	bulk.handle_list_input(mouse(begin,true));bulk.handle_list_input(motion(finish));bulk.focus_exited.emit()
	check(not bulk._pointer_pending and not bulk._marquee.visible and bulk.selected_ids==[10,20],"focus loss cancels gesture without selection mutation")
	bulk.select_card(50);bulk.select_kind("pv");bulk.select_kind("wind");bulk.select_card(30,true)
	check(bulk.selected_ids==[30] and bulk._range_anchor_id==30,"filter rebuild invalidates Shift anchor")
	bulk.set_selected_ids([30,999,123456]);check(bulk.selected_ids==[30],"selection rejects other kind and missing ID")
	game.devices=game.devices.filter(func(d):return d.id!=30);bulk.refresh_devices();check(bulk.selected_ids.is_empty() and bulk._range_anchor_id==-1,"deleted IDs and anchor invalidated safely")
	game.handle_escape();check(not bulk.visible,"Esc without gesture closes batch editor")
	check(game.device(10).params.rated_mw==5.0,"all selection interactions leave parameters unchanged")
	for key in ["camera","lod_camera","terrain","labels","infrastructure","selection","overlay","equipment","cables"]:
		var node=game.get(key)
		if is_instance_valid(node) and node.get_parent()==null:node.free()
	game.free();await process_frame
	print("FLYOUT_SELECTION_GESTURES_1003 checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
