extends PanelContainer
## Parameter editor; the energy model remains authoritative for all validation.
## Integration: preload this script, .new(), add_child(), then call
## set_parameters(kind, dictionary, construction_context=true). Apply with get_parameters(), followed by
## EnergyModel.validate(kind, values) and the controller's existing placement check.
## Restore defaults with the same construction_context argument. Pass false
## for an existing device so its construction-only initial_soc remains read-only.
## This control never mutates the supplied dictionary or the scene.

signal parameters_changed
signal validation_changed(errors: Array[String])

const Catalog = preload("res://scripts/device_catalog.gd")
const EnergyModel = preload("res://scripts/energy_model.gd")
const SiteSupport = preload("res://scripts/site_layout_support.gd")
const INK := Color("edf3f6")
const MUTED := Color("a5b7c4")
const BORDER := Color("344b59")
const ERROR := Color("ff9790")
const FIELD_COLOR := Color("14212b")
const ACCENT := Color("69d1bd")

# Schema describes the existing model only; bounds and default values are shown,
# not silently clamped. In particular, Cp's exact upper limit is 16/27.
const GROUPS := {
	"nitrogen_supply_boundary": [{"title": "有限氮气供给 · 库存与流量", "source": "N2(g)为外部预备物料的有限库存，不是制氮或捕集工厂。不会自动补给，不产生燃料、电量或热量；流量与库存分开计量。", "fields": [["capacity_kg", "N2(g)库存容量", "kg", "0 < 值 ≤ 1000"], ["max_outflow_kg_s", "最大供料流量", "kg/s", "0 ≤ 值 ≤ 0.1"]]}, {"title": "仅新建初始物料", "source": "初始物料作为新建时显式导入记账，仅新建可设置，且不得超过容量。已有设施不能通过单台或批量改参补料。", "fields": [["initial_inventory_kg", "新建初始物料", "kg", "0 ≤ 值 ≤ 容量"]]}],
	"co2_supply_boundary": [{"title": "有限二氧化碳供给 · 库存与流量", "source": "CO2(g)为外部预备物料的有限库存，不是制氮或捕集工厂。不会自动补给，不产生燃料、电量或热量；流量与库存分开计量。", "fields": [["capacity_kg", "CO2(g)库存容量", "kg", "0 < 值 ≤ 1000"], ["max_outflow_kg_s", "最大供料流量", "kg/s", "0 ≤ 值 ≤ 0.1"]]}, {"title": "仅新建初始物料", "source": "初始物料作为新建时显式导入记账，仅新建可设置，且不得超过容量。已有设施不能通过单台或批量改参补料。", "fields": [["initial_inventory_kg", "新建初始物料", "kg", "0 ≤ 值 ≤ 容量"]]}],
	"ammonia_synthesis_station": [{"title": "合成氨 · 产品缓冲与产量", "source": "固定profile3，产品为NH3(g)。产品留在本站有限缓冲，缓冲满则停产；无自动外售、清空或返电。反应物与产品不互换。", "fields": [["capacity_kg", "NH3(g)缓冲容量", "kg", "0 < 值 ≤ 200"], ["max_product_kg_s", "最大产品生成流量", "kg/s", "0 ≤ 值 ≤ 0.05"]]}, {"title": "实际辅电与热管理", "source": "辅机和电加热分别消耗实际AC电，排热受有限能力约束；MW电功率与MWth热功率分别计量。固定化学计量、相态、反应焓及工艺系数不可编辑，不模拟压力、催化剂、循环吹扫、启停或反应动力学。", "fields": [["rated_electric_mw", "工艺辅机电上限", "MW", "0 ≤ 值 ≤ 0.2"], ["heater_electric_mw", "工艺电加热上限", "MW", "0 ≤ 值 ≤ 0.15"], ["heat_rejection_mwth", "环境排热上限", "MWth", "0 ≤ 值 ≤ 0.4"]]}, {"title": "固定初始产品条件", "source": "新建设备不赠送产品，初始产品固定为0；已有产品只能通过真实生产积累，不提供补产物或清空按钮。", "fields": [["initial_inventory_kg", "新建初始产品", "kg", "固定0"]]}],
	"methanol_synthesis_station": [{"title": "合成甲醇 · 产品缓冲与产量", "source": "固定profile3，产品为CH3OH(l)。产品留在本站有限缓冲，缓冲满则停产；无自动外售、清空或返电。反应物与产品不互换。", "fields": [["capacity_kg", "CH3OH(l)缓冲容量", "kg", "0 < 值 ≤ 1000"], ["max_product_kg_s", "最大产品生成流量", "kg/s", "0 ≤ 值 ≤ 0.05"]]}, {"title": "实际辅电与热管理", "source": "辅机和电加热分别消耗实际AC电，排热受有限能力约束；MW电功率与MWth热功率分别计量。固定化学计量、相态、反应焓及工艺系数不可编辑，不模拟压力、催化剂、循环吹扫、启停或反应动力学。", "fields": [["rated_electric_mw", "工艺辅机电上限", "MW", "0 ≤ 值 ≤ 0.2"], ["heater_electric_mw", "工艺电加热上限", "MW", "0 ≤ 值 ≤ 0.15"], ["heat_rejection_mwth", "环境排热上限", "MWth", "0 ≤ 值 ≤ 0.4"]]}, {"title": "固定初始产品条件", "source": "新建设备不赠送产品，初始产品固定为0；已有产品只能通过真实生产积累，不提供补产物或清空按钮。", "fields": [["initial_inventory_kg", "新建初始产品", "kg", "固定0"]]}],
	"hydrogen_liquid_store": [
		{"title":"液氢储罐 · 库存与流量", "source":"气态氢在本站液化为液氢库存，出库经环境汽化后供气。容量与流量均为硬上限，不可切换相态或储氢技术。初始氢固定为0；没有充氢过程就没有可用库存。", "fields":[
			["capacity_kg","液氢库存容量","kg","0 < 值 ≤ 1000"],
			["charge_kg_s","最大充氢流量","kg/s","0 ≤ 值 ≤ 0.05"],
			["discharge_kg_s","最大供氢流量","kg/s","0 ≤ 值 ≤ 0.05"]]},
		{"title":"液化与汽化设备上限", "source":"各项均为独立设备硬上限。固定 profile：液化净电耗12 kWh/kg、出库辅电0.02 kWh/kg、气液相态焓差1.24 kWh/kg、每日蒸发0.1%。排热与环境吸热分别计量，不能作为免费返电或有用供热。", "fields":[
			["liquefier_electric_mw","液化用电上限","MW","0 ≤ 值 ≤ 1"],
			["discharge_aux_electric_mw","出库辅电上限","MW","0 ≤ 值 ≤ 0.02"],
			["heat_rejection_mwth","环境排热上限","MWth","0 ≤ 值 ≤ 1"],
			["ambient_vaporizer_mwth","环境汽化吸热上限","MWth","0 ≤ 值 ≤ 0.1"]]},
		{"title":"固定初始条件", "source":"不提供初始补氢或技术切换。现有液氢kg库存由实际运行独立保存。", "fields":[
			["initial_inventory_kg","新建初始氢库存","kg","固定0"]]}
	],
	"hydrogen_metal_hydride_store": [
		{"title":"LaNi5 固态储氢 · 宿主与流量", "source":"绑定 LaNi5 金属氢化物 profile，不可切换材料或相态。宿主干质量只在新建时选择；建成后锁定并独立保存。储氢容量由材料 profile 和干质量派生，默认10000 kg宿主对应120 kg氢容量；不提供独立容量旋钮。", "fields":[
			["dry_host_mass_kg","新建宿主干质量","kg","0 < 值 ≤ 10000"],
			["charge_kg_s","最大吸氢流量","kg/s","0 ≤ 值 ≤ 0.02"],
			["discharge_kg_s","最大释氢流量","kg/s","0 ≤ 值 ≤ 0.02"]]},
		{"title":"辅机与热管理上限", "source":"吸氢放热必须满足有限排热能力，释氢加热必须消耗实际AC电。固定材料与反应焓 profile 不可编辑；不模拟实际吸放氢动力学；热不是额外赠送的可用热库存。", "fields":[
			["charge_aux_electric_mw","吸氢辅电上限","MW","0 ≤ 值 ≤ 0.02"],
			["discharge_heater_electric_mw","释氢电加热上限","MW","0 ≤ 值 ≤ 0.4"],
			["heat_rejection_mwth","环境排热上限","MWth","0 ≤ 值 ≤ 0.4"]]},
		{"title":"固定初始条件", "source":"新建氢库存固定为0；宿主质量不是氢库存。编辑已有参数不能改变宿主、补氢或删除氢。", "fields":[
			["initial_inventory_kg","新建初始氢库存","kg","固定0"]]}
	],
"co2_liquid_cycle_store":[{"title": "闭式CO₂成套站 · 容量与功率", "source": "闭式CO₂压缩—液化—气化—膨胀成套站，含内部蓄热。工质总质量未标定，SOC=0不代表气仓无CO₂；不赠独立热库存/热输出。默认794.24MWh为内部等效库存。146MW×6.8h与100MW×6.14h来自河北院2026-10-09公开设计工况；净毛边界未核实，992.8→614MWh仅教学算术参考，非同循环实测性能。净转换系数0.8和614/794.24为教学拆分，不是压缩机/透平实测效率。默认自损0是理想化边界，可设置正值；未模拟温压/相平衡/启停。", "fields": [["capacity_mwh", "内部等效库存容量", "MWh", "0 < 值 ≤ 794.24"], ["charge_mw", "AC最大充电功率", "MW", "0 ≤ 值 ≤ 146"], ["discharge_mw", "AC最大放电功率", "MW", "0 ≤ 值 ≤ 100"]]}, {"title": "教学净转换与静置损失", "source": "同一步充放互斥。内部蓄热已在净系数内，不再次获得热量。参数不是工程保证值。", "fields": [["charge_efficiency", "净充电转换系数", "比例", "0 < 值 ≤ 1"], ["discharge_efficiency", "净返电转换系数", "比例", "0 < 值 ≤ 1"], ["self_discharge_per_h", "连续自损常数", "1/h", "0 ≤ 值 ≤ 1"]]}, {"title": "仅新建初始条件", "source": "默认能量库存为0，闭式CO₂工质仍存在。已有设备不因改参补能。", "fields": [["initial_soc", "新建初始能量比例", "比例", "0 ≤ 值 ≤ 1"]]}],
	"water_supply_boundary": [{"title": "有限供水库存", "source": "有限液态水边界，不自动补给。供水仅进入电解整站；当前库存以kg保存。教学简化未模拟水处理或水压。", "fields": [["capacity_kg", "水库存容量", "kg", "0 < 值 ≤ 1000000000"], ["max_outflow_kg_s", "最大供水流量", "kg/s", "0 ≤ 值 ≤ 1000"], ["initial_inventory_kg", "新建初始水库存", "kg", "0 ≤ 值 ≤ 容量"]]}],
	"electrolyzer_station": [{"title": "电解制氢整站", "source": "液态水+实际AC用电生成气态氢；氧排向环境。净用电包含本站辅机但不含独立储氢压缩。教学固定参数不代表品牌保证性能。电耗不得低于液水反应焓，排热不是可用供热端口。", "fields": [["rated_electric_mw", "电解净用电上限", "MW", "0 < 值 ≤ 10000"], ["max_hydrogen_kg_s", "产氢流量上限", "kg/s", "0 ≤ 值 ≤ 1000"], ["electricity_kwh_per_kg", "单位产氢净电耗", "kWh/kg", "液水反应焓下限 ≤ 值 ≤ 1000"]]}],
	"hydrogen_gas_store": [{"title": "气态储氢与压缩", "source": "独立气态氢kg库存；入库必须消耗实际压缩用电。不得用旧完整氢储能系统MWh重复计量。同一步充放互斥；气压/温度动态暂不求解。", "fields": [["capacity_kg", "气态氢容量", "kg", "0 < 值 ≤ 1000000000"], ["charge_kg_s", "最大入库流量", "kg/s", "0 ≤ 值 ≤ 1000"], ["discharge_kg_s", "最大出库流量", "kg/s", "0 ≤ 值 ≤ 1000"], ["compressor_electric_mw", "压缩机用电上限", "MW", "0 < 值 ≤ 10000"], ["compression_kwh_per_kg", "压缩单位电耗", "kWh/kg", "0 < 值 ≤ 1000"], ["leak_per_h", "连续泄漏常数", "1/h", "0 ≤ 值 ≤ 1"]]}, {"title": "仅新建初始库存", "source": "已有设备只读取运行库存，修改参数不能补氢或删除已有氢。", "fields": [["initial_inventory_kg", "新建初始氢库存", "kg", "0 ≤ 值 ≤ 容量"]]}],
	"fuel_cell_station": [{"title": "燃料电池返电整站", "source": "从气态储氢站取氢，空气氧作为显式环境边界；产生净AC电、液态产水和环境排热。效率基于氢LHV，反应焓与产水相态独立守恒。无氢不能返电。", "fields": [["rated_electric_mw", "净电出力上限", "MW", "0 < 值 ≤ 10000"], ["max_hydrogen_kg_s", "耗氢流量上限", "kg/s", "0 ≤ 值 ≤ 1000"], ["net_efficiency_lhv", "净返电效率LHV", "比例", "0 < 值 ≤ 1"]]}],
	"battery_sodium": [{"title": "钠离子电池储能 · 容量与功率", "source": "钠离子电池箱 + 双向PCS。聚合电能库存；不计算电芯化学、温度、老化或循环寿命。充放效率为可编辑教学假设，包含PCS，不重复扣逆变损耗。 同一步充放互斥；新建设备默认为空，当前库存独立保存。", "fields": [["capacity_mwh", "等效库存容量", "MWh", "0 < 值 ≤ 100000"], ["charge_mw", "AC最大充电功率", "MW", "0 ≤ 值 ≤ 10000"], ["discharge_mw", "AC最大放电功率", "MW", "0 ≤ 值 ≤ 10000"]]}, {"title": "净效率与静置损耗", "source": "充×放为不含静置自损的往返效率；辅机是否已合并按本技术边界。连续自损按库存×exp(−λ×小时)衰减，断线仍自损，暂停冻结。", "fields": [["charge_efficiency", "净充电效率", "比例", "0 < 值 ≤ 1"], ["discharge_efficiency", "净放电效率", "比例", "0 < 值 ≤ 1"], ["self_discharge_per_h", "连续自损率常数", "1/h", "0 ≤ 值 ≤ 1"]]}, {"title": "仅新建设备的初始状态", "source": "默认空库存；只用于新建初始化。已有设备的运行库存独立保存，编辑参数不能补充电量/热量，缩小容量不得抹除库存。", "fields": [["initial_soc", "新建初始库存比例", "比例", "0 ≤ 值 ≤ 1"]]}],
	"battery_flow": [{"title": "液流电池储能 · 容量与功率", "source": "正/负电解液罐 + 电堆 + 泵组 + 双向PCS。容量与功率分别约束；泵耗与PCS损耗已并入净充放效率，不额外生成电或热。未计算浓度、液位或膜传质。 同一步充放互斥；新建设备默认为空，当前库存独立保存。", "fields": [["capacity_mwh", "等效库存容量", "MWh", "0 < 值 ≤ 100000"], ["charge_mw", "AC最大充电功率", "MW", "0 ≤ 值 ≤ 10000"], ["discharge_mw", "AC最大放电功率", "MW", "0 ≤ 值 ≤ 10000"]]}, {"title": "净效率与静置损耗", "source": "充×放为不含静置自损的往返效率；辅机是否已合并按本技术边界。连续自损按库存×exp(−λ×小时)衰减，断线仍自损，暂停冻结。", "fields": [["charge_efficiency", "净充电效率", "比例", "0 < 值 ≤ 1"], ["discharge_efficiency", "净放电效率", "比例", "0 < 值 ≤ 1"], ["self_discharge_per_h", "连续自损率常数", "1/h", "0 ≤ 值 ≤ 1"]]}, {"title": "仅新建设备的初始状态", "source": "默认空库存；只用于新建初始化。已有设备的运行库存独立保存，编辑参数不能补充电量/热量，缩小容量不得抹除库存。", "fields": [["initial_soc", "新建初始库存比例", "比例", "0 ≤ 值 ≤ 1"]]}],
	"caes_aboveground": [{"title": "地上压缩空气储能 · 容量与功率", "source": "地上承压容器组 + 电驱压缩机 + 膨胀发电机。不是地下洞穴。净效率覆盖压缩、储气热管理及发电的教学损失；没有免费外部燃料或热源。聚合库存不是压力/气体质量，未计算压力、温度、流量或动态热力循环。 同一步充放互斥；新建设备默认为空，当前库存独立保存。", "fields": [["capacity_mwh", "等效库存容量", "MWh", "0 < 值 ≤ 10"], ["charge_mw", "AC最大充电功率", "MW", "0 ≤ 值 ≤ 2"], ["discharge_mw", "AC最大放电功率", "MW", "0 ≤ 值 ≤ 2"]]}, {"title": "净效率与静置损耗", "source": "充×放为不含静置自损的往返效率；辅机是否已合并按本技术边界。连续自损按库存×exp(−λ×小时)衰减，断线仍自损，暂停冻结。", "fields": [["charge_efficiency", "净充电效率", "比例", "0 < 值 ≤ 1"], ["discharge_efficiency", "净放电效率", "比例", "0 < 值 ≤ 1"], ["self_discharge_per_h", "连续自损率常数", "1/h", "0 ≤ 值 ≤ 1"]]}, {"title": "仅新建设备的初始状态", "source": "默认空库存；只用于新建初始化。已有设备的运行库存独立保存，编辑参数不能补充电量/热量，缩小容量不得抹除库存。", "fields": [["initial_soc", "新建初始库存比例", "比例", "0 ≤ 值 ≤ 1"]]}],
	"liquid_air_store": [{"title": "液态空气储能 · 容量与功率", "source": "电驱液化机/冷箱 + 低温绝热液罐 + 泵/膨胀发电机。净效率合并液化、冷/热回收与发电假设；自损代表等效待机损失，不声称计算实际蒸发量。未计算低温相变、压力或冷启动。 同一步充放互斥；新建设备默认为空，当前库存独立保存。", "fields": [["capacity_mwh", "等效库存容量", "MWh", "0 < 值 ≤ 100000"], ["charge_mw", "AC最大充电功率", "MW", "0 ≤ 值 ≤ 10000"], ["discharge_mw", "AC最大放电功率", "MW", "0 ≤ 值 ≤ 10000"]]}, {"title": "净效率与静置损耗", "source": "充×放为不含静置自损的往返效率；辅机是否已合并按本技术边界。连续自损按库存×exp(−λ×小时)衰减，断线仍自损，暂停冻结。", "fields": [["charge_efficiency", "净充电效率", "比例", "0 < 值 ≤ 1"], ["discharge_efficiency", "净放电效率", "比例", "0 < 值 ≤ 1"], ["self_discharge_per_h", "连续自损率常数", "1/h", "0 ≤ 值 ≤ 1"]]}, {"title": "仅新建设备的初始状态", "source": "默认空库存；只用于新建初始化。已有设备的运行库存独立保存，编辑参数不能补充电量/热量，缩小容量不得抹除库存。", "fields": [["initial_soc", "新建初始库存比例", "比例", "0 ≤ 值 ≤ 1"]]}],
	"hydrogen_storage_system": [{"title": "氢储能完整系统 · 容量与功率", "source": "电解制氢及压缩 → 储氢容器 → 燃料电池/逆变回发。库存MWh为氢低位热值LHV等效能量，不是可直接送出的AC电量。充电效率是电解+压缩净LHV效率；放电效率是燃料电池+逆变效率。不单设可接线氢端口，氢质量仅按33.33 kWh/kg LHV换算，不动态求解水耗、氢流体/压力或副产热。 同一步充放互斥；新建设备默认为空，当前库存独立保存。", "fields": [["capacity_mwh", "氢LHV库存容量", "MWh(LHV)", "0 < 值 ≤ 100000"], ["charge_mw", "AC最大充电功率", "MW", "0 ≤ 值 ≤ 10000"], ["discharge_mw", "AC最大放电功率", "MW", "0 ≤ 值 ≤ 10000"]]}, {"title": "净效率与静置损耗", "source": "充×放为不含静置自损的往返效率；辅机是否已合并按本技术边界。连续自损按库存×exp(−λ×小时)衰减，断线仍自损，暂停冻结。", "fields": [["charge_efficiency", "净充电效率", "比例", "0 < 值 ≤ 1"], ["discharge_efficiency", "净放电效率", "比例", "0 < 值 ≤ 1"], ["self_discharge_per_h", "连续自损率常数", "1/h", "0 ≤ 值 ≤ 1"]]}, {"title": "仅新建设备的初始状态", "source": "默认空库存；只用于新建初始化。已有设备的运行库存独立保存，编辑参数不能补充电量/热量，缩小容量不得抹除库存。", "fields": [["initial_soc", "新建初始库存比例", "比例", "0 ≤ 值 ≤ 1"]]}],
	"solid_thermal_store": [{"title": "固体介质储热 · 容量与功率", "source": "保温固体蓄热体 + 换热通道。当前仅90/60°C热水服务的等效热库存；容量是MWhth，不是电量。不自带电加热器、汽轮机或发电能力；需显式热源充热，发电需独立适配的转换链。当前90/60°C热端不兼容既有高温蒸汽发电链。未计算内部温度分布、材料热容曲线或冷启动。 同一步充放互斥；新建设备默认为空，当前库存独立保存。", "fields": [["capacity_mwhth", "储热容量", "MWhth", "0 < 值 ≤ 100000"], ["charge_mwth", "最大充热功率", "MWth", "0 ≤ 值 ≤ 10000"], ["discharge_mwth", "最大放热功率", "MWth", "0 ≤ 值 ≤ 10000"]]}, {"title": "净效率与静置损耗", "source": "充×放为不含静置自损的往返效率；辅机是否已合并按本技术边界。连续自损按库存×exp(−λ×小时)衰减，断线仍自损，暂停冻结。", "fields": [["charge_efficiency", "净充热效率", "比例", "0 < 值 ≤ 1"], ["discharge_efficiency", "净放热效率", "比例", "0 < 值 ≤ 1"], ["self_discharge_per_h", "连续自损率常数", "1/h", "0 ≤ 值 ≤ 1"]]}, {"title": "仅新建设备的初始状态", "source": "默认空库存；只用于新建初始化。已有设备的运行库存独立保存，编辑参数不能补充电量/热量，缩小容量不得抹除库存。", "fields": [["initial_soc", "新建初始库存比例", "比例", "0 ≤ 值 ≤ 1"]]}],
	"solar_tower_receiver": [{"title":"塔式集热 · 固定100镜/25m塔", "source":"100面×16m²=1600m²；镜场光学效率0.6、接收器热效率0.9为教学代理，不表示实测或商业保证。仅DNI输入，565/290°C预热稳态，不模拟冷启动、融盐或防冻能耗。", "fields":[
		["mirror_area_m2","固定镜面总面积","m²","固定1600"],["optical_efficiency","镜场光学效率","比例","0 < 值 ≤ 1"],["receiver_efficiency","接收器热效率","比例","0 < 值 ≤ 1"],["auxiliary_electric_ratio","辅机电 / 实际送热","MW/MWth","0.001 ≤ 值 ≤ 0.2"],["supply_temp_c","固定热盐温度","°C","固定565"],["return_temp_c","固定冷盐温度","°C","固定290"]]}],
	"molten_salt_store": [{"title":"双罐熔盐储热 · 固定565/290°C", "source":"0.5 MWhth，充热0.8 MWth、放热0.1 MWth为教学额定值。SOC表示相对290°C预热基线的热库存，不是实际罐温。充放互斥，盐泵必须有外部AC电；断线仍有自损。", "fields":[
		["capacity_mwhth","储热容量","MWhth","0 < 值 ≤ 100000"],["charge_mwth","最大充热功率","MWth","0 ≤ 值 ≤ 10000"],["discharge_mwth","最大放热功率","MWth","0 ≤ 值 ≤ 10000"],["charge_efficiency","充热效率","比例","0 < 值 ≤ 1"],["discharge_efficiency","放热效率","比例","0 < 值 ≤ 1"],["self_discharge_per_h","储热自损率常数","1/h","0 ≤ 值 ≤ 1"],["initial_soc","新建初始储热比例","比例","0 ≤ 值 ≤ 1"],["auxiliary_electric_ratio","盐泵电 / 充放热","MW/MWth","0.001 ≤ 值 ≤ 0.2"]]}],
	"salt_steam_generator": [{"title":"熔盐蒸汽发生器 · 盐水隔离", "source":"565/290°C熔盐直接向水蒸汽换热；固定1MPa/280°C蒸汽出口，复用既有闭合蒸汽回路。传热效率0.97，辅助盐泵须有外部AC电。已预热稳态，不走导热油。", "fields":[
		["capacity_mwth","热盐输入额定","MWth","0 < 值 ≤ 10000"],["transfer_efficiency","固定传热效率","比例","固定0.97"],["auxiliary_electric_ratio","盐泵电 / 热盐输入","MW/MWth","0.001 ≤ 值 ≤ 0.2"]]}],
	"steam_generator":[{"title":"蒸汽发生器 · 固定蒸汽工况", "source":"300/200°C Therminol 66油与水蒸汽隔离。固定1MPa/280°C出口，传热效率0.97；给水焓193.238810、蒸汽焓3008.6 kJ/kg。外部AC油泵供电不可省略；已预热，不模拟冷启动。", "fields":[["capacity_mwth","热油输入额定","MWth","0 < 值 ≤ 10000"],["transfer_efficiency","固定传热效率","比例","固定0.97"],["auxiliary_electric_ratio","油泵电 / 油热输入","MW/MWth","0.001 ≤ 值 ≤ 0.2"]]}],
	"steam_turbine":[{"title":"汽轮发电机 · 固定焓降", "source":"1MPa/280°C至10kPa；入口焓3008.6、排汽焓2426.78753 kJ/kg。固定教学等熵效率与发电机效率；实际毛电受质量流量、完整闭环和AC输出容量约束。", "fields":[["mass_flow_capacity_kg_s","蒸汽质量流量上限","kg/s","0 < 值 ≤ 1000"],["generator_efficiency","固定发电机效率","比例","固定0.95"]]}],
	"steam_condenser":[{"title":"冷凝器 · 有限环境排热", "source":"固定10kPa/45.806°C冷凝；25°C设计环境、最小端差10K。高环境温度降低排热能力；冷却辅机须有外部AC电。排热单列，不计为有用供热。", "fields":[["capacity_mwth","设计排热容量","MWth","0 < 值 ≤ 10000"],["auxiliary_electric_ratio","冷却电 / 排热","MW/MWth","0.001 ≤ 值 ≤ 0.2"],["condensing_temp_c","固定冷凝温度","°C","固定45.806"],["design_ambient_c","固定设计环境温度","°C","固定25"],["min_approach_k","固定最小端差","K","固定10"]]}],
	"feedwater_pump":[{"title":"给水泵 · 质量回流与水力功", "source":"10kPa冷凝水返回1MPa给水。固定入口焓191.81、出口焓193.238810 kJ/kg；水力增焓与电机损失分开记账。质量流量不创造水库存，闭环缺任何一段均停机。", "fields":[["mass_flow_capacity_kg_s","给水质量流量上限","kg/s","0 < 值 ≤ 1000"],["motor_efficiency","固定电机效率","比例","固定0.9"]]}],
	"parabolic_trough": [
		{"title":"槽式聚光集热器 · 开口面积基准", "source":"单槽12 m × 5.77 m = 69.24 m²。效率与热损系数为教学代理值；Therminol 66导热油，固定300/200°C，不发电。", "fields":[
			["aperture_area_m2","开口面积","m²","0 < 值 ≤ 6924"],
			["optical_efficiency","零损效率 η₀","比例","0 < 值 ≤ 1"],
			["heat_loss_w_m2k","一次热损系数 a₁","W/(m²·K)","0 ≤ 值 ≤ 20"],
			["heat_loss_quadratic_w_m2k2","二次热损系数 a₂","W/(m²·K²)","0 ≤ 值 ≤ 0.2"],
			["auxiliary_electric_ratio","辅机电 / 有用热","MW/MWth","0.001 ≤ 值 ≤ 0.2"]]},
		{"title":"固定300/200°C · DNI直接法向辐照", "source":"预热后的固定温区模型，平均油温250°C。仅接受DNI；夜间不产热。槽式单轴跟踪教学代理；无蒸汽、无发电、无室温冷启动。无辅机电不送热，多余热弃热。", "fields":[
			["supply_temp_c","固定供水温度","°C","固定300"],
			["return_temp_c","固定回水温度","°C","固定200"]]}
	],
	"high_temp_store": [
		{"title": "固定温区储热 · 容量与功率", "source": "教学假设：0.2 MWhth / 0.1 MWth，300/200°C Therminol 66导热油 理想分层/双区等效库存。供水品质固定；SOC 只表示库存比例，不是实际罐温，也不是完全混合水箱。", "fields": [
			["capacity_mwhth", "额定储热容量", "MWhth", "0 < 值 ≤ 100000"],
			["charge_mwth", "最大充热功率", "MWth", "0 ≤ 值 ≤ 10000"],
			["discharge_mwth", "最大放热功率", "MWth", "0 ≤ 值 ≤ 10000"]]},
		{"title": "储热效率与自损", "source": "教学假设：充、放热效率分别为 0.98；同一时段充放互斥。预热固定温区；放热须有下游油水换热泵或蒸汽循环辅机供电。断线仍有自损，暂停时库存冻结。", "fields": [
			["charge_efficiency", "充热效率", "比例", "0 < 值 ≤ 1"],
			["discharge_efficiency", "放热效率", "比例", "0 < 值 ≤ 1"],
			["self_discharge_per_h", "储热自损率常数", "1/h", "0 ≤ 值 ≤ 1"]]},
		{"title": "新建热库存", "source": "教学假设：新建初始 SOC 为 0，对应200°C冷端基线，非室温冷启动。热库存独立保存，改初始值不会给运行设备补热。缩小容量不得小于当前热库存，避免丢失热量。", "fields": [
			["initial_soc", "初始储热比例", "比例", "0 ≤ 值 ≤ 1"]]}
	],
	"oil_water_exchanger": [
		{"title":"油水换热器 · 300/200°C → 90/60°C", "source":"Therminol 66导热油向热水降级传热；再经隔离换热器供70/40°C需求。固定预热工况，辅机泵电 = 热油输入 × 0.01；无电不能传热。效率为能量比，非换热有效度。", "fields":[
			["capacity_mwth","热油输入额定","MWth","0 < 值 ≤ 10000"],
			["transfer_efficiency","能量传递效率","比例","0 < 值 ≤ 1"],
			["min_approach_k","最小换热温差","K","0 ≤ 值 ≤ 140"],
			["auxiliary_electric_ratio","泵电 / 热油输入","MW/MWth","0.001 ≤ 值 ≤ 0.2"]]}
	],
	"solar_thermal": [
		{"title":"非聚光真空管 · 吸热面积基准", "source":"默认30.3 m²为10个3.03 m²模块。几何数量向上取整，能量严格按输入吸热面积计算。η₀、a₁、a₂均采用吸热面积口径，不能混用总面积或采光面积。", "fields":[
			["absorber_area_m2","吸热面积","m²","0 < 值 ≤ 3030"],
			["optical_efficiency","零损效率 η₀","比例","0 < 值 ≤ 1"],
			["heat_loss_w_m2k","一次热损系数 a₁","W/(m²·K)","0 ≤ 值 ≤ 20"],
			["heat_loss_quadratic_w_m2k2","二次热损系数 a₂","W/(m²·K²)","0 ≤ 值 ≤ 0.2"],
			["auxiliary_electric_ratio","辅机电 / 有用热","MW/MWth","0.001 ≤ 值 ≤ 0.2"]]},
		{"title":"固定90/60°C · 教学等效固定面", "source":"平均流体温度75°C；按面上辐照减光学未捕获和散热计算可用热。输入为声明的固定倾斜面等效POA，不是DNI或GHI，不重复转置。非聚光、无跟踪、无蒸汽。无日照不产热，辅机无电不供热；多余热计为弃热。", "fields":[
			["supply_temp_c","固定供水温度","°C","固定90"],
			["return_temp_c","固定回水温度","°C","固定60"]]}
	],
	"wind": [
		{"title": "电功率额定值与运行风速", "source": "参考：NREL 5 MW 尺寸基线。可编辑电功率曲线；留空采用默认三次式。", "fields": [
			["rated_mw", "额定电功率", "MW", "0 < 值 ≤ 1000"],
			["cut_in_mps", "切入风速", "m/s", "0 ≤ 值 ≤ 99"],
			["rated_speed_mps", "额定风速", "m/s", "0 < 值 ≤ 100"],
			["cut_out_mps", "切出风速", "m/s", "0 < 值 ≤ 150"],
			["reference_air_density_kgm3", "参考空气密度", "kg/m³", "0.5 ≤ 值 ≤ 2.0"]]},
		{"title": "机组尺寸与转换效率", "source": "轮毂须高于转子半径；额定功率与转子、风速、效率须一致。", "fields": [
			["rotor_diameter_m", "转子直径", "m", "0 < 值 ≤ 1000"],
			["hub_height_m", "轮毂高度", "m", "0 < 值 ≤ 2000"],
			["drivetrain_efficiency", "传动链效率", "比例", "0 < 值 ≤ 1"],
			["cp_max", "最大功率系数 Cp", "无量纲", "0 < 值 ≤ 16/27"],
			["shear_exponent", "风切变指数", "无量纲", "0 ≤ 值 ≤ 1"]]}
	],
	"pv": [
		{"title": "直流阵列与逆变器", "source": "额定容量和损耗为场景假设；效率与损耗填比例，例如 0.96 = 96%。", "fields": [
			["dc_capacity_mw", "直流额定容量", "MW", "0 < 值 ≤ 10000"],
			["inverter_capacity_mw", "逆变器交流容量", "MW", "0 < 值 ≤ 10000"],
			["inverter_efficiency", "逆变器效率", "比例", "0 < 值 ≤ 1"],
			["dc_loss_fraction", "直流系统损耗", "比例", "0 ≤ 值 ≤ 1"]]},
		{"title": "温度响应与散热", "source": "Faiman 散热系数参考 Sandia PVPMC；温度系数与电池片温差为可编辑假设。", "fields": [
			["temp_coefficient_per_c", "功率温度系数", "1/°C", "−0.02 ≤ 值 ≤ 0"],
			["faiman_u0", "静态散热系数 U₀", "W/(m²·K)", "0 < 值 ≤ 500"],
			["faiman_u1", "风冷散热系数 U₁", "W·s/(m³·K)", "0 ≤ 值 ≤ 100"],
			["cell_delta_c_at_1000", "电池片温差 ΔT", "°C", "0 ≤ 值 ≤ 30"]]}
	],
	"collector_substation": [
		{"title":"基地汇集容量与损耗", "source":"教学整站：固定100×102 m占地；200 MW吞吐非120 MVA直接换算。一个星形汇集节点，不模拟电压/无功或站间级联。", "fields":[
			["capacity_mw", "接收端容量", "MW", "0 < 值 ≤ 200"],
			["loss_fraction", "站内有功损耗", "比例", "0 ≤ 值 < 1"]]}
	],
	"station": [
		{"title": "变电站容量与损耗", "source": "场景假设：容量限制作用于接收端；损耗只在通过变电站时计入一次。", "fields": [
			["capacity_mw", "接收端容量", "MW", "0 < 值 ≤ 10000"],
			["loss_fraction", "变电站损耗", "比例", "0 ≤ 值 ≤ 0.999999"]]}
	],
	"load": [
		{"title": "工业负荷与供电次序", "source": "教学假设：恒定有功需求，默认 2 MW；数字越小越优先供电，同优先级按设备编号。", "fields": [
			["demand_mw", "用电需求", "MW", "0 ≤ 值 ≤ 10000"],
			["priority", "供电优先级", "整数", "0–1000 的整数"]]}
	],
	"battery": [
		{"title": "储能容量与功率限制", "source": "教学假设：锂离子电池10 MWh / 3 MW容器式储能；容量是电量，功率是充放电速率。", "fields": [
			["capacity_mwh", "储能额定容量", "MWh", "0 < 值 ≤ 100000"],
			["charge_mw", "最大充电功率", "MW", "0 ≤ 值 ≤ 10000"],
			["discharge_mw", "最大放电功率", "MW", "0 ≤ 值 ≤ 10000"]]},
		{"title": "效率与自放电", "source": "教学假设：充、放电效率分别为 0.9，往返效率为 0.81；自放电默认关闭。", "fields": [
			["charge_efficiency", "充电效率", "比例", "0 < 值 ≤ 1"],
			["discharge_efficiency", "放电效率", "比例", "0 < 值 ≤ 1"],
			["self_discharge_per_h", "自放电率常数", "1/h", "0 ≤ 值 ≤ 1"]]},
		{"title": "新建设备初始状态", "source": "教学假设：新建时初始 SOC 为 0.5。当前储能电量独立保存；编辑参数不会恢复初始电量。", "fields": [
			["initial_soc", "初始荷电状态", "比例", "0 ≤ 值 ≤ 1"]]}
	],
	"electric_boiler": [
		{"title": "电热水锅炉 · 固定温区", "source": "教学假设：交流电输入 → 90/60°C 热水服务；温区固定，不可自由编辑。已充水、固定工作点，循环辅机包含在等效效率内。首版不求解液压、压力或蒸汽。", "fields": [
			["rated_electric_mw", "额定电输入功率", "MW", "0 < 值 ≤ 10000"],
			["thermal_efficiency", "电热转换效率", "比例", "0 < 值 ≤ 1"]]}
	],
	"fuel_boiler": [
		{"title": "燃气热水锅炉 · 低位热值边界", "source": "教学假设：天然气低位热值（LHV）输入 2 MW，效率 0.90，热水固定 90/60°C。形体尺度参考 Bosch Uni 3000 F 官方型录；运行额定及效率并非具体厂商规格。不模拟蒸汽、启动过程、压力或液压。", "fields": [
			["rated_fuel_mw", "额定燃料输入", "MW(LHV)", "0 < 值 ≤ 10000"],
			["thermal_efficiency", "燃料热效率", "比例 / LHV", "0 < 值 ≤ 1"]]},
		{"title": "辅机用电 · 与燃料输入联动", "source": "教学假设：辅机电功率 = 燃料输入功率 × 辅机比例；默认 0.01。辅机须从 ac_in 接收交流电，无可用电或热出口时不燃烧。辅机耗电单独记为电散失，不再计入热输出。", "fields": [
			["auxiliary_electric_ratio", "辅机电 / 燃料功率", "比例", "0.001 ≤ 值 ≤ 0.2"]]},
		{"title": "基地共享天然气供应", "source": "天然气供应开关、功率上限、低位热值及价格在基地资源中统一设置，所有燃气锅炉共用，不是设备库存。体积流率 = 燃料 MW × 1000 ÷ 低位热值 kWh/Nm³；成本 = 燃料 MW × 价格 元/MWh(LHV)。Nm³ 按 0°C、101.325 kPa 教学标准状态显示。默认热值和价格均为教学假设，不是市场报价；完整来源见随附《燃气锅炉来源与假设》。", "fields": []}
	],
	"thermal_store": [
		{"title": "固定温区储热 · 容量与功率", "source": "教学假设：4 MWhth / 2 MWth，90/60°C 理想分层/双区等效库存。供水品质固定；SOC 只表示库存比例，不是实际罐温，也不是完全混合水箱。", "fields": [
			["capacity_mwhth", "额定储热容量", "MWhth", "0 < 值 ≤ 100000"],
			["charge_mwth", "最大充热功率", "MWth", "0 ≤ 值 ≤ 10000"],
			["discharge_mwth", "最大放热功率", "MWth", "0 ≤ 值 ≤ 10000"]]},
		{"title": "储热效率与自损", "source": "教学假设：充、放热效率分别为 0.98；同一时段充放互斥。已充水、固定工作点，循环辅机包含在等效效率内。断线仍有自损，暂停时库存冻结。", "fields": [
			["charge_efficiency", "充热效率", "比例", "0 < 值 ≤ 1"],
			["discharge_efficiency", "放热效率", "比例", "0 < 值 ≤ 1"],
			["self_discharge_per_h", "储热自损率常数", "1/h", "0 ≤ 值 ≤ 1"]]},
		{"title": "新建热库存", "source": "教学假设：新建初始 SOC 为 0。热库存独立保存，改初始值不会给运行设备补热。缩小容量不得小于当前热库存，避免丢失热量。", "fields": [
			["initial_soc", "初始储热比例", "比例", "0 ≤ 值 ≤ 1"]]}
	],
	"heat_exchanger": [
		{"title": "隔离换热器 · 固定降温档", "source": "教学假设：热侧 90/60°C → 冷侧 70/40°C，只能降级供热，温区不可编辑。两侧供水端和回水端温差均为 20 K，都须达到最小换热温差。热连接代表一组供回水服务，不是单根质量流量管。", "fields": [
			["capacity_mwth", "热侧输入额定", "MWth", "0 < 值 ≤ 10000"],
			["transfer_efficiency", "能量传递效率", "比例", "0 < 值 ≤ 1"],
			["min_approach_k", "最小换热温差", "K", "0 ≤ 值 ≤ 20"]]},
		{"title": "换热边界说明", "source": "教学假设：已充水、固定工作点，循环辅机包含在等效效率内。效率是冷侧热输出 / 热侧吸收热量，其余散失到环境；不是换热有效度。首版未实现流量、比热、传热面积或液压模型。", "fields": []}
	],
	"heat_demand": [
		{"title": "独立热需求 · 固定服务温区", "source": "教学假设：70/40°C 恒定热需求，经隔离换热器供给；不能直连 90/60°C 锅炉。仅支持常量，不支持热需求时序导入；电功率 CSV 不作为热需求。", "fields": [
			["demand_mwth", "用热需求", "MWth", "0 ≤ 值 ≤ 10000"],
			["priority", "供热服务优先值", "整数", "0–1000 的整数"]]},
		{"title": "供热服务权重", "source": "教学假设：数值越小，缺供惩罚权重越高；优化以加权缺供为目标，不是严格优先级调度。电热服务权重是教学设定，不代表经济等价。已充水、固定工作点，循环辅机包含在设备等效效率内。", "fields": []}
	]
}

const FIELD_NOTES := {
	"rated_mw": "额定交流电功率上限；默认三次式还须满足转子捕获功率及传动链效率的联合约束。",
	"cut_in_mps": "切入 ≤ 实际风速 < 切出时运行；默认三次式另须满足切入 < 额定 < 切出。",
	"rated_speed_mps": "默认三次式达到额定功率的风速；自定义曲线按其点集插值，不由此字段重塑。",
	"reference_air_density_kgm3": "电功率曲线的参考空气密度；运行出力按实际密度与参考密度之比修正。",
	"cut_out_mps": "达到或超过切出风速时出力为零。",
	"rotor_diameter_m": "影响扫风面积与设备占地；单台修改仍需通过场地检查。",
	"hub_height_m": "须大于转子半径；有明确测风高度时才用于风速换算。",
	"drivetrain_efficiency": "气动功率至电功率的简化合并效率；0.944 表示 94.4%。",
	"cp_max": "气动功率系数上限，须不超过 Betz 极限 16/27（约 0.592593）。",
	"shear_exponent": "仅当气象数据提供测风参考高度时用于幂律换算；0.14 为场景近似。",
	"dc_capacity_mw": "标准测试条件下的直流额定容量；不是所有工况下的直流硬上限。",
	"inverter_capacity_mw": "交流输出上限；超过该值的转换后功率记为逆变器削峰。",
	"inverter_efficiency": "采用恒定效率简化；0.96 表示 96%，不应填写 96。",
	"dc_loss_fraction": "直流侧系统损耗比例；0.02 表示 2%。",
	"temp_coefficient_per_c": "相对 25°C 的线性功率温度系数；−0.004 表示每升高 1°C 下降 0.4%。",
	"faiman_u0": "Faiman 温度模型中的无风散热项；参考值 25。",
	"faiman_u1": "Faiman 温度模型中的风冷项；参考值 6.84，采用阵列局部风速。",
	"cell_delta_c_at_1000": "组件面辐照度为 1000 W/m² 时，电池片相对组件的温差；默认 3°C。",
	"capacity_mw": "变电站接收端损耗前的吞吐容量；不改变固定 4 MW 电网外送限制。",
	"loss_fraction": "变电站输入功率的损耗比例；0.01 表示 1%，上限为 0.999999。",
	"demand_mw": "负荷端需要接收的有功功率。当前采用恒定教学负荷；不足部分记为未供电功率，不算弃电。",
	"priority": "供电分配先满足数字较小的负荷；同优先级按设备编号排序。须填写 0–1000 的整数。",
	"capacity_mwh": "可存储的电量上限，单位 MWh，与充放电功率 MW 不同；运行电量独立于参数保存。",
	"charge_mw": "交流连接端吸收的充电功率上限；实际存入电量还须乘充电效率。0 表示不允许充电。",
	"discharge_mw": "交流连接端送出的放电功率上限；为送出这些电量，储能内部消耗须除以放电效率。0 表示不允许放电。",
	"charge_efficiency": "充电输入电量转成储能内部电量的比例；0.9 表示 90%，其余计入充电损耗。",
	"discharge_efficiency": "储能内部消耗电量转成放电输出电量的比例；0.9 表示 90%，其余计入放电损耗。",
	"self_discharge_per_h": "连续自放电率常数 λ，单位 1/h；按 E × exp(−λ × 小时) 衰减。0 表示不自放电；λ = 1 时一小时后剩余约 36.8%。",
	"initial_soc": "仅用于新建设备初始化：初始电量 = 容量 × 初始 SOC。0.5 表示 50%；已有设备的当前电量单独保存，编辑此草稿不会补充电量。"
}


const THERMAL_FIELD_NOTES := {
	"electric_boiler": {
		"rated_electric_mw": "交流电端实际收到的功率上限，单位 MW；出热功率 = 电输入 × 电热效率，单位 MWth。无可用热出口时不耗电。",
		"thermal_efficiency": "热输出 / 电输入。0.98 表示 98%；差额为转换损失。循环辅机已包含在此等效边界内，不重复扣电。"
	},
	"fuel_boiler": {
		"rated_fuel_mw": "天然气低位热值输入功率上限；默认 2.0 MW(LHV)。热输出 = 实际燃料输入 × 燃料热效率；还受共享供应、辅机电、管线和热需求限制。",
		"thermal_efficiency": "有用热输出 / 燃料低位热值输入；默认 0.90，额定出热 1.8 MWth。燃料差额单独记为转换散失；不得将高位热值（HHV）效率混入此边界。",
		"auxiliary_electric_ratio": "辅机电功率 / 燃料低位热值输入功率，不是热输出比例。默认 0.01，即额定燃料 2 MW 时辅机 0.02 MW；须为正数，单独计入电平衡和电散失。"
	},
	"thermal_store": {
		"capacity_mwhth": "热能库存上限，单位 MWhth，与热功率 MWth、电库存 MWh 分开。缩容不能低于当前库存；本表不修改运行库存。",
		"charge_mwth": "储热输入端实际收到的热功率上限；存入热量还须乘充热效率。0 表示不允许充热；同一时段不可同时充放。",
		"discharge_mwth": "储热输出端送出的热功率上限；内部消耗热量须除以放热效率。0 表示不允许放热；同一时段不可同时充放。",
		"charge_efficiency": "输入热量存入热库存的比例；0.98 表示 98%，差额作为充热转换损失。",
		"discharge_efficiency": "内部消耗热量转为输出热量的比例；0.98 表示 98%，差额作为放热转换损失。",
		"self_discharge_per_h": "连续热自损率常数，按库存 × exp(−常数 × 小时) 在时段开始衰减。默认 0.002/h；断线仍自损，暂停不自损。",
		"initial_soc": "仅用于新建设备：初始热库存 = 容量 × 初始 SOC。已有热库存独立保存；不是罐内实际温度，不会随参数编辑重新初始化。"
	},
	"heat_exchanger": {
		"capacity_mwth": "热侧输入额定功率，单位 MWth；冷侧最大输出还要乘能量传递效率。两路流入共用此能力，不能复制热量。",
		"transfer_efficiency": "冷侧热输出 / 热侧吸收热量，差额散失到环境。不是换热有效度；本版没有流量、比热、传热面积所需的详细换热模型。",
		"min_approach_k": "固定档 90/60→70/40°C 的供水端温差 90−70=20 K、回水端温差 60−40=20 K，两端都必须满足此值；不会提温。"
	},
	"heat_demand": {
		"demand_mwth": "需求端实际需要收到的热功率，单位 MWth；不足部分单独计入缺热，与缺电分开。当前仅支持恒定热需求。",
		"priority": "0–1000 的整数，数值越小权重越高。优化器最小化加权缺供，不能称为严格优先级；教学电热服务权重不代表经济等价。"
	}
}

static func construction_only(key:String)->bool:
	return key in ["initial_soc","initial_inventory_kg","dry_host_mass_kg"]

static func fixed_field(kind:String,key:String)->bool:
	for group in GROUPS.get(kind,[]):
		for field in group.fields:
			if field[0]==key:return str(field[3]).begins_with("固定")
	return false

func _field_note(key: String) -> String:
	if _kind in Catalog.Materials.CHEMICAL_KINDS:
		if key=="initial_inventory_kg":return "产品固定0，不赠送或补充产品。" if _kind in Catalog.Materials.SYNTHESIS_KINDS else "仅新建可设置，作为有限外部物料导入记账；已有设备不可改。"
		if key=="capacity_kg":return "kg为本站物料/产品库存容量，不是流量或能量；缩容不能抹除现有库存。"
		if key.ends_with("kg_s"):return "kg/s是实际供料或产品生成流量上限，不是kg库存；受剩余库存、缓冲容量与实际能源约束。"
		if key=="heat_rejection_mwth":return "MWth是环境排热硬上限，不是电功率，也不是可外送有用热。"
		return "有限实际AC设备功率；固定工艺和反应profile不可编辑，不额外创造物料或能量。"
	if _kind in ["hydrogen_liquid_store","hydrogen_metal_hydride_store"]:
		if key=="initial_inventory_kg":return "固定0 kg，仅从实际接入氢流积累库存；没有初始补氢入口。"
		if key=="dry_host_mass_kg":return "仅新建可设置的 LaNi5 宿主干质量；建成后与保存的宿主质量一致，不可单改或批改。氢容量由固定材料 profile 派生。"
		if key in ["charge_kg_s","discharge_kg_s"]:return "kg/s为实际氢流量上限，不是kg库存或MW功率；同时受AC辅电和有限热管理能力约束。"
		if key=="capacity_kg":return "液氢库存kg硬上限；缩容不得抹除当前实际氢库存。"
		if key in ["heat_rejection_mwth","ambient_vaporizer_mwth"]:return "MWth为有限环境换热硬上限，与MW电功率分开；不是可外送热端口。"
		return "本站设备的MW电功率硬上限，不改变固定profile单位电耗、相态或材料。"
	if _kind == "solid_thermal_store":
		return str(THERMAL_FIELD_NOTES.thermal_store.get(key, ""))
	if Catalog.is_electric_storage(_kind):
		if key == "capacity_mwh": return "储能内部等效库存上限；送出AC电量还须乘放电效率。氢储能以LHV计量，其余采用声明的聚合能量口径，不是压力或温度。"
		if key == "charge_efficiency": return "AC输入电量转成内部等效库存的净比例，包含当前技术链的转换与辅机损失。氢系统为电解+压缩LHV效率。"
		if key == "discharge_efficiency": return "内部等效库存转为AC输出电量的净比例；氢系统为燃料电池+逆变效率。充×放为不含静置损失的往返效率。"
	if _kind == "molten_salt_store":
		if key == "self_discharge_per_h": return "连续热自损率常数；默认0.005/h。预热565/290°C双罐热库存按exp(−λt)衰减；断线仍自损，暂停冻结。"
		if key == "auxiliary_electric_ratio": return "盐泵AC电 / 实际充入或放出热量；同一时段充放互斥，无外部AC不可充放。"
		if THERMAL_FIELD_NOTES.thermal_store.has(key): return THERMAL_FIELD_NOTES.thermal_store[key]
	if _kind == "solar_tower_receiver":
		if key == "mirror_area_m2": return "固定100面16m²镜面，总面积1600m²；修改不能暗中改变实体镜数。"
		if key == "optical_efficiency": return "镜场光学效率教学代理，含余弦、遮挡、反射与截获影响；不另重复扣除这些损失。"
		if key == "receiver_efficiency": return "接收器有效传热 / 光学截获能量；默认0.9为预热稳态教学代理。"
		if key == "auxiliary_electric_ratio": return "接收器与镜场辅助AC / 实际送出盐热；没有外部AC时不送热，剩余可用热计弃热。"
	if _kind == "salt_steam_generator":
		if key == "capacity_mwth": return "565/290°C热盐输入额定，蒸汽有效吸热须乘0.97；共享输入容量不因多条盐管而复制。"
		if key == "auxiliary_electric_ratio": return "独立盐泵AC / 实际热盐输入，计入Rankine辅机总电；不重复算入接收器或盐罐辅机。"
	return str(THERMAL_FIELD_NOTES.get(_kind, {}).get(key, FIELD_NOTES.get(key, "")))

var _kind := ""
var _construction_context := true
var _original: Dictionary = {}
var _fields: Dictionary = {}
var _displayed: Dictionary = {}
var _labels: Dictionary = {}
var _scroll: ScrollContainer
var _groups: VBoxContainer
var _status: Label
var _summary: Label
var _derived_capacity: Label
var _loading := false
var _curve_editor: TextEdit
var _curve_status: Label
var _curve_displayed_text := ""
var _curve_original_rows: Dictionary = {}

func _init() -> void:
	custom_minimum_size = Vector2(0, 160)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", _style(Color("0c151e"), BORDER, 8, 10))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	add_child(body)
	_summary = _label("", 14, MUTED)
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_summary)
	_scroll = ScrollContainer.new()
	_scroll.name = "ParameterScroll"
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.custom_minimum_size.y = 60
	_scroll.follow_focus = true
	body.add_child(_scroll)
	_groups = VBoxContainer.new()
	_groups.name = "ParameterGroups"
	_groups.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_groups.add_theme_constant_override("separation", 14)
	_scroll.add_child(_groups)
	_status = _label("", 14, MUTED)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.max_lines_visible = 3
	_status.add_theme_stylebox_override("normal", _style(FIELD_COLOR, BORDER, 6, 8))
	body.add_child(_status)

## Missing accepted fields inherit model defaults. Unknown supplied fields are
## retained so validate() rejects them rather than silently discarding data.
func set_parameters(kind: String, values: Dictionary, construction_context: bool = true) -> void:
	_loading = true
	_kind = kind
	_construction_context = construction_context
	_original = EnergyModel.defaults(kind)
	_original.merge(values.duplicate(true), true)
	_fields.clear()
	_displayed.clear()
	_labels.clear()
	_derived_capacity = null
	_curve_editor = null
	_curve_status = null
	_curve_displayed_text = ""
	_curve_original_rows.clear()
	for child in _groups.get_children():
		_groups.remove_child(child)
		child.queue_free()
	var defaults: Dictionary = EnergyModel.defaults(kind)
	_summary.text = "数值为当前草稿；检查并应用后生效。比例按 0–1 填写；悬停查看解释。"
	if Catalog.is_electric_storage(kind):
		_summary.text += " 初始 SOC 只用于新建设备。" if construction_context else " 当前电量独立保存；初始 SOC 在此只读。"
	elif Catalog.is_thermal_storage(kind):
		_summary.text += " 初始 SOC 只用于新建设备。" if construction_context else " 当前热库存独立保存；初始 SOC 在此只读。"
	if kind in ["hydrogen_liquid_store","hydrogen_metal_hydride_store"]:
		_summary.text+=" 初始氢固定0 kg；固定技术profile不可更换。"
		if kind=="hydrogen_metal_hydride_store":_summary.text+=" 宿主质量仅新建可改。" if construction_context else " 现有LaNi5宿主质量锁定，氢容量派生。"
	if kind in Catalog.Materials.SYNTHESIS_KINDS:_summary.text+=" 初始产品固定0；有限缓冲满则停产，无自动外售或清空。"
	elif kind in Catalog.Materials.FEED_KINDS:_summary.text+=" 有限物料，初始导入仅新建可设；已有设备不补料。"
	if THERMAL_FIELD_NOTES.has(kind):
		_summary.text += " MWth 表示热功率，MWhth 表示热量；温区固定。"
	for group_index in GROUPS.get(kind, []).size():
		_add_group(GROUPS[kind][group_index], defaults)
		if kind == "wind" and group_index == 0:
			_add_curve_editor()
	_scroll.scroll_vertical = 0
	_loading = false
	_refresh_validation()

## Valid numeric text becomes a number. Invalid/empty text stays a string so
## the existing model validator blocks application; no value is auto-clamped.
func get_parameters() -> Dictionary:
	var result: Dictionary = _original.duplicate(true)
	for key in _fields:
		# Construction-only values cannot be changed through an existing-device
		# draft, including programmatic text changes to its read-only editor.
		if (construction_only(key) and not _construction_context) or (key=="initial_inventory_kg" and fixed_field(_kind,key)):
			continue
		var raw: String = (_fields[key] as LineEdit).text.strip_edges()
		# Preserve untouched original numeric precision and integer types.
		if raw != str(_displayed.get(key, "")):
			result[key] = raw.to_float() if raw.is_valid_float() else raw
	if is_instance_valid(_curve_editor) and _curve_editor.text != _curve_displayed_text:
		result["power_curve_kw"] = _parse_curve(_curve_editor.text)
	return result

func get_validation_errors() -> Array[String]:
	var result: Array[String] = []
	for error in EnergyModel.validate(_kind, get_parameters()):
		result.append(_humanize_error(error))
	for error in _site_validation_errors().values():
		if not str(error) in result: result.append(str(error))
	return result

func _field_range(key: String, fallback: String) -> String:
	var limits: Dictionary = SiteSupport.parameter_limits(_kind)
	if not limits.has(key): return fallback
	var bound: Dictionary = limits[key]
	var minimum := float(bound.min)
	var maximum := float(bound.max)
	if minimum == maximum: return "固定安装规格 " + String.num(maximum, 6)
	# Fixed process/profile values remain fixed even when the site envelope is looser.
	if fallback.begins_with("固定"): return fallback
	var exclusive: bool = bool(bound.get("min_exclusive", false)) or (minimum==0.0 and fallback.begins_with("0 <"))
	return "%s %s 值 ≤ %s" % [String.num(minimum,6), "<" if exclusive else "≤", String.num(maximum,6)]

func _field_range_note(key: String) -> String:
	var note := _field_note(key)
	if SiteSupport.parameter_limits(_kind).has(key):
		note += "\n本设施支持范围来自统一安装规格；旧存档原值只显示、不自动截断，应用参数必须满足当前范围。"
		if key.begins_with("capacity_"):
			note += "当前库存不得因缩容丢弃；若库存超过目标容量，须先消耗库存。"
	return note

func _site_validation_errors() -> Dictionary:
	var errors: Dictionary = {}
	var complete: Dictionary = Catalog.defaults(_kind)
	complete.merge(get_parameters(), true)
	var limits: Dictionary = SiteSupport.parameter_limits(_kind)
	for key in limits:
		var bound: Dictionary = limits[key]
		var value: Variant = complete.get(key)
		if not (value is int or value is float) or not is_finite(float(value)):
			errors[key] = str(_labels.get(key,key)) + "须填写有效且有限的数值。"
		elif float(value)<float(bound.min) or float(value)>float(bound.max) or (bool(bound.get("min_exclusive",false)) and float(value)==float(bound.min)):
			var allowed := _field_range(str(key), "")
			errors[key] = "%s超出本设施支持范围：%s %s。旧值未自动修改。" % [_labels.get(key,key), allowed, bound.get("unit","")]
			if str(key).begins_with("capacity_"): errors[key] += "若当前库存超过目标容量，须先消耗库存，不可丢弃。"
	return errors

func _add_group(group: Dictionary, defaults: Dictionary) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(Color("14212b"), BORDER, 8, 9))
	_groups.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)
	var heading := Button.new()
	heading.text = str(group.title) + "  ▾"
	heading.alignment = HORIZONTAL_ALIGNMENT_LEFT
	heading.toggle_mode = true
	heading.button_pressed = true
	heading.custom_minimum_size.y = 40
	heading.add_theme_font_size_override("font_size", 16)
	for state in ["normal", "hover", "pressed", "focus"]:
		heading.add_theme_stylebox_override(state, _style(Color("1c2d3a") if state == "normal" else Color("263e4d"), BORDER, 6, 6))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		heading.add_theme_color_override(state, ACCENT)
	heading.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), ACCENT, 6, 6, 2))
	body.add_child(heading)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	body.add_child(content)
	heading.toggled.connect(func(open: bool):
		content.visible = open
		heading.text = str(group.title) + ("  ▾" if open else "  ▸"))
	var source := _label(str(group.source), 13, MUTED)
	source.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	source.add_theme_constant_override("line_spacing", 4)
	source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(source)
	if not group.fields.is_empty():
		var explanation := Button.new()
		explanation.name = "ParameterAssumptions"
		explanation.text = "模型与损耗说明  ▸"
		explanation.alignment = HORIZONTAL_ALIGNMENT_LEFT
		explanation.flat = true
		explanation.toggle_mode = true
		explanation.add_theme_font_size_override("font_size", 13)
		explanation.add_theme_color_override("font_color", MUTED)
		explanation.tooltip_text = str(group.source)
		content.add_child(explanation)
		source.visible = false
		explanation.toggled.connect(func(show: bool):
			source.visible = show
			explanation.text = "模型与损耗说明" + ("  ▾" if show else "  ▸"))
	if group.fields.is_empty():
		return
	if _kind == "hydrogen_metal_hydride_store" and group.fields.any(func(field): return field[0] == "dry_host_mass_kg"):
		var capacity_row := HBoxContainer.new()
		capacity_row.add_theme_constant_override("separation", 10)
		content.add_child(capacity_row)
		var caption := _label("派生氢容量", 14, MUTED)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		capacity_row.add_child(caption)
		_derived_capacity = _label("—", 22, INK)
		_derived_capacity.name = "DerivedHydrogenCapacity"
		capacity_row.add_child(_derived_capacity)
		var unit := _label("kg H₂", 13, MUTED)
		unit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		capacity_row.add_child(unit)
		capacity_row.tooltip_text = "由已绑定LaNi5材料profile与宿主干质量计算；不是独立可编辑字段，也不是当前氢库存。"
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	content.add_child(grid)
	for caption in ["参数", "数值", "单位", "允许范围 / 默认参考"]:
		grid.add_child(_label(caption, 14, MUTED))
	for field in group.fields:
		var key: String = field[0]
		var range_text := _field_range(key, str(field[3]))
		var range_note := _field_range_note(key)
		_labels[key] = str(field[1])
		var title := _label(str(field[1]), 16, INK)
		title.custom_minimum_size.x = 154
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title.tooltip_text = key + "\n" + range_note + "\n允许范围：" + range_text
		grid.add_child(title)
		var editor := LineEdit.new()
		editor.name = key
		editor.set_meta("parameter_key", key)
		editor.set_meta("parameter_label", str(field[1]))
		editor.set_meta("parameter_unit", str(field[2]))
		editor.set_meta("parameter_range", range_text)
		editor.set_meta("parameter_default", defaults.get(key, ""))
		editor.set_meta("parameter_note", range_note)
		editor.set_meta("construction_only", construction_only(key))
		editor.editable = (not construction_only(key) or _construction_context) and not fixed_field(_kind,key)
		editor.custom_minimum_size = Vector2(125, 40)
		editor.alignment = HORIZONTAL_ALIGNMENT_RIGHT
		editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		editor.text = str(_original.get(key, defaults.get(key, "")))
		_displayed[key] = editor.text
		editor.placeholder_text = "输入数值"
		editor.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
		editor.select_all_on_focus = true
		editor.add_theme_font_size_override("font_size", 18)
		editor.add_theme_color_override("font_color", INK)
		editor.add_theme_color_override("font_uneditable_color", MUTED)
		editor.add_theme_color_override("caret_color", INK)
		editor.add_theme_color_override("selection_color", Color("315c66"))
		editor.add_theme_stylebox_override("normal", _style(FIELD_COLOR, BORDER, 7, 7))
		editor.add_theme_stylebox_override("read_only", _style(Color("101c26"), BORDER, 7, 7))
		editor.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), ACCENT, 7, 7, 2))
		editor.tooltip_text = range_note + "\n允许范围：" + range_text
		if not editor.editable:
			editor.tooltip_text = "只读参数 · 此处不可修改\n" + editor.tooltip_text
		editor.text_changed.connect(func(_text: String): _on_field_changed())
		grid.add_child(editor)
		_fields[key] = editor
		var unit := _label(str(field[2]), 14, MUTED)
		unit.custom_minimum_size.x = 75
		unit.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		unit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		unit.tooltip_text = range_note
		grid.add_child(unit)
		var reference := _label(range_text + "\n默认 " + str(defaults.get(key, "—")), 14, MUTED)
		reference.custom_minimum_size.x = 145
		reference.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reference.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		reference.add_theme_constant_override("line_spacing", 3)
		reference.tooltip_text = range_note
		grid.add_child(reference)

## Curves are AC electrical power, not rotor/mechanical power. The controller
## still owns apply/cancel/undo; this editor only changes its private draft.
func _add_curve_editor() -> void:
	_labels["power_curve_kw"] = "电功率曲线"
	var panel := PanelContainer.new()
	panel.name = "PowerCurvePanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style(Color("14212b"), BORDER, 8, 9))
	_groups.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 7)
	panel.add_child(body)
	var title := _label("电功率曲线 · 每行：风速 m/s, 电功率 kW", 16, INK)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(title)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	body.add_child(actions)
	_curve_status = _label("", 14, MUTED)
	_curve_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(_curve_status)
	var clear_button := Button.new()
	clear_button.name = "ClearPowerCurve"
	clear_button.text = "清空曲线，采用默认三次式"
	clear_button.add_theme_font_size_override("font_size", 14)
	clear_button.add_theme_color_override("font_color", INK)
	clear_button.tooltip_text = "仅清空当前草稿；校验并应用后生效。不会修改其他设备。"
	clear_button.pressed.connect(func():
		if not _curve_editor.text.is_empty():
			_curve_editor.text = ""
			_on_field_changed())
	actions.add_child(clear_button)
	_curve_editor = TextEdit.new()
	_curve_editor.name = "power_curve_kw"
	_curve_editor.set_meta("parameter_key", "power_curve_kw")
	_curve_editor.custom_minimum_size = Vector2(0, 176)
	_curve_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_curve_editor.scroll_fit_content_height = false
	_curve_editor.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_curve_editor.placeholder_text = "留空：采用默认三次式。\n自定义曲线：每行输入两个数，以英文逗号分隔。"
	_curve_editor.add_theme_font_size_override("font_size", 18)
	_curve_editor.add_theme_color_override("font_color", INK)
	_curve_editor.add_theme_color_override("caret_color", INK)
	_curve_editor.add_theme_color_override("font_placeholder_color", MUTED)
	_curve_editor.add_theme_color_override("selection_color", Color("315c66"))
	_curve_editor.add_theme_stylebox_override("normal", _style(FIELD_COLOR, BORDER, 7, 8))
	_curve_editor.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), ACCENT, 7, 8, 2))
	_curve_editor.tooltip_text = "曲线给出参考空气密度下的交流电功率。已有传动损耗，不会再次乘传动链效率。\n风速、功率和每个线性插值段均须满足模型的额定值与物理约束；非法输入不会被裁剪或改写。"
	_curve_displayed_text = _format_curve(_original.get("power_curve_kw", []))
	_curve_editor.text = _curve_displayed_text
	_curve_editor.text_changed.connect(_on_field_changed)
	body.add_child(_curve_editor)
	var notes := _label("非空须有 2–256 点；风速 0–100 m/s 严格递增，电功率 0–额定 kW。\n按点间线性插值；点集范围外不外推，切出时归零。各段须通过 Cp / Betz 校验。", 14, MUTED)
	notes.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(notes)

func _format_curve(value: Variant) -> String:
	if not value is Array:
		return str(value)
	var lines := PackedStringArray()
	for point in value:
		var line: String
		if point is Dictionary and point.size() == 2 and point.has("wind_mps") and point.has("power_kw"):
			line = _curve_number_text(point.wind_mps) + ", " + _curve_number_text(point.power_kw)
		else:
			# Keep malformed or extra-field data visible and rejectable, not repaired.
			line = JSON.stringify(point, "", true, true)
		lines.append(line)
		_curve_original_rows[line] = point.duplicate(true) if point is Dictionary or point is Array else point
	return "\n".join(lines)

func _curve_number_text(value: Variant) -> String:
	if typeof(value) in [TYPE_FLOAT, TYPE_INT]:
		# Full precision avoids changing an untouched coordinate when another row
		# is edited. Unchanged rows below additionally retain original types.
		return JSON.stringify(value, "", true, true)
	return JSON.stringify(value, "", true, true)

func _parse_curve(text: String) -> Array:
	var points: Array = []
	for raw_line in text.split("\n"):
		var line: String = raw_line.strip_edges()
		if line.is_empty():
			continue
		if _curve_original_rows.has(line):
			var original: Variant = _curve_original_rows[line]
			points.append(original.duplicate(true) if original is Dictionary or original is Array else original)
			continue
		var columns: PackedStringArray = line.replace("，", ",").split(",", true)
		if columns.size() != 2:
			# A malformed row remains an invalid array entry for the model validator.
			points.append(line)
			continue
		var wind_text: String = columns[0].strip_edges()
		var power_text: String = columns[1].strip_edges()
		points.append({"wind_mps": wind_text.to_float() if wind_text.is_valid_float() else wind_text,
			"power_kw": power_text.to_float() if power_text.is_valid_float() else power_text})
	return points

func _on_field_changed() -> void:
	if _loading:
		return
	_refresh_validation()
	parameters_changed.emit()

func _refresh_validation() -> void:
	if is_instance_valid(_curve_status):
		var curve: Variant = get_parameters().get("power_curve_kw", [])
		_curve_status.text = ("留空 · 默认三次式" if curve.is_empty() else "%d 个点 · 自定义电功率" % curve.size()) if curve is Array else "曲线格式待修正"
	if is_instance_valid(_derived_capacity):
		var draft := get_parameters()
		var mass: Variant = draft.get("dry_host_mass_kg")
		var valid_mass: bool = (mass is float or mass is int) and is_finite(float(mass)) and float(mass) > 0.0
		_derived_capacity.text = String.num(Catalog.inventory_capacity(_kind, draft), 3) if valid_mass else "—"
	var errors: Array[String] = get_validation_errors()
	# Highlight only fields named by the authoritative validator. This is
	# presentation feedback, never a repair, clamp or separate validation rule.
	var raw_errors: Array = EnergyModel.validate(_kind, get_parameters())
	var site_errors := _site_validation_errors()
	for key in _fields:
		var invalid := site_errors.has(key)
		for error in raw_errors:
			if str(error).begins_with(str(key) + " "):
				invalid = true
				break
		_fields[key].add_theme_stylebox_override("normal", _style(FIELD_COLOR, ERROR if invalid else BORDER, 7, 7))
	if errors.is_empty():
		_status.text = "参数检查通过 · 点击「校验并应用」生效；取消不改动设备。"
		_status.add_theme_color_override("font_color", ACCENT)
	else:
		_status.text = "待修正：" + errors[0]
		if errors.size() > 1:
			_status.text += "（共 %d 项，悬停查看）" % errors.size()
		_status.add_theme_color_override("font_color", ERROR)
	_status.tooltip_text = "\n".join(errors)
	validation_changed.emit(errors)

func _humanize_error(error: String) -> String:
	if error.begins_with("Unknown device kind:"):
		return "不支持的设备类型：" + _kind
	if error.begins_with("Unknown ") and " parameter: " in error:
		return "存在模型不接受的字段：" + error.get_slice(" parameter: ", 1)
	if error.begins_with("power_curve_kw "):
		return _humanize_curve_error(error)
	for key in _labels:
		if error.begins_with(str(key) + " must be a finite number"):
			return str(_labels[key]) + "须填写有效且有限的数值。"
		if error.begins_with(str(key) + " must be an integer"):
			return str(_labels[key]) + "须填写允许范围内的整数。"
		if error.begins_with(str(key) + " exceeds fixed facility maximum"):
			return str(_labels[key]) + "超过固定设施硬上限，请按右侧范围修改。"
		if error.begins_with(str(key) + " must be "):
			return str(_labels[key]) + "超出允许范围，请按右侧范围修改。"
	if error == "Wind speeds must satisfy cut-in < rated < cut-out":
		return "风速须满足：切入 < 额定 < 切出。"
	if error == "Wind speeds must satisfy cut-in < cut-out for power_curve_kw":
		return "自定义曲线的运行风速须满足：切入 < 切出。"
	if error == "Hub height must exceed rotor radius":
		return "轮毂高度须大于转子半径（直径的一半）。"
	if error.begins_with("Rated power requires Cp="):
		return "额定功率超过转子、额定风速和效率允许的功率；请联合调整这些参数。"
	return error

func _humanize_curve_error(error: String) -> String:
	if error.begins_with("power_curve_kw must be an array"):
		return "电功率曲线须为点集；每行填写：风速 m/s, 电功率 kW。留空采用默认三次式。"
	if error.begins_with("power_curve_kw must contain"):
		return "电功率曲线须包含 2–256 个点，或全部留空采用默认三次式。"
	var point_number: String = error.get_slice(" ", 2)
	var point_label := "电功率曲线第 %s 点" % point_number
	if error.begins_with("power_curve_kw point "):
		if "must be an object" in error:
			return point_label + "格式有误；每行只填两个数，以逗号分隔。"
		if "has unknown field:" in error:
			return point_label + "含未知字段：" + error.get_slice("has unknown field: ", 1)
		if "wind_mps must be a finite number" in error:
			return point_label + "的风速须为有效且有限的数值（m/s）。"
		if "wind_mps must be between" in error:
			return point_label + "的风速须在 0–100 m/s 范围内。"
		if "wind_mps must be strictly increasing" in error:
			return point_label + "的风速须大于前一点；不可重复或倒序。"
		if "power_kw must be a finite number" in error:
			return point_label + "的电功率须为有效且有限的数值（kW）。"
		if "power_kw must be nonnegative" in error:
			return point_label + "的电功率不能小于 0 kW。"
		if "power_kw must not exceed" in error:
			return point_label + "的电功率超过额定值；注意此处单位为 kW（1 MW = 1000 kW）。"
		if "requires Cp=" in error:
			var required: String = error.get_slice("requires Cp=", 1).get_slice(" ", 0)
			var limit: String = error.get_slice("maximum is ", 1).get_slice(" ", 0)
			return point_label + "需要 Cp=%s，超过上限 %s；请检查功率、转子、密度与效率。" % [required, limit]
	if error.begins_with("power_curve_kw segment "):
		if "unbounded Cp" in error:
			return "电功率曲线第 %s 段在零风速附近超出物理上限；正功率前须有一段零功率区间。" % point_number
		if "requires interior Cp=" in error:
			var required: String = error.get_slice("requires interior Cp=", 1).get_slice(" ", 0)
			var speed: String = error.get_slice(" at ", 1).get_slice(" ", 0)
			return "电功率曲线第 %s 段在 %s m/s 处需要 Cp=%s，超过物理上限；端点合格仍不足以通过。" % [point_number, speed, required]
	return "电功率曲线未通过检查：" + error

func _label(text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result

func _style(background: Color, border: Color, radius: int, padding: int, width: int = 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style
