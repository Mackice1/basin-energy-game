# BASIN 02 / 荒原 · 能源大基地 — 1.0.0.4 阶段二

## 同版本增量：场景存档与全域取景

版本继续为 **1.0.0.4**，在[阶段二已发布基线](https://github.com/Mackice1/basin-energy-game/tree/ef23e76e28e37bc4882cfac5f90c4020d3193d20)上改进场景入口与取景：保存/读取卡前置，提供场景名和未保存反馈；全景按HUD及侧栏后的实际视口适配4×4km，保留局部聚焦，并最小修复外背景材质。设备、物理算法及schema版本不变。

已记录的针对性自动测试通过，原生1180×812及640×480窗口验证首屏存档控件、确认/Esc取消、全域与局部聚焦及侧栏适配。原生GUI没有覆盖正式存档，成功保存和失败分支由隔离headless槽验证；本批不宣称重跑全部历史测试。详见[本批范围与验收](docs/ux_next/UX_BATCH_SCOPE.md)。公开整理未重跑游戏，不包含私人存档、运行证据或遥测，不创建标签或Release。

## 保留的阶段二已公开说明

本批为已验收的 **1.0.0.4** 增量，基于 [1.0.0.3 阶段一公开基线](https://github.com/Mackice1/basin-energy-game/tree/56400dde7c7c23c8a8d8705152305c3cf0c9118c)。版本唯一源仍是 `project.godot`；不创建标签或 Release，不改写历史。下方 1.0.0.3 与更早说明仅记录当时范围，其中“后续计划”和未包含项目不能替代本节的当前状态。

## 物料链、真实尺度与界面

- 目录扩展至 39 类，加入独立气态/液态/固态储氢、甲醇与氨化工链、CO₂ 储能整站和相关物料设施。有限库存、物料/能量账本、原料约束、排热与真实 GLPK 优化联动；非零产出来自实际供料和能量，不是展示曲线或免费原料。
- 参考规格与安装占地分别说明，按米制尺寸进行建设校验；4×4 km 建造域保留原地形核心，外围采用运行时地表扩展与过渡。既有高度场与二进制模型未替换。旧教学比例存档保留显式兼容，采用新规格需迁移预览/确认或新场景，不静默搬移设施或截断库存。
- 参数分组、窄窗口滚动和输入焦点下 Esc 取消；右侧运行/物料信息及详情返还主场景。真实设备外观为原创简化程序化模型，依据与适用范围见各项参考说明，不是厂家 CAD。

详见 [本批发布说明](docs/phase2/RELEASE_1004.md)、[最终原生验收](docs/phase2/FINAL_NATIVE_ACCEPTANCE_1004.md)、[39 类几何与容量边界](docs/phase2/GEOMETRY_CAPACITY_AUDIT_39.md)及 [物料模型契约](docs/phase2/MATERIAL_MODEL_CONTRACT.md)。

## 验证范围

- **181 个 Godot 测试程序**完成验证，来自基线全库、修复夹具后复跑及最后受影响项目的定向汇总，**不是一次不中断的全库运行**。
- 最终 Python 完整 discovery **363 项、0 跳过**。另有 **44 组真实 GLPK→Godot 严格独立审计**，含 36 组固定种子边界；专项与 Python 计数重叠，不能相加。
- 原生 GUI 验证实际启动 Python/GLPK、24 个预测时段返回已证明最优；非零醇氨数据通路由实际化工运行与严格审计覆盖，不把零输入场景的最优解说成非零化工优化结果。实际检查还包括化工实时曲线与详情、640 像素宽参数窗口、输入焦点下 Esc 取消、参考设备放置/重叠拒绝及 4 km 地表过渡。
- **没有逐一人工遍历全部 39 类的全部组合**。已有批量选择与站内交互沿用此前原生验收及本轮自动回归，不称本轮全部人工重做。公开整理仅做源文件身份、隐私和 Git 树核验，没有重跑游戏或测试。

固定规格、静态气腔/热容筛查与有限物料链属于教学模型，**不是压力容器认证、工程选型或动态压力/液位仿真**。Terrain3D 直接 Image 读取的导出警告仍存在，源码运行已验收，不宣称跨平台打包、稳定 FPS、显存或长期内存稳定性已验证。

## 公开内容与复现

保留执行源码、参数数据、测试与生成器、既有运行资产及第三方许可证；不新增项目许可证。研究参考只保留来源 URL、技术出处和许可边界，未取得再分发许可的研究图片不发布。原始验收日志、截图、玩家存档/备份、进程信息与实时遥测不发布，既有经审查的安全合成夹具保持不变。需要生成的跨语言测试夹具属于本地测试输出，先按随附测试的导出入口生成，再运行相应 Godot 审计，不能把开发环境结果视为干净克隆无需前置步骤的保证。

Version **1.0.0.4** adds bounded material/chemical chains and reference-scale facilities, bringing the catalog to 39 types, alongside the 4 km domain and UI refinements. Acceptance aggregates 181 Godot programs across baseline, fixture repair and final targeted runs, plus 363 Python tests without skips. The 44 real-GLPK cross-language audits overlap that count. Native checks covered a 24-period optimal solve, nonzero chemical runtime data, narrow-window Escape and terrain transitions, not every combination. These educational models are not engineering certification. Publication preparation reran no application tests and excludes private runtime data and third-party research imagery.

## 保留的 1.0.0.3 阶段一及更早历史说明

# BASIN 02 / 荒原 · 能源大基地 — 1.0.0.3 阶段一

本次为已验收的阶段一增量，基于 [1.0.0.2](https://github.com/Mackice1/basin-energy-game/tree/5436b0a97386030eb63551820dcc153f5867d212)，不是全部后续需求完成。版本唯一源为 project.godot；不创建标签或 Release。

- 新增钠离子、液流、地上压缩空气、液态空气、制氢—储氢—燃料电池综合储能链及固体储热，保留锂电与独立双罐熔盐。目录共27类，有有限库存、损耗、功率约束、端口、存档和优化支持，不仅是外观。
- 底部常态单行分类，设备面板向上展开；参数分组与Esc；右侧同类任意子集批改，Shift范围、框选和半选全选。只提交指定字段，整组校验后原子应用。
- 选中设备显示真实运行曲线，功率与SOC分轴、固定缓冲、限频采样；不编造出力。CAES采用地上容器/机房/热回收区外观与哑光分色，8种储能图标独立。
- 新存档schema13/model22，读取旧schema3–12；新增储能优化快照schema7。模型参数为教学假设，不是工程选型或安全认证。

## 验证与未包含范围

最终记录为117个Godot脚本、153项Python测试（真实GLPK，无跳过）通过；Godot全轮期间另有CAES材质补丁，材质相关4脚本7374检查另行通过。原生窗口复验Shift选3/5、框选2/5、半选状态、真实曲线、CAES哑光与8种图标。公开整理仅核对源码/哈希/隐私，没有再次运行游戏测试。

未逐一人工遍历全部27类详情或全部曲线，不保证跨平台导出、真实GPU帧率/显存或长期GUI稳定性。独立气/液/固储氢、醇氨化工、CO2流程、变电站进一步校核和右侧燃料/天气/运行布局反馈属于后续工作，**不包含在本阶段**。阶段二文档是计划，不是已实现功能。

技术边界见[技术说明](docs/storage_1003/TECHNOLOGY_AND_ASSUMPTIONS.md)，验证和复现见[验收说明](docs/storage_1003/ACCEPTANCE.md)，外观来源见[CAES参考](docs/storage_1003/CAES_VISUAL_REFERENCES.md)。运行日志、玩家存档/备份、截图、遥测与内部路径不公开；现有资源/第三方许可证保留，原创代码不新增许可证。

## 保留的1.0.0.2与更早历史说明

# BASIN 02 / 荒原 · 能源大基地 — 1.0.0.2

## 同版本增量：大地图基础设施视觉细化

在 [此前 1.0.0.2 详情场景提交](https://github.com/Mackice1/basin-energy-game/tree/6200bba0437bd6b582b1677ca35a63c3b5c81acc)上增加大地图显示层改进，继续使用 **1.0.0.2**，不新增版本标签、发布页或改写历史。下方公开 README 原内容保留为此前同版本与历史阶段说明。

- 三座既有外送支撑细化为钢格构塔、横担、绝缘子、银铝色示意导线束、弧垂与地线，并使用近/远两级预生成网格。塔中心、地图边界外送锚点、原送出上限与玩家连接端点/路径计算不变，不新增电压、回路或电气能力。
- 公路保留原进出端、通达关系与路面宽度；东段可见道路平缓绕开塔基，补充路肩和近景标线。绕行是显示层修正，不扩大碰撞、建设区域或修改原逻辑路线。
- 新增 1024×1024 预烘焙地表颜色图。原高度场、控制权重、四类地表材质与地形着色器不变；已有水气路线和勘察框仅合并绘制，不新增每帧几何重建。

详见 [大地图增量说明](docs/WORLD_INFRASTRUCTURE_1002_ZH.md)和 [外送走廊参考与边界](docs/EXPORT_CORRIDOR_VISUAL_1002_ZH.md)。本轮不改容量、物理求解、存档、控制器或既有 GLB 模型，不把显示细节等同于工程精度。

## 本增量验证范围

最终绕塔及导线对比度修订后，**10 个针对性套件与现有 `tests/run_all.sh` 均通过**。19 项电调度和 26 项热调度真实 GLPK 测试共 45 项在本轮较早验收时通过、无跳过，**不是最终视觉修订后重跑的结果**。这些是已验收源码记录，公开整理只做文件/哈希/隐私检查，没有重跑游戏测试，也不宣称全部历史测试通过；此前已披露的历史站内响应式失败不因此消失。

同场景 CPU 软件渲染的最终帧时变化为 **−5.3% 至 +4.8%**，有快有慢且存在短时波动，不能据此宣称加速、流畅或真实 GPU 性能达标。原生图形验收检查四档视图与图层切换前后模拟状态一致；完整实鼠标连线/建造流程和跨平台打包不在本轮已验证范围。

运行所需的新颜色图及其生成器、显示脚本和测试已包含。运行日志、性能/状态快照与截图不发布；公开说明保留可读结果、来源范围和复现入口。不新增项目许可证。

This same-version **1.0.0.2** increment refines the world road, export-corridor visuals and baked landscape color. Tower positions, export anchors, player-connection calculations, capacities and physical models remain unchanged. Ten final targeted suites and the existing bounded aggregate runner passed; 45 real-GLPK tests passed earlier in the iteration, not after its last visual revision. Software-rendered frame times varied from −5.3% to +4.8%, not evidence of a speed improvement. Runtime evidence is omitted and publication preparation did not rerun tests.

## 保留的此前 1.0.0.2 及历史公开说明

# BASIN 02 / 荒原 · 能源大基地 — 1.0.0.2

当前版本 **1.0.0.2**，在 [1.0.0.1 公开基线](https://github.com/Mackice1/basin-energy-game/tree/f97065c04d383717188ff729d5734915f9625755)上增量更新设备详情与塔站外观。版本唯一源仍是 `project.godot` 的 `application/config/version`，项目名称和存档目录规则不变。不创建标签、发布页或重写历史。下方 1.0.0.1、V23、V22 说明保留为历史记录；[版本规则](docs/VERSIONING.md)同步标明 1.0.0.2，当前版本以项目配置及本节为准。

## 本轮变化与边界

- 21 种设备详情统一灰蓝背景、实体地台、天空反射与阴影，继续保留 1.0.0.1 的相机边界。适配取景排除地台与隐藏选择环，并调整近裁面及阴影偏移。
- 光伏详情展示 3 块代表性组件；变电站详情展示精细变压器/开关柜组合。两者只是独立展示示例，不代表全场数量，不改主场景光伏阵列、容量、端口或物理计算。
- 塔站采用参考敦煌外置吸热器光热塔形态的原创简化资产。塔高 25 m、靶点 24 m、100 面定日镜及 1,600 m² 镜面积保持不变，不是实厂尺寸复刻或厂家 CAD。只有已有 `tower_station_preview.glb` 被替换，其他已有 GLB 不变。
- 原物理核心、设备目录、尺寸定义、主场景控制器及站内控制器保持不变。本轮不增加能源技术、容量、发电能力或工程精度。

操作、模型边界与来源见 [1.0.0.2 详情说明](docs/DETAIL_STUDIO_1002_ZH.md)和 [变电站模型说明](docs/STATION_DETAIL_MODEL_1002_ZH.md)。

## 验证状态：通过范围与已知失败

最终针对性记录为 **311 项新详情测试 + 23,522 项相机边界 + 1,021 项原设备详情 = 24,854 项，0 失败**；`tests/run_all.sh` 的既定测试集也通过。**这不等于全部历史测试通过。** 历史站内响应式测试 1,565 项中仍有 9 个 headless 拾取/拖动断言失败，独立 1.0.0.1 基线复现相同 9 项；未计作本轮通过。

真实原生 Godot 输入已验证滚轮放大/缩小、左键拖动、适配、返回与 1024 小窗口重开。**右键旋转只有自动回归覆盖，本轮没有可靠原生右拖证据。** 图形运行使用 CPU 软件渲染，不宣称真实硬件 GPU 性能达标。上述为已验收源码的记录，公开整理没有重跑游戏测试；详情说明保留验证出处与复现入口。

## 公开内容

公开源码保留运行所需 GLB、结构数据、GDScript、测试及建模生成器。此次不发布运行日志、截图、录屏或实时遥测。新增塔模型的可选 `.blend` 编辑工程因含本机路径元数据而省略，原文件在本地保留；可使用 `tools/build_csp_tower_visual.py` 重建，因此不声称本次含完整 Blender 编辑工程。资产清单中的该 `.blend` 路径记录原构建来源，不表示已随仓库提供。原有安全合成夹具和其他历史建模源保持不变，不新增项目许可证。

Version **1.0.0.2** refines the detail-view studio and representative PV/substation models, and replaces only the existing tower GLB. Physics, capacity, field arrays and controllers are unchanged. The latest three targeted suites recorded 24,854 assertions with zero failures and the bounded `run_all.sh` suite passed; a historical station-responsive suite still has nine failures reproduced on 1.0.0.1. Native wheel/left-drag/fit/back/small-window flows were checked, but right-drag rotation has automated coverage only. Runtime evidence and the new optional Blender project are omitted; the generator remains available. Publication preparation did not rerun tests.

## 保留的 1.0.0.1 与更早公开说明

# BASIN 02 / 荒原 · 能源大基地 — 1.0.0.1

当前正式版本号为 **1.0.0.1**，采用“主版本.功能版本.修订版本.构建号”四段格式，集中读取 `project.godot` 的 `application/config/version`。日常小改通过同一仓库的 Git 提交累积，批次验收后才统一更新版本；本次不创建标签或发布页。规则见 [版本命名](docs/VERSIONING.md)。

## 本轮：设备详情相机边界

- 缩小上限按当前模型包围盒、旋转与视窗宽高比计算，为适配距离的 1.6 倍；不同设备不共用固定世界距离。
- 连续拖动、缩放、旋转及窗口变化后，模型包围盒中心保持在视窗中央 60% 区域，避免拖出视野。放大仅保留很小的数值安全距离，近距离允许看局部，不保证完整模型始终可见。
- “适配模型”恢复完整取景；窗口变化不再强制重置旋转。约束仅用于设备详情相机，不写入参数、库存、连接、时钟或存档。基地/厂站相机与能源求解未改。
- 运行窗口显示集中版本号；`application/config/name` 保持原值，避免已有 `user://` 存档目录迁移。

详见 [详情相机边界与验证](docs/CAMERA_LIMITS_1001_ZH.md)。原已验收源码记录了 **23,522 项新增相机断言 + 1,021 项详情回归 + 107 项入口回归 = 24,650 项，0 失败**，另有真实原生桌面 GUI 的缩小、连续拖动和版本标题验证。这是该次针对性验收，不是全部历史测试重跑；公开整理没有重新运行测试。运行日志、截图及实时遥测不随公开源码发布。

## 版本沿革与公开基线

下方 V23、V22 是保留的**历史内部阶段快照**，不是当前四段版本号。V23 公开基线可在 [此提交](https://github.com/Mackice1/basin-energy-game/tree/97e684249986f42305b17974059e1bc83b502654)追溯；V22 链接和原运行、验证、许可说明继续保留。V23 冻结源码包不覆盖、不追溯改名；不另建 V23.1。本次没有新增项目许可证。

Version **1.0.0.1** uses a single version setting in `project.godot`. This commit refines only the device-detail camera limits and displays that version in the window title, while preserving the save-directory name and physical models. The accepted source recorded 24,650 targeted assertions with zero failures plus native GUI checks, not a complete historical rerun. V23/V22 below are historical internal snapshots; routine changes accumulate as commits without creating a tag or release for every edit.

## 保留的历史 V23 / V22 公开说明

# BASIN 02 / 荒原 · 能源大基地 — V23

2026-10-21：在已公开的 [V22 基线](https://github.com/Mackice1/basin-energy-game/tree/b06d64f85271a3a568205c89b146bc1e2cd35e71)上加入左键平移与全设备二级详情。下方原 V22 公开 README 保留，运行依赖、许可说明和历史验证限制继续适用；V23 使用与验证以本节和 [V23 操作说明](docs/NAVIGATION_DEVICE_DETAILS_V23_ZH.md)为准。

## V23 新增与操作变化

- 选择/浏览模式下，左键拖动平移视角，小幅抖动仍按单击处理并在松开时选中。主场景/厂站/详情的阈值分别为 6/5/4 px；拖动后不选中、不放置、不移动设备。从 UI 区域起拖不会穿透。
- 要移动设备，先显式选择“移动”。中键平移、右键旋转、滚轮缩放及既有键盘导航保留。
- 完整目录 21 类设备均可通过单击后的“进入设备详情”按钮或双击打开独立二级页，展示已有真实 3D 资产及运行、参数、连接、边界四个分区。返回或 Escape 保留上一级状态、选择与相机。
- 原电热站、运行塔站和未投运塔站继续使用各自已有场景；未投运塔站仍不发电。详情直接读取主模拟，不复制库存、不改主时钟，也不虚构设备内部可操作结构。
- V22 的运行资产、设备目录与核心能源/热/蒸汽/熔盐求解保持不变。本次只是导航与只读详情改动，不代表新增能源技术或工业级精度。

## V23 验证范围

原 V23 验收记录为 **20 个针对性回归套件、37,700 项断言、0 失败**，另通过原生桌面 GUI 输入验证：拖动/单击区分、UI 起拖隔离、设备详情真实入口、返回保留状态，以及详情随主模拟实时更新。**不是全部历史测试重跑，也不是跨平台导出认证。** 这些是原 V23 实测记录；此次公开整理仅进行文件、哈希与隐私检查，没有重新运行游戏测试。

逐套计数、原始记录来源和复现边界见 [V23 验证说明](docs/VALIDATION_V23.md)。完整运行日志、状态快照、遥测和截图不随公开仓库发布；已有 V22 合成回归夹具保留。V22 验证基线仍可在 [V22 验证说明](docs/VALIDATION_V22.md)及上述基线提交查阅。

V23 adds thresholded left-button camera panning and read-only secondary detail pages for all 21 device types. Existing station interiors, runtime assets, device catalog and physical solvers are retained. The original V23 acceptance recorded 20 targeted suites / 37,700 assertions / zero failures plus native GUI checks, not a rerun of every historical test. See the [V23 guide](docs/NAVIGATION_DEVICE_DETAILS_V23_ZH.md) and [validation provenance](docs/VALIDATION_V23.md). No new license is introduced.

## 保留的 V22 公开 README / Preserved V22 public baseline

# BASIN 02 / 荒原 · 能源大基地 — V22

中文优先；English overview follows below.

一个使用 Godot 的能源基地建设与运行原型：在地形上布置设备、进入厂站、连接电/热网络，观察天气、储能和供需变化，并使用独立 GLPK 后端分析固定容量调度。

这是 **V22 界面与设备外观整合版本**，保留此前风电、光伏、电池、电热水锅炉、燃气热水锅炉、光热、储热、闭式蒸汽循环和塔式熔盐运行模型。V22 的界面与外观改动不代表新增工业级物理精度。

## 快速运行

1. 安装 **Godot 4.6.3 Standard**，不需要 .NET。本项目使用 Compatibility 渲染。
2. 克隆完整仓库，在 Godot 中导入根目录的 `project.godot`。不要只复制脚本；`addons/`、`assets/` 和 `generated/` 都是运行所需内容。
3. 等待首次资源导入完成。若首次插件脚本加载异常，退出并重新打开编辑器，再按 F5。
4. 默认入口为 `main.tscn` → `scripts/world_game.gd`。新游戏从空设备场景开始。

也可以在仓库根目录运行：

```sh
godot --headless --editor --path . --import --quit
godot --path .
```

### GLPK 优化依赖

运行优化分析另需 **Python 3.9+** 和 **GNU GLPK 5.0 的 `glpsol`**。Python 后端只使用标准库；Godot 本体不需要 Python 才能打开地图。

默认从 `PATH` 查找 `python3` 和 `glpsol`；可以在启动 Godot 前指定：

```sh
export BASIN_PYTHON=python3
export BASIN_GLPK=/absolute/path/to/glpsol
godot --path .
```

Windows 可设置同名环境变量，指向相应的 Python 和 `glpsol.exe`。跨平台桌面导出尚未认证，不保证随附插件二进制适配所有机器。

仓库包含未修改的 GLPK 5.0 源码压缩包和许可证，**不包含已安装的 GLPK 可执行文件**。具体求解接口见 [后端说明](tools/DISPATCH_SOLVER.md)；现有 `tools/run_cloud.sh` 和部分历史测试仍含原测试环境路径，在其他机器上请先检查并显式设置依赖路径。

## 基本操作

- 右键拖动旋转，中键平移，滚轮缩放；W/A/S/D 平移。
- 在建造栏选择设备并放置；Esc 退出建设模式。
- 通过端口连接设备。选择厂站后进入站内建设和检查热设备。
- 暂停/运行及 1–60 倍模拟速度共用同一模拟时钟。
- CSV 导入用于明确的气象或功率输入，模板在 `templates/`。
- GLPK 窗口是独立分析，不会自动把优化结果写回实时状态。

详细操作和历史阶段差异见 [原项目说明](docs/HISTORY_README.md)、[塔式熔盐运行](docs/TOWER_OPERATION_STAGE_V21_ZH.md)、[V22 设备外观](docs/EQUIPMENT_APPEARANCE_V22_ZH.md)及 [CSV 导入](docs/CSV_IMPORT.md)。旧文档中的版本标题、测试数量和证据链接均属于相应历史阶段。

## 源码布局

- `project.godot`、`main.tscn`：项目入口。
- `scripts/`：Godot 场景、界面、设备目录、电/热运行模型及存档校验。
- `tools/dispatch_solver.py`：独立 GLPK 调度后端；`tools/` 还包含模型构建和验证工具。
- `assets/`、`generated/`、`config/`：运行模型、字体、地形资源和配置。
- `art_source/blender/`：Blender 源文件与生成脚本。
- `addons/`：Terrain3D、Asset Placer 及随附许可/平台二进制。
- `templates/`：示例 CSV；`tests/`：自动化及图形验证脚本。
- `docs/`：模型假设、操作说明和历史设计记录。
- `evidence/`：少量合成测试输入/结果与资产哈希收据，不含玩家存档或完整历史录像。
- `third_party/glpk/`：GLPK 原始源码压缩包与 COPYING。

## 验证状态与限制

此前 V22 验收报告记录了 **89 个 Godot 测试脚本覆盖、127 项 Python/真实 GLPK 测试通过，以及 11 项原生 GUI 检查通过**。这些是之前的运行记录，**不是 2026-10-21 公开整理时重新运行的结果**。Godot 最终 UI 复查执行 88 个脚本，另一个长时昼夜集成测试沿用同版物理模型的先前通过记录。

公开整理只做文件与哈希检查，不修改运行脚本、物理模型或二进制资产。详见 [验证说明](docs/VALIDATION_V22.md) 和 [公开整理说明](docs/PUBLICATION_NOTES.md)。部分历史重启/原生 GUI 测试依赖未公开的运行输出，需要先重新生成夹具；不能把旧测试报告理解为干净克隆上的全套测试保证。

这仍是教学/探索原型，不是 AC/DC 潮流、施工设计、安全校核、精准天气预测或工业设备数字孪生。地形图片直接加载相关导出警告和性能边界仍存在；软件渲染性能不代表真实 GPU 性能。没有宣称 Windows/macOS/Linux 安装包或所有桌面交互均已验证。

## 权利与第三方内容

公开存放用于项目管理和代码查阅。**本次公开整理没有为项目原创代码或原创资产新增开源许可证，也不表示授予其通用再分发许可。** 第三方组件继续受各自随附许可证约束；相关文件未移除。

- Terrain3D：[`addons/terrain_3d/LICENSE.txt`](addons/terrain_3d/LICENSE.txt)。
- Asset Placer：[`addons/asset_placer/LICENSE`](addons/asset_placer/LICENSE)。
- 字体：[`assets/FONT-LICENSE.txt`](assets/FONT-LICENSE.txt)。
- GLPK：[`third_party/glpk/COPYING`](third_party/glpk/COPYING) 与随附源码声明。

第三方分发义务和未来安装包许可需要按实际分发内容审查；本 README 不替代相关许可文本。

## English overview

BASIN 02 V22 is a Godot energy-base construction and operation prototype. It combines terrain-based equipment placement, station interiors, electrical/thermal networks, weather and storage simulation, and a separate fixed-capacity GLPK dispatch analysis. V22 integrates UI and equipment-appearance refinements while retaining the earlier energy models.

Use **Godot 4.6.3 Standard / Compatibility** and import `project.godot`, then press F5. Optimization additionally requires **Python 3.9+ and GNU GLPK 5.0 (`glpsol`)**. Set `BASIN_PYTHON` and `BASIN_GLPK` if the executables are not on `PATH`. The repository includes GLPK source and license, not an installed solver executable.

The earlier validation reported **89 Godot scripts covered, 127 Python/real-GLPK tests passed, and 11 native GUI checks passed**. These were **not rerun during the public-source preparation on 2026-10-21**. The final UI recheck ran 88 scripts and retained a previous long day/night integration pass. Historical runtime saves, screenshots and full logs are intentionally omitted; some archive-dependent QA needs regenerated fixtures.

This is an educational prototype, not an engineering-grade power-flow, hydraulic, safety or construction tool. Desktop exports and all platform combinations are not certified. See [validation](docs/VALIDATION_V22.md) and [publication notes](docs/PUBLICATION_NOTES.md).

No new open-source license is granted for the project's original code or assets by this publication. Bundled third-party components retain their existing licenses listed above.
