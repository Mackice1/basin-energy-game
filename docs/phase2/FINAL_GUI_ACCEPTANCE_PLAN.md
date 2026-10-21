# 本批统一实际窗口验收清单

公开整理说明：本文保留研究或开发阶段记录；带时间的计数、计划与待验收状态仅适用于对应时点，不代表逐项人工验收已完成。最终范围见[最终原生验收](FINAL_NATIVE_ACCEPTANCE_1004.md)。原始运行日志、截图、玩家存档、备份与研究图像不随源码分发；下文非公开记录仅为来源说明。公开整理没有重新运行游戏或测试。

历史验收计划：以下检查清单保留为验收方法，不表示每项都已人工执行。最终已执行范围与未覆盖边界见[最终原生验收](FINAL_NATIVE_ACCEPTANCE_1004.md)。

## 切换与恢复
1. 只读观察用户是否正在持续输入。持续输入即暂停操作，不抢桌面。
2. 使用独立测试副本，并先确认可恢复的基线；记录设备、连接、参数、库存和模拟时刻。没有安全的保存目标时停止切换，不覆盖已有存档。
3. 正常关闭旧游戏，确认无第二游戏实例，再从开发完成副本启动；config/name 保持不变。所有破坏性验收只在独立临时场景进行。
4. 结束后恢复本次检查前核对的基线，并校验布局、连接、参数、库存及模拟时刻；不使用过期基线覆盖之后的操作。异常时回滚并明确失败项。

## 画面和操作
- 默认底栏仅分类一行；上展大图标动画可中断；类别映射/悬浮提示正确。
- 顶部与右侧气象、燃料、运行、物料资源、尺寸/设置卡片，名称/数值/单位层级统一，不断行单位、不挤成密表。1180×812及可用较窄窗口检查。
- 单参数弹窗 Esc 只关闭一层；详情/专页/批量窗口重复进出；地图选择与视角保留，不退出游戏。
- 批量同类任意子集、单击/框选/Shift范围/三态全选，仅应用明确修改字段。宿主/初始化不可批改。
- 真实运行后才显示曲线；液/固H₂ kg/s和SOC独立轴，选择切换/取消/重置不串历史。

## 模型与新功能
- 保留用户认可CAES；独立CO₂大气仓/储液/蓄热站与CAES视觉和技术名称明显不同。
- 新基地汇集站与旧中压单元区分；AIS母线、主变及控制区不只是放大柜子。
- 地图边界地表/远山、草灌无矩形板、石块贴地；资源接口与原位置/额度一致。
- 六类制储返电设施和四类化工设施能合法放置、显示命名物料端口、进入详情。可在“场景”选择新增“制氢与醇氨完整链示例”：确认后12设备20连接，真实天气产生产品，单次撤销恢复原场景，不需手工拼装验收。
- 新液流完整模块采用新占地；旧液流原位置/尺寸兼容并明确图标化说明。
- 真实水→电解→气/液/固储氢→燃料电池供电；有限N₂/CO₂及储氢→醇/氨，缺原料/功率/冷却或满产品仓停产。产品库存不得靠删除清空。
- 优化气/液/固kg目标及产品目标若实现，实际GLPK结果状态、不可行说明和无修改实时场景均检查。

## 证据
记录原生截图、窗口尺寸、实际源路径与版本、当前进程数、错误日志、前后存档摘要；性能记录同场景启动RSS与有限运行采样，区分headless和实机，不把Blender结构图当Godot视觉验收。

## Historical checkpoint: 19:17 UTC

Earlier checks covered real chemical output and Esc/selection behavior. The later real-scale checks below were planned separately; their final executed scope is summarized in FINAL_NATIVE_ACCEPTANCE_1004.md. No individual planned item should be inferred to have passed from this checklist alone.

Additional final native checks after that handoff:
- Actual 4×4km buildable field, 10m/world unit; camera can reach extensions without empty terrain gaps. Site placement tests full clearance, not centre alone.
- CO₂ remains the separate approximately752×752m whole site (not each warehouse), about3.53% of16km². Five air/gas warehouses are components within that one site. Show scale consistently beside other rated plants; never shrink just to fit old map.
- Existing unmarked layouts display the prominent old-scale compatibility mode. Existing ratings, stocks and coordinates survive. New construction is blocked in compatibility mode until reviewed migration or a new reference scene.
- Migration preview identifies parameter/range and collision problems; no silent moving, clamping or disposal. On a compatible independent fixture, verify backup, apply, and one-step undo. Do not silently commit a conflicted user scene.
- New supported-profile water, solid heat, H₂, N₂ and NH₃ storage has real net inventory accommodation. Check ground contact and dimensions visually, not just source AABBs.
- First-level thermal/tower sites show exactly the installed child equipment at local metric coordinates. Move a child and verify immediate facade rebuild, no phantom tanks and no duplicate tower/mirrors.
- Parameter form shows the same supported-size ranges as bulk editing, placement and optimizer. Derating keeps installed hardware; legacy unlimited ratings are not presented as physically supported new installations.

Headless successes do not close these native checks. This was a historical acceptance gate; the final summary, not this plan, states the completed scope.


## 历史实际验收路线（19:39 UTC制定时待执行）

前置门槛：容量证据、代码与定向回归收口后，获得用户明确桌面交接；用户正在操作时不得执行。实际像素截图和真实输入才可勾选完成，headless结果不能代替。

1. **锁定最新恢复基线。** 按上节保存、备份并记录摘要；截当前地图/选择/视角。备份可读取且完整前，不关闭窗口、不替换场景。核对实际代码版本与基线，不凭窗口版本标题推测源码；本地路径不随源码公开。
2. **单实例切换。** 正常关闭当前实例并核对已退出，再启动本轮完成副本；验收期间始终只有一个游戏实例。不并开旧版与新版；不使用既有玩家存档槽写入测试场景。每张内部验收记录附时间、分辨率和代码版本；机器路径不随源码公开。
3. **旧档模式与取消。** 载入独立旧档测试副本，看顶部“旧比例兼容”与右侧“选中设备 → 技术详情”说明；旧参数、坐标、库存不自动变化。尝试新建应明确提示先迁移。点“校验并迁移为米制（不缩放原坐标）”，看到范围/碰撞问题后按Esc或取消；比较取消前后完整场景摘要必须相同，无移动、截断、补能或丢弃库存。存在问题不得确认实际玩家场景迁移。可迁移样本的备份/确认/一次撤销，仅在独立副本另测。
4. **新reference场景与4km边界。** 待新增入口实现及专项通过后，从“模板与场景 → 新建空白真实规格场景”进入：先取消确认一次，原场景摘要不变；再确认应为空设备/连接、时间归零、库存为空且暂停，不写原存档；一次撤销应精确恢复之前场景。随后再次新建用于本轮独立测试，确认真实规格模式及1世界单位=10m。该入口目前正在接入，未获实现/测试完成确认前不得记录通过；无需人为往用户槽位注入外部临时档。平移观察东南西北扩展地表连续，完整4×4km、±200世界单位（±2000m）。同一设备在边界内预览有效，中心仍在场内但完整占地越界时必须拒绝；记录明确边界原因，避免禁建区/坡度错误冒充边界通过。
5. **钠电与CO₂尺度。** 在独立新场景以冻结参考规格放置钠电：应为本轮要求的**3个真实电池箱体**，PCS/冷却柜不冒充电池箱，一级和详情一致，地面接触及检修空隙清楚。若最终证据/实现尚未支持3箱，本项为阻塞，不靠改文字放行。CO₂约752×752m是**完整场址**，五个长拱仓只是其内部构件；占16km²地图约3.53%，不能按每仓752m或缩成CAES。容量降额不缩安装区，不宣称现场测量CAD或压力/气量已核实。
6. **一级院区真实成员。** 在独立电热站示例，一级看到的锅炉、水罐、换热器与二级当前安装清单逐一对应，无固定装饰双罐。移动一件后Esc返回，一级位置立即更新；再做一次添加、参数更新、删除并撤销，成员/几何同步且ID、库存、拓扑按操作语义保留。塔站同样只出现一套塔/镜场、一个对应控制设备。新热水罐为两只实际并联分层水罐，不是两份库存；沿低视角看罐脚/基础与地面接触，不悬浮、不穿地。旧未标记水罐仍旧几何，不能在详情中悄悄变新。
7. **窄屏参数与单位。** 1180×812后缩至640×480，打开风机、热水罐及一类物料设备参数：字段/数值/单位各自对齐，MWth/MWhth/kg/s不拆成孤立换行；固定安装规格、共享上限可见，旧超限值不静默截断。滚动可到所有字段，关闭/取消/应用按钮一直可达且不被表单盖住；Esc只关当前层。保存前后核对取消未改参数或库存。若实际窗口最小尺寸限制640，记录真实限制，不能拿逻辑布局结果冒充原生像素通过。
8. **恢复本次检查基线。** 只读取步骤1那份最新基线，核对全部摘要，保留暂停及原选择/视角或明确说明无法恢复的观察状态。核对单实例与日志无新脚本错误，截图最终场景。记录每项通过/失败/待验证及证据路径；存在未完成项不得宣称全面验收或发布。

本轮最小证据集：最新基线保存/备份清单；旧模式及迁移取消前后；4km有效/越界预览；钠电3箱；CO₂整场比例；一级/二级热站成员和贴地近景；640宽参数窗口；最终检查基线恢复。所有破坏性测试都在临时副本，不替用户决定容量削减或迁移。

19:42 UTC 无界面补证：新建空白真实规格场景入口已实装，test_reference_layout_world 当前150检查/0失败，包含新建后立即合法建造、暂停/清零、撤销恢复原设备/网络/库存账与时钟。极端旧99999MWh锂电撤销已通过；只限制旧可见代表箱至48，容量、占地不改，新真实规格4箱仍全部显示。该补证不是按钮实际GUI验收。
