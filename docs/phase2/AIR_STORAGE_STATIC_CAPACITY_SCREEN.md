# 地上压缩空气 / 液态空气：有限净容积与返电筛查

公开整理说明：本文保留研究或开发阶段记录；带时间的计数、计划与待验收状态仅适用于对应时点，不代表逐项人工验收已完成。最终范围见[最终原生验收](FINAL_NATIVE_ACCEPTANCE_1004.md)。原始运行日志、截图、玩家存档、备份与研究图像不随源码分发；下文非公开记录仅为来源说明。公开整理没有重新运行游戏或测试。

2026-10-21。范围仅为 `reference_size_v1` 的固定状态必要条件；没有重写运行物理、增加流体库存、修改外观或迁移用户存档。CAES 默认仍0.25 MWh内部 /0.1 MW；LAES仍8 MWh内部 /充2 MW、放1 MW。

## 共同边界与代码合同

运行仍使用原有限SOC及充放效率。新增共享判断是：`capacity_mwh × discharge_efficiency ≤ net_electric_screen_mwh`，比较的是满内部SOC可输出的AC能量，不将内部MWh、原始热量、液体火用或厂家AC名牌混为一谈。效率可以调整，但不能让其与容量的组合越过同一净容积的筛查预算。小容量高效率可通过；大容量高效率可能拒绝。

`scripts/site_layout_support.gd` 与 `tools/site_layout_support.py` 只读同一JSON。`required_geometry` 返回净腔、有效容积、请求返电量、固定筛查上限和 `energy_screen_pass`；`assess_device` 对越界返回 `energy_screen_exceeded`，不截断任何参数或库存。缺少/非有限/非数值效率失败关闭。无site标识的历史世界继续原教学运行；迁移评估指出问题，原值保持不变。任何标识触发全世界严格模式，混合标识不能降级绕过。

`screen_is_performance_guarantee=false`、`pressure_is_simulated=false`、`soc_is_pressure_or_liquid_level=false`、`pressure_vessel_certified=false`。通过筛查不意味着已完成压缩机/膨胀机选型、实际压力设计、换热器与蓄热质量、保温或长期循环标定。0.1/1/2MW仍是此实现有限教学功率包络。

## CAES：104.552m³净直筒、50bar固定参考

四只现外壳各总长15m、外半径0.9m。内部只计半径0.8m、直筒13m，完全不计封头体积，共 `4π×0.8²×13 =104.55220351146832m³`。径向/端部差额为本模型净腔分配，不是壁厚强度或安全认证。

固定参考：50bar绝对压力、298.15K；环境参考1bar；理想干空气γ=1.4，R=287.05J/(kg·K)。这不是满SOC实际压力，不生成压力/质量状态，不主张真实设备可一路放至1bar或无残余气体。残余气体不被额外当作可用库存，也没有添加隐藏底料。

只作为参考上限，理想刚性绝热罐经可逆膨胀机无再热排气的总功可独立积分。令 `r=p0/p`，罐内归一化质量 `x=m/m_initial`，则 `T/T_initial=x^(γ−1)`，膨胀机出口温度为 `T_initial×r^((γ−1)/γ)`；积分 `cp×(T−T_out)dm` 从 `x=r^(1/γ)` 到1，得到：

`W_no_reheat = pV/(γ−1) × [1+(γ−1)r−γr^((γ−1)/γ)]`。

结果为 **0.19972593183091922MWh**。另一项等温闭系统可用功 `V[p ln(p/p0)−p+p0]` 为0.42576314717198677MWh，只单独报告，绝不作为无再热电产出。默认0.25×0.70=**0.175MWh AC**低于较严的前者；η放=1时0.25MWh超过它而拒绝。默认返电所需等效净直筒体积约91.6087m³，小于实际分配104.5522m³。

该无再热式是理想气体、恒比热、理想膨胀边界的**必要上限，不是实机可达量**。实际额定应低于它；恒γ、非理想气体、压降、机组效率、排气温度和传热均未标定。既有0.75充电/0.70放电及自损继续单独计入运行，不从本计算额外发电或加热。全参考压力罐的理论空气质量只是静态元数据，不能由其反推现SOC，不能断言一次0.333MWh充电会把全部罐充到50bar。

来源：
- [NASA理想等熵关系](https://www.grc.nasa.gov/www/k-12/airplane/isentrop.html)与[比热关系](https://www.grc.nasa.gov/www/k-12/airplane/specheat.html)支持推导；此处积分及净腔为本实现算术。
- [地上CAES实验与数值研究，2024](https://doi.org/10.1016/j.enconman.2024.119073)：真实试验采用190bar初压、35bar调压，在50bar停止。它只支持地上高压设备的量级与边界重要性，不是本50bar至环境参考推导的实证。
- [地上液活塞系统实验/模型，2021](https://www.sciencedirect.com/science/article/pii/S0196890421007123)含8→40bar实验；不把其装置或效率挪成本设备。
- [Barbour等2021原始分析](https://pmc.ncbi.nlm.nih.gov/articles/PMC8111675/)指出储热、变压过程与部件集成的重要性。这里不借用地下洞穴容量，亦不计外购燃料或外部余热。

## LAES：101.687m³有效液量、明确的300kJ/kg教学筛查

两外壳半径2m、高9.6m。内部只计半径1.7m、高7m直筒，不计封头，共127.108838764243m³；80%有效充装得到 **101.68707101139441m³液体**。预留0.30m径向及2.60m总轴向差额，不作为保温/封头认证。

Guizzi等2015的独立LAES循环模型不依赖外部余热，内部回收充电压缩热及放电冷量。Table3状态1R为78.74K、0.100MPa绝对、872.08kg/m³；§3.3估算有效净放电比功390kJ/kg。这里采用 **300kJ/kg净AC**作为较低的**教学筛查假设**，不是文献实测值、液体火用或被证明的保守下限。热/冷回收设备仍需后续独立容量核对，不能由两只小型回收容器的外观证明完整循环能力。

由此有效最大参考液量为 **88679.26088761684kg**，净返电筛查预算 **7.389938407301404MWh**。默认8×0.65=**5.2MWh AC**所需等效液量62400kg /71.55306852582332m³，小于有效液量。η放=1且内部8MWh会超过预算而拒绝；内部4MWh、η放=1通过。这里的kg仅静态尺寸核对，不进入现有物料账或作为可免费补充的液空气。

来源：[论文DOI](https://doi.org/10.1016/j.energy.2015.10.030)、[作者Michele Manno上传全文](https://www.researchgate.net/publication/284251709_Thermodynamic_analysis_of_a_liquid_air_energy_storage_system)、[大学元数据记录](https://art.torvergata.it/handle/2108/127241)。大学页此次直取403，数值核对来自作者全文，不声称取得大学附件。另[Highview Pilsworth官方说明](https://highviewpower.com/news-announcements/world-first-liquid-air-energy-storage-plant/)含外部填埋气发动机余热，不把该项目性能当作本无外热循环校准。

## 同批共享模块元数据与旧液流标识

- 钠离子：Quantum N2.5[厂家PDF](https://zttek.tech/wp-content/uploads/2018/10/Datasheet_Quantum-N2.5.pdf)名义单箱2.5MWh/1.25MW、7.120×2.896×2.800m。固定三箱提供7.5MWh/3.75MW参考名牌，教学分配6MWh/2MW不改。含辅机的9×3.5×4m单元不是厂家壳体尺寸；循环效率不从照片推出。
- 液流：Sumitomo[2025.10目录](https://sumitomoelectric.com/sites/default/files/2025-09/download_documents/RFB_Catalog_EN.pdf)的2MWhAC/334kWAC子模块、六子模块12MWhAC/2MW站参考；保留两站十二子模块。厂家AC额定与现内部12MWh不同口径。
- 显式 `site_geometry_profile=reference_size_v1` 与旧 `geometry_profile=flow_icon_v1`不相容，共享评估拒绝；省略geometry字段的直接新调用保持新默认；无site标识旧档保留旧图标及原坐标，不静默变更。

## 验证与未闭环项

定向Godot：空气容量61项、flow标识18项、共享全目录1365项通过。Python数字积分独立复算CAES闭式公式，验证边界相邻浮点、小容量高效率及旧模式不改值；Godot/Python逐字段一致。实际GLPK充放回放同时覆盖两设备默认及高效率小容量。

初次GLPK专项暴露既有末步库存负1.11022302462516e−16MWh；Godot严格拒绝，原始request/result已保留。该求解数值问题交独立求解器修复修复，不以绝对值阈值夹库存或放宽审计掩盖。最终结果以 非公开验收记录（未随源码分发） 的验收记录为准；此段不冒称GUI验收或全库通过。

最终定向复核：求解器修复以事务式可表示流率修复末步负库存后，本专项独立重跑共享/solver/空气/flow共50个Python测试全部通过（0跳过）；Godot1365+61+18=1444项全部通过。真实GLPK四种场景均通过Godot原输入独立审计，篡改库存仍拒绝，带标识与无标识物理报告一致。原失败fixture保存在非公开验收记录中；修复后的请求和结果单独保存，未覆盖诊断证据。哈希及结果保存在非公开验收记录（未随源码分发）。
