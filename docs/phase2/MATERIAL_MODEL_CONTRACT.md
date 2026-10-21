# Chemical material phase 2C: frozen core contract

公开整理说明：本文保留研究或开发阶段记录；带时间的计数、计划与待验收状态仅适用于对应时点，不代表逐项人工验收已完成。最终范围见[最终原生验收](FINAL_NATIVE_ACCEPTANCE_1004.md)。原始运行日志、截图、玩家存档、备份与研究图像不随源码分发；下文非公开记录仅为来源说明。公开整理没有重新运行游戏或测试。

Core production editing was frozen for the parent's final regression at 2026-10-21 18:20 UTC. This document records the implemented model and focused evidence, not GUI acceptance or a release declaration. Only the development copy was changed.

## Version and compatibility boundary

- Current integration: save schema 19, model 27, optimizer schema 12; 39 implemented equipment kinds. Application display version 1.0.0.4 is managed separately.
- The four chemical kinds alone use `material_chemical_2c_v3`, version 3. Their defaults, hard maxima, atomic masses, reference enthalpies and process constants are frozen in `data/material_process_profiles_v3.json`.
- The four original water/electrolysis/gas-storage/fuel-cell kinds retain `material_hydrogen_2a_v1`, version 1. Liquid and LaNi5 hydrogen facilities retain `material_hydrogen_2b_v2`, version 2. Neither is silently relabeled or assigned new default parameters.
- Earlier catalog boundaries are explicit: legacy 27; material 2A 31; CO2 32; collector 33; phase hydrogen 35. Save 18 is the separate liquid-flow geometry batch with the same 35 physical kinds and v2 ledger. Chemical equipment is invalid under earlier schemas.
- CO2 storage and collector retain their independent version-1 profiles. Per-device profile is read via `Catalog.model_profile(kind)` and `Catalog.model_profile_version(kind)`; a mixed scene is not assigned one device profile wholesale.

## Four finite facilities

1. `nitrogen_supply_boundary`: externally prepared N2 gas at 25 C. Capacity and initial-stock defaults/maxima are 1000 kg; outflow is 0.05 kg/s by default, maximum 0.1 kg/s.
2. `co2_supply_boundary`: externally prepared CO2 gas at 25 C, with the same mass/rate limits. It is not a capture plant or a liquid CO2 reservoir.
3. `ammonia_synthesis_station`: net N2 + 3 H2 -> 2 NH3. Product is a finite 25 C gas buffer, default/maximum 200 kg.
4. `methanol_synthesis_station`: net CO2 + 3 H2 -> CH3OH + H2O. Product and released byproduct water are liquids at 25 C. Product buffer is default/maximum 1000 kg.

Both synthesis facilities start with exactly zero product. Product-rate defaults/maxima are 0.02/0.05 kg/s. Total electrical rating, internal heater electrical rating and heat-rejection rating have defaults equal to their hard maxima: 0.2 MW, 0.15 MW and 0.4 MWth. Parameters cannot invent adjustable thermochemical constants or an extra energy stock.

State is exactly the supported material state: `{material_inventory_kg: {species: kg}}`, with N2, CO2, NH3 or CH3OH respectively. `Catalog.inventory_capacity(kind, params)` returns the bounded mass capacity. Existing LaNi5 host remains immutable and its H2 capacity remains 0.012 times dry host mass.

Actual new construction of a preloaded feed boundary records an explicit inventory/enthalpy import. This is a finite external material supply, not free air separation, carbon capture, renewable electricity, fuel LHV or an energy credit. Product is retained locally: no sale, automatic emptying, conversion to electricity or product-transfer consumer exists. Nonempty inventory cannot be silently removed.

## Typed routes and atomic dispatch

- N2: `n2_out` -> `n2_in`, carrier `material_n2_gas`, species `N2`, phase `gas`, grade `n2_gas_25c`, unit kg/s.
- CO2: `co2_out` -> `co2_in`, carrier `material_co2_gas`, species `CO2`, phase `gas`, grade `co2_gas_25c`, unit kg/s.
- Synthesis also accepts AC at `ac_in` and H2 gas at `h2_in`, using the existing `h2_gas_delivery` grade. All three hydrogen storage kinds may supply it. No inter-store hydrogen transfer is introduced.
- Material routes have finite `mass_flow_capacity_kg_s` and zero configured mass loss. Wrong species, grade, endpoint, invented loss or direction is rejected.

Each production transaction reserves feed inventory, beginning-of-step post-loss H2, all typed pipes, product headroom, actual process electricity, phase-store discharge auxiliaries, electrical lines/station capacity and heater/cooler capacity before any live state is committed. Fuel cells and synthesis share the same finite H2 discharge budget. Same-step new H2 cannot pass directly through a charging store to a consumer, and charge/discharge remain mutually exclusive.

Chemical process AC and liquid/metal discharge auxiliaries may use wind/PV or finite electric storage. Fuel cells or turbine output cannot bootstrap these material processes. Existing electrolyzer and H2 charging provenance remains renewable-only. Atomic reservation is performed on scratch copies; failure publishes no partial flow or stock change.

Runtime first serves actual loads, then uses remaining wind/PV for products in stable equipment-ID order before ordinary storage charging. It does not proactively drain a battery to chase an unspecified product target. The optimizer may use eligible finite storage to meet an explicit product floor. Dispatch policy differs from optimization policy; their physical equations and constraints do not.

## Thermochemical accounting

Frozen molar masses in kg/kmol: H2 2.016, O2 31.998, H2O 18.015, N2 28.014, CO2 44.009, NH3 17.031, CH3OH 32.042. They derive from H 1.008, O 15.999, N 14.007, C 12.011.

Formation enthalpies at the stated phases, kJ/kmol: H2/O2/N2 zero; liquid H2O -285830; gaseous CO2 -393510; gaseous NH3 -45940; liquid methanol -238400. The frozen source-review documents identify the thermochemical references. These are not complete process performance calibrations.

- NH3 net reaction enthalpy: -45940 / 17.031 / 3600 = -0.749287247437679 kWh/kg product.
- Methanol net reaction enthalpy: (-238400 - 285830 + 393510) / 32.042 / 3600 = -1.133234851479655 kWh/kg product.
- Teaching process inputs: ammonia auxiliaries 0.25 kWh/kg and internal process heat 0.5 kWh/kg; methanol 0.15 and 0.6 kWh/kg. Both heater efficiencies are 0.95.
- Actual AC per kg is auxiliary + process heat / heater efficiency. Heater rating separately limits the latter component. Total rejected heat per kg is actual AC minus net reaction enthalpy. Internal process heat is not counted twice as an external energy input or a stored energy quantity.

Reference-state inventory and H/C/N/O conservation include finite source and retained product stocks. O2 venting/intake, liquid water release, H2 leakage, environmental phase heat and rejected heat are explicit boundaries. H2 LHV remains an indicator for actual hydrogen stock only, not hydrogen bound in NH3/CH3OH. Neither LHV nor exothermic reaction enthalpy is automatically available electricity or useful heat. No useful heat-export port is supplied by these chemical facilities.

The nine reference keys are H2O_liquid_25c, H2_gas_25c, H2_liquid_20k, H2_bound_lani5, O2_gas_25c, N2_gas_25c, CO2_gas_25c, NH3_gas_25c and CH3OH_liquid_25c. Signed reference enthalpy is legitimate; negative physical mass is not.

## Reporting and ledger migration

New aggregate report fields:

- Powers: `chemical_electric_mw`.
- Rates: `ammonia_produced_kg_s`, `methanol_produced_kg_s`, `nitrogen_withdrawn_kg_s`, `co2_withdrawn_kg_s`, `chemical_hydrogen_consumed_kg_s`, `chemical_water_released_kg_s`.
- Stocks: `ammonia_inventory_kg`, `methanol_inventory_kg`, `nitrogen_inventory_kg`, `co2_inventory_kg`.
- Residuals: `carbon_element_error_kg`, `nitrogen_element_error_kg`.

Per-device fields add `nitrogen_in_kg_s`, `nitrogen_out_kg_s`, `co2_in_kg_s`, `co2_out_kg_s`, `product_produced_kg_s`. Existing electric, water, heat and next-inventory fields remain. Source operating mode is `supply` only above the common material activity threshold 1e-10 kg/s; otherwise it is `idle`. Existing water mode behavior is preserved.

Historical `hydrogen_consumed_kg_s` remains fuel-cell consumption only. `hydrogen_discharged_kg_s` includes fuel cells and chemicals; `water_released_kg_s` is the total liquid boundary release. Stock fields and residuals are not integrated as rates.

Ledger version 3 contains exactly 43 fields: all 36 v2 fields plus seven cumulative fields: chemical_electric_mwh, ammonia_produced_kg, methanol_produced_kg, nitrogen_withdrawn_kg, co2_withdrawn_kg, chemical_hydrogen_consumed_kg and chemical_water_released_kg. It reconciles reaction counters, actual per-device stock, imports/exports, H/C/N/O, signed reference enthalpy and immutable host mass.

Public pure APIs in MaterialDispatch:

- `initial_energy(devices=[])`: current v3 observation-period anchor.
- `initial_energy_v2(devices=[])` and `initial_energy_v1()`: explicit frozen historical contracts.
- `validate_energy(ledger, devices=null)`: version-aware; `validate_energy_v2(...)`: strict frozen v2.
- `accumulate_energy(ledger, report, dt_s)`: version-aware; returns an empty dictionary on failure without input mutation.
- `bootstrap_from_legacy(old_ledger, devices)`: returns v2, preserving old counters in `legacy_v1_history` and anchoring actual current inventory once.
- `upgrade_ledger_v2_to_v3(ledger, devices)`: validates old v2, preserves its original opening/current/import/export/host/history/counters, changes ledger identity, and appends seven zeros. It does not reset or reimport inventory.
- `import_inventory_event(...)`, `remove_inventory_event(...)`: version-aware transactions; nonempty removal is invalid.
- `cumulative_electric_input_mwh(ledger)`: all material AC including historical v1 use; invalid input returns NAN.

Bootstrap/upgrade/event results contain `{valid, errors, ledger}`. Old saves below 17 bootstrap v1 -> v2 once, then upgrade v2 -> v3. Saves 17/18 validate frozen v2 and only upgrade. Current save 19 requires v3. Restore/undo/redo reload complete accounts without a construction import. Canonical numeric IDs survive JSON int-to-float conversion without weakening stock comparison.

## Optimizer and independent acceptance

Schema 12 permits optional `options.terminal_product_kg`, mapping canonical synthesis device IDs to finite nonnegative kg no greater than the actual device capacity. It defaults to `{}`. An explicit goal is a hard terminal lower bound; unavailable material/power/thermal service makes it infeasible, not free production. Existing supply-priority/strict-supply behavior is unchanged. Baseline runtime is not claimed to satisfy hydrogen or product terminal goals. There is no product price, sales objective or invented profit.

Schema-12 material totals contain exactly 27 numeric fields: the old 18, two phase-power counters and seven chemical counters. Independent Godot acceptance calls `Model.Dispatch.audit_optimization_result(original_request, result)`, not just Python's validation flag. It reconstructs every inventory recurrence from the original initial state and audited routes/flows. It verifies all next states, per-step physics, profile identities, cumulative ledger and terminal goals. A reported previous stock never becomes the authority for the next step.

Dimensioned material tolerance is 2e-6 absolute plus 2e-12 relative; at 1e9 kg this is about 0.002002 kg, not a 200 kg window. Reference cancellation allows 16 double-precision epsilons times gross opposing terms, not unlimited relative tolerance on historical throughput. General electrical audit retains its separate relative tolerance 2e-7. This is floating-point bookkeeping, not arbitrary precision. Raw legal inventories and decisions are never repaired to make a failed audit pass. Machine-level shadow recurrence boundary rounding is not a rewrite of solver or live stock.

## Focused evidence and limits

Actual logs in this directory establish:

- Chemical runtime physics: 2445 checks, zero failures, including 150 randomized shared fuel-cell/chemical cases with all three H2 stores and bounded routes/resources.
- 23 actual GLPK fixtures: 21 optimal, two explicitly infeasible. Godot independent cross-language replay and tampering: 1012 checks, zero failures.
- Four clean 100-step controls plus 16 adversarial results: 26 checks, zero failures. Balanced transfers of only 1e-6 kg per step between identical N2/CO2/NH3/CH3OH devices preserve fleet stock but are rejected by original-input recurrence at step 2.
- Ledger v3: 1339/0; frozen ledger v2: 692/0; phase-hydrogen runtime: 3622/0; phase-hydrogen GLPK replay: 345/0; legacy material catalog and replay: 163/0 each; CO2 replay: 140/0; collector replay: 88/0.
- Large-inventory legacy gas paired-stock replay: 2/0. A clean 1000-step case passes, while offsetting per-device drift below each local stock tolerance is rejected by anchored cumulative recurrence.
- Actual chemical optimization-controller integration: 19/0, including both explicit product targets.
- Full Python suite: 310/310 (278 legacy + 32 chemical). Twelve schema-11 physical payloads exactly match the captured pre-edit solver for steps, totals, initial states and model identity. This is targeted differential coverage, not a claim of identical diagnostic logs or all possible old topologies.

The acceptance index, source hashes, solver evidence and implementation-stage reproducibility notes are nonpublic provenance records, not files distributed in this repository. World/save/UI/full-regression/GUI records are separate. See FINAL_NATIVE_ACCEPTANCE_1004.md for the final scope and clean-clone fixture prerequisites.

This is a bounded teaching whole-facility model. It does not simulate pressure safety, catalyst kinetics, recycle/purge streams, startup trajectories, detailed thermofluid dynamics, vendor performance or industrial plant sizing. Feed purity and net stoichiometry are fixed assumptions. N2/CO2 preconditioning occurs outside the modeled boundary; products remain inside finite buffers. These limits are explicit rather than unimplemented behavior presented as supported.
