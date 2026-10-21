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
