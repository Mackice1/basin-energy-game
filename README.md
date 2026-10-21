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
