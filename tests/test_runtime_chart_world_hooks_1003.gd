extends SceneTree
const Fixture=preload("res://tests/test_compact_build_bulk_ui_1003.gd")
class HookController:
	extends Fixture.UIController
	var fail_step:=false
	func solve_at(_time:float)->Dictionary:
		if fail_step:return {"error":"test invalid step"}
		return {"next_states":{"10":{"energy_mwh":5.0}},"devices":{"10":{"charge_mw":1.0,"discharge_mw":0.0}},"valid":true}
class ChartProbe:
	extends Control
	var host:Node
	var captures:Array=[]
	var resets:=0
	func capture_step(report:Dictionary,time:float):captures.append({"report":report.duplicate(true),"time":time,"host_time":host.elapsed_s,"inventory":host.device(10).state.energy_mwh})
	func reset_history():resets+=1;captures.clear()
	func sync_target():pass
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,note:String):
	checks+=1
	if not ok:failures.append(note);push_error("CHART_HOOK_FAIL "+note)
func _initialize():call_deferred("run")
func settle():
	for i in 6:await process_frame
func run():
	root.content_scale_size=Vector2i.ZERO;root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	var game=HookController.new();root.add_child(game);await settle()
	for resolution in [Vector2i(1180,812),Vector2i(958,660)]:
		root.size=resolution;await settle();game._layout_workspace();await settle()
		print("CHART_LAYOUT ",resolution," root=",game.hud_root.size," views=",game.hud_views.get_global_rect()," context=",game.hud_context.get_global_rect()," chart=",game.runtime_chart.get_global_rect()," available=",game.runtime_chart_layout_available)
		check(game.runtime_chart_layout_available,"supported chart size available")
		var rect:Rect2=game.runtime_chart.get_global_rect()
		check(Rect2(Vector2.ZERO,Vector2(resolution)).encloses(rect),"chart inside viewport")
		for panel in [game.hud_header,game.hud_views,game.hud_context,game.hud_build,game.hud_footer,game.hud_dock.get_node("DockRail")]:check(not rect.intersects(panel.get_global_rect()),"chart clear of "+panel.name)
	# Four scale controls + distinct source/SOC labels require 230 vertical px.
	# Do not overlay the build toolbar when this room is unavailable.
	for resolution in [Vector2i(640,480),Vector2i(480,320)]:
		root.size=resolution;await settle();game._layout_workspace();check(not game.runtime_chart_layout_available,"insufficient four-scale chart area flagged hidden")
	game.ui_regions.erase(game.runtime_chart);game.runtime_chart.free()
	var probe:=ChartProbe.new();probe.host=game;game.hud_root.add_child(probe);game.runtime_chart=probe
	game.devices=[{"id":10,"kind":"battery","x":0.0,"z":0.0,"params":game.model.defaults("battery"),"state":{"energy_mwh":0.0}}]
	game.selected_id=10;game.paused=false
	game.refresh();game.solve_at(0);check(probe.captures.is_empty(),"refresh and solve-only do not sample")
	check(game.advance(1.0),"successful committed step advances")
	check(probe.captures.size()==1,"one committed step captured")
	check(probe.captures[0].time==1 and probe.captures[0].host_time==1 and probe.captures[0].inventory==5,"capture follows committed time and inventory")
	game.fail_step=true;check(not game.advance(1.0) and probe.captures.size()==1,"failed step does not create sample")
	game.fail_step=false;game.checkpoint();check(probe.resets==1 and probe.captures.is_empty(),"checkpoint resets old scene history")
	var state:Dictionary=game.state().duplicate(true);game.restore(state);check(probe.resets==2,"restore clears history before scene application")
	for key in ["camera","lod_camera","terrain","labels","infrastructure","selection","overlay","equipment","cables"]:
		var node=game.get(key)
		if is_instance_valid(node) and node.get_parent()==null:node.free()
	game.free();await process_frame
	print("RUNTIME_CHART_WORLD_HOOKS_1003 checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
