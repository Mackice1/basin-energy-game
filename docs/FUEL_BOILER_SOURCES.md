# 首台燃料设备：天然气热水锅炉（来源、尺度与教学假设）

查阅日期：2026-10-16。设备键 `fuel_boiler`。本阶段只接入天然气热水锅炉，不含蒸汽、汽轮机、燃气发电机、燃料切换或气网压力模型。参数是可审计的教学假设，不是某厂家某型号的数字孪生、选型书或施工图。

## 1. 原始来源和如何使用

1. **Bosch 官方 Uni 3000 F 产品册，第 3 页技术表**：1850 kW 型列出的长度 3480 mm、锅炉宽度 1510 mm、总高度 1730 mm、烟气接口 400 mm，用作锅炉本体外形的量级与比例参考。没有把它当作包含燃烧器、燃气阀组、独立烟囱和检修空间的完整尺寸。
   - https://www.bosch-industrial.com/gb/media/country_pool/service/catalogues/br_uni_3000f.pdf
2. **Bosch 官方安装维护手册 6 720 812 900 (2014/10)，第 11 页表 11**：1850 kW 型额定热输出 1850 kW、额定热输入 2024 kW。第 4 页说明用于热水采暖。该手册与上面产品册版本和尺寸标注口径不同；本项目不把不同表格拼成“厂家精确模型”。运行额定另取教学值。
   - https://www.bosch-industrial.com/gb/media/country_pool/service/manuals/hot_water_boilers/6720812900_bosch_uni_3000f_installation_manual_uk.pdf
3. **Bosch 官方商业供热产品总册，第 22–23 页**：该系列为低压热水锅炉，给出最高约 93% NCV 的说明，同时注明该估计对应部分负荷和平均水温 60°C，效率取决于燃料、设计温度和负荷。它只是效率量级与口径背景，不是本游戏固定 90/60°C 工作点的实测保证。
   - https://www.bosch-industrial.com/ocsmedia/optimized/full/o365540v272_BOSCH_Range_Brochure_UK.PDF
4. **Viessmann 官方 Vitoplex 200 700–1950 kW 数据表，第 3 页**：另一独立量级核对，1950 kW 热输出对应 2120 kW 热输入，400 mm 烟道接口。不同厂家数据没有混用于同一机组标定。
   - https://www.viessmann.com.au/content/dam/public-brands/au/pdf/Datasheet_Vitoplex200_700%20to%201950.pdf/_jcr_content/renditions/original.media_file.download_attachment.file/Datasheet_Vitoplex200_700%20to%201950.pdf
5. **IEA 官方 Glossary** 的 “Billion cubic metres (bcm)”“Natural gas”“Lower heating value”条目：给出 36 PJ/bcm 的 LHV 能量换算量级，并区分净/低位热值与总/高位热值；气体体积必须附温压基准。IEA 气体统计还使用 15°C 基准，不能把一个表中的立方米直接当作任意账单的标准立方米。
   - https://www.iea.org/glossary
6. **NREL 技术报告 46267，表 41**：该研究案例对天然气采用 36.6 MJ/Nm³ 低位热值，折合约 10.17 kWh/Nm³。这是研究假设示例，证明 10 kWh/Nm³ 的教学量级合理，不代表各地天然气组成、温压基准或合同热值完全一样。
   - https://www.nrel.gov/docs/fy09osti/46267.pdf
7. **美国能源部 BTO, The Heat Is On (2019-10-10)**：燃料供热设备通常仍需要电力驱动控制与辅助功能；停电可能令设备停供热。该文只支持“辅助电力是独立依赖”的机制，不提供本设备 1% 辅机率的厂测依据。
   - https://www.energy.gov/cmei/buildings/articles/heat-performance-improvements-natural-gas-devices

## 2. 当前参数合同

| 项目 | 默认值 | 口径及状态 |
|---|---:|---|
| 燃料 | 天然气 | 唯一支持的燃料；不是通用燃料桶 |
| `rated_fuel_mw` | 2.0 MW_LHV | 额定燃料低位热值输入；不是热输出或发电容量 |
| `thermal_efficiency` | 0.90 | `Q = η F`，恒定 LHV 热效率教学近似 |
| `auxiliary_electric_ratio` | 0.01 | `Paux = α F`，以燃料能量输入为分母；不是 `α Q` |
| 热接口 | `heat_out`，90/60°C 一次热水 | 一条逻辑热边代表成对供水/回水服务，不是蒸汽管道 |
| 电接口 | `ac_in`，AC_BUS | 辅助电输入，不能反向发电 |
| 默认天然气低位热值 | 10 kWh_LHV/Nm³ | 明示教学设定；体积显示按本项目规定的标准状态 0°C、101.325 kPa；没有温压或压缩因子求解 |
| 默认燃料价格 | 300 CNY/MWh_LHV | 明示教学价格，不是市场报价、采购预算或地区现行气价 |

在额定输入且辅机电源足够时，一台默认设备的热输出为 1.8 MWth、辅机用电为 0.020 MWe、燃料侧未转为有用热的功率为 0.2 MW。对应天然气体积为 `2 × 1000 / 10 = 200 Nm³/h`，燃料费用为 `2 × 300 = 600 CNY/h`。时段积分乘小时，分别得到 MWh_LHV、MWhth、MWh_e、Nm³ 和 CNY。上述算式是默认值的可复算示例，不保证实时每时每刻都满负荷。

辅助电量另入电网络平衡，不抵消或虚增燃料供应；该固定效率没有再把辅助电力转成额外可售热量。没有辅助电力、没有可达热负荷、没有燃料供应或受到网络/设备容量约束时，允许的热输出下降或归零。燃料供应上限、实际消耗和费用应以运行/优化结果为准，不能因展示多个模块而重复增加。

## 3. 尺度和场地合同

- 单个完整原创教学模块：长 **5.0 m**、宽 **3.0 m**、含烟囱高 **4.5 m**。锅炉参考壳体为 3.480×1.510×1.730 m；燃烧器、阀组、底撬、管路和烟囱位置为原创布置。
- 本体 GLB 轴序为 Godot `(x, y, z)`，包围盒 `(-0.25, 0, -0.15)` 至 `(0.25, 0.45, 0.15)`。全部只经过一次 **0.1 world/m** 转换。Blender 源文件按米建模，没有任意压缩到站内。
- 每 2 MW_LHV 额定燃料输入对应一个视觉模块，数量 `ceil(rated_fuel_mw / 2.0)`，最少一台；末台可能不满额。改变效率不会改变几何，扩容增加等尺寸模块，不放大/缩小单台。
- 模块之间 2 m，外周 2 m 检修边带为教学预留；默认安装矩形 **9×7 m = 63 m²**，实体底撬投影 **15 m²**。外接圆半径 `sqrt(9²+7²)/2 = 5.700877 m`，即 **0.5700877 world**。外接圆不是建筑面积。
- 原有 48×48 m 站内净区和 80×60 m 外院区不变。空间不足时拒绝建设或增容，不缩小设备；展示复本共享一个设备编号、运行额定和一组逻辑端口。
- **这些边带、间距和 4.5 m 烟囱不是消防、燃气安全、烟囱排放扩散、噪声或工程净距认证。** 图中没有燃烧火焰、动态烟羽、排放量或安全距离推断；未模拟压力、点火/熄火序列、最小稳定负荷、启停成本和炉体热惯性。

## 4. 资产和复现

- 可编辑源：`art_source/blender/fuel_boiler.blend`
- 独立生成脚本：`art_source/blender/build_fuel_boiler.py`，复用已有热设备导出辅助函数，但不重建或改写旧 GLB
- 导出资产：`assets/models/fuel_boiler.glb`；独立清单 `assets/models/fuel_boiler_manifest.json`
- 运行 `blender -b -t 4 --python art_source/blender/build_fuel_boiler.py -- --render`，随后使用项目正常 Godot 资源导入流程
- 可辨识结构：炉门、强制通风燃烧器、燃气阀组、竖直烟道、铜色供水与蓝色回水；沿用既有珠白/深蓝/金属色低多边形工业风格，不是电锅炉改色
- 一套静态网格、7 个不透明材质面、4,168 三角形、182 KiB GLB（无外部纹理）。一个默认模块加选择环，不含隐藏运行节点或额外容量
- 图形缺失时提供同米制体积的程序化备用模型，包含独立燃烧器、燃气管路和烟道；固定 .1 缩放仅是米到世界单位的换算
- `tests/test_fuel_visual.gd` 检查真实导入 GLB、米制包围盒、端口合同、等尺寸模块、容量无副作用、材质恢复、备用外形及旧尺寸保留；不能代替实际工程认证

工作室预览位于 `evidence/fuel_boiler/fuel_boiler_studio.png`。运行态连接、燃料限供和 GLPK 验收由相应集成测试与验收记录另行报告。
