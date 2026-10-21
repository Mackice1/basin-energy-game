# 四种储能：实图核查、构件整改与液流版本兼容

公开整理说明：本文保留研究或开发阶段记录；带时间的计数、计划与待验收状态仅适用于对应时点，不代表逐项人工验收已完成。最终范围见[最终原生验收](FINAL_NATIVE_ACCEPTANCE_1004.md)。原始运行日志、截图、玩家存档、备份与研究图像不随源码分发；下文非公开记录仅为来源说明。公开整理没有重新运行游戏或测试。

> 后续版本说明（2026-10-21）：本文保留先前研究与历史教学几何记录。新 `reference_size_v1` 钠电已改为 3 个有额定/尺寸依据的完整箱体；液流默认为 12 MWh 内部库存、固定两大模块共十二组。以 `SODIUM_FLOW_CAPACITY_REFERENCE.md` 的补证、计量边界与测试为准；下文旧 5 MWh/10 MWh 复制阈值不作为新厂家额定。固热新尺寸见 `REFERENCE_SITE_GEOMETRY_VERIFICATION.md`。

核查与实施2026-10-21。照片只保存在临时研究目录，不复制为游戏资产。下列原图/原页均已实际打开像素；结构核对图是Godot headless导出几何后Blender CPU渲染，**不是Godot实际灯光、GUI或FPS验收**。

## 钠离子

- 运营方[大唐2024-07-01报道](https://www.china-cdt.com/dtwz/xwzx/mtgz/2024/12/I1313444661209071616.html)，[已看640×480航拍](https://www.china-cdt.com/dtwz/ueditor/jsp/upload/image/20240702/1719902253319040175.png)。正文日期与URL月份不同，以正文为准。6月30日投运一期50MW/100MWh，规划总量100MW/200MWh不能混称已建。
- 制造商[海钠2024-11-29](https://www.hinabattery.com/index.php?id=227)，[已看900×491潜江实拍](https://www.hinabattery.com/data/upload/image/20241129/1732851461737897.jpg)：长条白色电池仓、独立变流设备、设备基脚、连续检修面和冷却部件。
- 大唐[另一官方转载](https://www.china-cdt.com/dtwz/xwzx/mtgz/2024/12/I1313444661519450112.html)记42电池仓/21升压变流一体机。这是站级信息，不能证明本模型每箱5MWh或6.5m外形。

整改：原金色整箱改白灰壳+钠色识别带，新增基脚、角框、独立通风冷却件/电缆入口，PCS保持独立。6.5×3.2×3m及每模块5MWh/2.5MW仍为原教学尺度，未取得该尺寸钠电商品的容量证明；不以锂电5MWh箱体资料替代证明。当前默认可能包含多模块。

## 液流

- 制造商[北海道实际项目](https://sumitomoelectric.com/products/flow-batteries/case-studies/hokkaido-wind-integration)，[已看656×410双层箱体阵列](https://sumitomoelectric.com/sites/default/files/styles/crop_sei_cp_656x410/public/2024-11/products/overview_card/DSC_0332_0.JPG?h=60d59222&itok=CFGOwwSS)，[已看早期站罐室](https://sumitomoelectric.com/sites/default/files/styles/crop_sei_cp_656x410/public/2024-10/products/overview_card/10.1%E9%9A%8E%E3%82%BF%E3%83%B3%E3%82%AFPCS%E5%AE%A4_0.jpg?h=b82efc23&itok=tf36oEvT)。2022年17MW/51MWh与2015年15MW/60MWh是不同项目，不混合。
- [Sumitomo目录2025.10](https://sumitomoelectric.com/sites/default/files/2025-09/download_documents/RFB_Catalog_EN.pdf)，已看PDF第1、3页（第1页含封面/尺寸图；第3页印刷页03/04）。40ft参考模块12.192×4.902×5.425m；下部两个电解液箱，上部电堆箱/泵/热交换部件。目录完整布置例8MWh AC为39×12m、12MWh AC为38×15m。

新flow_process_v2：每10MWh内部教学库存/2MW采用38×15×5.5m完整工艺模块，加外围教学余量后42×19m；六组参考尺寸的双层设备，独立PCS/控制、双独立电解液回路/检修走道。不是把商品12MWh AC充作内部10MWh的物理参数。库存和功率不改。默认20MWh对应两模块，总占地42×36m；不能把单模块图当默认总场。

旧flow_icon_v1：14×10m工艺占位、18×14m单模块安装区及原双圆罐外形保留，明确旧档图标化，不称真实储液量或10MWh实尺度。设备级geometry_profile由world/save/inspector传递，旧缺标记不自动升级，不迁移已存位置，不偷偷更换碰撞半径。Spatial第四参数默认flow_process_v2；Visual接收visual_geometry_profile。

## 液态空气

- [Highview本人CEC 2017-07-11讲义](https://indico.cern.ch/event/578092/contributions/2642055/attachments/1491699/2319008/Cryogenic_Engineering_Conference_-_Madison_WI_-_July_11_2017.pdf)，已看第23、24页1600×1200原页。第23页是350kW/2.5MWh试验站，第24页是5MW/15MWh Pilsworth示范站；2017照片不证明2018正式开放时点。
- 实拍可辨高立式绝热罐、工艺塔体、独立压缩/回发区、检修平台/梯、粗绝热管和支撑。第23页罐字样Liquid Nitrogen，仅借鉴低温部件外观，不把游戏液态空气库存定义为纯氮。讲义18/19页区分独立内部热/冷回收与外部废热配置。
- 施工方[Alpha的Pilsworth说明](https://alphaconstruction.co.uk/sector/energy/storage/pilsworth-energy-storage-greater-manchester/)核对基础、容器、压缩/透平建设范围；其三张旧图片URL现404，**未将其当已看图片**。Highview2018新闻PDF本轮超时，不声称已读。

整改：补真实梯级、平台支撑/栏杆、内部热冷回收小容器与独立往返管、管廊支架、机组接管，保持20×16×11m原教学模块。没有外部热网口，不添加免费废热或照抄Highview效率；现尺寸不是Pilsworth实测缩比，容量不从罐体反算。

## 固体蓄热

- 制造商[EnergyNest2018制造说明](https://energy-nest.com/thermal-battery-ready-for-construction/)，[已看2304×1536钢框管式模块](https://energy-nest.com/wp-content/uploads/2018/09/ENE-Manufacturing-and-shipping-3.jpeg)，[已看1024×768端部回弯管近照](https://energy-nest.com/wp-content/uploads/2018/10/ENE-Manufacturing-and-shipping-7-1024x768.jpeg)。可见钢框、斜撑、重复固体元件和内嵌换热通道；不把制造照片当投运。
- [2020-10-19交付](https://energy-nest.com/first-commercial-thermal-battery/)，[已看800×600模块交付图](https://energy-nest.com/wp-content/uploads/2020/10/modules.jpg)，保温包覆、支墩、吊装角件明确。

整改：补支墩/钢框/斜撑、前端重复元件检修盖、双进回水汇管及封闭回支管。原8×6×5m与4MWhth/2MWth教学模块不变。照片产品使用高温导热油，**仅为构件形式参考，不是游戏90/60°C水回路性能证据**；游戏只有heat_in/heat_out、无电输出/蒸汽口，未增加热机。外观不证明材料质量、温度动态或可用热容。

## 验收

独立test_storage_reference_geometry_phase2：68项通过，单模块三角形：钠564，旧液流1908，新液流10152，LAES12624，固体5484，均6–7材质。所有组件位于声明包络内；真实端口/参数不变；新旧液流半径分别一致，不默改原档。原storage_visual_details_1003 255项通过。非公开验收记录（未随源码分发）四张结构图已逐张看像素，清楚可辨工艺部件；仍需最终实际GUI灯光核对。
