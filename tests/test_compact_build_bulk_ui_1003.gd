extends SceneTree
const Fixture=preload("res://tests/test_visual_ui.gd")
class UIController:
	extends Fixture.UIController
	func _ready():
		cfg={"max_build_slope_degrees":8.0,"grid_export_mw":4.0}
		for kind in KINDS:templates[kind]=model.defaults(kind)
		make_ui();booted=true;set_process(false);refresh()
var game
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures.append(message);push_error("COMPACT_BULK_UI_FAIL "+message)
func _initialize():call_deferred("run")
func settle():
	for i in 6:await process_frame
func escape(window:Window=null,echo:bool=false):
	var event:=InputEventKey.new();event.pressed=true;event.keycode=KEY_ESCAPE;event.echo=echo
	if window:window.window_input.emit(event)
	else:game._input(event)
func run():
	root.content_scale_size=Vector2i.ZERO;root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	game=UIController.new();root.add_child(game);await settle()
	for resolution in [Vector2i(1440,900),Vector2i(1024,768),Vector2i(800,600),Vector2i(640,480)]:
		root.size=resolution;await settle();game._layout_workspace();await settle()
		var canvas:=Rect2(Vector2.ZERO,Vector2(resolution))
		check(not game.hud_dock.get_node("DockRail").get_global_rect().intersects(game.hud_context.get_global_rect()),"rail clear of bottom controls "+str(resolution))
		game.hud_layer_button.pressed.emit();await settle();game._layout_workspace();await settle()
		check(not game.hud_layers.get_global_rect().intersects(game.hud_context.get_global_rect()),"map layers clear of controls "+str(resolution))
		game.hud_layer_button.pressed.emit()
		for category in game.BUILD_CATEGORIES:
			game.category_buttons[category].pressed.emit();await settle();game._layout_workspace();await settle()
			for panel in [game.hud_header,game.hud_context,game.hud_build,game.hud_footer]:check(canvas.encloses(panel.get_global_rect()),str(resolution)+" panel contained "+panel.name)
			for panel in [game.hud_context,game.hud_build,game.hud_footer]:
				for other in [game.hud_context,game.hud_build,game.hud_footer]:
					if panel!=other:check(not panel.get_global_rect().intersects(other.get_global_rect()),"no compact stack overlap")
			check(resolution.y-game.hud_context.position.y<=186,"compact bottom footprint "+str(resolution)+" actual="+str(resolution.y-game.hud_context.position.y))
			for key in game.tool_buttons:check(game.tool_buttons[key].visible==(key in game.BUILD_CATEGORIES[category].kinds),"only category devices visible "+key)
			for key in game.category_buttons:check(canvas.encloses(game.category_buttons[key].get_global_rect()),"horizontal category contained "+key)
			for key in game.hud_actions:check(canvas.encloses(game.hud_actions[key].get_global_rect()),"context cancel/selection action contained "+key)
			if category=="storage":
				print("COMPACT_LAYOUT ",resolution," stack_px=",resolution.y-game.hud_context.position.y," shelf_px=",game.hud_build.size.y)
				game.build_scroll.ensure_control_visible(game.tool_buttons.solid_thermal_store);await settle()
				check(game.build_scroll.get_global_rect().intersects(game.tool_buttons.solid_thermal_store.get_global_rect()),"last storage reachable by scroll")
	game.select_build_category("power");game.start_build("wind");game.select_build_category("storage");await settle()
	check(game.mode=="select" and game.ghost==null,"switch category cancels stale placement")
	game.dimension_profile="metric_v1";game.start_build("battery_sodium");check(game.mode=="build","new storage build tool works");escape(null,true);check(game.mode=="build","echo ignored");escape();check(game.mode=="select","Escape cancels build once")
	for x in [-60.0,-30.0,0.0,30.0,60.0]:check(game.add_equipment("wind",Vector2(x,-30)),"install wind for bulk UI")
	game.device(0).params.shear_exponent=0.1;game.device(2).params.shear_exponent=0.3
	root.size=Vector2i(1024,768);await settle()
	game.open_bulk_parameters();await settle()
	var bulk=game.bulk_parameter_editor
	bulk.select_kind("wind")
	for id in [0,2,4]:bulk._cards[id].button_pressed=true
	await settle()
	for size in [Vector2i(1024,768),Vector2i(800,600),Vector2i(640,480)]:
		root.size=size;bulk.size=Vector2i(size.x-40,size.y-40);await settle()
		var area:=Rect2(Vector2.ZERO,Vector2(bulk.size))
		check(area.encloses(bulk._apply.get_global_rect()),"batch fixed apply button contained "+str(size))
		check(area.encloses(bulk._selection.get_global_rect()),"batch selection contained "+str(size))
		for key in bulk._fields:check(bulk._fields[key].get_global_rect().end.x<=bulk.size.x,"batch field right edge contained "+key)
	check(bulk.selected_ids==[0,2,4],"arbitrary checkbox IDs retained")
	check(bulk._fields.shear_exponent.placeholder_text=="混合值","mixed untouched field marked")
	check(not bulk._enabled.shear_exponent.button_pressed,"mixed field not automatically enabled")
	bulk._fields.rated_mw.text="4";bulk._fields.rated_mw.text_changed.emit("4")
	check(bulk._enabled.rated_mw.button_pressed,"explicit edit enables field")
	var before:Dictionary=game.state().duplicate(true)
	escape(bulk);check(not bulk.visible,"Escape closes staged batch")
	check(game.state()==before,"Escape batch does not modify scene")
	game.open_bulk_parameters();bulk.select_kind("wind");bulk.set_selected_ids([0,2,4]);await settle()
	bulk._fields.rated_mw.text="4";bulk._fields.rated_mw.text_changed.emit("4")
	var applied:Dictionary=bulk.apply_selection();check(applied.ok,"explicit batch applies through UI")
	for i in 5:check(game.device(i).params.rated_mw==(4.0 if i in [0,2,4] else 5.0),"UI only updates selected ID "+str(i))
	check(game.device(0).params.shear_exponent==0.1 and game.device(2).params.shear_exponent==0.3,"unmodified mixed values preserved")
	escape(bulk)
	game.select_device(0);game.open_parameters(false);await settle()
	check(game.param_dialog.visible,"single parameter editor opens")
	before=game.state().duplicate(true)
	game.parameter_form._fields.rated_mw.text="3";game.parameter_form._fields.rated_mw.text_changed.emit("3")
	escape(game.param_dialog,true);check(game.param_dialog.visible,"parameter Esc echo ignored")
	escape(game.param_dialog);check(not game.param_dialog.visible,"native parameter window Esc closes")
	check(game.state()==before,"single parameter Escape never applies draft")
	game.start_build("wind");game.ask("Cancel only test",func():pass);await settle()
	escape(game.confirmation);check(not game.confirmation.visible and game.mode=="build","confirmation consumes one layer and retains build")
	escape();check(game.mode=="select","second Esc cancels underlying build")
	for key in ["camera","lod_camera","terrain","labels","infrastructure","selection","overlay","equipment","cables"]:
		var node=game.get(key)
		if is_instance_valid(node) and node.get_parent()==null:node.free()
	game.free();await process_frame
	print("COMPACT_BULK_UI_1003 checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
