extends SceneTree
const Chart=preload("res://scripts/device_runtime_chart.gd")
const Workflow=preload("res://scripts/example_base_workflow.gd")
const Model=preload("res://scripts/energy_model.gd")
var checks:=0
var failures:=0
func check(ok:bool,label:String):
 checks+=1
 if not ok:failures+=1;push_error(label)
func _initialize():
 var chart:=Chart.new()
 var f:=Workflow.fixture()
 var r:=Model.dispatch(f.devices,f.links,Workflow.teaching_weather(82800),{},1.0)
 check(r.valid,"real multiple-sink dispatch valid")
 var station:Dictionary=r.devices["2"]
 check(r.served_mw>0 and r.charge_mw>0 and r.delivered_mw>0,"actual load charge and grid sinks active")
 check(station.sent_mw>station.delivered_mw and station.delivered_mw>0,"station sending is not grid receipt")
 for kind in ["station","collector_substation"]:
  var item:Dictionary={"kind":kind}
  var datum:Dictionary=chart._extract(item,station)
  check(datum.labels==["站端总送出","电网净接收"],kind+" truthful labels")
  check(datum.values==[station.sent_mw,station.delivered_mw] and datum.unit=="MW",kind+" genuine paired values in MW")
  var partial:Dictionary=chart._extract(item,{"sent_mw":3.0})
  check(partial.labels==["站端总送出"] and partial.values==[3.0],kind+" missing grid not guessed")
  partial=chart._extract(item,{"delivered_mw":1.0})
  check(partial.labels==["电网净接收"] and partial.values==[1.0],kind+" missing total not guessed")
  check(chart._extract(item,{}).is_empty(),kind+" absent data no sample")
  check(chart._extract(item,{"valid":false,"sent_mw":3.0,"delivered_mw":1.0}).is_empty(),kind+" invalid rejected")
  check(chart._extract(item,{"sent_mw":NAN,"delivered_mw":INF}).is_empty(),kind+" nonfinite rejected")
 chart.free()
 print("STATION_RUNTIME_CHART checks=",checks," failures=",failures)
 quit(0 if failures==0 else 1)
