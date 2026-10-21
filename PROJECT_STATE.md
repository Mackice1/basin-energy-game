# 当前阶段 V21：塔式熔盐昼夜发电

1600m²四圈镜场接565/290°C熔盐、有限双罐库存和直接盐水蒸汽发生器；复用闭式蒸汽发电，支持日间充热与夜间有限库存供电。新增运行塔站，旧预览保持未投运。schema12/model21；物性、辅电、守恒与教学边界见 [V21指南](docs/TOWER_OPERATION_STAGE_V21_ZH.md)。下方为历史记录。

# 当前阶段 V20.1：环绕式塔镜场外观修正

四圈径向错列100面4×4 m定日镜，总镜面1600 m²；站地160×160 m、内区120×120 m、塔高25 m不变。仍是未投运零出力预览。详见 [V20.1说明](docs/TOWER_RING_PREVIEW_V20_1_ZH.md)。schema11/model20和V20热电模型不变。下方为历史记录。

# 当前阶段 V20：闭式蒸汽发电与塔式站预览

2026-10-16：槽式300/200°C油接固定工况蒸汽发生器、汽轮发电机、干冷凝汽器及给水泵闭合循环；独立160×160m塔式镜场为未投运只读预览。当前schema11/model20，读取旧schema3–10。物性、外部辅电、质量/能量守恒、热天降额和边界见 [V20指南](docs/RANKINE_POWER_STAGE_V20_ZH.md)。下方为历史记录。

# 当前阶段 V19：槽式高温光热供热与储热

2026-10-16：独立300/200°C导热油、双罐可用焓库存、油水隔离换热及DNI单轴跟踪。当前写出 schema 10 / model 19，读取旧 schema 3–9。完整模型、来源、操作和预热边界见 [V19指南](docs/HIGH_TEMP_TROUGH_STAGE_V19_ZH.md)。下方为历史阶段记录。

# 当前阶段 V18：真空管光热集热

当前写出 schema 9 / model 18；旧 schema 3–8可读。详见 docs/SOLAR_THERMAL_STAGE_V18_ZH.md；其余历史记录如下。

# 当前阶段：V17 燃气热水锅炉

2026-10-16：单台天然气热水锅炉、有限共享燃料资源、独立燃料/辅机/热量账和联合 GLPK 已接入。当前写出 schema 8 / model 17，兼容旧 schema 3–7；默认燃料供给关闭。操作、单位、教学假设和边界见 [V17 指南](docs/FUEL_BOILER_STAGE_V17_ZH.md)。下方 V16 记录为此前阶段。

# 当前阶段：V16 米制设备与沉浸式电热站

2026-10-16 第二轮有边界界面优化：站内双工具组/分页详情、小窗逻辑尺寸修正、重叠标注避让及明确连接反馈。最新边界与验收见 [V16.2 界面优化](docs/BOUNDED_REFINEMENT_V16_2_ZH.md)。

2026-10-16 操作打磨完成：单击选中/明确进入、原子拖动与撤销、兼容连线提示、镜头/UI 隔离及屏幕尺度标签。最新验收、截图和实操录像见 [V16.1 操作打磨说明](docs/INTERACTION_POLISH_V16_1_ZH.md)；下方旧测试数量与性能以该说明为准。

2026-10-15。当前权威说明：[IMMERSIVE_METRIC_V16_ZH.md](docs/IMMERSIVE_METRIC_V16_ZH.md)。下方V15及更早章节为历史记录，其版本号、示意尺寸、测试数量和性能结果不能代表当前版本。

- 新游戏统一0.1 world/m，schema 7 / model 16，保存 `dimension_profile`。schema 3–6继续按 `legacy_illustrative` 读取；不自动缩放坐标。显式米制迁移先校验再确认，可撤销；失败不改变场景。
- Blender GLB覆盖锅炉、双罐储热、隔离换热器及电热站；存储罐完整高度7.635 m，院区最高附件9.1 m。院区80×60 m、站内净区48×48 m，同一尺度，内部净区不重复计地。
- PV按550 Wp组件片数；电池/中压/电热设备按固定参考模块数排布。实体、检修安装区、保守碰撞外接圆及转子包络分开计算。容量增长重新检查场地，视觉模块不增加运行库存或功率。
- 默认内部三角布局为锅炉(-1,-0.7)、储热(0.9,-0.6)、换热器(0,1)，坐标为世界单位。地图地貌占位方块移除；外部服务点为标记，水源/交通/燃料明确“场地示意”。管道是连接几何，无新增水力学。
- 最终完整固定回归已通过：`evidence/immersive/full_regression_final.log`，43个Godot汇总共329981项检查、45项Python测试（19+26），全部通过。实际图形进程通过4个GLB与站内三视图，视角不改状态：`evidence/immersive/gui.log`。真实保存后独立进程读回schema 7米制场景、8设备/8连线和库存不变：`evidence/immersive/restart_glpk_final.log`，另通过该真实读档状态的2时段GLPK原始决策审计及实时状态隔离检查。求解器补修已校验整数值线路ID的float→int规范化，不改变调度约束；风机基础/维护板专项1220项通过。外部厂站两张近景通过，见 `evidence/immersive/facade_gui.log`。
- 云软件渲染配对报告已完成：同旧快照/相机的站内运行平均3.53→9.01 FPS；独立米制新例子站内运行6.09 FPS。基地差异不能证实明显改善，不能称流畅；测量对应冻结渲染候选。真实GPU、所有实鼠标路径、跨平台可执行导出和V16最终冻结包恢复仍待验。地形PNG直接Image读取的导出警告尚需处理，GLPK/Python及Terrain3D目标平台依赖仍需验证。

# 历史阶段：V15 厂站内外两层布局

2026-10-15：电热站整体基地外观、内部独立3D建设与端口映射；schema6/model15；计算只使用既有电热设备一次。指南 docs/STATION_HIERARCHY_ZH.md。以下是此前阶段记录。

# 历史阶段：V14 首批完整电热链

2026-10-15：在已备份天气版上接入锅炉、热储、隔离换热器与独立热需求，schema 5 / model 14。当前指南见 docs/THERMAL_STAGE1_USER_ZH.md；以下保留此前阶段历史记录。

# 历史阶段：天气与太阳位置（2026-10-15）

当前活动源码在真实V13需求入口版上完成天气阶段。位置/日期/固定时区参与太阳位置；教学情景与CSV字段逐项优先，新增云量/雨强，直接可用功率仍最高优先。球内动态图标无常驻文字，与顶部底框一体连接。3D太阳/环境光、云量柔暗、最多6条风线同源且可关闭。未实现三维体积云、地表降雨粒子或在线当地天气；未扩热设备。

完整边界：[CLIMATE_WEATHER_STAGE_ZH.md](docs/CLIMATE_WEATHER_STAGE_ZH.md)。验证：94,522项Godot检查、19项真实GLPK Python案例通过；实际软件渲染GUI验证日/夜、云/雨数据与缺测、连续帧/暂停、特效关闭、60倍及进程重启读档。云端llvmpipe约4–5fps，关闭新特效也相近，桌面性能/导出未验证。

以下为此前阶段记录，天气描述冲突时以本节及新天气文档为准。

# V13 demand-entry update — 2026-10-15

底部建造栏已移除电负荷，需求改从右侧用电需求设置，以抽象接入标记展示；旧kind/load、存档与GLPK兼容。当前验证与入口见 docs/DEMAND_ENTRY_UPDATE.md。

# V13 slider/weather update — 2026-10-15

当前速度已改1–60整数滑条与右侧输入，顶部新增原创天气球；详见 docs/SPEED_WEATHER_UPDATE.md，完整回归91963条Godot断言＋19项Python测试通过。天气球是现有全局数据的显示，不是外部真实天气。

# V13 update — 2026-10-15

当前状态以 docs/GLPK_V13_ZH.md 与 docs/V13_VALIDATION.md 为准。固定容量GLPK、独立时序图、可选倍速与默认收起图标面板已实现并云端验证。位置地理建模、资源模板库、桌面打包仍未实现或未验证。存档结构继续使用schema4/model12，保持V12兼容，不保存预测结果与倍速。

# V12更新提示
2026-10-15新增源网荷储、schema4/model12与Blender GLB，完整状态见README.md和docs/FOUNDATION_V12.md。下文是保留的V11历史记录。

# BASIN 02 — project checkpoint

Status: working terrain prototype, not a finished game. V1 is preserved separately as Basin01-Godot-Prototype.zip.

## Restore on a fresh machine

1. Install official Godot 4.6.3 standard edition (not .NET). Keep Compatibility rendering enabled.
2. Extract this entire folder. Do not copy only map.gd: addons, generated data, fonts, and config are required.
3. Import project.godot in Godot. Let first resource import finish, then fully restart the editor. Asset Placer's initial script reload can invalidate its static singletons; a clean second launch is required.
4. Run the main scene with F5. Alternatively, after import: godot --path <this-folder>.
5. Automated core checks: godot --headless --path <this-folder> -- --self-test.
6. Graphical screenshot verification: godot --path <this-folder> -- --capture. Saves six actual engine viewport images to preview/ then exits.

No absolute machine path is needed. .godot is disposable and intentionally excluded from the distributable checkpoint. No login, repository access, or cloud account is required to run this local project.

## Locked versions and sources

- Godot 4.6.3.stable.official.7d41c59c4, Compatibility / OpenGL3. Cloud graphical tests use software llvmpipe; performance on hardware varies.
- Terrain3D 1.0.2-stable: https://github.com/TokisanGames/Terrain3D/releases/tag/v1.0.2-stable
- Official archive: Terrain3D_v1.0.2-stable.zip. SHA256 a071850250ec5e596aa54da61c01d75768774eb379ee997584d426a45f4884a2, verified after download.
- Terrain3D license: MIT, included in addons/terrain_3d/LICENSE.txt. Official release explicitly supports Godot4.4–4.6+ and fixes Compatibility shader constants. Renderer support: https://terrain3d.readthedocs.io/en/stable/docs/platforms.html
- Asset Placer 1.6.0: https://github.com/levinzonr/godot-asset-placer ; commit 1dbf9fd782566780d6a6c52bd4197f448622f0aa. MIT license included in its addon folder. This is official upstream, not an unverified assumption about a user fork.
- Original terrain/textures: generated by scripts/generate_landscape.py, reproducible with Python + numpy + scipy + Pillow; CC0 dedication and parameters in generated/GENERATION_NOTES.md and metadata.json.
- Noto Sans CJK font license is in assets/FONT-LICENSE.txt.

## Completed

- Real Terrain3D GDExtension integration, four 512-region maps, 0.25 vertex spacing, five LOD levels, centered on the viewed map target rather than the elevated rendering camera; the terrain is not the previous hand-built triangle mesh.
- 1024² float32 heightfield with localized low mountains, branching gullies, alluvial aprons, broad flat Gobi land, limited dunes and saline depression.
- Four tileable material sets: gravel, bedrock, sand, salt; albedo + height and normal + roughness RGBA.
- 2,000 instanced rocks/pebbles plus 260 sparse shrubs, deliberately limited vegetation.
- Three camera presets, orbit/pan/zoom, terrain picking, eight overlays, slope and exclusion screening, explicit external fuel/water/grid interfaces.
- Asset Placer installed and second editor-import pass checked. Its editor placement workflow has NOT yet been visually validated or used to author these procedural rock instances.

## Deliberately not done

- No complete industrial simulation, economy, savegame progression, real GIS or engineering approval.
- No voxel mining/tunneling requirement; godot_voxel is not integrated.
- No claim of physical erosion simulation: this is structured synthetic terrain with modeled gullies and fans.
- No exported stand-alone executable yet. Raw generated data and PNG inputs are required; an export preset must explicitly retain those source files before an executable build.
- Asset Placer's Decal brush outline is unavailable in Compatibility. Single placement can be used; visual editor testing remains necessary.

## User direction: empty starting map

The starting map must contain no prebuilt power plants or generating equipment. Existing boundary utility markers denote external interfaces, not player-built stations. Future construction UI should sit at the bottom, Cities: Skylines-like: equipment categories → generation/source → wind, PV, solar thermal, coal, gas → independently modeled assets. Turbines, PV panels, substations, boilers, steam turbines, generators and auxiliaries remain separate placeable objects. This checkpoint does not implement that construction system.

## Next useful work

1. Review graphical terrain/material quality and GPU performance, and revise with user feedback.
2. Author reusable rock/shrub scenes and validate actual Asset Placer surface placement in the editor.
3. Improve infrastructure assets and map selection overlays while preserving responsive camera controls.
4. Only then expand equipment as independent boiler/turbine/generator/auxiliary scenes and typed ports.

## Navigation

main.tscn and scripts/map.gd are the runtime entry. config/map.json holds scenario values. generated/ contains all baked portable terrain inputs. addons/ contains actual plugin code and desktop binaries. preview/ contains engine captures and test records.

## Portable package size

The checkpoint bundles Linux x86_64, Windows x86_64, and macOS Terrain3D binaries. Mobile/Web binaries and disposable caches are omitted; other platforms need the matching official release assets. The UI font is a renamed Noto Sans CJK subset (Basin UI) containing this project's current characters, under the same included license. New labels with characters outside that subset may require regenerating or replacing the UI font. The unchanged full font remains available in the V1 checkpoint.

Default low_spec=true uses Terrain3D's official lightweight shader and disables dynamic sunlight shadows. This preserves texture blending, normals, holes and color maps; it deliberately omits expensive projection/detiling features. Low-spec settings do not establish a frame-rate guarantee. preview/performance.json records actual graphical capture timing including overlay rebuilds and PNG writes; it is not a steady-state game benchmark.

## Last verified checkpoint

2026-10-14: actual Godot graphical execution on llvmpipe (LLVM19.1.7,256bits), gl_compatibility. Six actual viewport PNGs reviewed. Corrected the earlier stepped terrain boundary by centering LOD geometry on the viewed target and closing the side edge. Sand and saline transitions were softened; no prebuilt generating equipment is present.

The 149 sampled frames in the capture sequence averaged 3.58 fps, with median225ms and P95548ms. This includes changing overlays and writing images and is not a steady-state benchmark. It is nevertheless slow on this software-rendered cloud setup; this checkpoint does NOT claim smooth gameplay. A real GPU has not been benchmarked. Next work is performance profiling and art refinement, not expanding the whole power/economy simulation or claiming city-builder production quality.

The included original upstream Asset Placer is installed for later editor authoring; this checkpoint's scatter is procedural MultiMesh code, not Asset Placer-authored placement. Its updater network warning and small shutdown-resource warnings remain. Runtime self-test passes. This is an intentionally explicit technical preview status.

Restore validation: the final self-contained ZIP was extracted into a fresh directory without .godot. Official Godot imported it, then the restored project passed all self-test assertions, including four Terrain3D regions, eight overlays, exclusion/buildability, three camera modes and picking. Final package includes all six reviewed screenshots and the measured performance JSON. Import-time editor-plugin warnings are distinct from passing runtime checks.
