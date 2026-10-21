# 地图收边、荒漠地物与资源接口：参考和实施边界

公开整理说明：本文保留研究或开发阶段记录；带时间的计数、计划与待验收状态仅适用于对应时点，不代表逐项人工验收已完成。最终范围见[最终原生验收](FINAL_NATIVE_ACCEPTANCE_1004.md)。原始运行日志、截图、玩家存档、备份与研究图像不随源码分发；下文非公开记录仅为来源说明。公开整理没有重新运行游戏或测试。

核查/实施2026-10-21，仅新副本。`map.gd`+`environment_visual.gd`为独立纯显示层，未扩大可建设地图、未改气/煤/水额度、真实设备布局或任何物理模型。没有操作GUI。

## 先看过的真实图片

所有第三方图片仅链接，临时下载核验后不加入项目资产。

| 类别 | 一手来源与已查看图片 | 像素观察→实现 | 不作出的推论 |
|---|---|---|---|
| 沙漠灌木 | [国家林草局“梭梭”](https://www.forestry.gov.cn/c/www/dzw/544490.jhtml)，[实景图](https://www.forestry.gov.cn/u/cms/www/202401/30093453g1rq.jpg) | 实际查看：不规则细分枝/疏松树冠、沙丘间团簇与空地；改为多方向细枝、尖叶/干草，不用矩形贴片或三团实心壳。 | 当前只是通用旱生灌草轮廓，不保证植物物种鉴定，也不把照片植被密度整片复制到合成场址。 |
| 荒漠地形/岩石 | [NPS干旱地貌](https://home.nps.gov/subjects/geology/arid-landforms.htm)，[Wild Horse Mesa实景图](https://www.nps.gov/subjects/geology/images/arid_Mojave-NP_Wild-Horse-Mesa-2013-09-04-NPS-Photo-by-Dale-Pate.jpg) | 实际查看：裸露山脊多层低频轮廓、冲积坡、地面浅色不规则石块；低面数外环/远山、三种棱面岩石、埋入地表的根部。 | 不复制美国特有Joshua tree到中国沙戈场景；只参考地貌/石块形态，不称实测地形。 |
| 煤炭物流 | [RBCT运营流程](https://rbct.co.za/operations/)，[煤运铁路实拍](https://rbct.co.za/wp-content/uploads/2022/06/Infrastructure_1-768x478.jpg)、[堆取料机/堆煤实拍](https://rbct.co.za/wp-content/uploads/2022/06/Infrastructure_2-768x509.jpg) | 已查看：铁路车辆、深色长低堆煤、钢支架/皮带输送，保留同类关键轮廓。地图原公铁位置旁画小型静态堆装区和既有轨道上的车厢。 | 不把港口整体缩进本地图、不新增海港/船舶、不从煤堆几何生成库存或产能。 |
| 外引水接口 | [Grundfos Rottal实际供水案例](https://www.grundfos.com/my/about-us/cases/how-demand-driven-distribution-resulted-in-30-percent-energy-savings)，[官方PDF第1页](https://www.grundfos.com/content/dam/global/activity-assets/isolutions-wu/documents-and-cases/cases/wu-water-networks/wu-case-water-distribution-rottal-2019/wu-case-water-distribution-rottal-2019-pcs-gb-en.pdf) | 已渲染并查看页首实际机房照片：并排立式多级泵、顶置电机、横向进出集管、独立控制柜；做同类小泵阀组合及开敞检修棚。 | 图片没有本地图设备尺寸，棚为原创展示。不是地下取水井或水厂，不新增净化过程、储水或无成本水源。 |
| 天然气接口 | [Hi-Tech Gas Skids制造方](https://hitechskids.com/)，[燃气阀表管段产品照片](https://hitechskids.com/assets/images/product/GAS-PRESSURE-TRAIN-SKID.JPG)；[Emerson成套调压计量说明](https://www.emerson.com/en/final-control/products/tartarini-stations-skids) | 已看前者照片的真实阀体、法兰、圆压力表、直管/控制元件；双列阀表管段、钢撬及小控制箱是原创边界设施示意。Emerson文字支持调压/过滤/计量模块身份。 | 产品照片不是完整运营站现场图，尚未核实本地图90,000m³/h匹配型号/总图；不称其为厂家成套复制或真实额定设备。 |

排除项：Hi-Tech的MRS/DRS白底图实际是CAD效果图，已看后不算实拍；其“our-experience”图是大型工厂形象图，不能证明小型调压站结构。Emerson图片与Cadent正文直接下载403，未绕过、未宣称看过。NPS creosote照片虽取得，但未用作中国具体物种证据。照片只能支持构型，不能推出承压、功率、消防和流量选型。

## 实施

### 非建设背景

- `NonBuildableDesertSurround`从原Terrain3D的±128边缘开始，128/150/205/290/430 world五道轮廓形成4条外环，128方位段，总1024三角，1网格1材质。
- 内边沿使用原`height_at`，外圈是低频沙戈远山及逐层去饱和色，不改原高度图/控制图/区域导入，不增加Terrain3D区块或占地格。
- 没有碰撞/拾取/可建设注册，地图相机目标和建造范围仍保持原[-100,100]×[-70,70]；不是新增可用土地。

### 地物

- 3种低面数不规则岩石共享实例批次，随机方位、非均匀尺寸、温灰/土色；下缘埋入原地面并顺坡旋转。
- 草丛为渐尖三角叶片，灌木为窄枝与分支尖叶，不使用矩形纹理板、透明排序、风动shader或高模。
- 保持原数量上限1580石块+232灌草，保留同一随机种子、主要原散布区域；对原道路/轨道/气水走廊及资源标记范围剔除冲突地物。这不修改设备、道路或建设位置。
- 远景span≥180关闭细小草木，近景显示；石块3批次。无动态阴影或新贴图。

### 三个资源接口

`ExternalResourceIllustrations`父级metadata明确`resource_production_added=0`、`logical_ports_added=0`、`not_constructed_devices=true`。

锚点严格保持gas(-80,-5)、coal(-85,13)、water(-76,42)，标记与标签不移动。设施外形放在原线旁，小底板/设备逐顶点依原地形贴合；煤车放在既有轨道，不重画公路铁路。每设施1个顶点色网格，均无碰撞和生产。现标签“场地示意”保留，**这些不是新建可调度工厂，也不是四种物质链新设备**。

本层是区域地图上的原型化资源入口示意，不声称工程比例/OEM CAD或额度决定外形尺寸；`not_to_engineering_scale`明确标注。以后若升级为真实工程站，应新建明确类型、尺寸证据和占地契约，不能拿该装饰外壳直接投入生产。

## 验证与交接

- 新测试`tests/test_environment_visual_phase2.gd`：8325检查通过，1743个实例，近景总53677三角；隔离headless构建约16ms，仅CPU创建时长，不是GPU帧率。
- 验证外环不覆盖原地形、无CollisionObject3D、地物避开道路/接口、每实例有顶点接触地面、LOD切换、配置/额度字节不变、固定种子可重现、全部几何预算受限。
- `height_at/stream_x/slope_at/exclusion/biome/land_color/make_terrain/pick_ground`八个权威函数与改前逐字一致。没有编辑地图JSON、地形数据或原道路脚本。
- API保持不变；map只增加三个显示节点变量与构建/LOD调用。新显示脚本的节点均可移除，不影响原模拟。
- 最终应用截图和GPU帧率需要统一GUI验收。本专项禁止操作GUI，因此离屏图只标为几何审查，不冒称窗口截图或交互完成。


## Verification and inspection, 2026-10-21

The dedicated headless test passed 8,325 checks, 0 failures. The scene has 1,743 scatter instances and 53,677 near-view triangles; CPU construction in this run took 16,182 microseconds. These are construction/geometry measurements, not GUI FPS or a GPU performance claim. Eight terrain/buildability functions remain byte-identical: height_at, stream_x, slope_at, exclusion, biome, land_color, make_terrain, pick_ground.

Original geometry was exported headlessly to glTF and rendered by Blender in background mode, then both PNGs were visually inspected. The two previews and test log are nonpublic acceptance records and are not distributed with the source. These are **offline geometry previews**, not application screenshots: simplified ground, no game roads, atmospheric shader, labels, or actual camera environment. The far ring is visibly faceted in this diagnostic view; the close view confirms separate pipe/gauge components rather than only a marker. This historical geometry check did not perform actual GUI comparison or frame timing; the final acceptance summary defines the later native scope.

Original `tests/test_world_infrastructure_1002.gd` was rerun after concurrent material UI integration completed; final result is in 非公开验收记录（未随源码分发）. No integration file was changed to make the scenery test pass.
