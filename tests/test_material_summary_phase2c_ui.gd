extends SceneTree
const C=preload("res://scripts/device_catalog.gd")
const Inspector=preload("res://scripts/device_inspector.gd")
const Chart=preload("res://scripts/device_runtime_chart.gd")
const HostTest=preload("res://tests/test_device_inspector_v23.gd")
const Physics=preload("res://tests/test_chemical_process_physics.gd")
const M=preload("res://scripts/energy_model.gd")
var checks:=0
var failures:Array[String]=[]
func check(ok:bool,message:String):
 checks+=1
 if not ok:failures.append(message);push_error("MATERIAL_SUMMARY_UI "+message)
func _initialize():call_deferred("run")
func run():
 root.gui_embed_subwindows=true
 var host:=HostTest.Host.new();root.add_child(host)
 var inspector:=Inspector.new();host.add_child(inspector);inspector.setup(host)
 var chart:=Chart.new()
 for kind in C.implemented_kinds():
  chart.target_kind=kind
  var expected:="产品占容" if kind in C.Materials.SYNTHESIS_KINDS else ("库存占容" if kind in C.Materials.INVENTORY_KINDS else "SOC")
  check(chart._inventory_axis_label()==expected,"correct semantic percent axis "+kind)
 for kind in C.Materials.KINDS:
  var p:Dictionary=C.defaults(kind)
  var item:Dictionary={"id":7,"kind":kind,"params":p,"state":C.initial_state(kind,p)}
  if kind in C.Materials.INVENTORY_KINDS:item.state.material_inventory_kg[C.Materials.species(kind)]=1.25
  var report:Dictionary={"generated_mw":111.0,"available_mw":222.0,"next_inventory_kg":999.0,"water_out_kg_s":.001,"water_in_kg_s":.002,"hydrogen_in_kg_s":.003,"hydrogen_out_kg_s":.004,"product_produced_kg_s":.005,"nitrogen_in_kg_s":.006,"nitrogen_out_kg_s":.007,"co2_in_kg_s":.008,"co2_out_kg_s":.009,"water_released_kg_s":.010,"oxygen_vented_kg_s":.011,"oxygen_from_air_kg_s":.012,"electric_input_mw":.02,"electric_output_mw":.03,"heat_rejected_mwth":.04,"environment_heat_in_mwth":.05}
  host.devices=[item];host.result={"devices":{"7":report}}
  var before:=var_to_bytes([host.devices,host.result,host.links])
  check(inspector.open_device(7),"material inspector opens "+kind)
  await process_frame
  var text:String=inspector.texts["运行"].text
  check(text.begins_with("已提交库存"),"committed inventory first "+kind)
  check(text.find("实际流量")<text.find("完整计算与持久状态"),"actual flows precede raw generic data "+kind)
  check(text.find("完整计算与持久状态")<text.find("111"),"unfiltered original data retained at rear "+kind)
  check(text.contains("222") and text.contains("999"),"all prior raw fields preserved "+kind)
  if kind in C.Materials.INVENTORY_KINDS:
   var summary:=inspector._material_summary(item,report)
   check(summary.contains("1.25 /") and not summary.contains("999"),"committed stock never substituted with prediction "+kind)
   check(summary.contains("库存占容") and not summary.contains("SOC"),"material summary not called SOC "+kind)
  if kind in C.Materials.SYNTHESIS_KINDS:
   var summary:=inspector._material_summary(item,report)
   check(summary.find("实际产品生成")<summary.find("氢输入"),"chemical product flow prioritized")
   check(summary.contains("0.02 MW") and summary.contains("0.04 MWth"),"separate power units")
   check(summary.contains("NH3(g)" if kind=="ammonia_synthesis_station" else "CH3OH(l)"),"actual product phase")
   check(not summary.contains("发电功率") and not summary.contains("净电输出"),"no irrelevant generation zeros in summary")
  var missing:=inspector._material_summary(item,{})
  check(missing.contains("尚无有效流量结果"),"no missing report fabricated as zero")
  check(before==var_to_bytes([host.devices,host.result,host.links]),"read-only summary "+kind)
  inspector.close_device()
 var fixtures:=Physics.new()
 for kind in C.Materials.SYNTHESIS_KINDS:
  var fixture:Dictionary=fixtures.fixture(kind);var cc:Dictionary=C.Materials.chemical_coefficients(kind)
  var report:Dictionary=M.dispatch(fixture.devices,fixture.links,{}, {"1":{"mw":cc.electric_kwh_per_kg/1000.0}},3600.0)
  check(report.valid,"real report valid")
  if not report.valid:continue
  var summary:=inspector._material_summary(fixture.devices[4],report.devices["5"])
  check(summary.contains("0 /") and not summary.contains("1 /"),"real preview leaves committed product empty")
  check(summary.contains("实际产品生成") and summary.contains("kg/s") and summary.contains("实际用电与排热"),"real process summary is populated")
  fixtures.advance(fixture,report)
  summary=inspector._material_summary(fixture.devices[4],report.devices["5"])
  var committed:float=fixture.devices[4].state.material_inventory_kg[cc.product]
  check(absf(committed-1.0)<1e-7 and summary.contains(inspector._value(committed)+" /"),"after real commit stock advances to actual one kg: "+summary)
 fixtures.free();chart.free();inspector.free();host.free();await process_frame
 print("MATERIAL_SUMMARY_PHASE2C_UI checks=",checks," failures=",failures.size());quit(0 if failures.is_empty() else 1)
