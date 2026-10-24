extends Window
## A read-only inspection/comparison surface. Scene replacement requires the
## host's existing confirmation, and never writes a save.
const Workflow=preload("res://scripts/example_base_workflow.gd")
const ThemeKit=preload("res://scripts/ui_theme.gd")
var host:Node
var current:Label
var results:Label
var compare_button:Button
var refresh_button:Button
var demo_button:Button
var replay_button:Button
var source_details:Label
var running:=false
var run_token:=0

func _label(text:String,size:int=14)->Label:
 var l:=Label.new();l.text=text;l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;l.add_theme_font_size_override("font_size",size);return l
func _button(text:String,callback:Callable)->Button:
 var b:=Button.new();b.text=text;b.custom_minimum_size.y=38;b.pressed.connect(callback);return b
func setup(owner_host:Node)->void:
 host=owner_host;title="小基地：建设 → 运行 → 比较";name="BaseWorkflowPanel"
 size=Vector2i(780,580);min_size=Vector2i(580,420);transient=true;exclusive=true;visible=false
 theme=host.hud_root.theme if is_instance_valid(host.hud_root) else ThemeKit.create(load("res://assets/BasinUI.otf"))
 close_requested.connect(_close)
 var bg:=ColorRect.new();bg.color=Color("17212c");bg.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(bg);bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var margin:=MarginContainer.new();add_child(margin);margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,18)
 var column:=VBoxContainer.new();column.add_theme_constant_override("separation",10);margin.add_child(column)
 column.add_child(_label("先建通，再运行，最后公平比较",22))
 column.add_child(_label("建造：左键放置，连续 / 单次可切换，右键或 Esc 退出。连线：依次选择起点与兼容终点，右键退出。普通模式右键拖动转视角；设备朝向暂由规格固定。",13))
 var row:=HBoxContainer.new();column.add_child(row)
 demo_button=_button("载入明显风变示例（全新库存）",_request_demo);demo_button.name="LoadBeginnerExample";demo_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(demo_button)
 refresh_button=_button("刷新当前流向",_refresh);refresh_button.name="RefreshBaseFlow";row.add_child(refresh_button)
 replay_button=_button("真实气象逐小时回放（逐秒积分）",_replay);replay_button.name="ReplayRealWeather";column.add_child(replay_button)
 var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(scroll)
 var body:=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_theme_constant_override("separation",12);scroll.add_child(body)
 var provenance:=RichTextLabel.new();provenance.name="RealWeatherProvenance";provenance.bbcode_enabled=true;provenance.fit_content=true;provenance.scroll_active=false
 provenance.text="来源：[url=https://open-meteo.com/en/docs/historical-weather-api]Open-Meteo Historical Weather API[/url] / [url=https://cds.climate.copernicus.eu/datasets/reanalysis-era5-single-levels]Copernicus ERA5[/url] · [url=https://creativecommons.org/licenses/by/4.0/]CC BY 4.0[/url]。小时再分析气象，非现场实测；光伏30°朝南辐照为服务商派生。曲线是模型送出，非场站实测功率。"
 provenance.meta_clicked.connect(func(url):OS.shell_open(str(url)));body.add_child(provenance)
 source_details=_label("示例 / 比较的数据来源："+load("res://scripts/real_weather_source.gd").source_label()+"\n可回放2025-06-01 00:00至06-08 00:00，UTC+8；逐小时零阶保持，无秒级观测。",13);body.add_child(source_details)
 current=_label("");current.name="CurrentBaseFlow";body.add_child(current)
 body.add_child(HSeparator.new())
 body.add_child(_label("容量比较 · 相同初态与历史气象",18))
 body.add_child(_label("复制当前允许的设备和线路，比较 0.5× / 1× / 2× 锂电容量，充放功率不变。电池和储氢清零，水恢复参数初值；不读取当前累计量，也不写回游戏。2025-06-01 00:00→06-02 00:00（UTC+8）的同一24小时历史气象、300秒离散计算，不是实时1秒积分；气象为ERA5再分析，倾斜面辐照为派生量，设备出力仍由模型计算。\n电池仅供负荷，不供制氢或外送。全系统成本未建模，不显示伪造的成本排名。",13))
 compare_button=_button("计算三种电池容量",_compare);compare_button.name="CompareBatteryCapacity";body.add_child(compare_button)
 results=_label("尚未计算。先载入示例，也可修改参数后重新比较。");results.name="CapacityComparisonResult";body.add_child(results)
 var close:=_button("关闭 / 取消计算",_close);close.name="CloseBaseWorkflow";column.add_child(close)
func open()->void:
 _refresh();popup_centered(Vector2i(mini(780,maxi(580,host.get_viewport().size.x-40)),mini(580,maxi(420,host.get_viewport().size.y-40))))
func _close()->void:
 if running:results.text="已取消计算；未修改场景或存档。可重新计算。"
 run_token+=1;running=false;hide();_buttons(false)
func _buttons(busy:bool)->void:
 compare_button.disabled=busy;demo_button.disabled=busy;refresh_button.disabled=busy;replay_button.disabled=busy
func _replay()->void:
 if host.start_weather_replay():_close()
func _request_demo()->void:
 _close()
 host.ask("替换当前场景为8节点风光、负荷、电池、有限供水、电解和气态储氢外送示例？从2025-06-03 17:59:30（UTC+8）全新起算，18时100m风由9.73变为12.22m/s。ERA5逐小时阶梯及派生辐照，非秒级实测或场站实测出力。电池和氢从空库存开始，供水10000 kg。保留已有存档，一次撤销可恢复当前场景。",func():
  if host.beginner_base_example():call_deferred("open"))
func _refresh()->void:
 var r:Dictionary=host.result
 var m:Dictionary=r.get("material",{})
 var hydrogen:=0.0;var water:=0.0
 for d in host.devices:
  var stock:Dictionary=d.get("state",{}).get("material_inventory_kg",{})
  hydrogen+=float(stock.get("H2",0));water+=float(stock.get("H2O",0))
 current.text="当前场景 · %s · %s\n主要流向（非完整收支）\n可发电 %.3f MW → 负荷实供 %.3f MW / 储能充电 %.3f MW / 电解 %.3f MW / 储氢压缩 %.3f MW / 外送 %.3f MW\n缺供 %.3f MW · 弃电 %.3f MW · 储能放电 %.3f MW\n制氢 %.5f kg/s · 当前氢库存 %.2f kg · 当前水库存 %.2f kg\n%s"%[host.scene_name,"已暂停（下方是此时刻可运行流量）" if host.paused else "运行快照（面板打开时暂不推进，关闭后继续）",r.get("generated_mw",0),r.get("served_mw",0),r.get("charge_mw",0),m.get("electrolyzer_electric_mw",0),m.get("compression_electric_mw",0),r.get("delivered_mw",0),r.get("unserved_mw",0),r.get("curtailed_mw",0),r.get("discharge_mw",0),m.get("hydrogen_produced_kg_s",0),hydrogen,water,Workflow.explain(r,host.devices)]
func _compare()->void:
 if running:return
 var errors:String=host.capacity_comparison_layout_error()
 if not errors.is_empty():results.text="未计算："+errors;return
 var job:Dictionary=Workflow.begin_comparison(host.devices,host.links)
 if not job.get("valid",false):results.text="未计算："+str(job.get("error","不支持"));return
 running=true;run_token+=1;var token:=run_token;_buttons(true)
 var base_name:String=host.scene_name
 while not job.done:
  Workflow.step_comparison(job,4)
  results.text="正在计算 %.0f%%；关闭窗口可取消，不会修改场景或存档。"%(float(job.progress)*100.0)
  await get_tree().process_frame
  if token!=run_token:return
  if not visible:
   running=false;_buttons(false);return
 running=false;_buttons(false)
 var answer:Dictionary=job.result
 if not answer.get("valid",false):results.text="计算失败："+str(answer.get("error","模型拒绝"));return
 var lines:Array[String]=["比较快照："+base_name+"（不随当前运行自动更新）",str(answer.get("boundary",""))]
 for item in answer.cases:
  lines.append("\n%.1f MWh 电池（×%.1f）\n负荷供电 %.3f / 缺供 %.3f MWh · 外送 %.3f MWh · 弃电 %.3f MWh\n制氢 %.3f kg · 取水 %.3f kg\n期末：电池 %.3f MWh，氢 %.3f kg，水 %.3f kg"%[item.battery_capacity_mwh,item.multiplier,item.served_mwh,item.unserved_mwh,item.exported_mwh,item.curtailed_mwh,item.hydrogen_produced_kg,item.water_used_kg,item.battery_final_mwh,item.hydrogen_final_kg,item.water_final_kg])
 lines.append("\n成本：未建模。结果受固定调度规则、有限库存和线路约束影响，不保证容量越大所有指标越好。")
 results.text="\n".join(lines)
