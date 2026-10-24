extends RefCounted
## Pure historical-weather workflow. Never writes a save or mutates the live scene.
## Capacity comparison uses a fixed real-source 24 h, 300 s discrete scenario, not
## the live 1 s integrator, a forecast, economic optimization or site certification.
const RealWeather = preload("res://scripts/real_weather_source.gd")
const Model = preload("res://scripts/energy_model.gd")
const Catalog = preload("res://scripts/device_catalog.gd")
const Sites = preload("res://scripts/site_layout_support.gd")
const Series = preload("res://scripts/series_import.gd")
const Materials = preload("res://scripts/material_dispatch.gd")
const ALLOWED := ["wind","pv","station","collector_substation","load","battery","water_supply_boundary","electrolyzer_station","hydrogen_gas_store"]
const BOUNDARY := "敦煌附近ERA5再分析2025-06-01 00:00—06-02 00:00（北京时间），同一逐小时历史源，300秒零阶保持离散（不同于实时1秒步长）；100m风速经既有0.14幂律折算90m轮毂（模型假设），30°朝南GTI为服务商推算，非站点实测。仅改锂电容量，充放功率不变；初始电池/氢均空、水按参数初始库存。负荷→电池→制氢→外送，电池不供制氢/外送。非最优调度；成本未建模；不校核新布局碰撞。"

static func specification() -> Dictionary:
	var kinds := ["wind","pv","station","load","battery","water_supply_boundary","electrolyzer_station","hydrogen_gas_store"]
	var positions := [Vector2(-50,-35),Vector2(-5,-35),Vector2(20,0),Vector2(55,0),Vector2(20,35),Vector2(-35,40),Vector2(-5,40),Vector2(55,40)]
	var specs: Array = []
	for i in kinds.size():
		var p: Dictionary = Catalog.defaults(kinds[i])
		if kinds[i]=="battery":p.merge({"capacity_mwh":4.0,"charge_mw":1.0,"discharge_mw":1.0,"initial_soc":0.0},true)
		if kinds[i]=="load":p.demand_mw=1.5
		if kinds[i]=="electrolyzer_station":p.rated_electric_mw=0.5
		specs.append({"id":i,"kind":kinds[i],"params":p,"position":positions[i]})
	var links: Array = []
	for pair in [[0,2,"out","in"],[1,2,"out","in"],[2,3,"out","in"],[4,2,"ac","in"],[2,6,"out","ac_in"],[2,7,"out","ac_in"],[5,6,"water_out","water_in"],[6,7,"h2_out","h2_in"],[2,-1,"out","in"]]:
		links.append(_typed_line(specs,pair[0],pair[1],pair[2],pair[3]))
	return {"name":"风光储氢外送示例","specs":specs,"links":links,"notes":"8个节点：风光→汇集站→负荷/电池/电解与压缩/外网；有限供水→电解→有限储氢。初始电池与氢为空，水10000 kg；不是免费补能。风机轮毂90m，100m风速按既有0.14幂律折算；光伏接收30°朝南GTI推算辐照，非实测功率。"}

static func fixture() -> Dictionary:
	var spec := specification()
	var devices: Array = []
	for s in spec.specs:
		devices.append({"id":s.id,"kind":s.kind,"name":s.kind,"params":s.params.duplicate(true),"state":Catalog.initial_state(s.kind,s.params),"x":s.position.x,"z":s.position.y})
	return {"devices":devices,"links":spec.links.duplicate(true)}

static func _typed_line(specs: Array,a: int,b: int,ap: String,bp: String) -> Dictionary:
	var port: Dictionary=Catalog.port(specs[a].kind,ap)
	var line: Dictionary={"from":a,"to":b,"from_port":ap,"to_port":bp,"loss_fraction":0.01 if port.unit=="MW" else 0.0}
	for key in ["carrier","unit","species_id","phase_id","grade_id"]:
		if port.has(key):line[key]=port[key]
	line["capacity_mw" if port.unit=="MW" else "mass_flow_capacity_kg_s"]=6.0 if port.unit=="MW" else 1.0
	if b==-1:line.capacity_mw=4.0
	return line

static func weather_at(time_s: float) -> Dictionary:return RealWeather.sample(time_s)
static func real_imports() -> Array:return RealWeather.imports()
# Compatibility names for earlier integration only; no synthetic source remains.
static func teaching_weather(time_s: float) -> Dictionary:return weather_at(time_s)
static func teaching_imports() -> Array:return real_imports()

static func begin_comparison(devices: Array,links: Array,step_s: float=300.0) -> Dictionary:
	if not RealWeather.dataset().valid:return RealWeather.dataset()
	if step_s<=0.0 or step_s>3600.0 or not is_finite(step_s):return {"valid":false,"error":"比较步长须在0至3600秒之间。"}
	if devices.is_empty():return {"valid":false,"error":"请先载入示例或建立风光储氢基地。"}
	var has_battery := false
	for d in devices:
		if str(d.get("kind","")) not in ALLOWED:return {"valid":false,"error":"此比较只支持风光、汇集站、负荷、锂电、供水、电解和气态储氢；未替其他链条作假设。"}
		if d.kind=="battery":has_battery=true
	if not has_battery:return {"valid":false,"error":"需要至少一座锂电池，才能比较容量。"}
	var jobs: Array=[]
	for multiplier in [0.5,1.0,2.0]:
		var job := _begin_case(devices,links,multiplier,step_s)
		if not job.valid:return job
		jobs.append(job)
	return {"valid":true,"done":false,"index":0,"jobs":jobs,"cases":[],"step_s":step_s,"progress":0.0,"result":{}}

## Run at most budget dispatch steps, then return. Caller can await process_frame
## and discard the job to cancel. No scene tree or shared live objects are stored.
static func step_comparison(job: Dictionary,budget: int=8) -> void:
	if not job.get("valid",false) or job.get("done",false):return
	var current: Dictionary=job.jobs[job.index]
	_step_case(current,maxi(1,budget))
	if not current.valid:
		job.valid=false;job.done=true;job.result={"valid":false,"error":current.error};return
	job.progress=(float(job.index)+float(current.t)/86400.0)/3.0
	if current.done:
		job.cases.append(current.output);job.index+=1
		if job.index==3:
			job.done=true;job.progress=1.0
			job.result={"valid":true,"cases":job.cases,"duration_h":24.0,"step_s":job.step_s,"boundary":BOUNDARY.replace("300秒",str(int(job.step_s))+"秒"),"cost_modeled":false,"source":RealWeather.metadata(),"start_s":0.0,"end_s":86400.0}

static func compare_capacity(devices: Array,links: Array,step_s: float=300.0) -> Dictionary:
	var job:=begin_comparison(devices,links,step_s)
	if not job.valid:return job
	while not job.done:step_comparison(job,32)
	return job.result

static func simulate(devices: Array,links: Array,multiplier: float=1.0,step_s: float=300.0) -> Dictionary:
	if step_s<=0.0 or step_s>3600.0 or not is_finite(step_s):return {"valid":false,"error":"比较步长无效。"}
	var job:=_begin_case(devices,links,multiplier,step_s)
	if not job.valid:return job
	while not job.done:_step_case(job,32)
	return job.output if job.valid else {"valid":false,"error":job.error}

static func _begin_case(devices: Array,links: Array,multiplier: float,step_s: float) -> Dictionary:
	var copy: Array=devices.duplicate(true)
	var capacity := 0.0
	for d in copy:
		d.params=Catalog.defaults(d.kind).merged(d.get("params",{}),true)
		if d.kind=="battery":
			d.params.capacity_mwh*=multiplier;d.params.initial_soc=0.0;capacity+=float(d.params.capacity_mwh)
		if d.kind=="hydrogen_gas_store":d.params.initial_inventory_kg=0.0
		d.state=Catalog.initial_state(d.kind,d.params)
		var errors: Array=Model.validate(d.kind,d.params)
		if not errors.is_empty():return {"valid":false,"error":"方案参数不支持："+str(errors)}
		var supported: Dictionary=Sites.assess_device(d)
		if not supported.supported:return {"valid":false,"error":"容量超出当前有限规格支持范围（未计算）："+str(supported.issues)}
	var output := {"valid":true,"multiplier":multiplier,"battery_capacity_mwh":capacity,"generated_mwh":0.0,"served_mwh":0.0,"unserved_mwh":0.0,"exported_mwh":0.0,"curtailed_mwh":0.0,"hydrogen_produced_kg":0.0,"water_used_kg":0.0,"battery_final_mwh":0.0,"hydrogen_final_kg":0.0,"water_final_kg":0.0,"max_balance_error_mw":0.0,"hours":[]}
	var ledger: Dictionary=Materials.initial_energy(copy)
	return {"valid":true,"done":false,"copy":copy,"links":links.duplicate(true),"ledger":ledger,"output":output,"t":0.0,"step_s":step_s}

static func _step_case(job: Dictionary,budget: int) -> void:
	var copy: Array=job.copy
	var links: Array=job.links
	var ledger: Dictionary=job.ledger
	var output: Dictionary=job.output
	var t: float=job.t
	var step_s: float=job.step_s
	var count:=0
	while t<86400.0 and count<budget:
		var dt := minf(step_s,86400.0-t)
		# Never cross an explicit weather change with stale input.
		for edge in [(floor(t/3600.0)+1.0)*3600.0]:
			if t<edge and t+dt>edge:dt=edge-t
		var weather := weather_at(t)
		if not weather.get("valid",false):
			job.valid=false;job.done=true;job.error=weather.get("error","历史气象无效");return
		var result: Dictionary=Model.dispatch(copy,links,weather,{},dt)
		if not result.valid:
			job.valid=false;job.done=true;job.error="模型拒绝比较方案："+str(result.errors);return
		var next_ledger:Dictionary=Materials.accumulate_energy(ledger,result,dt)
		if next_ledger.is_empty():
			job.valid=false;job.done=true;job.error="比较的物质累计账本校验失败。";return
		ledger=next_ledger
		for pair in [["generated_mwh","generated_mw"],["served_mwh","served_mw"],["unserved_mwh","unserved_mw"],["exported_mwh","delivered_mw"],["curtailed_mwh","curtailed_mw"]]:output[pair[0]]+=float(result.get(pair[1],0))*dt/3600.0
		output.hydrogen_produced_kg+=float(result.get("material",{}).get("hydrogen_produced_kg_s",0))*dt
		output.water_used_kg+=float(result.get("material",{}).get("water_withdrawn_kg_s",0))*dt
		output.max_balance_error_mw=maxf(output.max_balance_error_mw,absf(float(result.balance_error_mw)))
		for d in copy:
			if result.next_states.has(str(d.id)):d.state=result.next_states[str(d.id)].duplicate(true)
		t+=dt
		if is_equal_approx(fmod(t,3600.0),0.0):output.hours.append({"hour":t/3600.0,"served_mw":result.served_mw,"unserved_mw":result.unserved_mw,"exported_mw":result.delivered_mw,"curtailed_mw":result.curtailed_mw,"hydrogen_kg_s":result.get("material",{}).get("hydrogen_produced_kg_s",0)})
		count+=1
	job.t=t;job.ledger=ledger
	if t<86400.0:return
	for d in copy:
		if d.kind=="battery":output.battery_final_mwh+=float(d.state.energy_mwh)
		if d.kind=="hydrogen_gas_store":output.hydrogen_final_kg+=float(d.state.material_inventory_kg.H2)
		if d.kind=="water_supply_boundary":output.water_final_kg+=float(d.state.material_inventory_kg.H2O)
	if not Materials.validate_energy(ledger,copy).is_empty():
		job.valid=false;job.done=true;job.error="比较最终物质账本不闭合。";return
	job.done=true

static func explain(report: Dictionary,devices: Array) -> String:
	if not report.get("valid",false):return "当前拓扑或参数无效，先处理模型错误；不显示虚构流量。"
	var out: Array[String]=[]
	if float(report.get("unserved_mw",0))>1e-7:out.append("存在缺供：当前实际供给、库存和连接能力未满足负荷。")
	if float(report.get("curtailed_mw",0))>1e-7:out.append("存在弃电：可发电量超过当前可用负荷、充能和外送通道的接收能力。")
	var material: Dictionary=report.get("material",{})
	if float(material.get("hydrogen_produced_kg_s",0))>1e-9:out.append("正在制氢；供水、电解电耗和压缩电耗已同时计入。")
	elif devices.any(func(d):return d.kind=="electrolyzer_station"):
		var water_empty:=devices.any(func(d):return d.kind=="water_supply_boundary" and float(d.get("state",{}).get("material_inventory_kg",{}).get("H2O",0))<=1e-9)
		var full:=devices.any(func(d):return d.kind=="hydrogen_gas_store" and float(d.get("state",{}).get("material_inventory_kg",{}).get("H2",0))>=float(d.params.get("capacity_kg",0))-1e-9)
		if water_empty:out.append("有供水库存耗尽，请检查该供水端及其连接。")
		if full:out.append("有储氢罐已满，请检查该制氢链的接收空间。")
		if not water_empty and not full:out.append("制氢未运行：检查剩余风光电、水管、氢管及压缩供电；电池不为电解供电。")
	out.append("固定优先规则：负荷→电池充电→制氢→外送；不是经济最优调度。")
	return "\n".join(out)
