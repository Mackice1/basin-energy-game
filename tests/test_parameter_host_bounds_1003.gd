extends SceneTree
const Fixture=preload("res://tests/test_compact_build_bulk_ui_1003.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String):
	checks+=1
	if not ok:failures.append(message);push_error("PARAM_HOST_BOUNDS "+message)
func _initialize():call_deferred("run")
func settle():
	for i in 6:await process_frame
func find_button(node:Node,text:String)->Button:
	if node is Button and node.text==text:return node
	for child in node.get_children():
		var found:=find_button(child,text)
		if found:return found
	return null
func run():
	root.content_scale_size=Vector2i.ZERO;root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	var game=Fixture.UIController.new();root.add_child(game);await settle()
	check(game.add_equipment("wind",Vector2.ZERO),"wind installed")
	for resolution in [Vector2i(1024,768),Vector2i(800,600),Vector2i(640,480)]:
		root.size=resolution;await settle();game.select_device(0);game.open_parameters(false)
		# Headless DisplayServer has an empty monitor rectangle and clamps native
		# popup_centered to 1×1. Exercise the same requested logical window size.
		if DisplayServer.get_name()=="headless":game.param_dialog.size=Vector2i(mini(940,resolution.x-24),mini(790,resolution.y-24))
		await settle()
		var bounds:=Rect2(Vector2.ZERO,Vector2(game.param_dialog.size))
		print("PARAM_BOUNDS ",resolution," window=",game.param_dialog.size," parent_v=",game.parameter_form.get_parent().get_rect()," form=",game.parameter_form.get_global_rect()," apply=",find_button(game.param_dialog,"校验并应用").get_global_rect())
		check(game.param_dialog.size.x<=resolution.x and game.param_dialog.size.y<=resolution.y,"parameter popup fits screen "+str(resolution))
		for text in ["关闭 / Esc","取消","校验并应用","恢复参考默认（待应用）"]:
			var button:=find_button(game.param_dialog,text)
			check(button!=null and bounds.encloses(button.get_global_rect()),"fixed control contained "+str(resolution)+" "+text)
		check(bounds.encloses(game.parameter_form.get_global_rect()),"scroll form fits shell "+str(resolution))
		check(bounds.encloses(game.param_errors.get_global_rect()),"error feedback fits shell "+str(resolution))
		check(not game.parameter_form.get_global_rect().intersects(find_button(game.param_dialog,"校验并应用").get_global_rect()),"form does not cover commit button")
		game.handle_escape();check(not game.param_dialog.visible,"Esc closes shell")
	for key in ["camera","lod_camera","terrain","labels","infrastructure","selection","overlay","equipment","cables"]:
		var node=game.get(key)
		if is_instance_valid(node) and node.get_parent()==null:node.free()
	game.free();await process_frame
	print("PARAMETER_HOST_BOUNDS_1003 checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
