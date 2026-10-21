# 接续批次需求覆盖与交付边界

公开整理说明：本文保留研究或开发阶段记录；带时间的计数、计划与待验收状态仅适用于对应时点，不代表逐项人工验收已完成。最终范围见[最终原生验收](FINAL_NATIVE_ACCEPTANCE_1004.md)。原始运行日志、截图、玩家存档、备份与研究图像不随源码分发；下文非公开记录仅为来源说明。公开整理没有重新运行游戏或测试。

已验收基线：1.0.0.3，原仓库main `56400dde7c7c23c8a8d8705152305c3cf0c9118c`。以下表格及带时间记录保留开发阶段状态；最终状态见本文末节与[最终原生验收](FINAL_NATIVE_ACCEPTANCE_1004.md)，不能把早期待验收项、全库自动测试和最终定向人工检查混为一谈。

| 需求 | 开发阶段状态（历史） | 验收/约束 |
|---|---|---|
| 多元储能8项及27类目录 | 已验收基线 | 有限库存、效率、自损、热电分离、GLPK/存档一致；原集成氢系统保持兼容，不重复计算 |
| 底部单分类行/上展图标/顶部HUD | 已验收基线 | 保留工具入口，142px默认底部，动画可打断 |
| 批量参数/框选/Shift/半选全选/Esc | 已验收基线 | 原生Shift二次翻转已修；任意子集、明确修改字段、取消无修改 |
| 真实运行曲线 | 已验收基线 | 已提交真实数据、240点环形缓存、4Hz重绘、SOC分轴、切换重置；有真实非零充电headless证据 |
| CAES地上实图建模 | 已验收，用户认可保留 | 不推翻；区分厂房/蓄热/地上压力容器，不借盐穴容量背书 |
| 右侧资源/运行/设置面板全局美化 | 代码与headless已通过，待合并统一GUI验收 | 已看3图；卡片分组、卡片内对齐、大中小字号、单位不换行、精度统一、帮助可折叠，禁止整页纯表格风 |
| 独立气态H2完整链 | 2A主世界/GLPK/几何专项已通过，统一GUI待验收 | 有限液水→电解整站→压缩气库→燃料电池→负荷；species/kg/s、氧/产水/泄漏/排热边界、原子事务、保存/优化独立审计 |
| 液态H2 | 已实现，World/GLPK/UI/保存与拆除撤销通过；待最终GUI | 液化用电、低温库存/蒸发损失、气化热与真实设备参考；不能仅气罐换皮 |
| 固态H2 | 已实现，固定宿主/派生容量/吸放热账与World链通过；待最终GUI | 具体储氢材料、温级、吸放氢热、有限库存；未核实不建假按钮 |
| 氨生产整站 | 已实现，有限原料/产品与真实World、GLPK交叉通过；待最终UI/GUI | 有限N2+H2、真实计量/辅助电热/产品缓冲，不免费空气产氨 |
| 甲醇生产整站 | 已实现，有限原料/产品与真实World、GLPK交叉通过；待最终UI/GUI | 有限CO2碳源+H2、产水/热电/产品约束，无碳源不生产 |
| 独立压缩/液化CO2储能 | 有限等效库存实现及双实现专项已通过，统一GUI待验收 | 非公开研究图像已查看；大气仓/储液/蓄热闭式气液相变，非CAES换皮；100MW/1000MWh口径与614MWh放电依据差异明确，首次并网不当商运 |
| 旧中压变配电单元真实化 | 尺度核查完成，一级/二级共用真实几何已实现，待GUI | 保留旧station容量、端口与存档，不放大小柜冒充基地升压站 |
| 独立基地级汇集升压站 | 已实现、核心393项/世界23项/控制器16项通过，GUI待验收 | 独立kind、额定容量/占地/AC端口；真实AIS典型布局，教学汇集节点不伪称电压潮流仿真 |
| 全目录厂站真实参考 | 27类基线及新增12类参考核对完成 | 逐项实图/尺寸来源与模型映射；最新要求一级统一真实米制，旧图标仅隔离兼容；有限规格与静态容量核对仍在收口 |
| 地图边界/远景收边 | 4×4 km实际建造域及轻量背景已实现，统一GUI待验收 | 核心高度/坡度/位置不变，外圈真实可建，域外远山不可建；10m/world统一，不高模堆性能 |
| 植被/石块真实感 | 几何已实现，统一GUI待验收 | 先照片；稀疏草灌轮廓无矩形板边，低模实例化/LOD，自然石形/方向/尺度贴地，保留道路/设备点击 |
| 天然气/煤源/外引水资源外观 | 真实参考与几何专项已通过，统一GUI待验收 | 现名“天然气接口”“公铁物流 / 煤源”“外引水 / 限额”；仅真实资源设施外观，保留位置/额度/接口语义，不买API或新增联网 |

## 每个可交付段的共同门槛

保存原场景并可恢复、无界面全回归、真实GLPK/独立审计（涉及物理时）、小屏/实际界面截图、性能边界说明、明确未完成项。GUI须经交接，发现持续用户输入即停止抢输入。后续发布仅对上述main基线做增量。

2026-10-21 17:12 UTC集成记录：新版物质主世界17项、优化控制器16项、save115项、chart7项、参数表18项通过；旧network17924项与expanded_storage1163项通过。历史存档fixture固定旧目录，不放宽新验证。四类真实几何及最终GUI仍未验收。

2026-10-21 17:30 UTC：2A当前主世界22项、建造/详情32项、优化控制器16项及全部material隔离回归通过。CO₂运行703项、Godot真实GLPK交叉140项、Python220项通过；有限等效库存教学参数不声称复现木垒实测效率。Blender CPU结构核对图不是Godot实机截图。当时本批尚未GUI验收。

2026-10-21 17:42 UTC：独立collector_substation默认/上限200MW，固定100×102m。save16/model25/opt10与33类现目录；旧schema15明确冻结32类。新站不支持站间级联，界面与非法连线明确说明。当前2A+CO₂检查点全目录回归正在收尾，初次缺导入缓存/缺历史塔式fixture的环境问题保留日志并独立重跑，不冒称初跑全通过。

2026-10-21 18:03 UTC：2A+CO₂+基地汇集站独立检查点142个Godot测试最终全部通过，原始4个历史fixture目录契约失败已修fixture并回归，不放宽验证。2B当前save17/model26/opt11；新相态profile2与旧四物料设备profile1并存。JSON数值ID标准化修复，实际World22/0，真实GLPK12份解逐步交叉345/0；独立账本692/0，UI12专项1959检查通过。仍在补多步逐设备库存锚定、World相态拆除/undo、全目录照片与液流尺度兼容，2C尚未编码，未GUI验收。

2026-10-21 18:17 UTC：应用统一1.0.0.4（当时尚未原生切换验收）。save19/model27/opt12；几何schema18保留35类，旧液流无标记仍按图标化占地，新建flow_process_v2采用完整工艺。2C四类设施已进建造/详情/参数/端口及物质账，主世界21项、历史14/16/17/18账迁移96项通过；12设备20条typed连接的可撤销完整示例8项通过，真实天气运行产生醇氨。2C物理2445项、真实GLPK23组跨语言1012项通过（含2明确不可行），产品目标控制器19项通过。最终全回归、剩余设备族照片核对和一次实际GUI仍未完成。

2026-10-21 18:44 UTC：165个Godot测试及310个Python测试完成后，随后进行1.0.0.4原生检查。真实帧步暴露液氢取尽时−1.08e−19kg浮点越界，严格账本拒绝后元素映射访问报错；没有将首次无界面全绿当作最终完成。最小事务流率修正、极小dt参考焓流率求和、显式无效映射拒绝已通过12357项专项（含随机分数步、1e−12小步、长步、1/7/60倍运行/暂停恢复与GLPK交叉）。另修外环与真实地形边缘未接合、物料管标签缺屏幕尺寸适配。当前等待统一重启后的实机复验，尚未最终冻结发布。

## 2026-10-21 19:10 UTC: real first-level metric requirement (in progress)

The consistent real-scale requirement supersedes first-level icon-scale allowances. The proposed and approved engineering domain is exactly 4,000 × 4,000 m, with 10 m per world unit in every direction. The former 25 m metadata/UI conversion was inconsistent with equipment geometry. Existing coordinates, terrain samples and energy/material state are not rescaled. The map implementation preserves original core height and slope and extends the actual buildable domain, not only scenery. Existing electricity loss fractions remain explicit parameters; the solver has no distance-derived wire/pipe pressure or loss model. A larger map must not silently change these fractions.

Status, not a completion claim:
- Installed station facade now displays actual child equipment at its recorded local metric coordinates, including rebuilding after internal movement; no generic fixed tanks stand in for installed equipment.
- Save schema 20 has the larger domain. Historical schemas through 19 keep historical boundary validation.
- Migration is a reviewable candidate with collision and full-footprint boundary checks. It does not move objects or change their capacities, stocks, IDs or links; applying requires a successful independent original-save backup and provides undo.
- Existing flow icon geometry is preserved until explicit migration. Finite site reference profiles and physically supported container/material volumes are being integrated for other identified mismatches.
- Capacity/auxiliary-power editing, construction and optimization must share finite supported geometry envelopes. Arbitrarily huge ratings on unchanged equipment are not accepted as engineering-real layouts.
- New test `test_metric_domain_migration.gd`: 14 checks pass for expanded-domain validation, historical bounds, read-only preview, unchanged quantities, collision rejection and stale review rejection.
- No GUI actions occurred after the user's current desktop operation restriction. New scale work still needs complete regression and subsequently authorized native visual acceptance. This section does not freeze or publish the source.

2026-10-21 19:41 UTC：176个Godot测试全库已跑完，原27个失败经生产根因修复和旧/新合同明确后逐项重跑通过；该结果不是随后容量证据改动后的最终冻结。349个Python测试通过（含真实GLPK与Godot交叉）。最新容量静态合同尚在收口，钠电由厂家2.5MWh真实箱体改为3整箱支撑6MWh，CAES/LAES将增加容量×放电效率耦合筛查；旧档不追改。新增空白真实规格场景入口避免仅提示“另建场景”却无入口，确认后可撤销、不写已保存文件。其恢复旧超大电池专测发现旧视觉未限制模块渲染，导致测试进程退出137，已交最小LOD修复；不能将该失败记为通过。该阶段未进行原生桌面检查。

## 2026-10-21 20:30 UTC 最终覆盖结论

此前“待容量屏/待LOD/未操作GUI/待最终验收”是历史时点，本节取代其当前状态。39类固定参考规格与联合容量边界已实现，钠电/液流/CAES/LAES/固态氢容量依据与简化边界已有专文；旧超大电池仅代表性LOD而不截库存。4km实际建造域及10m单位转换、物理地形不变、显式旧比例兼容/迁移预览/撤销与新空白场景完成。最后地表shader法线/纹理过渡在实际窗口验证修复，不改地形网格。

最终181个Godot程序通过记录来自基线全库、修复fixture复跑及最终定向回归汇总，不是一次不中断的全量运行；完整Python为363测试通过、0跳过。44组真实GLPK独立审计与363重叠，不相加；必要原生GUI、真实非零醇氨曲线、24步优化返回、640px参数滚动和Esc、钠电/CO₂比例检查完成。旧档显式兼容，不静默迁移布局或截断库存。详见 `FINAL_NATIVE_ACCEPTANCE_1004.md`、`FINAL_REFERENCE_DIMENSIONS_39.md`、`RELEASE_1004.md`。此验收记录不单独声明仓库推送已完成。后续以成熟UI体验为主，不追加本批功能。
