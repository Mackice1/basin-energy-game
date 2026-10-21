# 首批电热链实施接口规范（设计稿，尚未实现）

日期：2026-10-15。基线：Basin02 V13，既有源网荷储、schema4/model12、GLPK固定容量调度。本文只新增设计文件，不修改主代码。实现工程师应以本文件的验收门槛逐项落地，不能把设计目录当成已运行功能。

## 1. 第一批范围与边界

推荐 3 种独立可建造设备：电热水锅炉 `electric_boiler`、固定温区等效储热 `thermal_store`、隔离换热器 `heat_exchanger`；另设独立热需求节点 `heat_demand`，通过“需求设置”配置，不塞进发电设备栏。继续保留原电需求逻辑，配合另一项移除建造栏电负荷的工作。

玩家闭环：风光/电池 → 变电站 → 电热水锅炉 → 换热器 → 热需求；锅炉也可将富余热存入储热，储热随后经换热器供热。全链设备可以单独选中、改参、连线、拆除、查看故障。锅炉无电、换热器断路、库存为空，都会实际改变供热。

首版是固定温区的热服务网络，不是液压模型、压力容器设计或动态水/蒸汽仿真。循环水/循环泵的物料回路内置，给出“已充水、固定工作点、循环辅机包含在设备等效效率内”的明确边界；没有用水计费、液位或压力数字。禁止把锅炉端口命名为 steam，禁止90°C热水接汽轮机。

不要添加占位煤电站、光热发电站、汽轮发电一体图标。后续火电的锅炉、汽轮机、发电机必须独立建造。现有总设计文档允许合并汽轮发电机的可选描述，对本用户本次任务不适用。

## 2. 温区与连接契约

首版锁定两个配置档，不开放自由温度编辑：

| grade_id | 介质/含义 | 供/回温度 | 允许角色 |
|---|---|---|---|
| hw_primary_90_60 | water_equivalent 热服务 | 90/60°C | 锅炉出口、储热充放、换热器热侧 |
| hw_secondary_70_40 | water_equivalent 热服务 | 70/40°C | 换热器冷侧、独立热需求 |

这两个档是教学工作点，不是地区供热规范。图上的热连接代表一组供回水服务的能量传输，不是一根可测质量流量的管子。MWth基于同一设备相应供回温差定义；两侧质量流量可以不同，但能量必须由换热器守恒。热储采用理想分层/双区等效库存，供水品质固定，不把 SOC 插值成“实际罐温”。不得称为完全混合水箱。

换热器的两个端温差都必须合格：T_hot_supply − T_cold_supply ≥ ΔT_min，T_hot_return − T_cold_return ≥ ΔT_min。本档均20K，默认 ΔT_min=5K。它只能降级供热，不能提温。以后增加档位时要重新验证，不能只比较一个供水温度。

端口结构统一：`{id,direction,carrier,unit,grade_id}`；电口另有 `voltage_level:AC_BUS`，无热 grade。热 carrier 用 `heat_water`，unit 用 `MWth`；不要继续让全局 `Catalog.CARRIER` 决定每个口。

- electric_boiler: `ac_in` 输入 electricity_ac/MW；`heat_out` 输出主温区热。
- thermal_store: `heat_in` 输入主温区热；`heat_out` 输出主温区热。独立方向端口可画两条线，但同一步充放互斥。
- heat_exchanger: `hot_in` 输入主温区热；`warm_out` 输出次温区热。
- heat_demand: `heat_in` 输入次温区热。

热边示例：`{from:10,to:11,from_port:"heat_out",to_port:"hot_in",carrier:"heat_water",unit:"MWth",grade_id:"hw_primary_90_60",capacity_mwth:2,loss_fraction:0}`。

电边继续使用 capacity_mw；热边只用 capacity_mwth。拒绝同一边含两种容量、错误单位、未知端口/品位、倒接、自连、重复同端口边。热分流按实际流量求和，共享额定能力，绝不能复制上游输出。不要用当前“每个叶子设备只能一条线”规则限制整个锅炉，否则电输入与热输出冲突；应改为每个电叶子一个电站接入，热口按独立拓扑规则检查。

首版只允许以下热路径：锅炉→换热器、锅炉→储热、储热→换热器、换热器→热需求。可分流/汇流；不允许储热互充、换热器串联、任意热环网，不允许锅炉直接接次温区需求。UI建线、存档读取、实时调度与Python求解器用同一合法性表。

## 3. 参数、单位与状态

以下数值全部是可验算教学默认值，非厂家额定性能或工程选型。物理依据见第9节。

| kind | params（默认） | state |
|---|---|---|
| electric_boiler | rated_electric_mw=2.0; thermal_efficiency=0.98 | {} |
| thermal_store | capacity_mwhth=4.0; charge_mwth=2.0; discharge_mwth=2.0; charge_efficiency=0.98; discharge_efficiency=0.98; self_discharge_per_h=0.002; initial_soc=0.0 | {energy_mwhth:0.0} |
| heat_exchanger | capacity_mwth=2.0（热侧输入额定）; transfer_efficiency=0.98; min_approach_k=5.0 | {} |
| heat_demand | demand_mwth=1.0; priority=10 | {} |

各热设备有不可变 `model_profile` 指向上述温区；在目录与存档中记录版本。效率必须 (0,1]，额定/容量有限正数，充放功率和需求可为0，自损系数[0,1]/h，初始SOC[0,1]，priority整数[0,1000]。上限沿既有电设备的防恶意输入范围：功率≤10000、容量≤100000；不是工程许可范围。拒绝NaN、Inf、bool冒充数字及未知字段。initial_soc 只用于新建，不可覆盖读档库存。

`transfer_efficiency` 是“送到冷侧的热 / 热侧吸收的热”，损失记环境；不是换热器 effectiveness ε。不要把 ε=.98 宣称为98%能量效率；实际 ε-NTU 模型需要流量、比热和传热面积，本版没有实现。额定能力及固定温差档共同限制工作点。

## 4. 同一时段的物理方程

统一 dt_h=dt_s/3600；流量MW/MWth；电库存MWh；热库存MWhth。

锅炉活动量 P_b 是“其电端收到的功率”：0≤P_b≤rated_electric_mw；Q_b=η_b P_b。电损耗/内置辅机不可再次从电网扣同一份。总转换损耗 L_b=P_b−Q_b 单列为环境散失。没有可用热出口时P_b=0，不给锅炉虚构无限热汇。

换热器热侧 Q_h：0≤Q_h≤capacity_mwth；Q_c=η_hx Q_h；L_hx=Q_h−Q_c。Q_c等于实际下游发送流量总和（含后续线路损失），不得有免费弃热变量掩盖过剩。热边 received=(1−loss_fraction)sent，sent≤capacity_mwth；第一版热边固定loss_fraction=0，以免固定温度假设下虚构实际管道温降。若开放非零损耗，须标“等效服务损失，未求解沿程温度”，并加入同一账本。

储热在时段开始先自损，与现有电池一致：

E_decay=E_before exp(−λ dt_h)
E_end=E_decay+(η_ch Q_ch−Q_dis/η_dis)dt_h
0≤E_end≤Emax
Q_ch≤Qch_max z; Q_dis≤Qdis_max(1−z); z为二元变量

其中 Q_ch 是储热输入端收到的热，Q_dis是输出端送出的热。充热上限另受(Emax−E_decay)/(η_ch dt_h)，放热上限受E_decay η_dis/dt_h。库存只在所有设备、连接及全局账本验证成功后提交一次。暂停dt=0不自损、不充放，不除零。自损随时间发生，孤岛/断线储热仍自损。

时段账本（均按端口定义，不能重复计损）：

- 电：实际发电+电池放电=电需求实供+电池充电+锅炉电输入+外送+电网络损失。
- 热网络：锅炉出热+储热放热=热需求实供+储热充热+换热器损失+热网络损失。
- 锅炉：P_b=Q_b+L_b。
- 热储：E_before+Q_ch dt_h=E_end+Q_dis dt_h+自损MWhth+充放转换损失MWhth。

可再生可用量=实际发电+弃电；热需求=实供+缺供。电/热缺供各自显示，不混成一个“缺电”数字。综合能量审计可以比较统一能量单位，但UI电储SOC和热储SOC永不合并。

## 5. GLPK与实时策略的统一接口

现有 `dispatch_solver.py` 的 `DEFAULTS/RANGES/normalize`、仅电路径建模、`next_states.energy_mwh`审计都需要扩展；不能只改图标/目录。保留原电源→站→负荷/电池/电网路径，新增“站→锅炉电口”的电路径终点，令送达总量等于变量P_b。热边采用直接非负流变量，加第4节逐节点平衡和转换方程，形成同一GLPK问题。锅炉输出不是独立自由变量，禁止先按额定发热再去检查缺电。

储热二元模式与现有电池一样严格执行；仅靠吞吐惩罚不足以保证互斥。实际仍是GLPK混合整数固定容量调度，不新增容量规划。

建议调度输入schema升至2（与存档schema分别管理），steps增加 `heat_demand_mwth:{"id":value}`，键集合必须恰为全部热需求ID；电字段保留旧语义，不把锅炉塞进外生demand_mw。锅炉用电由解内生决定。CSV增加独立 `heat_demand` 字段和kWth/MWth单位；必须绑定热需求ID，不复用风光 `power` 出力CSV。若首轮尚未扩展CSV，热需求只能常量且UI直说不支持时序导入，不能把已有电CSV当成热需求。

目标延续既有词典序：
1. 最小加权未服务能量 Σdt_h[(1001−priority_e)u_e + heat_service_weight(1001−priority_h)u_h]。默认heat_service_weight=1，明确“教学服务权重，非电热经济等价”，不能称严格优先级调度。
2. 在保持第一阶段最优下最大化交付外送电量。
3. 保持前两阶段，最小电池及储热端口吞吐（权重分别显式1），并用很小且固定/可审计的设备热活动量破除无意义循环；若需要额外严格词典级，可独立第四阶段，不用未解释的大M权重混装。

`strict_supply`覆盖电、热需求；新增 `terminal_heat_soc_fraction` 只约束每个热储末端库存，不能把原 terminal_soc_fraction静默套到热储。超时、取消、infeasible、错误以及可行未最优状态沿用现有合同，热场景绝不静默退回忽略热设备的旧模型。

每step增加 thermal:{demand_mwth,served_mwth,unserved_mwth,boiler_heat_mwth,charge_mwth,discharge_mwth,energy_mwhth,soc,network_loss_mwth,exchanger_loss_mwth,storage_conversion_loss_mwth,self_discharge_mwhth,balance_error_mwth,energy_balance_error_mwhth}；另列 boiler_electric_mw、boiler_conversion_loss_mw。per-device记录全部输入/输出、模式、状态前后值；per-line根据carrier分别报告sent_mw/received_mw或sent_mwth/received_mwth。不得用既有电energy_mwh容纳热库存。

next_states 按设备种类为 {id:{energy_mwh:...}} 或 {id:{energy_mwhth:...}}。原initial_states/final_states同理。totals积分使用真实dt。独立审计必须从拓扑与原始参数重算守恒、效率、边容量、库存、互斥、温区，不能只相信求解器输出 residual=0。容差沿现有 abs=2e−6、rel=2e−7 并按量纲分别比较。

实时贪心也需要跨载体统一分配。建议先把热需求按路径损耗和η换算为锅炉可调电需求，与电需求共享资源；可用储热按规则供热；仅确认热接纳和电可用后统一提交。这个策略不是预测最优。必须同一参数、同一物理审计，不能在贪心中满储继续吞电。若实时策略无法可靠实现跨链预留，可用一个短时段调度事务，但不可同步阻塞渲染、不可每帧启动进程。实现选择与运行时间要实测，不宣称性能保证。

## 6. 存档、撤销、参数编辑和UI

建议新存档schema5/model14（数字由主实现与并行变更最后协调），旧schema4按旧电模型读入，不凭空加锅炉/热需求。电池state保持原字段；热储仅接受energy_mwhth。旧端口缺省推断只对旧电设备有效，新热边必须显式端口、carrier、grade和单位。未知热版本拒绝整份载入，提示原因，不部分恢复。

缩小热储容量至低于当前库存：默认拒绝修改并说明库存/拟设容量，避免暗中抹掉热量。改变初始SOC不影响运行库存。拆设备/撤销/读档应沿现有事务恢复状态与连线；重新装回不得免费补满。设备删除使依赖热需求缺供，不能隐藏需求。更改参数、拓扑、CSV、时间、库存或需求后revision更新，旧优化结果失效；预测不写回实时状态，除非现有明确应用流程验证后提交。

UI至少显示：电热水锅炉电输入/出热/损失；热储MWhth/SOC/充放/自损；换热器90/60→70/40°C、热输入/输出；需求请求/实供/缺供。端口形状或文字区分电与热，不能只靠红绿色；连接拒绝给中文原因。状态至少覆盖“未接电”“热出口未连接”“温区不匹配”“热储已空/已满”“下游能力不足”。热量图表独立轴和单位；优化对比新增供热与热库存曲线。新中文字需检查当前子集字体。

文件改动面：device_catalog、energy_model参数验证、network_dispatch、world_game/map建造与需求UI、parameter_form、equipment_visual、save_validator、series_import（如纳入）、optimization_controller/panel/chart、Python求解器及文档/测试。避免把逻辑重复复制到UI内部。

## 7. 首批必须通过的验收

所有数值测试先设线路/站损耗、自损为0（另有专门损失例）。每个用例同时覆盖实时策略与GLPK可行性/独立审计，UI另测。

A. 直接供热：发电2MW、锅炉η=.98、换热η=.98、热需求2MWth。得到锅炉耗电2、出热1.96、换热输出1.9208、缺热.0792；两转换损失分别.04和.0392，合计.0792。无虚构缺电或供热。

B. 电热争用：发电2MW，电需求1MW，热需求.9604MWth，两者均可满足，锅炉只耗1MW。设置同等权重、供给不足时按声明目标验证最优，别要求与贪心有完全相同分配。

C. 两小时蓄热：小时1发电2MW且无需求，小时2无发电且有热需求；锅炉η=.98、储热充/放η=.98、换热η=.98。预测应有理由在小时1充热：储热端收到1.96，E_end=1.9208MWhth；小时2最大放热1.882384MWth，到需求1.84473632MWth。这个数字是五个边界中的四次.98转换，不可少扣/重复扣。本例用future需求或末端SOC约束促使储热，不能要求无未来用途时仍充满。

D. 热储孤岛初始1MWhth、λ=.002/h、dt=1h，E_end=exp(−.002)=.998001998667；自损.001998001333MWhth。跨dt仅自损应精确一致；含充放的先衰减离散约定应按指定dt比较，不假称任意步长完全相同。

E. 满空与互斥：E=0不放热，E=Emax不能继续充热；每step模式互斥，负数库存/超容/NaN被拒；dt=0完全冻结。拆线只停端口交换，不停自损。

F. 拓扑与品位：电线不能接热口；锅炉主温区不能直供次温区；换热器不可倒供90°C；错误热端/回温差被拒。分两路不复制功率；两个锅炉到一台换热器共同受热侧额定限制；断电锅炉但已充热储仍可供热（本版循环辅助已并入等效边界）。

G. 瓶颈与过剩：换热容量.5MWth时输出≤.49；储热已满且需求0，锅炉耗电0，风光按原规则外送或弃电。无热汇时禁止无意义电→热→弃热。

H. 保存恢复：运行中热储非零→保存→重开→相同后续输入，状态轨迹一致；旧V13电存档原状可用。未知kind、state字段、版本和损坏拓扑整份拒绝，不改变当前场景。参数编辑/撤销/结果过期要测。

I. GLPK故障：真实求解器运行、缺失、超时、取消、热strict_supply不可行、热terminal floor不可行、篡改热流/状态后的独立审计拒绝；不把无热设备旧19项测试“通过”算成热功能通过。

J. 图形验收：空图开始→放3设备→需求设置→电热连线→播放→储热切换→选中每设备→改参→断线→读档→优化曲线，实际截图逐项确认。检查控制栏不再出现电负荷建造按钮、需求设置仍可用。只有全部过关才标为可运行首批。

## 8. 后续顺序：真正模块化光热/火电

阶段2：固定设计点蒸汽动力岛。分别建造煤锅炉、汽轮机、发电机、凝汽器、给水泵、冷却模块、辅机模块；煤/空气/水/环境作为明确边界。辅机模块可以代表磨煤/鼓引风等集合，但不得把整个机组缩为一图标。没有完备回路前设备不进可运行建造栏。

必须新增质量kg/s与一致参考的比焓kJ/kg，steam/liquid_water、pressure等级、shaft_power/MWmech；端口不复用heat_water。每个设计点的p/T/h及相态从IAPWS校核，禁止凭温差直接算汽轮机功。锅炉 m(h_out−h_in)/1000=η_b·m_coal·LHV；汽轮机W=m(h_in−h_out)/1000；发电机P=η_gW；凝汽器排热=m(h_exhaust−h_cond)/1000；泵功与给水焓升统一记账。冷端容量不足、辅机电不足、没给水都应限产。回路初始充水、设备启动状态、外部启动电/电池必须保存；不允许把本时段尚未建立的发电当成启动电导致零资源自启动。

阶段2只可声称“经校核固定工况的质量/焓守恒”，不是连续压力动态求解、锅炉安全控制或汽轮机湿汽侵蚀预测。启停若未建模，UI明确准稳态运行、没有自由启停优化，不编造启动时间。

阶段3：光热场/接收器独立成设备，先产合格高温热，再接独立高温储热、蒸汽发生器，复用阶段2汽轮机/发电机/冷端。资源必须DNI；当前irradiance_wm2不能无说明当DNI。新加DNI导入/环境字段、光学/热损失、跟踪和循环辅机；熔盐/导热油独立grade，不接90°C热储。先定有效温区与物性再选真实示例参数，不能将“太阳能→电”封装替代。

可选较小中间步：低温太阳能集热器进入已实现90/60服务档，用经验证的温升与辐照性能边界，且命名为太阳能供热；不可因此宣称CSP发电完成。燃气/联合循环和氢链留到以上各闭环验证后。

## 9. 已核对的一手来源与适用范围

1. DOE《Improving Process Heating System Performance》：电阻加热将电转热、近100%局部转换作为理想上界背景；不证明本项目.98参数。https://www.energy.gov/sites/default/files/2014/05/f15/process_heating_sourcebook2.pdf
2. EnergyPlus官方 Engineering Reference v24.2：水箱质量/热容/热量收支与水温微分平衡，说明详细罐温模型需要更多状态；本文固定品质库存是进一步教学简化，不能宣称复现EnergyPlus。https://energyplus.net/assets/nrel_custom/pdfs/pdfs_v24.2.0/EngineeringReference.pdf
3. DOE Thermal Storage System CSP Basics：介绍两罐/温跃层储热概念；此处只借鉴冷热区概念，未采用其CSP工程温度或材料参数。https://www.energy.gov/cmei/systems/thermal-storage-system-concentrating-solar-thermal-power-basics
4. DOE CSP Basics：聚光先取得热，再通过动力过程发电，支持光热场/热储/动力岛拆分。https://www.energy.gov/cmei/systems/concentrating-solar-thermal-power-basics
5. US EPA Catalog of CHP Technologies，Steam Turbines章节：锅炉→汽轮机/发电→凝汽/过程热→泵→锅炉的模块与循环关系。https://www.epa.gov/sites/default/files/2015-07/documents/catalog_of_chp_technologies.pdf
6. IAPWS IF97官方发布：水/蒸汽工业物性计算及适用域，为后续p/T/h工作点校核依据；当前首批没有调用它。https://www.iapws.org/relguide/IF97-Rev.html

证据等级：守恒/转换方向/循环模块来自上述基础模型；2MW、4MWhth、90/60与70/40°C、.98效率、.002/h自损、5K最小温差全部是本项目教学假设。不要写成引用来源中的“标准参数”。真实设备示例应在后续独立添加厂商数据表、工作点及边界，不与当前默认混用。
