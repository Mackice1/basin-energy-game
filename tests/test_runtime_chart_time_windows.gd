extends SceneTree
const Chart=preload("res://scripts/device_runtime_chart.gd")
const Catalog=preload("res://scripts/device_catalog.gd")
class Host:
	extends Node
	const DEVICE_NAMES={"wind":"风机"}
	var selected_id:=0
	var paused:=false
	var font_full:Font
	var runtime_chart_layout_available:=true
	var build_tray_open:=false
	var devices:Array=[{"id":0,"kind":"wind","params":{},"state":{}}]
	func device(id:int)->Dictionary:return devices[0] if id==0 else {}
	func station(_id:int)->Dictionary:return {}
	func modal_visible()->bool:return false
	func runtime_curve_source_caption()->String:return "2025-06-03 18:00 UTC+8 · 源每小时/阶梯"
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,label:String):
	checks+=1
	if not ok:failures.append(label);push_error(label)
func _initialize():call_deferred("run")
func report(value:float)->Dictionary:return {"devices":{"0":{"sent_mw":value,"valid":true}},"step_valid":true}
func run():
	var host:=Host.new();root.add_child(host)
	var chart:=Chart.new();root.add_child(chart);chart.setup(host)
	check(chart.view_index==2 and chart.scale_buttons.size()==4,"default one hour and four controls")
	for i in 31:chart.capture_step(report(2.4 if i<15 else 4.8),237570.0+i,1000)
	check(chart.sample_count==31,"all accelerated committed seconds captured at identical wall time")
	var before:=chart.history()
	for index in 4:
		chart.scale_buttons[index].pressed.emit()
		check(chart.view_index==index,"button selects window %d"%index)
		check(chart.history()==before,"window change preserves raw history %d"%index)
		check(chart.view_history().size()==31,"short history remains readable %d"%index)
		check("不足窗口" in chart.view_caption(),"short history disclosed %d"%index)
	chart.reset_history()
	for t in range(15001):chart.capture_step(report(1.0 if t<7200 else 4.0),float(t),1000)
	check(chart.sample_count==14401 and chart.samples.size()==14401,"bounded four hour inclusive history")
	var all:=chart.history()
	check(all[0].t==600.0 and all[-1].t==15000.0,"ring chronological full four hours")
	for index in 4:
		chart.set_view_index(index)
		var points:=chart.view_history()
		check(points.size()==int(Chart.VIEW_SECONDS[index])+1,"window inclusive samples %d"%index)
		check(points[-1].t-points[0].t==Chart.VIEW_SECONDS[index],"window true duration %d"%index)
		check(not "不足窗口" in chart.view_caption(),"full window disclosed %d"%index)
	chart.set_view_index(3)
	var raw:=chart.view_history();var drawn:=chart.render_history(raw,100)
	check(drawn.size()<raw.size() and drawn.size()<=602,"render reduction bounded by columns not raw history")
	check(drawn[0].t==raw[0].t and drawn[-1].t==raw[-1].t,"render retains endpoints")
	check(drawn.any(func(p):return p.values[0]==1.0) and drawn.any(func(p):return p.values[0]==4.0),"render retains real extrema")
	var monotone:=true
	for i in range(1,drawn.size()):monotone=monotone and drawn[i].t>drawn[i-1].t
	check(monotone,"render points chronological")
	# Add a one-second narrow spike and an explicit unobserved gap.
	chart.reset_history()
	for i in 1001:chart.capture_step(report(9.0 if i==501 else 1.0),float(i),1000)
	chart.capture_step(report(2.0),2000,1000)
	drawn=chart.render_history(chart.view_history(),10)
	check(drawn.any(func(p):return p.values[0]==9.0),"single genuine spike not erased by decimation")
	check(drawn[-1].gap_before and drawn[-2].t==1000.0,"gap marked and both endpoints preserved")
	var count:=chart.sample_count
	chart.capture_step({"step_valid":false,"devices":{}},2001,1000)
	check(chart.sample_count==count,"failed step never invented")
	chart.capture_step(report(3.0),1.0,1000)
	check(chart.sample_count==1 and chart.history()[0].t==1.0,"rollback clears history")
	check(chart.view_index==3,"history reset preserves requested view choice")
	for index in 4:
		chart.set_view_index(index);chart.size=Vector2(350,280);chart.queue_redraw();await process_frame
		check(chart.scale_buttons[index].button_pressed,"visible control selected")
	chart.reset_history();chart.set_view_index(2)
	for i in 3276: chart.capture_step(report(1.0),float(i)*1.1,1000)
	var fractional:=chart.view_history()
	check(fractional[-1].t-fractional[0].t<3600.0,"fractional cadence need not hit window cutoff")
	check(not "不足窗口" in chart.view_caption(),"raw retained coverage determines full window")
	chart.size=Vector2(310,230);chart.queue_redraw();await process_frame
	check(chart.scale_buttons[-1].position.x+chart.scale_buttons[-1].size.x<=chart.size.x-13,"buttons inside narrow chart")
	for height in [230.0,280.0]:
		var graph:=Rect2(45,95,289,maxf(20,height-211))
		var soc_box:Rect2=chart._soc_plot_rect(graph)
		check(soc_box.position.y-6-(graph.end.y+14)>=16,"SOC label separated from elapsed axis")
		check(soc_box.end.y+3<=height-39-10,"SOC bottom label clears source caption")
	host.paused=true;chart.sync_target();check(not chart.visible,"pause unchanged")
	chart.queue_free();host.queue_free();await process_frame
	print("RUNTIME_CHART_TIME_WINDOWS checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
