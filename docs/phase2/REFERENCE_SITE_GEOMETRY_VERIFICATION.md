# reference_size_v1 几何定向验证记录

公开整理说明：本文保留研究或开发阶段记录；带时间的计数、计划与待验收状态仅适用于对应时点，不代表逐项人工验收已完成。最终范围见[最终原生验收](FINAL_NATIVE_ACCEPTANCE_1004.md)。原始运行日志、截图、玩家存档、备份与研究图像不随源码分发；下文非公开记录仅为来源说明。公开整理没有重新运行游戏或测试。

时间：2026-10-21 19:17 UTC。仅实现可见硬件与占地，不改变运行容量、物种、调度或守恒方程；未启动 GUI，未发布。全库回归由集成检查另行执行，本记录不替代其结果。

## 交付与版本

- `scripts/spatial_dimensions.gd`：第 5 个可选参数为 `site_geometry_profile="reference_size_v1"`，第 4 个 flow 几何参数不变。显式空串保留旧几何。新标识使用共享 `site_layout_support_v1.json` / `SiteLayout.required_geometry()` 的净腔与物性合同。
- `scripts/equipment_visual.gd`：读取 `visual_site_geometry_profile`，显式空串旧件、缺 key 的新直调默认新件。修改后的净腔由独立外壳包围，未将旧小壳均匀缩放后冒充容量。新双水罐使用 metric builder，不使用旧 GLB。
- 内部净尺寸 / 所需容积来自共享合同；外壳差、框架、保温、底座及检修余量仍为教学设计，不是压力容器壁厚或安全认证。
- 新标识降额不缩减安装硬件；已允许的离散模块扩展仍按模块计。此几何参数副本不回写原运行 params。
- 下列 SHA-256 为 19:16:32 UTC 阶段快照，不是最终集成冻结版本。此后集成补水罐独立回水喷嘴、无效 metric 安全返回、钠电容量参考几何及极端旧锂电 LOD；最终版本以冻结源码清单为准。

阶段快照 SHA-256（保留溯源，不能代替最终 manifest）：

| 文件 | SHA-256 |
|---|---|
| equipment_visual.gd | `b29d36fd26b4a1a8e640be069110b0ce0dea3512cbf45fbf10f0e1cd9c230df2` |
| spatial_dimensions.gd | `8024c2f2060ce4ba49522bfbc0e523c7d0d0d173a4208dd20ae0fddf9ee841b7` |

## 可重跑专项

文件：`tests/test_reference_site_geometry.gd`。所有工程依赖均为 `res://` 相对路径，不依赖临时基线或用户桌面。

在工程根目录运行：

```sh
godot --headless --path . --script res://tests/test_reference_site_geometry.gd
```

如果执行环境的 HOME 不可写，应按该环境测试规范将 HOME / XDG 缓存和数据目录指向可写测试目录；不要向源码或冻结基线写入运行日志。此次首个未配置可写 HOME 的 Godot 进程在创建用户数据目录时崩溃，没有完成测试；改为专用临时用户目录后正常执行。

最终结果：`REFERENCE_SITE_GEOMETRY PASS checks=107 failures=[]`。

覆盖：6 类共享净腔一致性、最低净容积、可见 mesh AABB / 地面 / 安装包络、有限端口数、参数不变性、旧标识隔离、降低容量不缩外壳与模块数；另验证 PV / 锂电 / 电站 / 油 / 盐 / 太阳能热 / 槽式 / 电解站的降额几何下限。

| kind | 新净腔 / 芯体 m³ | 合同最低 m³ | 新工艺区 x×z m | 含四周检修区 x×z m |
|---|---:|---:|---:|---:|
| thermal_store | 150.796447 | 148.746808 | 11×6 | 15×10 |
| solid_thermal_store | 360（其中80%实钢288） | 339.702760（实钢271.762208） | 22×7 | 26×11 |
| hydrogen_gas_store | 75.549020 | 71.428571 | 22×9 | 26×13 |
| hydrogen_storage_system | 44.614050 | 42.861429 | 24×16 | 28×20 |
| nitrogen_supply_boundary | 5.458706 | 4.761905 | 18×14 | 22×18 |
| ammonia_synthesis_station | 64.875983 | 60.606061 | 60×40 | 64×44 |

气氢仍为 54 根竖直瓶束；集成氢仍为 5 只卧罐。N₂ 120 只瓶的原外壳已经容得下共享净腔，其外形不需无根据放大。NH₃ 4 只气罐改为包括半球端头的更高壳体。固热用固定两只 180 m³ 净芯体，通道 / 空隙分数计入合同，不声称展示了全部内部通道 CAD。

## 旧几何历史差分证据

本轮另在临时目录加载改前脚本作历史对比，结果：`REFERENCE_LEGACY_REGRESSION PASS checks=244 failures=[]`。该测试依赖改前快照，**不是可独立重跑的交付测试**，没有把绝对临时路径脚本放入仓库。

对比基线 SHA-256：

| 基线 | SHA-256 |
|---|---|
| equipment_visual 改前 | `657b9e3edc4ccf35dcf2e1fb5319d1e2907d2d34652828225bac307dc449e00b` |
| spatial_dimensions 几何改前 | `05d9d952018bc118cf2f1c66bb32e4278dc2c7c6fa343d0467765a6f71f4f53b` |

Spatial 基线是在新增兼容函数签名后、实际几何改动前取得，内部形状仍为原版。临时 Visual 对照仅将 Spatial preload 指向该基线，未调整任何几何数字。

244 项包括：6 类旧件的模块数、单元尺寸、实体 / 安装包络、碰撞半径、后端、端口坐标、mesh 个数及每个 mesh 的 AABB / 局部 transform，与改前一致；全部共享支持种类默认参数可生成有限几何，允许的运行功率降为零仍保留几何；嵌套旧水罐参数的递归 fallback 不丢失空标识。

首次历史测试比较了 Godot 自动生成的重名节点编号，4 项名称比较不稳定；改为比较 mesh AABB 与 transform 后通过。没有为迎合该测试修改生产几何。

旧快照的预期包络（x,height,z，m）可用于人工复核：水罐(8.5,7.635,5)、固热双模块(18,5,6)、独立气氢(17,4,8)、集成氢(24,5,16)、N₂(18,4,14)、NH₃(60,15,40)。旧件没有被补上“净腔通过”metadata，也没有自动获得新支持标识。
