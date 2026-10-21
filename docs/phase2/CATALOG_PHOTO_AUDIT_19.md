# 原目录19项：官方实物照片分族核查

公开整理说明：本文保留研究或开发阶段记录；带时间的计数、计划与待验收状态仅适用于对应时点，不代表逐项人工验收已完成。最终范围见[最终原生验收](FINAL_NATIVE_ACCEPTANCE_1004.md)。原始运行日志、截图、玩家存档、备份与研究图像不随源码分发；下文非公开记录仅为来源说明。公开整理没有重新运行游戏或测试。

核查日期：2026-10-21，18:21–18:29 UTC。只在 phase2 副本做阅读与记录，**本轮没有修改运行模型、尺寸、端口、物理或存档**。下述图都已通过 view_image 打开实际像素；PDF先在本地渲染，再看页面/图版，不把搜索摘要当成看过照片。

核查目标是纠正设备身份和可辨认构件，不是购买厂家CAD或为每件教学设备取得定量认证。A形态=已有真实同族设备/构件照片，并逐项对照现模型；不表示精确复刻、厂家额定、安全距离、材料/承压或性能认证。照片中数十至数百MW的设施不会替代游戏的小型教学参数。

## 1. 风、光、电池

### E1 Vestas：风机
- 官方页面：https://www.vestas.com/en/energy-solutions/onshore-wind-turbines/4-mw-platform
- 实际查看：页面 Helena 风场照片，1600×1200：
  https://vestas.scene7.com/is/image/vestas/V150-4.2%20MW%20Helena%2013?qlt=85&wid=1600
- 像素可见三叶片上风向水平轴、锥形塔筒、轮毂/机舱的总体关系以及地面间隔。不是塔基检修细节照片。
- 对照：wind 现有三叶片、机舱和锥形塔匹配，保留。游戏90m轮毂/126m叶轮保持已有参数，不称照片V150复刻，亦不根据远景推基础尺寸。

### E2 JinkoSolar：地面PV
- 官方项目页：https://www.jinkosolar.com/en/site/solutionlist/26
- 实际查看 Sweihan 地面电站航拍：
  https://jinkosolarcdn.shwebspace.com/uploads/28.jpg
- 密集分区行列、行间空隙、地面通行带与排布方向可辨。相邻29.jpg是水面项目，已排除作为地面支架依据。
- 对照：pv 米制多片阵列及分行支架保留。JKM550M既有单片2.278×1.134m尺寸和游戏数量来自单独资料，不能用航拍认证；该远景也不证明某个跟踪器型号。

### E3 BW ESS：Bramley PowerTitan 2.0
- 运营方：https://bw-ess.com/news/bw-ess-secures-financing-for-its-operational-331mwh-bramley-bess
- 设备技术身份交叉页：https://bw-group.com/newsroom/articles/2025/02/bw-ess-celebrates-inauguration-of-the-uks-largest-battery-energy-storage-system/
- 实际查看1600×1067现场阵列：
  https://craft-bwess.s3.eu-west-2.amazonaws.com/_landscape1600/965/Bramley-Option-2-scaled.webp
- 可见分组长方体机柜、检修门/端部设备、独立混凝土支承、通道和后方汇集区。剪彩人物照不是设备细节依据，已排除。
- 对照：battery 米制箱体的多检修门、端面通风/HVAC、基座与按模块阵列已有对应，保留。原额定/尺寸不改；独立升压设备仍为另一个kind，不因照片后方变电区给电池添加免费升压站。颜色不必抄绿色商标涂装。

## 2. 水热、锅炉、管式/板式换热

### H1 Aralsan与远大：电阻热水锅炉
- 制造商：https://www.aralsan.com/en/product/ask-e-electric-hot-water-boiler
- 实际查看产品实物抠底组合照：
  https://www.aralsan.com/sites/default/files/aralsan_electric_hot_water_boiler_0.jpg
- 实物的钢撬、圆筒水体、电加热/独立电控柜、接管阀表可辨；这不是燃烧器锅炉。
- 补充制造现场页：https://www.yd-boiler.com/yuandaboiler/500kw-electric-hot-water-heater.html
- 实际查看带包装的设备/电柜出厂照片：
  https://www.yd-boiler.com/yuandaboiler/wp-content/uploads/2023/09/electric-hot-water-boiler-china-2.jpg
  铭牌图china-3.jpg仅用于排除错认，不能当构型照片。该产品为常压85/60，并非本游戏90/60承压工作点，不采用其工况。
- 对照：electric_boiler 已有卧式保温筒体、鞍座、电热元件端盖/线槽、独立电柜、无烟囱，保留。卧式选择及既有量级有ECOTHERM厂家文件，实物照片用于组件核查而非把两个品牌拼成真型号。
- ECOTHERM 2025/2023 PDF本轮远端下载503，web文本可读但截图失败，**不列为本轮已看实拍**；Newtronic旧PDF地址返回文字网页转档，已排除。Chromalox PDF第1页产品合成图只作辅助，不代替上述实物。

### H2 Haase：大型水储热
- 厂家案例：https://www.haasetank.de/referenzen/grossspeicher-fur-abwaerme-bei-der-stadtreinigung-hamburg/
- 实际查看厂商图片：
  https://www.haasetank.de/app/uploads/2019/08/41074TY008-1024x683.jpg
- 工业室内圆筒绝热外护壳、顶部、上下分离管口及贴地安装可见。图片不能显示内部温度分层。
- 对照：thermal_store 的银色绝热筒、外壳拼缝、上下供回接管、检修口/支承保留；双筒是游戏固定品位库存教学组合，不声称照片就是125m³双筒。Huch网页有尺寸资料但图片下载失败，不虚称看过其案例图。

### H3 Alfa Laval：板框水水换热
- 厂家页：https://www.alfalaval.us/products/heat-transfer/plate-heat-exchangers/gasketed-plate-and-frame-heat-exchangers/
- 实际查看工厂培训照片：
  https://www.alfalaval.us/globalassets/images/local/usa/service/kristi_lauren_gphe_training_640x360.jpg
- 人员旁真实蓝色固定压板、四个大法兰、压紧螺栓/后部板束可辨。
- 对照：heat_exchanger 现资产固定前后压板、板束、拉杆、四物理供回口和底脚均匹配；逻辑热网仍两个成对供回端口，不变成四条独立能量边。保留现有模型和参数。

### H4 Bosch：燃气热水锅炉
- 厂家案例索引：https://www.bosch-industrial.com/global/en/commercial-industrial/solutions/references/references-manufacturing-industry/
- 实际查看KSB热水机房：
  https://www.bosch-industrial.com/global/media/country_pool/solutions/references/ksb/ksb_heizkessel_nah_770x434.webp
- 可见卧式绝热锅炉、强制送风燃烧器、黄色燃气阀管、立式烟道与供回管道。
- 对照：fuel_boiler 的独立燃烧器/气阀组、卧式壳体、烟道、热水供回已对应，保留。该现场不是Uni3000F原型号精确复刻，不以其额定替换既有尺寸/教学参数。

### H5 Viessmann：真空管集热
- 厂家目录：https://www.viessmann.co.uk/content/dam/public-brands/gb/pdf/technology-brochures/en/Solar-thermal-systems.pdf/_jcr_content/renditions/original.media_file.download_attachment.file/Solar-thermal-systems.pdf
- 实际看PDF第4页玻璃管近景及第17页屋面安装实拍；第14页孤立产品图不作为现场实拍。
- 对照：solar_thermal 的并排真空玻璃管、上集管箱、下支托、倾斜架及热管路匹配，保留24管教学模块。目录300-TM与旧SP2A型号不同，只核同族可见结构，不移植性能。

### H6 Pirobloc：热油容器与油水换热
- 厂家换热页：https://www.pirobloc.com/en/products/heat-exchangers/
- 实际查看工厂卧式保温管壳、螺栓端盖、鞍座、分离阀管及控制柜：
  https://www.pirobloc.com/wp-content/uploads/2024/06/piro10.jpg
- 厂家热油膨胀系统页：https://www.pirobloc.com/en/products/expansion-tanks/
- 实际查看完整撬及上部容器：
  https://www.pirobloc.com/wp-content/uploads/2024/06/piro11.jpg
  https://www.pirobloc.com/wp-content/uploads/2018/05/deposito-exp-skid2.jpg
- oil_water_exchanger：现有卧式管壳、两侧独立介质管、鞍座、电辅机柜与实物同族，保留。没有改成普通板换。
- high_temp_store：可从实拍核实保温金属壳、罐顶接口/维护件、支承及热油系统接管这类构件。**照片中的高位卧式膨胀罐不是游戏竖式冷热双罐储热站，也不能用来证明其容量。** 游戏双罐仍明确为Therminol66定品质教学组合，尺寸沿既有质量/体积假设；本次只达成构件级外观参考，不将“已看照片”升级成整站实测认证。未发现需要凭另一种膨胀罐强改现双罐方向的依据。

## 3. 槽式、塔式、盐热与汽水回路

### C1 Sener与Sulzer：槽式/接收塔/盐罐
- 建设方：https://www.group.sener/en/project/gemasolar-solar-thermal-power-plant/
- 实际查看Gemasolar中央塔及环形定日镜：
  https://www.group.sener/wp-content/uploads/2022/06/sener-solar-plata-gemasolar-1-scaled.jpg
- 建设方热储能页：https://www.group.sener/en/markets/energy/dispatchability-storage/thermal/
- 实际查看NOORoⅠ全场航拍，能分辨双圆罐、工艺岛、成行槽式集热；NOORoⅢ图核中央塔与径向镜场：
  https://www.group.sener/wp-content/uploads/2025/09/sener-concentrated-solar-power-nooro1-copyMasen.jpg
  https://www.group.sener/wp-content/uploads/2022/06/sener-solar-nooro-iii-2-scaled.jpg
- Sulzer太阳能给水应用页所用实际槽式近景（不是泵照片）：
  https://www.sulzer.com/en/shared/products/md-high-pressure-stage-casing-pump
  https://www.sulzer.com/-/media/images/applications/power-generation/renewables/solar-power-generation/id1268_feedwater_pumps_14015.jpg?mw=720&hash=DE8305FBFB9A9F551D9831DF2FBB130E
- parabolic_trough：现反射槽曲面、焦线接收管、支架/转轴/油管匹配。12m×5.77m仍单镜段，不等同完整SCA。
- solar_tower_receiver：现塔顶接收器、竖直塔身、塔基与定日镜场组织匹配。现25m是明确教学塔，不把Gemasolar140m强缩后称实厂米制复刻。
- molten_salt_store：现低矮大圆筒热/冷盐双罐、基础、保温顶/泵管与现场同族，保留。双罐只输出565/290热品位，蒸汽/发电必须显式外接。

### C2 Aalborg CSP：油/盐蒸汽发生设备族
- 厂家2011技术目录：
  https://www.aalborgcsp.com/fileadmin/user_upload/beUid/1/1-Downloadable_materials/1-Brochures/2011_09_01__Brochure_SGS_technical.pdf
- 实际查看第2页Fig.1多段卧式换热/蒸发设备、保温壳、管汇和黄色检修平台；第7页左实际汽包照片。第1页模型、第3–5页工程示意不是实拍。
- 厂家2016目录：
  https://www.aalborgcsp.com/fileadmin/user_upload/beUid/1/1-Downloadable_materials/1-Brochures/1-ENG/2016-11-15_Aalborg_CSP_Power_plant_technologies_8-pager_brochure_DIGITAL_ENG.pdf
- 实际查看PDF第3张跨页（印刷内页4–5）中央保温壳/平台照片；该跨页文字区分热油SGS3与熔盐SGS4。**照片自身未证明属于SGS4，右侧盐配置为示意图，不能伪标盐厂实拍。**
- steam_generator / salt_steam_generator：现有管壳蒸发容器、给水/蒸汽分离管、筒体鞍座、控制柜核对后保留，是小功率集总教学撬，不假装50MWe多段厂的精确缩版。盐型的“实际照片覆盖”仅指可迁移的真实换热容器/管汇构件；盐材质、热追踪和多级真实工程布局没有由照片验证。各自Catalog介质/端口仍完全区分。

### C3 Siemens：小型汽轮发电机
- 厂家2016公告：https://press.siemens.com/global/en/pressrelease/siemens-supply-nine-compact-steam-turbines-great-britain-and-united-states
- 实际查看SST-040实物组合机：
  https://assets.new.siemens.com/siemens/assets/api/uuid:ce4040eb-d9ab-4b4d-83e2-aff96c4631be/width:1024/im2016080926pg_300dpi.jpg
  同页SST-110工厂照片另已看，不把大机组等同小机：
  https://assets.new.siemens.com/siemens/assets/api/uuid:0b1d5b5b-c340-4a1b-b6d7-a60519adb0d1/im2016080927pg_300dpi.jpg
- 对照：steam_turbine 壳体、轴系/联轴器、带散热的发电机、共用底座和进排汽管方向匹配，保留。现教学小功率不自称SST-040的300/420kW。

### C4 SPIG：干式冷凝排热
- 厂家目录：https://spig-gmab.com/wp-content/uploads/2024/11/SPIG_002_Air-Cooled-Condensers.pdf
- 实际查看第1页大蒸汽总管/排热架、第2页实际安装、风机下视、倾斜翅片和支柱；第3页上方CAD明确排除。
- 对照：steam_condenser 采用集总表面冷凝壳+上层干式翅片风机、支架、乏汽/凝结水管和风机电柜；构件已对应，保留。它不是该大型Δ架/直接ACC的精确缩版，亦不新增耗水冷却塔。
- 排除：Alfa Laval 100MW Niagara WSAC PDF虽已看真实照片，但为湿表面空冷，不能证明游戏“干式无外水”方案；SPG Partanna页面文本可读、图片503，未算已看。

### C5 Sulzer：给水泵
- 厂家目录：
  https://www.sulzer.com/en/-/media/files/products/pumps/radial-split-pumps/brochures/hpt_multistage_barrel_casing_e00616.pdf
- 实际查看第2页真实给水泵端面、螺栓筒体、接管和底座；第1/3/4页渲染/剖面不当实拍。
- 对照：feedwater_pump 共轴泵筒/电机、轴承支墩、联轴器、吸排管及电柜保留。简化外壳没有展示每级叶轮，不声称由外形证明扬程或HPT大型额定。

## 4. 旧电→氢→电完整系统

hydrogen_storage_system复用同日已实际看过的Pacific Energy Denham前景/航拍，厂家/集成商URL、图像身份与原项目功率见MATERIAL_2A_VISUAL_REFERENCES.md。现三段为电解压缩柜、独立气体容器组、燃料电池/逆变柜，与实际整站分区可对应；Hexagon照片只能核气瓶钢框/汇流，不能证明现卧式钢罐就是其直立复合瓶产品。

旧kind继续是**等效电储能黑箱**，20MWhLHV库存/净可返电不是厂家站额定；不将新气/液/金属氢三kind的已实现分类反向套入旧存档。现卧式容器图标不属于液氢或LaNi5，不引入真实压力仿真。保留模型和旧存档尺寸。

## 保留决定、验证与剩余边界

- 已逐项核对19类的对应代码、原资产生成器和可用历史结构图；另实际打开8张旧热工资产结构图作轮廓检查。保留是基于身份/组件匹配，不是只改覆盖表字母。
- 本轮不需要新增运行几何补丁；没有为照片额定改容量/端口、放大土地或迁移旧存档。运行模型最后写入仍18:14:39 UTC。
- 原27类中25类设备均有真实同族设施或构件像素核查；load/heat_demand两项明确为抽象需求标记，不虚构工厂。**只有构件级证据的热油双罐、盐蒸汽发生器和旧集成H2已在上述段落限定，不宣称全27项实厂复刻或精确比例认证。**
- 照片只链接。临时研究图片不放进游戏资产。来源、实际查看文件摘要与覆盖kind保存在非公开研究记录中；公开文档保留来源链接，不分发版权图。
- Headless定向回归结果见同目录日志；实际Godot灯光/GUI验收仍由主线执行，不能用旧Blender结构图代替。
