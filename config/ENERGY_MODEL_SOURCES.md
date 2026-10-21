# BASIN energy model: definitions, assumptions and primary references

Version: rebuilt model, 2026-10-15. Runtime: Godot 4.6.3. Implementation is `scripts/energy_model.gd`; standalone tests are `tests/test_energy_model.gd` and `tests/test_wind_curve.gd`.

This is an educational steady-state active-power transport model. It does not calculate voltage, current, frequency, reactive power, phase angle, protection coordination, dynamic stability, turbine wakes, or terrain shading. It is unsuitable for engineering design or bankable yield estimates. Values not explicitly tied to a reference below are editable scenario assumptions.

## Public API and units

The model extends `RefCounted`; its four public functions can be called on the preloaded script or an instance:

- `defaults(kind)` returns a fresh dictionary for `wind`, `pv`, or `station`.
- `validate(kind, params)` returns an array of error strings. An empty array means accepted. Partial parameter dictionaries inherit defaults. Unknown fields, nonnumeric and nonfinite values, out-of-domain values, and inconsistent wind specifications are rejected.
- `generation(kind, params, weather)` returns AC terminal power `mw`, its `source`, validity/errors, and model-specific diagnostics.
- `solve(devices, links, weather, direct={})` returns a fresh network report and does not mutate any input.

Power is MW throughout except user-supplied wind `power_curve_kw` points, whose electrical power is explicitly kW; wind speed is m/s; distances are m; irradiance is W/m²; temperatures are °C; air density is kg/m³. Fractions and efficiencies are dimensionless, not percentages. Converting a power sample to energy is the caller's responsibility: MWh = MW × elapsed seconds / 3600. There is no implicit time integration here.

Device inputs have a nonnegative integer stable `id`, `kind`, and `params`. `x` and `z` may be present but have no electrical effect. They do not silently introduce distance losses or resource effects. Device IDs survive deletion/reordering and JSON numeric roundtrips; array positions are not IDs.

Weather keys:

- `wind_speed_mps`: wind at turbine hub height by default; default 0.
- `wind_height_m`: optional measurement reference height. When present, hub wind = measured wind × (hub height / reference height)^shear_exponent. No correction is applied unless the reference height is explicit. The default exponent 0.14 is a scenario approximation, not a calibrated site parameter.
- `air_density_kgm3`: default 1.225. No hidden altitude correction.
- `irradiance_wm2`: plane-of-array irradiance, not GHI; default 0. It must already include the caller's intended orientation/shading effects. The model does not infer solar geometry from a clock.
- `air_temp_c`: ambient air temperature, default 25.
- `pv_wind_speed_mps`: array-local wind for Faiman cooling; falls back to `wind_speed_mps` if absent. For measured data at different heights, supply this field explicitly; the model does not claim hub and array-local wind are interchangeable.
- `source`: provenance string, default `weather`.

Direct inputs are keyed by `str(device_id)` and contain `{mw, source}`. They represent already-converted AC terminal power. A present direct sample, including exactly zero, overrides weather for that generator only. It is capped at the wind generator rating or PV inverter rating. Excess is separately reported as `nameplate_clipped_mw`; it is not included in available generation or network curtailment. Invalid direct data produces a visible error and zero output rather than silently falling back. The caller owns CSV selection, time interpolation, range policy and source precedence before constructing these inputs.

## Wind: default constrained approximation or a custom electrical curve

Reference sizing follows the NREL 5-MW reference turbine: 5 MW, rotor diameter 126 m, hub height 90 m, cut-in 3 m/s, rated speed 11.4 m/s, cut-out 25 m/s. The reference is a research turbine, not a manufacturer's warranted device. See Jonkman et al., *Definition of a 5-MW Reference Wind Turbine for Offshore System Development*, NREL/TP-500-38060, Table 1-1: [official report](https://docs.nrel.gov/docs/fy09osti/38060.pdf).

Wind parameters include `reference_air_density_kgm3` (0.5–2.0 kg/m³, default 1.225) and `power_curve_kw` (default `[]`). Missing fields merge these defaults, so old nine-parameter wind devices and templates retain their previous outputs. The reference density describes the density at which the selected curve is specified; actual weather `air_density_kgm3` is separate and still defaults to 1.225.

With an empty curve, the implementation deliberately uses the previous transparent cubic approximation, not digitized OpenFAST results:

- Rotor incident power: `K = 0.5 * rho * pi * (D/2)^2 * v^3 / 1e6` MW.
- At cut-in ≤ v < cut-out: preliminary electric power = `Pr * (v³ - vci³)/(vr³ - vci³) * rho/reference_air_density_kgm3`.
- Output = min(preliminary power, Pr, K × Cp_max × drivetrain_efficiency), bounded below by zero.
- Below cut-in and at or above cut-out, output is zero.

Defaults use `Cp_max=0.49` and a lumped drivetrain/generator efficiency of `0.944`. These are explicit simplified parameters; they are not an independent replay of the reference turbine controller. Changes to diameter, rating, efficiency and rated speed must remain mutually feasible.

Validation checks that electric rated power requires no more than `Cp_max` after drivetrain losses, and `Cp_max ≤ 16/27`. The latter is the ideal actuator-disk Betz limit described by the [U.S. Department of Energy wind guide](https://www.energy.gov/cmei/systems/windexchange/small-wind-guidebook). Rotor radius must also be below hub height.

Why this is an interior-curve check: below rated at reference density, aerodynamic Cp is proportional to `1 - (vci/v)^3`, which is monotone increasing. On the electrical plateau, Cp decreases as `v^-3`. Therefore the rated point bounds the complete analytic interior at reference density. Runtime kinetic-power/Cp capping additionally enforces this bound for other densities. A straight-line interpolation between feasible endpoints can exceed a cubic kinetic-power envelope; the empty-curve branch does not use such chords. The tests also sample 2,199 interior wind speeds and several densities.

### Custom electrical power curve

A nonempty `power_curve_kw` array replaces the cubic power shape. Each point is exactly `{ "wind_mps": number, "power_kw": number }`. There must be 2–256 points; wind speeds are finite, strictly increasing and within 0–100 m/s; electrical power is finite, nonnegative and no greater than `rated_mw * 1000`. Power need not be monotone. Unknown point fields and malformed values are rejected, not sorted, repaired or coerced. `rated_speed_mps` remains a positive bounded legacy parameter but does not shape or constrain the custom curve; its cutoffs only require `cut_in_mps < cut_out_mps`. Rotor/hub geometry, efficiencies and Cp bounds still apply.

At the hub-height wind speed:

1. Output is zero below cut-in and at or above cut-out, even when the curve contains a nonzero point there.
2. Within that operating interval, output is zero outside the first/last point speed. Endpoints are inclusive. There is no extrapolation or implicit rated plateau.
3. Inside the point range, interpolate electrical kW linearly, convert to MW, multiply by actual density / reference density, and cap at the electrical nameplate rating.

The curve is already electrical terminal power. Drivetrain efficiency is used to infer aerodynamic Cp for validation and reporting; it is **not multiplied into electrical output a second time**. The simple density ratio is an explicit educational approximation, not a claim to implement an IEC density-normalization procedure or turbine control model.

Cp is a **strict validation rule**, not a runtime adjustment to custom points. Every point and every complete line segment, including portions outside the operating cutoffs, must satisfy `P_electric / (0.5 * rho_reference * A * v^3 * drivetrain_efficiency) <= Cp_max <= 16/27` (with a 1e-9 Cp floating-point tolerance). A curve that violates this rule is invalid and cannot generate power; it is never silently clipped to the Cp envelope.

For the full-segment proof, let a segment be `P(v)=a*v+b`. Apart from positive constant factors, `Cp=P(v)/v^3`, with derivative `(-2*a*v-3*b)/v^4`. Its extrema over a positive-wind segment occur at endpoints or the sole stationary point `v=-3*b/(2*a)` when that point lies strictly inside. All are evaluated analytically. A positive linear rise starting at `(0,0)` has unbounded Cp as wind approaches zero and is rejected; include a zero-power interval before positive output. A zero-power segment through zero is valid. This validation catches infeasible interiors even when both endpoints pass.

Multiplying electrical power and incident kinetic power by the same actual/reference density ratio preserves the validated Cp. Nameplate clipping can only reduce Cp, so no additional runtime Cp clipping is needed. Diagnostics include `curve_mode`, `reference_air_density_kgm3`, `reference_curve_mw` (after operating cutoffs), `density_adjusted_mw`, `curve_in_range` and `nameplate_clipped_mw`. Custom density clipping obeys `density_adjusted_mw = generated_mw + nameplate_clipped_mw` and is excluded from the downstream network balance.

An explicit direct electrical-power sample, including zero, still overrides the curve and all weather corrections. Invalid direct input does not fall back to the curve. Device parameter validation remains required for either source. Nested curves survive ordinary dictionary deep-copy and JSON save/restore without a separate external file.

## PV: Faiman temperature, explicit DC/AC conversion

The temperature model follows the form documented by [Sandia PVPMC, Faiman Module Temperature Model](https://pvpmc.sandia.gov/modeling-guide/2-dc-module-iv/module-temperature/faiman-module-temperature-model/):

`T_module = T_air + POA / (U0 + U1 * local_wind)`

Default U0=25 W/(m²·K) and U1=6.84 W·s/(m³·K) are the combined fitted coefficients reported there for the studied module constructions. They are not universal mounting coefficients.

A separate module-to-cell correction is applied: `T_cell = T_module + (POA/1000) * cell_delta_c_at_1000`. Its form follows [Sandia PVPMC, Sandia Cell Temperature Model](https://pvpmc.sandia.gov/modeling-guide/2-dc-module-iv/cell-temperature/sandia-cell-temperature-model/). The default 3°C offset is an editable scenario assumption.

DC power uses a linear irradiance/temperature relationship:

`gross_DC = DC_STC_rating * (POA/1000) * max(0, 1 + gamma * (T_cell - 25))`

The irradiance and temperature normalization follow the standard form discussed by [Sandia PVPMC, PVWatts](https://pvpmc.sandia.gov/modeling-guide/2-dc-module-iv/point-value-models/pvwatts/). This implementation is not the full PVWatts algorithm: it omits low-light correction, spectral effects, angle-of-incidence effects and detailed current-voltage behavior. The default gamma=-0.004 /°C is a scenario assumption. The STC DC rating is a reference condition, not a hard cap: cold conditions or irradiance above 1000 W/m² can increase DC output.

Default DC STC capacity is 1.2 MW, inverter AC capacity 1 MW, DC system loss 2%, and constant inverter efficiency 96%. After DC losses, conversion and inverter clipping are separated explicitly:

- `DC = gross_DC * (1 - dc_loss_fraction)`
- `inverter_loss = DC * (1 - inverter_efficiency)`
- `AC = min(inverter_capacity, DC - inverter_loss)`
- `clipping = DC - inverter_loss - AC`

Thus `DC = AC + inverter_loss + clipping`. All network generation is the resulting AC, so conversion losses are not counted again in transmission losses. Constant efficiency is a simplification; there is no startup threshold or part-load inverter curve.

## Network, capacities and accounting

Only wind/PV → station → grid routes are legal. Grid endpoint is `-1`, with a fixed 4 MW receiving/export limit. No generator can connect directly to grid, and stations do not generate power. Incoming links, station throughput and outgoing links all have independent limits.

A link has `from`, `to`, `capacity_mw`, `loss_fraction`. Link capacity applies at its sending terminal. Station capacity applies at its receiving terminal before station loss. Station output = input × (1-loss_fraction). All losses are explicitly multiplied once. Defaults are 4 MW/1% for stations and omitted link fields; real engineering line and transformer losses are not inferred from these illustrative values.

Duplicate ordered endpoint pairs are rejected after the first valid connection. They are not automatically treated as parallel circuits. Invalid or missing endpoints, wrong connection types, malformed/nonfinite values and losses outside [0,1) are diagnosed. A zero-capacity line is valid but carries no flow.

Dispatch is a linear program over complete generator → station → grid paths. A primal simplex implementation with Bland's rule maximizes delivered grid MW subject to shared generator budgets, each line capacity, each station input capacity and the global grid limit. Each path's constraint coefficients include precisely its upstream retention factors. This permits rerouting when greedy assignment would strand a generator. It does not impose equal/fair dispatch or electricity-market priorities. Different equally optimal dispatches can differ per device, while total delivered MW is unchanged. A defensive iteration limit reports `optimal=false` and a warning rather than pretending optimality.

Only accepted source power is dispatched. Disconnected generation and downstream bottlenecks are curtailed before entering the network, so they do not create fictitious line losses. Source power sent onto a complete route is conserved as grid delivery plus line/station losses. There is no storage or modeled demand other than grid export.

The report provides:

- `devices[str(id)]`: generation/source/model diagnostics, `sent_mw`, `delivered_mw` (attributable grid delivery), `curtailed_mw`, input/output/loss, validity/errors and utilization.
- Generator `loss_mw` includes all downstream route losses attributable to that generator. Station `loss_mw` includes that station's own losses. Do not sum both device categories to obtain total loss; use the report total or sum line losses plus station losses.
- `lines`: one entry per original link, preserving input order, with validity/reason, sent/received/loss MW, capacity, utilization and active state.
- `generated_mw`: available AC after generation/inverter/nameplate limits, before network curtailment.
- `delivered_mw`, `curtailed_mw`, `line_loss_mw`, `station_loss_mw`, `loss_mw`.
- `balance_error_mw = generated - delivered - curtailed - loss`, expected near floating-point zero.
- `nameplate_clipped_mw`: direct power or density-adjusted custom-curve power above device nameplate, outside the network balance.
- `errors`, `warnings`, `optimal`, `grid_capacity_mw`; short balance aliases and `net_mw=delivered_mw` for clients.

PV conversion/DC losses and clipping are available in generator diagnostics but are outside the network balance, whose starting point is AC generation. `connected` means a valid adjacent connection exists; it does not promise a complete route or nonzero transmission. Inspect delivered/curtailed power and line validity for operational status.

## Reproducible verification

From the project directory:

`godot --headless --path . --script tests/test_energy_model.gd`

The pure suite checks default/invalid parameters, rated/cut-in/cut-out behavior, wind curve interior Cp, density and height behavior, Faiman values and PV heat/cooling response, DC/inverter accounting, precedence including direct zero, malformed topology, duplicate links/IDs, grid/station/line capacity and exact serial losses. It includes an adversarial rerouting topology and 120 seeded random networks; every random case checks capacities, conservation, JSON roundtrips and order-independent maximum total delivery. This verifies implementation consistency, not real-world calibration or full application behavior.

Custom-curve regression command:

`godot --headless --path . --script tests/test_wind_curve.gd`

This adds schema and numeric-boundary checks; exact interpolation and no-extrapolation checks; analytic interior-Cp adversarial cases; near-zero and densely sampled seeded segments; reference/actual density separation; electrical power not double-converted; direct-input precedence; clipping and network conservation; old-formula equality over 1,505 speed/density pairs; and dictionary/JSON/save-validator/undo-snapshot compatibility.
