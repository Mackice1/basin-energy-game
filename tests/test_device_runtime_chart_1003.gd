extends SceneTree
const Chart = preload("res://scripts/device_runtime_chart.gd")
const Model = preload("res://scripts/energy_model.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
class Host:
	extends Node
	const DEVICE_NAMES = {"wind":"风机","battery":"锂电","solid_thermal_store":"固体蓄热"}
	var selected_id := 0
	var paused := true
	var devices: Array = []
	var font_full: Font
	var runtime_chart_layout_available := true
	var build_tray_open := false
	func device(id: int) -> Dictionary:
		for item in devices:
			if int(item.id)==id: return item
		return {}
	func station(_id: int) -> Dictionary: return {}
	func modal_visible() -> bool: return false
var checks := 0
var failures: Array[String] = []
func check(ok: bool, message: String):
	checks+=1
	if not ok: failures.append(message);push_error(message)
func _initialize(): call_deferred("run")
func run():
	var host := Host.new();root.add_child(host)
	host.devices = [{"id":0,"kind":"wind","params":Catalog.defaults("wind"),"state":{}}]
	var chart := Chart.new();root.add_child(chart);chart.setup(host)
	var report := {"devices":{"0":{"valid":true,"generated_mw":5.0,"sent_mw":1.2}},"step_valid":true}
	chart.capture_step(report,1.0,1000)
	check(chart.sample_count==0 and not chart.visible,"paused/never run has no graph")
	host.paused=false;chart.sync_target()
	check(not chart.visible,"no data no empty chart")
	chart.capture_step(report,1.0,1000)
	check(chart.sample_count==1 and chart.visible,"first actual step appears")
	check(chart.history()[0].values[0]==1.2,"wind uses dispatched output, not potential 5MW")
	check(chart.target_name=="风机 #0","Chinese target title")
	chart.capture_step(report,1.5,1250);check(chart.sample_count==1,"simulation sample throttle")
	chart.capture_step(report,2.0,1100);check(chart.sample_count==1,"wall-time sample throttle")
	chart.capture_step(report,2.0,1400);check(chart.sample_count==2,"next genuine sample")
	for index in 300: chart.capture_step(report,float(index+3),2000+index*250)
	check(chart.sample_count==240 and chart.samples.size()==240,"bounded actual ring")
	var points:=chart.history();check(points[0].t==63.0 and points[-1].t==302.0,"ring chronological order")
	host.paused=true;chart.sync_target();check(not chart.visible,"pause hides")
	check(chart.sample_count==240,"pause invents no data")
	host.paused=false;host.selected_id=7;chart.sync_target();check(chart.sample_count==0 and not chart.visible,"deselection/deletion clears")
	host.devices.append({"id":7,"kind":"battery","params":Catalog.defaults("battery"),"state":{"energy_mwh":2.5}})
	var stored := {"devices":{"7":{"valid":true,"charge_mw":0.4,"discharge_mw":0.0}}}
	chart.capture_step(stored,304,80000)
	check(chart.has_soc and chart.power_unit=="MW","storage separate SOC and power units")
	check(chart.history()[0].soc==25.0,"SOC from committed inventory not initialSOC")
	check(chart.history()[0].values==[0.4,0.0],"real charge/discharge pair")
	chart.reset_history();check(chart.sample_count==0 and not chart.visible,"scene reset clears same-ID history")
	chart.capture_step({"devices":{"7":{"charge_mw":0.4}}},305,81000)
	check(chart.sample_count==0,"missing report is not fabricated zero")
	chart.capture_step({"devices":{"7":{"valid":false,"charge_mw":0.4,"discharge_mw":0.0}}},306,82000)
	check(chart.sample_count==0,"invalid report rejected")
	chart.capture_step(stored,307,83000)
	chart.capture_step(stored,10,84000)
	check(chart.sample_count==1 and chart.history()[0].t==10.0,"time rollback drops old scene history")
	host.devices[1]={"id":7,"kind":"solid_thermal_store","params":Catalog.defaults("solid_thermal_store"),"state":{"energy_mwhth":4.0}}
	chart.capture_step({"devices":{"7":{"charge_mwth":0.0,"discharge_mwth":0.5}}},11,85000)
	check(chart.sample_count==1 and chart.power_unit=="MWth" and chart.history()[0].soc==50.0,"thermal power not electricity")
	var before:=chart.reset_generation
	chart.capture_step({"error":"invalid","devices":{}},12,86000)
	check(chart.sample_count==1 and chart.reset_generation==before,"failed step adds no point")
	chart.dirty=true;chart.redraw_accumulator=0.0;chart._process(0.1);check(chart.dirty,"redraw capped below4Hz")
	chart._process(0.2);check(not chart.dirty,"low-frequency redraw scheduled")
	chart.size=Vector2(310,170);chart.queue_redraw();await process_frame
	check(chart.size.y==170.0,"compact actual draw no minimum overflow")
	host.build_tray_open=true;chart.sync_target();check(not chart.visible,"tray hides graph")
	host.build_tray_open=false;host.runtime_chart_layout_available=false;chart.sync_target();check(not chart.visible,"tiny viewport hides graph")
	host.runtime_chart_layout_available=true
	for kind in Catalog.implemented_kinds():
		var params: Dictionary = Catalog.defaults(kind)
		var item: Dictionary = {"id":7,"kind":kind,"params":params,"state":Catalog.initial_state(kind,params)}
		if Catalog.is_thermal(kind): item["model_profile"]=Catalog.model_profile(kind)
		host.devices=[item];host.selected_id=7;chart.reset_history()
		var actual: Dictionary = Model.dispatch([item],[],{"wind_speed_mps":12.0,"irradiance_wm2":1000.0,"air_temp_c":25.0,"dni_wm2":800.0,"dni_source":"test actual input","solar_altitude_deg":60.0,"solar_azimuth_deg":180.0,"is_day":true},{},1.0)
		chart.capture_step(actual,1.0,1000)
		if chart.sample_count!=1: print("CHART_MISSING ",kind," ",actual.get("devices",{}).get("7",{}))
		check(chart.sample_count==1,"real dispatch schema chart support "+kind)
		if chart.sample_count==1: check(chart.history()[0].values[0]==0.0,"disconnected means real zero, not available potential "+kind)
	await process_frame
	chart.queue_free();host.queue_free();await process_frame
	print("RUNTIME_CHART_1003 checks=%d failures=%d"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
