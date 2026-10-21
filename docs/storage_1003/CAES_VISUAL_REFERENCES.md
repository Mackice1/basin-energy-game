本文件含阶段开发记录；当前阶段一最终验证以[验收说明](ACCEPTANCE.md)为准。后续计划不表示已实现。

# CAES 外观图源、逐图查看与构件映射

核查日期：2026-10-21。范围：`caes_aboveground` 外观修正与氢储存形态调查。

## 先说明模型边界

- 本设备仍为地上储气、无外部燃料的聚合教学系统，默认 **0.25 MWh / 0.1 MW**。单模块 **24×18×6 m**，0.1 world/m；容量/功率、模块数算法、占地、存档、求解和双向 `ac` 锚点均未改变。
- 下列大型项目照片只支持构型辨认。**照片中的项目不是本游戏参数的实证，更不能把盐穴容量转给地上几只容器。** 未实现地下储气、压力/质量/温度瞬态，也没有凭照片建立压力容器设计或安全距离认证。
- 新模型是依据照片特征重建的原创简化几何，不是某一电站的缩比复刻。照片没有提供的尺寸、数量和小型系统布置仍是明确的教学取值。储热装置无独立免费热源、无额外库存、无新端口，损失继续包含在既有净效率中。
- 所有第三方图片只在临时目录下载、实际查看像素。**没有复制图片到仓库、资产包或发行目录，也未作为贴图使用。** 本文件只保留公开链接。

## 已实际查看的 CAES 图片

### A. 中国能建国际集团：金坛盐穴压气储能实景航拍

- [建设单位项目页，Energy Storage Projects 中的 Jintan](https://www.ceecgroup.com/en/energy-and-electric-power)
- [已查看原图，1000×667](https://cdn.ceecgroup.cn/assets/images/business/electric-power-6-3-6duR5Pz.webp)
- 像素可见：浅色长方体机房、深色屋面与通风器、室外成组设备、具有立柱和横梁的高架管廊、检修道路。只据此采用机房与管廊的可见构造，**不把画面前方卧罐自行判定为储气罐**。
- 页面称其为盐穴项目。对本地上设备，不引入盐穴、不引用该页电站功率作为地上罐组证据。
- 对应标识：`CEEC_JINTAN_PHOTO`。

### B. 工程热物理所供图：中国科学院张家口项目机房内景

- [中国科学院原文，2022-10-01，图片注明工程热物理所供图](https://www.cas.cn/cm/202210/t20221001_4849738.shtml)
- [已查看第二幅原图，600×337](https://www.cas.cn/cm/202210/W020221001319809543362.jpg)
- 像素可见：钢结构机房、屋架/立柱、桥式检修吊车梁、水平电机/机组机座、架空及转弯的保温管路、周边通行空间。
- 对应标识：`IET_ZHANGJIAKOU_HALL`。新机房保留两个可辨认的压缩、膨胀发电机组，前壁采用明确的教学剖开表现，并非声称原厂房敞开。

### C. 同一原文：张家口项目外景

- [已查看第一幅原图，600×337](https://www.cas.cn/cm/202210/W020221001319688669952.jpg)
- 像素可见：灰色机房之外的两只金属反光球形容器，独立支腿、顶部平台和外部检修设施。图片本身不提供容器压力或容量。
- [中南院官方应城技术说明](https://www.csepdi.ceec.net.cn/art/2024/4/9/art_60719_2520291.html)明确将其项目的球形罐定义为高压热水储热系统，并将空气储存定义为地下盐穴。因此，**球形不等于储气**，也不能看见球罐就称其为氢罐。
- 新模型采用两只小型保温球形热缓冲体的外形特征，并用“换热·蓄热（非储气）”标签分区。其直径、数量和布置属于教学绘制，不推导原图设备的热工参数，不声称两个项目设计完全相同。
- 对应标识：`IET_ZHANGJIAKOU_EXTERIOR`。

### D. Pressvess 压力容器制造商：独立地上空气容器实物

- [制造商 Air Receivers 产品与实物照片页](https://www.pressvess.co.uk/products/air-receivers/)
- [已查看实物照片 slide-3，1200×900](https://www.pressvess.co.uk/img/air-receivers/air-receiver-slide-3.jpg)：卧式圆筒、浅碟形封头、两点鞍座、撬架和外伸接管。
- [已查看车间实物照片 slide-5，1024×768](https://www.pressvess.co.uk/img/air-receivers/air-receiver-slide-5.jpg)：长圆筒、浅封头、侧面螺栓人孔、端部法兰、支座/底板和吊耳。
- 仅采用上述构件形态。制造商网页的容积/压力范围不移植到游戏，也不能由这些照片证明本模型的 0.25 MWh。新绘制的 15 m 长、1.8 m 直径接收器是教学几何，不是厂家型号、容积承诺或选型建议。
- 对应标识：`PRESSVESS_RECEIVER_3_5`。

### 明确排除的图片

- [中国能建国际站应城图](https://cdn.ceecgroup.cn/assets/images/business/electric-power-6-1-pMFhpVR.webp)已查看，其像素呈现建筑效果图特征，**不作为已建成实景证据**。
- Pressvess 主横幅已查看，是产品合成/渲染，不用于替代上述车间实物图。
- 部分中国能建国内站和工程热物理所原站直连返回超时/503，未把未取得的图片记为“已看”。改用同建设单位国际站实景及中科院官方供图，不使用无法核实出处的转载图。

## 构件到图片的映射

| 程序节点/构件 | 依据 | 实现与限制 |
|---|---|---|
| `CompressorExpanderMachineHall`，屋面通风器、钢柱、检修吊车梁 | A、B | 明确厂房而非露天两个玩具机；前壁剖开只为识别机组 |
| `ElectricDrivenAirCompressor` / `AirExpanderGenerator`，机座与保温接管 | B | 保留独立压缩、膨胀发电阶段；内部叶轮与级数未拟真 |
| `ThermalRecoveryAndStorageArea`，支腿保温热罐和换热器列 | C 的外形，B 的保温管路；官方储热边界说明 | 与储气区分离；无新增热源或第二份库存 |
| `AbovegroundAirVesselBank` / `AirReceiver` | D | 四列圆筒、浅碟形端盖、鞍座、吊耳、螺栓人孔、法兰和汇管；不再使用长胶囊近似整个容器 |
| `ElevatedProcessPipeGallery` | A、B | 高架支柱、横梁、保温总管、下接支管；不伪称求解管道流动 |
| 机房 / 换热蓄热 / 地上储气三处标签 | 上述分区 | 仅首模块标注以免大量模块重复堆字；既有 AC 端口不变 |

## 氢储能核查：调查结论，不是已实现的分类

当前隔离工程代码（不是对用户正操作窗口的视觉断言）中，`_storage_hydrogen()` 调用 `_storage_pressure_bank(..., 5, 5.5, 0.65, ...)`，是五列长 5.5 m、直径 1.3 m 的卧式胶囊网格，不是 `SphereMesh` 大球罐；但当前目录没有气态/液态/固态子型，外形和名称不能据此宣称分类完成。本次没有修改氢系统外观或物理。

已实际查看下列三类原始产品图片：

1. **气态瓶组**：[Hexagon Purus 原厂新闻页](https://hexagonpurus.com/news/hexagon-purus-receives-inaugural-order-for-uk-market-to-deliver-hydrogen-distribution-systems-from-a-leading-global-industrial-gas-company)，[已查看图片，1200×630](https://d2unncwr0d5wwb.cloudfront.net/purus/_1200x630_crop_center-center_82_none/45-ft-container-11.jpg?mtime=1702447567)。可见成排黑色细长复合气瓶、钢框与交叉支撑。此图为配送系统，不将运输瓶组直接等同于本游戏固定储能站认证设计。
2. **液氢**：[Linde 液氢罐官方页](https://www.linde-engineering.com/products-and-services/plant-components/liquefied-hydrogen-tank-solutions)，[已查看 LH2 Container 图片，736×414](https://assets.linde.com/-/media/celum-connect/2024/11/15/13/06/lh2_container2_183668.jpg?impolicy=focal-point&cw=736&ch=414&fx=1024&fy=599&r=fe74914231)。可见 ISO 框中的单只大型卧式绝热容器，与裸露高压瓶列明显不同。液化耗电、低温绝热/蒸发损失应独立定义，不能仅把气瓶换白色。
3. **固态金属氢化物**：[控制系统供应商 Beckhoff 对 GKN 的案例](https://www.beckhoff.com/en-en/company/news/consistent-use-of-renewable-energies-with-flexible-metal-hydride-storage-systems.html)，[已查看 HY2MEGA 开箱实物图，1160×772](https://www.beckhoff.com/media/pictures/content-images/news/gkn-hydrogen-wasserstoffspeicher-container-hy2mega.jpg)。可见集装箱中的密集小筒阵列、管线及热管理设备。这里的“固态”是材料结合储氢，不是把纯氢冻成固体。吸放氢需要区分吸热/放热与辅助耗能，不能靠同一个损耗数字和大球罐外观冒充子型。

本节只为后续分类提供可追溯形态和边界，未加入化工工厂、外售氢、水/氧库存或新的氢/热端口。

## 验证

- 新增 `tests/test_caes_reference_visual_1003.gd`：645 项检查通过，含默认、4 模块与合法上限 40 模块构型；验证分区、真实端口、原锚点、包络、标注、无额外库存/物理和材质批处理。
- 原存储详情测试 255、全设备相机边界 30242、详情地台 395、标注相机 318、设备视觉 6156、米制尺寸 251 项均通过。
- 另以 Godot headless 导出当前程序网格，Blender 后台离屏渲染两个观察方向，并实际查看生成图片像素，确认厂房、热罐、储气列、管廊分离。首轮可选降噪器不可用，关闭后两图均成功。原图/模型不含在项目中；自己生成的预览和测试日志保留于 `evidence/storage_visual_1003/caes_reference_revision/`。
- 未操作或重启用户窗口；离屏预览隐藏了屏幕空间文字，不冒称运行应用的 GUI 验收。三个文字标签另由 headless 测试验证。
