# 2A finite water → electrolysis → gas hydrogen → fuel cell: visual references

公开整理说明：本文保留研究或开发阶段记录；带时间的计数、计划与待验收状态仅适用于对应时点，不代表逐项人工验收已完成。最终范围见[最终原生验收](FINAL_NATIVE_ACCEPTANCE_1004.md)。原始运行日志、截图、玩家存档、备份与研究图像不随源码分发；下文非公开记录仅为来源说明。公开整理没有重新运行游戏或测试。

Reviewed 2026-10-21. Original procedural meshes only. Third-party photos are linked, not copied into the repository. Downloaded reference images were actually opened with `view_image` before implementation. The four facilities are independent simulated devices, not merely four parts of the old all-in-one hydrogen store.

## Evidence register: actual images and their limits

### Water reservoir and supply skid

- Manufacturer: [Balmoral GRP sectional tanks](https://www.balmoraltanks.com/solutions/grp-sectional-tanks).
- Inspected actual close photograph: [sectional tank, ladder, bolted panel seams and flanged nozzles](https://mail.balmoraltanks.com/images/products/tanks-grp-sectional-2.jpg). The corresponding www image timed out; the manufacturer's mail subdomain delivered the image. Visible rectangular panels, horizontal/vertical flanges, ladder and inspection access inform the reservoir mesh. The photo does not establish a 10-tonne model.
- Pump reference already inspected for map resource review: [Grundfos Rottal case PDF](https://www.grundfos.com/content/dam/global/activity-assets/isolutions-wu/documents-and-cases/cases/wu-water-networks/wu-case-water-distribution-rottal-2019/wu-case-water-distribution-rottal-2019-pcs-gb-en.pdf), page 1 actual installation photograph: vertical multistage pumps, dark top-mounted motors, common header. This informs the separate pump/meter skid, not a new simulated power input.
- Original teaching geometry: 3×2×2 m gross rectangular tank (12 m³), leaving headroom/unused volume for the default 10,000 kg usable allocation; total module 6×5×3 m. This is not a certified hydraulic, materials, water-quality or auxiliary-power design. Finite inventory, no automatic refill and no unlimited water source.

### Electrolyser enclosure and power supply

- Manufacturer: [Nel MC Series PEM](https://nelhydrogen.com/product/mc-series-pem/).
- Dimensions verified in [MC Series datasheet, revision J](https://nelhydrogen.com/wp-content/uploads/2021/01/MC-Series_PD-0600-0136-Rev-J.pdf): 12.2×2.5×3 m electrolyser enclosure; 6.1×2.5×2.6 m power enclosure. Page 1 was rendered and inspected: it is a product rendering, **not a field photograph**. It corroborates two separate enclosures plus optional cooling structure, not an as-built site.
- Actual construction/integrator reference: [Pacific Energy Denham project](https://pacificenergy.com.au/project/denham-h2-demonstration-plant/), inspected [front field photograph](https://pacificenergy.com.au/wp-content/uploads/2025/08/DJI_0892_crop.jpg) and [aerial photograph](https://pacificenergy.com.au/wp-content/uploads/2025/08/DJI_0514-1-1024x767.webp). Visible corrugated container enclosures, separate electrical equipment, exposed pipes/vent masts and independently arranged auxiliaries inform the layout. Denham has two 174 kW electrolysers and a 100 kW fuel cell; it is **not** the proposed 2 MW module, nor proof of MC500 geometry.
- Original 15×9×4 m installation module retains the two Nel enclosure dimensions without stretching. Cooling skid and vent positions are teaching layout assumptions. Its 2 MW AC limit and conversion coefficients come from the simulation profile, not Nel's 2.5 MW MC500 specification.
- Rejected as model evidence after pixel inspection: Nel Pacific Energy thumbnail is a group interview and Nel NREL thumbnail is a person beside PV, not usable electrolyser detail. No shape was inferred from those thumbnails.

### Gas hydrogen storage

- Manufacturer: [Hexagon Purus UK distribution-system order](https://hexagonpurus.com/news/hexagon-purus-receives-inaugural-order-for-uk-market-to-deliver-hydrogen-distribution-systems-from-a-leading-global-industrial-gas-company).
- Inspected [45-ft cylinder-frame photograph](https://d2unncwr0d5wwb.cloudfront.net/purus/_1200x630_crop_center-center_82_none/45-ft-container-11.jpg?mtime=1702447567). Pixel inspection shows **upright dark composite cylinders** inside a pale steel frame with cross braces and top connections. An earlier shorthand describing these as horizontal cylinders was incorrect; the new model uses upright cylinders.
- Original 17×8×4 m stationary teaching module: 13.7 m-class rack, 54 explicit slender upright vessels, separate compressor enclosure, valve/meter train and electrical control. Photo-derived construction vocabulary does not certify stationary use, individual cylinder size, pressure, gas density, usable volume, or capacity. The model does not copy a trailer's approval to a stationary facility.
- 1,000 kg is an explicit teaching inventory allocation. It is not inferred from visible vessel count. Geometry cannot prove pressure safety. This kind is gaseous H₂ only: no sphere, cryogenic liquid tank, or solid-hydride identity; no automatic electrolysis or power generation inside the storage device.

### Fuel-cell cabinet bank, inverter and cooling

- Manufacturer: [Ballard stationary power](https://www.ballard.com/stationary-power-generation/) and [FCwave](https://www.ballard.com/fcwave/).
- Inspected [FCwave isolated cabinet image](https://www.ballard.com/wp-content/uploads/2024/10/FCwave-1.png): twin access doors, upper louvers and lower front service couplings. It is a manufacturer product illustration; photographic provenance is not independently established. The actual Denham installation photos above supply the field-layout reference, without claiming their 100 kW installation is a 1 MW Ballard plant.
- [Official linked FCwave datasheet](https://www.ballard.com/wp-content/uploads/2024/11/FCwave_20241008.pdf), page 2 specifies 1.215×0.738×2.195 m with air filter, 200 kW and DC voltage. The current web overview lists 1.209×0.741×2.195 m; this model deliberately uses the dated linked datasheet's dimensions and does not silently blend revisions.
- Original 12×7×3.5 m teaching module has six fixed-size cabinets, a dry-cooling bank and separate inverter/AC switchgear. Six 200 kW DC reference components are not equated directly to 1.2 MW net AC. The simulation's 1 MW net-AC bound remains authoritative; auxiliaries and conversion are included in its fixed net coefficient. This is not a certified complete Ballard plant, detailed thermal design or explicit heat recovery.
- Rejected after inspection: Ballard `featured-spg.jpg` is a server room, not a fuel-cell photograph.

## Geometry and port contract

All dimensions are in metres; existing conversion remains 0.1 world unit/m. Whole modules replicate by rating/allocation rather than being stretched. Module spacing and outer maintenance margin are both 2 m teaching allowances, not hydrogen fire/safety separation certification. Large installations retain full analytical placement area but display at most 32 clearly declared representative modules. Default facilities show every module.

Ports copy the authoritative catalog exactly:

| Device | Actual ports |
|---|---|
| water_supply_boundary | water_out: liquid H₂O, kg/s |
| electrolyzer_station | ac_in MW; water_in liquid H₂O kg/s; h2_out gas H₂ supply grade kg/s |
| hydrogen_gas_store | ac_in MW; h2_in gas supply grade kg/s; h2_out gas delivery grade kg/s |
| fuel_cell_station | h2_in gas delivery grade kg/s; ac_out MW |

No mesh adds ports, inventory, dispatch capacity, oxygen sales, heat export or hidden water replenishment. All sources are appearance/dimension references, not safety-design advice.

## Verification

`tests/test_material_visual_phase2.gd`: 168 checks, zero failures. Covers exact catalog ports/metadata, finite world anchors, declared site envelope, ground contact, non-mutating geometry, fixed-size replication, cheap save/placement query, million-module analytical bounds, batching and bounded LOD. GUI rendering and application frame timing are separate integration acceptance; no GUI operations were performed for this work.

Original geometry was exported headlessly and rendered in Blender background mode, then all four final front-side views were opened and inspected: 非公开验收记录（未随源码分发）. They show distinct panel reservoir/pumps, paired electrolyser/power containers/cooler, upright cross-braced gas-cylinder bundle/compressor, and FC cabinet bank/inverter/cooler. These previews use independent inspection lighting, not application screenshots; no manufacturer pictures are embedded. Legacy storage detail (255 checks), authoritative spatial geometry (251), and inspector camera limits (35,842) also passed in the isolated headless environment.
