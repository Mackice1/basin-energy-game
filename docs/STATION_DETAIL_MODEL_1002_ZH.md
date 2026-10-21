# 变电站详情模型：1.0.0.2

## 类型识别与边界

原米制模型位于 `equipment_visual.gd::_build_metric_electrical`，是油浸变压器与封闭中压开关柜的简化组合；`spatial_dimensions.gd` 沿用 SMA MV Power Station 2000SC 的 6.813 × 2.941 × 5.538 m 参考包络，按每个教学模块 2 MW 排布。用户截图中的两个块状单元是该分组显示，不是大型高压露天开关站。旧非米制模型也保留，不覆盖。

当前求解只使用容量和损耗，不计算电压等级、无功、交流潮流、变压器电磁暂态或保护动作。因此新模型不标注一个虚构的运行电压，不添加高压AIS母线场、额外逆变器、发电能力或保护功能。资料中厂家20kV等值仅用于识别设备类别，不写入游戏参数。

## 新增的独立详情LOD

`scripts/station_detail_sample.gd` 使用 `.new()` 创建 Node3D，`device_kind == "station"`。所有尺寸以米定义，只供设备二级页。展示一个代表性变压器与三柜门封闭开关柜，不代表全站数量、不按容量复制，也不是SMA或其他厂家的CAD复刻。

- 油箱、底法兰、盖板垫片和螺栓、吊耳、双侧23片散热片与上下集油管。
- 三相套管底法兰、棕色瓷绝缘裙、顶端夹具、三条分离的绝缘连接电缆。
- 小型储油柜及支撑、油位窗、连管、加油盖、排油阀、铭牌和接线箱。
- 开关柜底座、防雨顶边、三分柜门、门缝、合页、把手、静态仪表窗、操作面板、警示牌和通风百叶。
- 局部设备条形基础、钢支承与示意接地连接。没有场地地板，统一浅色地面由详情查看器提供，不参与模型AABB。

本模型的构造及走线仅为工业外观示意；净距、绝缘等级、散热、短路力、保护和施工安全未作工程设计。仪表窗、标识和开关把手均静态，不显示虚构运行状态。

## 一手来源核对

1. [SMA MV Power Station 1000SC–2000SC 数据表](https://files.sma.de/downloads/MVPS1000SC-2000SC-DEN1518-V22web.pdf)：用于核对中压组合站类别，而非复制其内部逆变器或电气能力。
2. [SMA 运输安装要求](https://files.sma.de/downloads/MVPS21MOW-TA-en-25.pdf)，第4–7页产品组成与选项：变压器、开关柜、逆变器的范围分开；开关柜有三单元配置。本游戏只精细化原有变压器/开关柜显示，未新增逆变器。
3. [Hitachi Energy 地面配电变压器](https://www.hitachienergy.com/ch/it/products-and-solutions/transformers/distribution-transformers/liquid-filled-distribution-transformers/small-distribution-transformers-up-to-315-kva/ground-mounted-distribution-transformers)：核对地面油浸三相变压器可使用散热片/散热器及带或不带储油柜构型。当前外观是原创代表性构型，不声称特定厂牌型号。

## 性能与测试

`tests/test_station_detail_sample.gd` 检查纯展示结构、代表性标识、无运行电压、无电气端口API、包络/落地和三角预算，并导出改前/改后真实Godot生成几何用于离屏审查。

改前单模块设备主体252三角、6种材质；完整导出含端口/选择标记共1,188三角、7种材质；不把原全场多模块总数混为新单模块性能对比。

新模型实测304个构造细节，合并为9个材质/9个MeshInstance3D，14,484三角。AABB原点(-3.215, 0, -1.375)m，尺寸(6.190, 2.855, 2.780)m。相较逐细节节点，运行时仅9个网格批次。无外部贴图和插件新增。

运行：

    XDG_DATA_HOME=/tmp/station-detail-test/data XDG_CONFIG_HOME=/tmp/station-detail-test/config XDG_CACHE_HOME=/tmp/station-detail-test/cache godot --headless --path . --script res://tests/test_station_detail_sample.gd

`tools/render_station_detail_review.py` 从导出的GLB生成相同镜头/灯光的前后对比，离屏Blender图仅验证几何与材质，不冒充Godot应用截图。Blender4.3不支持Godot4.6的KHR_node_visibility，脚本仅在临时审查副本中去除该扩展，不改原始几何。应用内取景与交互由集成验收另测。

## 增量清单

- `scripts/station_detail_sample.gd`：独立详情几何；与求解、容量、主场景占地、锚点隔离。
- `tests/test_station_detail_sample.gd`：针对性测试与前后GLB导出。
- `tools/render_station_detail_review.py`：可复现离屏比较。
- `docs/STATION_DETAIL_MODEL_1002_ZH.md`：本说明。
- 本地生成的几何统计、前后审查 GLB 与离屏图片不随公开仓库发布；可运行上述测试与审查工具重新生成。

集成后仅设备详情页选择此变电站模型并显示代表性范围说明，主场景变电站模块、容量、端口及尺寸/求解/存档定义不变。1.0.0.2 中 `equipment_visual.gd` 的另行变动用于共用塔站外观，不代表此变电站详情模型改变主场景电气行为。最新集成验证范围、已知历史失败与原生输入边界见 [1.0.0.2 说明](DETAIL_STUDIO_1002_ZH.md)。公开整理没有重跑这些测试。
