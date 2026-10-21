extends SceneTree
const Fixture=preload("res://tests/test_compact_build_bulk_ui_1003.gd")
var game
var bulk
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,note:String):
	checks+=1
	if not ok:failures.append(note);push_error("BULK_NATIVE_POINTER_FAIL "+note)
func _initialize():call_deferred("run")
func settle():
	for i in 6:await process_frame
func pointer(local:Vector2,pressed:bool,shift:bool=false):
	var e:=InputEventMouseButton.new();e.position=Vector2(bulk.position)+local;e.global_position=e.position;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;e.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;e.shift_pressed=shift
	root.push_input(e,true)
func click(id:int,shift:bool=false):
	var local:Vector2=bulk._cards[id].get_global_rect().get_center()
	pointer(local,true,shift);await process_frame;pointer(local,false,shift);await settle()
func run():
	# Embedded native Window routing exercises window_input then BaseButton GUI
	# delivery without opening a desktop window or invoking an external input tool.
	root.gui_embed_subwindows=true;root.content_scale_size=Vector2i.ZERO;root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED;root.size=Vector2i(1180,812)
	game=Fixture.UIController.new();root.add_child(game);await settle()
	game.devices=[]
	for id in [0,1,4,5,6]:game.devices.append({"id":id,"kind":"wind","x":float(id)*30,"z":0.0,"params":game.model.defaults("wind")})
	game.open_bulk_parameters();bulk=game.bulk_parameter_editor;bulk.size=Vector2i(1060,730);await settle();bulk.select_kind("wind");await settle()
	check(bulk.is_embedded(),"native Window is embedded for headless GUI routing")
	var before:Dictionary=game.state().duplicate(true)
	# Negative control: restore the old double-owner endpoint behavior in memory.
	# This must reproduce the screenshot defect through the full GUI event path.
	bulk.set_selected_ids([0]);bulk._range_anchor_id=0;bulk._cards[4].button_mask=MOUSE_BUTTON_MASK_LEFT
	await click(4,true);check(bulk.selected_ids==[0,1],"negative control reproduces old native endpoint flip")
	bulk._cards[4].button_mask=0;bulk.set_selected_ids([]);bulk._range_anchor_id=-1
	await click(0);check(bulk.selected_ids==[0],"native ordinary checkbox click selects first")
	await click(4,true);check(bulk.selected_ids==[0,1,4],"native Shift press/release keeps inclusive final checkbox selected")
	check(bulk._cards[4].button_pressed and bulk._range_anchor_id==0,"range end remains checked and first anchor remains stable")
	await click(4,true);check(bulk.selected_ids==[0,1,4],"repeat native Shift click does not toggle endpoint off")
	bulk.set_selected_ids([]);await click(6);await click(1,true);check(bulk.selected_ids==[1,4,5,6],"reverse native Shift selects visible-order range")
	bulk.set_selected_ids([]);await click(0);await click(4);check(bulk.selected_ids==[0,4],"ordinary native checkbox clicks retain arbitrary subset")
	await click(4);check(bulk.selected_ids==[0],"ordinary native checkbox click toggles off once")
	bulk._cards[1].grab_focus()
	for pressed in [true,false]:
		var event:=InputEventAction.new();event.action="ui_accept";event.pressed=pressed;bulk.push_input(event,true)
	await settle();check(bulk.selected_ids==[0,1],"native keyboard checkbox acceptance unaffected")
	var start:Vector2=bulk._cards[0].get_global_rect().get_center();var finish:Vector2=bulk._cards[4].get_global_rect().get_center()
	pointer(start,true)
	var motion:=InputEventMouseMotion.new();motion.position=Vector2(bulk.position)+finish;motion.global_position=motion.position;motion.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(motion,true)
	await process_frame;pointer(finish,false);await settle()
	check(bulk.selected_ids==[0,1,4],"native drag across checkbox rows does not toggle final card on release")
	check(game.state()==before,"native pointer and keyboard selection do not apply parameters")
	check(not game.left_pan_active and not game.left_pan_pending,"batch pointer does not begin map pan")
	for id in bulk._cards:check(bulk._cards[id].button_mask==0,"device checkbox mouse handled only by list "+str(id))
	bulk.cancel()
	for key in ["camera","lod_camera","terrain","labels","infrastructure","selection","overlay","equipment","cables"]:
		var node=game.get(key)
		if is_instance_valid(node) and node.get_parent()==null:node.free()
	game.free();await process_frame
	print("BULK_NATIVE_POINTER_1003 checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
