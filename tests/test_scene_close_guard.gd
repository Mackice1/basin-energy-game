extends SceneTree
## Native embedded Window input, no desktop GUI, scene boot or save writes.
const Guard = preload("res://scripts/scene_close_guard.gd")
const UITheme = preload("res://scripts/ui_theme.gd")
var checks := 0
var failures: Array[String] = []
var save_requests := 0
var quit_requests := 0
var scene := {"name":"有未保存更改的基地", "devices":[{"id":7,"x":1.25,"state":{"energy_mwh":2.5}}],"dirty":true}
var guard

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures.append(message); push_error("SCENE_CLOSE_GUARD " + message)
func _initialize() -> void: call_deferred("run")
func settle():
	for i in 4: await process_frame
func fresh():
	if is_instance_valid(guard): guard.free()
	guard = Guard.new()
	root.add_child(guard)
	guard.setup(UITheme.create(load("res://assets/InterfaceCJK.ttc")))
	guard.request_save.connect(func(): save_requests += 1)
	guard.quit_confirmed.connect(func(): quit_requests += 1)
func show_dirty(caption: String = "有未保存更改的基地"):
	guard.request_close(caption, true)
	# Headless monitor reports no usable rect; exercise logical native layout.
	if DisplayServer.get_name() == "headless":
		guard.position=Vector2i(24,24);guard.size=Vector2i(mini(560,root.size.x-48),250)
	await settle()
func key(code: Key, pressed: bool, echo: bool = false, physical: bool = false):
	var event := InputEventKey.new()
	if physical: event.physical_keycode=code
	else: event.keycode=code
	event.pressed=pressed;event.echo=echo
	root.push_input(event,true)
func click(button: Button):
	var point := Vector2(guard.position) + button.get_global_rect().get_center()
	for pressed in [true,false]:
		var event := InputEventMouseButton.new()
		event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT
		event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event,true);await process_frame
	await settle()
func run():
	root.gui_embed_subwindows=true;root.size=Vector2i(1180,812)
	var before := var_to_bytes(scene)
	fresh();await show_dirty()
	check(guard.visible and guard.exclusive and guard.is_embedded(),"dirty scene opens one exclusive native dialog")
	check(guard.get_ok_button().text=="取消" and guard.get_ok_button().has_focus(),"initial/default action is cancel")
	check(guard.dialog_text.contains("有未保存更改的基地") and guard.dialog_text.contains("不会写入文件或自动退出"),"scene identity and save behavior are explicit")
	check(save_requests==0 and quit_requests==0 and var_to_bytes(scene)==before,"opening is read-only")
	var dialog_id:int=guard.get_instance_id();var child_count:int=guard.get_child_count()
	for i in 5: guard.request_close("重复关闭", i%2==0)
	check(guard.visible and guard.get_instance_id()==dialog_id and guard.get_child_count()==child_count,"repeated close does not stack dialogs")
	check(quit_requests==0 and save_requests==0,"repeated close cannot tunnel through dirty prompt with false flag")
	key(KEY_ENTER,true);key(KEY_ENTER,false);await settle()
	check(not guard.visible and quit_requests==0 and save_requests==0,"native Enter defaults to non-destructive cancel")
	await show_dirty();key(KEY_ESCAPE,true,true);await settle()
	check(guard.visible and quit_requests==0,"echo Escape is consumed without closing")
	guard.discard_button.grab_focus();key(KEY_ESCAPE,true);key(KEY_ESCAPE,false);await settle()
	check(not guard.visible and quit_requests==0,"Escape cancels even when discard has focus")
	await show_dirty();key(KEY_ESCAPE,true,false,true);key(KEY_ESCAPE,false,false,true);await settle()
	check(not guard.visible and quit_requests==0,"physical Escape also cancels")
	await show_dirty();await click(guard.get_ok_button())
	check(not guard.visible and save_requests==0 and quit_requests==0,"native cancel click does nothing destructive")
	await show_dirty();guard.close_requested.emit();await settle()
	check(not guard.visible and quit_requests==0,"closing the confirmation itself cancels rather than exits")
	await show_dirty();await click(guard.save_button)
	check(not guard.visible and save_requests==1 and quit_requests==0,"go-to-save only requests the existing scene save card")
	check(var_to_bytes(scene)==before,"go-to-save never mutates scene or dirty state")
	# A host save failure has no completion callback or deferred-quit mechanism.
	await settle();check(quit_requests==0 and scene.dirty,"failed/not-performed save cannot trigger exit")
	await show_dirty();check(guard.visible and quit_requests==0,"close after failed save asks again")
	check(guard.handle_escape() and not guard.visible,"host priority arbitration can cancel exactly this layer")
	check(not guard.handle_escape(),"hidden guard does not consume later Esc layers")
	guard.custom_action.emit(&"discard");guard.custom_action.emit(&"save")
	check(quit_requests==0 and save_requests==1,"stale actions while hidden cannot quit or reopen save")
	for extent in [Vector2i(1180,812),Vector2i(640,478)]:
		root.size=extent;await show_dirty("很长的中文场景名称".repeat(40))
		var bounds:=Rect2(Vector2.ZERO,Vector2(guard.size))
		check(guard.theme.default_font!=null and guard.dialog_text.contains("…"),"bounded scene name retains Chinese font")
		for button in [guard.get_ok_button(),guard.save_button,guard.discard_button]:
			check(bounds.encloses(button.get_global_rect()),"all three choices fit "+str(extent)+button.text)
		check(not guard.save_button.get_global_rect().intersects(guard.discard_button.get_global_rect()),"destructive and save choices never overlap")
		guard.handle_escape()
	await show_dirty();await click(guard.discard_button)
	check(not guard.visible and quit_requests==1 and save_requests==1,"only explicit native discard confirms quit for a dirty scene")
	guard.request_close("重复",false);guard.custom_action.emit(&"discard")
	check(quit_requests==1,"quit confirmation is emitted only once")
	fresh();guard.request_close("已保存场景",false)
	check(not guard.visible and quit_requests==2,"clean scene confirms normal close without a prompt")
	check(var_to_bytes(scene)==before,"all decisions preserve scene data; host alone owns persistence and shutdown")
	guard.free();await process_frame
	print("SCENE_CLOSE_GUARD checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
