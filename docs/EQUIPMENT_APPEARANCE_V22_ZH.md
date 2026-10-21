# V22 设备外观美化补丁

## 范围与边界

基于完整 V21 的独立工作副本。仅修改显示几何、材料、真实管口定位和站内管路表现，不修改设备目录、求解器、额定功率、容量、效率、温度工作点或存档计算语义。水储热仍是 90/60°C 固定双区等效库存的并联双筒，不改成熔盐冷热双罐。所有造型为可运行游戏中的工业原型化表达，不是制造图或施工级设计。

## 实际变化

- 电热水锅炉：银灰保温护板、鞍座、法兰电热接线罩、控制柜、电缆套管、顶部供水接管、压力表、独立回水与管托。没有新增燃烧器或烟囱。
- 水储热：两筒统一银灰金属护板与分段接缝，90/60°C 只用窄识别带；保留两筒都具备上供下回的原模型语义。新增检修人孔、法兰、管架立柱与支臂。
- 水水板式换热器：明确改为固定前板四角连接、后方压紧板、薄板与垫片束、上下导杆、拉紧螺栓和支柱。两套介质通过各自端口流道，不画成混合容器。没有把油水换热器或盐蒸汽发生器错误替换成板换。
- 风机：保留轮毂中心高 90m、叶轮直径 126m 和旋转轴/电端口；按这个尺寸基准减小原先偏大的机舱、塔径、塔门与电柜，补维护踏步、锚栓、检修盖、通风口、地面盖板电缆沟。没有按额定功率反推几何。
- 电池柜保留普通浅色户外涂装，补柜体接缝与HVAC格栅；光伏增加倾斜横梁和前后支腿，仍批处理成网格而非逐面新增节点。
- 熔盐仍分热565°C/冷290°C两只独立罐，补金属接缝、顶部泵头/顶部入罐管、立管支架和下部服务接口，未增加防冻或泵功耗物理模型。
- 站内短距热水服务使用真实 Port_* 与新 Return_* 物理锚点。Return_* 不属于逻辑端口，不增加网络边或容量。配对供回水使用前方低位通道、弯头和独立支撑，避免原先所有线被抬到最高罐顶。银灰实体管与小面积回路色标分开；AC仍走电缆托盘。

## 尺度与性能

热模型保持原包围盒、模块占地与0.1 world unit/m。水储热的毫米级回水端超差已修复，最终8.5×5×7.635m。

| 模型 | V21三角数 | V22三角数 | 网格 |
|---|---:|---:|---:|
| 电热水锅炉 | 3252 | 4124 | 1 |
| 水储热双筒 | 6016 | 7928 | 1 |
| 板式换热器 | 5112 | 6516 | 1 |
| 热站外观 | 10008 | 10008 | 1 |
| 风机 | 2796 | 5692 | 5（含旋转部件） |

热设备共享7种无纹理PBR材料，未新增高分辨率贴图或依赖。风机保持原5网格旋转层级。光伏的支架仍同批处理网格，保留极大阵列降级策略。管路小构件仅显示，不参与计算。

## 官方造型核对依据

以下只用于原型形态/材料方向，不声称复刻厂家CAD或采用厂家尺寸作为本项目额定设计。

1. Chromalox 电热蒸汽/热水成套设备设计资料：电阻加热压力容器与独立电控，不需要燃烧烟道。
   https://www.chromalox.com/-/media/Chromalox/Documents/Design-Guides/dg-packaged-systems-steam-boiler.pdf?hash=0408B641BA7287A85C0BC123FD205F68&la=en
2. Alfa Laval 垫片板框换热器：板束、固定/移动框板、压紧螺栓、上承重杆与下导杆的真实结构。
   https://www.alfalaval.us/products/heat-transfer/plate-heat-exchangers/gasketed-plate-and-frame-heat-exchangers/
3. Austria Email 缓冲罐：钢制内筒、银灰涂装钢板外护层、隔热及多个侧面连接口。没有照搬其家用产品容量。
   https://www.austria-email.com/products/buffer-and-combined-tanks/hot-cold-buffer-tank/all-purpose-buffer-tank/
4. Huch 大型/特殊储罐：立式钢罐、保温层、支撑/支腿及高低温储罐用途。
   https://huch.com/gross-sonderspeicher/
5. Vestas 生命周期资料：塔身、机舱、轮毂/叶片、基础、变压/开关设备和场内电缆作为独立组件。
   https://www.vestas.com/content/dam/vestas-com/global/en/sustainability/reports-and-ratings/lcas/LCA_V100-1_8MW_onshore_GridStreamer_version1_2011.pdf.coredownload.inline.pdf

## 验证与图像

真实 Blender 4.3.2 GLB 前后渲染位于 evidence/equipment_v22/before、after；compare_*.png 使用相同镜头、照明和尺度，明确标注“离屏模型副本审阅，非游戏整合完成”。不是AI生成概念图。

Godot 4.6.3 无界面导入和功能/几何测试日志位于 evidence/equipment_v22/validation。专门新增 test_equipment_v22.gd，核对物理回水锚点、逻辑端口数量、服务线端点、管托和设备/连接数据不变。最后的游戏实机截图由UI整合分支负责。

## 整合

按 evidence/equipment_v22/merge_manifest.json 复制文件。station_interior.gd 已与UI分工，不能整文件覆盖：只应用 patches/station_interior_geometry.patch。不复制 .godot 缓存或自动生成的 .import 文件。重新导入GLB后执行新测试及原回归。
