extends SceneTree
const Interior=preload("res://scripts/station_interior.gd")
const PriorTest=preload("res://tests/test_station_interior.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func run():
	var host=PriorTest.Host.new();root.add_child(host)
	var interior=Interior.new();host.add_child(interior);interior.setup(host)
	for n in 3:
		check(interior.open_station(0),"repeated open")
		await process_frame
		interior.selected_id=123 # A selection is not an edit/modal layer.
		var echo:=InputEventKey.new();echo.keycode=KEY_ESCAPE;echo.pressed=true;echo.echo=true
		interior._window_input(echo)
		check(interior.visible,"echo cannot close page")
		interior.remove_confirmation.popup_centered();interior._pending_remove=123
		check(interior.handle_escape(),"modal Esc consumed")
		check(interior.visible and not interior.remove_confirmation.visible and interior._pending_remove==-1,"only removal confirmation dismissed")
		interior.set_interaction_mode("connect")
		interior.handle_escape()
		check(interior.visible and interior.interaction_mode=="select","only active link mode cancelled")
		interior.selected_id=123
		interior.handle_escape()
		check(not interior.visible,"selected device does not obstruct returning")
		check(host.selected_id==0,"return keeps originating station selected")
		check(not interior.handle_escape(),"hidden page does not consume another layer")
	interior.free();host.free()
	print("STATION_ESCAPE_1003 checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
