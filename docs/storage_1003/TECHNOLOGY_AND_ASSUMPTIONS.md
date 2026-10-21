本文件含阶段开发记录；当前阶段一最终验证以[验收说明](ACCEPTANCE.md)为准。后续计划不表示已实现。

# 多元储能 1.0.0.3：技术依据与模型边界

核查日期：2026-10-21。这里的额定容量、功率、效率、安装间距及外观模块数量都是游戏教学假设，不是制造商性能担保、压力容器设计或工程选型。新装置初始库存为零。已有电池保留原 ID 和历史初始库存规则，旧存档不会重新赠送初始能量。

## 技术依据

- DOE 的压缩空气储能技术评估明确区分地下储库与地上罐体；地上罐体需要地面占地，不能继承盐穴的规模和成本优势。本项目只建设地上压力容器组、压缩机和膨胀发电配套装置，不建地下空间。来源：[DOE CAES Technology Strategy Assessment, 2023](https://www.energy.gov/sites/default/files/2023-09/8_Technology%20Strategy%20Assessment%20-%208%20Compressed%20Air%20Energy%20Storage%20_508.pdf)。
- PNNL 的 GridPIQ 说明往返效率是接网点输出能量与输入能量之比，并列举不同技术的历史参考值。其通用 CAES 指标并不等于本项目地上罐体的标定。本项目只把该资料用于效率量纲和技术差异检查，不把历史样本当成性能承诺。来源：[PNNL Energy Storage System Efficiency](https://gridpiq.pnnl.gov/v2-beta/doc/technologies/es/es-efficiency/)。
- 钠电本轮明确为常温钠离子，不是高温钠硫。DOE 对两条路线作了区分，因此不能把钠硫的运行温度或效率直接填给钠离子。来源：[DOE Sodium Batteries Technology Strategy Assessment, 2023](https://www.energy.gov/sites/default/files/2023-09/6_Technology%20Strategy%20Assessment%20-%20%236%20Sodium%20Batteries_508.pdf)。
- 液态空气储能包含用电液化、低温储存、气化膨胀发电阶段。本项目的冷/热回收折算在净充放效率内，不引入未核算的外部余热，也不宣称与某一真实电站完全相同。来源：[Highview Power, Infrastructure & Technology](https://highviewpower.com/infrastructure-technology/)。
- 制氢采用电解水的电输入到氢低位热值（LHV）能量转换；返电是燃料电池而非直接把氢库存当成电量。压缩和电力电子折入净阶段效率。本项目不把电解效率、燃料电池效率或整个链条效率相互混用。来源：[DOE PEM Electrolysis Technical Targets](https://www.energy.gov/cmei/fuels/technical-targets-proton-exchange-membrane-electrolysis)；[DOE Fuel Cell Technology Comparison](https://www.energy.gov/cmei/fuels/comparison-fuel-cell-technologies)。
- DOE 的热储能资料说明熔盐双罐储热通过换热器/蒸汽动力系统才能发电，固体介质也可储热。热量本身不等于电量。来源：[DOE Thermal Storage System Basics](https://www.energy.gov/cmei/systems/thermal-storage-system-concentrating-solar-thermal-power-basics)；[DOE Thermal Energy Storage Strategy Assessment, 2023](https://www.energy.gov/sites/default/files/2023-07/Technology%20Strategy%20Assessment%20-%20Thermal%20Energy%20Storage.pdf)。

## 本轮模型约定

电储能均为可独立放置的完整设施：锂离子电池站、钠离子电池站、液流电池站、地上压缩空气储能站、液态空气储能站、制氢—储氢—燃料电池返电站。它们共享确定性调度和库存守恒实现，不意味着底层物理相同。容量代表模型内部可用能量库存；氢能容量为氢 LHV，而非已可输出的 AC 电量。CAES/LAES 使用等效可用储能库存，不计算压力、温度或气/液质量方程。

固体蓄热是独立的固体介质储热成套装置，带固定温级换热边界。本轮仅提供 90/60°C 热水侧充放热接口。不是高温电阻炉模型，不新增直连 AC 的隐含电加热，不可直接发电；电转热必须通过已有电锅炉，向终端供热须走适配的换热器。高温固体储热/蒸汽耦合暂不作未验证扩展。

熔盐复用已有 molten_salt_store：565/290°C 热盐端口、独立 AC 辅机端口及原有热账本；无需重复增加一个熔盐种类。其返电仍必须经过熔盐蒸汽发生器、汽轮机、冷凝器和给水泵闭合循环。一级独立放置并不免除其温级、辅机和循环约束。

电储能每步的库存变化为：

    E_next = E_after_self_loss + P_charge * eta_charge * dt_h
             - P_discharge / eta_discharge * dt_h

其中 E_after_self_loss = E_before × exp(−self_discharge_per_h × dt_h)，不是把每小时率常数误当成每步固定扣除比例。

库存上下界、端口功率、线路容量/损耗、变电站容量/损耗均继续约束调度。禁止同一步同时充放；空库存无法供电，满库存无法继续充入。损耗必须非负，净输出不超过已投入能量和初始库存允许的能量。热储能使用同构的 MWhth/MWth 守恒，但不能跨越到 AC 输出。

氢能成套链只提供外部双向 AC 接口；电解、压缩/储氢与燃料电池是站内明确阶段，不把站内零件当成新的一层建造项。此模型没有氢气管网、氢销售、加氢站、水资源短缺或危险品运行模拟，不能据此进行实际氢工程安全设计。

本轮不实现储能设备 CAPEX/OPEX 或经济容量选型。地上 CAES 的容量/安装用地是独立教学配置，但没有任何盐穴成本被套入，也不能据此宣称廉价。既有燃气燃料费不应被误认作储能全寿命成本。

## 验收限制

无界面数值与结构测试不等于 GUI 人工视觉验收。用户操作既有窗口期间不打开新 GUI、不改当前存档。完成后需另行验收：分类栏在小屏实际可读性、横向滚动、选中/取消提示、所有二级页 Esc、各设施实物外观与地形遮挡、交互帧率和显存。

## 默认教学参数（代码为准）

| 技术 | 库存容量 | 充/放端口限额 | 净充×放效率 | 连续自损率常数（1/h） |
|---|---:|---:|---:|---:|
| 钠离子 | 6 MWh | 2/2 MW | 0.92×0.92 | 0.0001 |
| 液流 | 12 MWh | 2/2 MW | 0.85×0.85 | 0.0002 |
| 地上 CAES | 0.25 MWh | 0.1/0.1 MW | 0.75×0.70 | 0.002 |
| 液态空气 | 8 MWh | 2/1 MW | 0.70×0.65 | 0.002 |
| 制氢—储氢—返电 | 20 MWh(LHV) | 2/1 MW | 0.65×0.50 | 0.0001 |
| 固体储热 | 8 MWhth | 2/1 MWth | 0.95×0.95 | 0.001 |

以上每一个数都是本游戏的简化假设，不能引用为真实设备参数。CAES 额外限制容量≤10 MWh、充/放功率≤2 MW，仅为避免把教学地上设备无限放大成盐穴级系统的界面护栏，不是压力容器工程安全上限。既有锂电和熔盐默认参数保持原模型，不在本批静默改变已有设施。
