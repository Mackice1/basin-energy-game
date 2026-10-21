# Fixed-capacity joint electric/thermal GLPK dispatch backend

`dispatch_solver.py` uses Python 3.9+ standard-library code and a real GLPK
`glpsol` executable. It does not require a Python optimization package and does
not access the network. The application remains a radial active-power transport
teaching model with a stage-one fixed-grade hot-water service network,
**not AC/DC electrical power flow, hydraulics, dynamic water/steam simulation, unit commitment, a tariff
optimizer, or a capacity-expansion model**.

## Invocation

```sh
python3 tools/dispatch_solver.py \
  --input snapshot.json --output result.json \
  --glpsol /path/to/glpsol \
  --cancel-file /path/to/request.cancel
```

`--glpsol` and `--cancel-file` are optional. The executable defaults to `glpsol`
on `PATH`; it is called with an argument list and `shell=False`. Model and
machine-readable solution files live in a temporary directory and are removed
after solving. Output is written by atomic replacement. Input and output paths
should be unique for each application request. The caller must check the request
ID and scene revision before using any result. No simulation state is changed
by this process.

Creating the cancellation file cancels a running GLPK process within the normal
100 ms polling interval. SIGTERM/SIGINT also clean up the GLPK child. Cancellation
returns `cancelled`, `success: false`, and no steps. The caller should allow time
for this cleanup before forcibly killing Python. Killing Python with SIGKILL
alone cannot execute cleanup; if necessary, terminate its complete process group.

Exit codes are 0 for a validated schedule, 3 for timeout/cancellation without a
schedule, and 2 for other failures. A process that exits normally but reports
`feasible` is successful, but its full lexicographic optimum was not proven.
Always read the JSON rather than inferring status from exit code alone.

## Input

```json
{
  "devices": [
    {"id": 0, "kind": "wind", "params": {"rated_mw": 5}},
    {"id": 1, "kind": "station", "params": {"capacity_mw": 4, "loss_fraction": 0.01}},
    {"id": 2, "kind": "load", "params": {"demand_mw": 2, "priority": 10}},
    {"id": 3, "kind": "battery", "params": {"capacity_mwh": 10}, "state": {"energy_mwh": 5}}
  ],
  "links": [
    {"from": 0, "to": 1, "capacity_mw": 4, "loss_fraction": 0.01},
    {"from": 1, "to": 2, "capacity_mw": 4, "loss_fraction": 0.01},
    {"from": 1, "to": 3, "capacity_mw": 4, "loss_fraction": 0.01},
    {"from": 1, "to": -1, "capacity_mw": 4, "loss_fraction": 0.01}
  ],
  "steps": [
    {"time_s": 0, "dt_h": 1, "available_mw": {"0": 3}, "demand_mw": {"2": 2}},
    {"time_s": 3600, "dt_h": 1, "available_mw": {"0": 0}, "demand_mw": {"2": 2}}
  ],
  "options": {"terminal_soc_fraction": null, "strict_supply": false, "timeout_s": 30},
  "grid_capacity_mw": 4,
  "metadata": {"request_id": "unique-request", "scene_revision": 12, "start_time_s": 0}
}
```

- Device IDs are unique nonnegative integers, within exact JSON number precision.
  `-1` is the export grid and must not appear as a device.
- Supported devices and parameter defaults mirror `scripts/device_catalog.gd`:
  wind, PV, station, load, battery and the four schema-2 thermal kinds documented below.
  Parameters may be full defaults or partial
  overrides; unknown parameters are rejected. The caller supplies already
  computed AC-terminal renewable availability, so this backend does not evaluate
  weather, wind curves or PV conversion. It validates generator parameter types,
  ranges and curve shape, but physical wind-curve Cp validation belongs to the
  source model (`energy_model.gd`). Availability exceeding nameplate is rejected.
- Each leaf has at most one station attachment. Station rings, station-to-station
  links, duplicated links, wrong directions, incompatible ports and missing
  endpoints are rejected as a whole. Disconnected devices are allowed: their
  generation is curtailed and their demand is unmet, unless strict supply makes
  the problem infeasible. A battery cable is bidirectional regardless of the
  legal orientation in which it was created.
- Each schema-1 step is a contiguous interval beginning at `time_s` with strictly positive
  `dt_h` (schema-2 pause semantics are documented below). Its `available_mw` object must include exactly every wind/PV ID and its
  `demand_mw` object exactly every load ID, as string keys. Empty objects are valid
  when there are no corresponding devices. Powers are piecewise constant.
- The initial battery state is fixed to its supplied `state.energy_mwh`. If state
  is omitted, `capacity_mwh * initial_soc` is used. Catalog SOC limits are 0 and 1;
  no separate minimum-SOC or maximum-SOC parameter exists in this version.
- `terminal_soc_fraction`, when non-null, imposes a floor on **every battery** at
  the end of the horizon, including disconnected batteries. It never changes
  their initial energy. `strict_supply` fixes all unmet demand to zero. Neither
  constraint is silently relaxed when infeasible.
- Timeout is one shared wall-clock budget across all objective stages, in
  `(0, 3600]` seconds, default 30. GLPK also receives its own time limit.
- `horizon_hours`, `step_minutes`, and `load_multiplier` are allowed numeric UI
  annotations in `options`; the backend uses the explicit steps and loads as
  authoritative and does not apply the multiplier again.
- `metadata` is echoed unchanged for request correlation. Limits: 64 MiB CLI
  input, 2,000 devices, 10,000 steps, and 300,000 decision variables. Booleans are
  not accepted as numeric parameters; NaN, infinity, duplicate JSON keys,
  duplicate device IDs, negative powers and invalid schemas are rejected.

## Network and storage constraints

Each electrical path is generator → its attached station → load/battery/boiler/explicit grid,
or battery → its attached station → load/boiler. A path decision `x` is source-terminal MW:

1. Incoming line sending-end flow is `x`; station receives `x * (1 - line_loss)`.
2. The station capacity limits the **total arriving/input MW**.
3. Outgoing line sending-end flow is station input times `(1 - station_loss)`.
4. The load, charging battery or grid receives that outgoing flow times
   `(1 - outgoing_line_loss)`.

All path uses share line capacities; the grid export limit is shared across all
stations. There is no implicit grid connection, no grid import, no battery export
and no battery-to-battery transfer. All capacities remain fixed.

For each battery and interval:

```text
E_after_decay = E_before * exp(-self_discharge_per_h * dt_h)
E_end = E_after_decay
        + (charge_efficiency * charge_mw
           - discharge_mw / discharge_efficiency) * dt_h
0 <= E_end <= capacity_mwh
charge_mw <= charge_rating * mode
discharge_mw <= discharge_rating * (1 - mode)
mode is binary
```

The binary mode prevents simultaneous charge/discharge; it is not approximated
by a throughput penalty. Charge/discharge are AC-terminal powers. Self-discharge
occurs before charging/discharging, matching the current one-step model.

## Objective and status

For electric-only snapshots, three GLPK solves establish a lexicographic objective, fixing each completed
stage's objective before starting the next:

1. Minimize sum of `unserved_mw * dt_h * (1001 - load_priority)`.
2. Maximize delivered export MWh while retaining stage 1's optimum.
3. Minimize battery AC throughput, `charge_mwh + discharge_mwh`, while retaining
   both earlier optima.

The first objective is weighted unmet energy, not the greedy policy's absolute
priority ordering. Smaller priority values receive larger weights. The last
objective avoids gratuitous storage use. Curtailment is reported rather than
assigned an artificial economic benefit: surplus energy is not charged merely
to hide curtailment or dissipated by extra cross-period cycles. These are transparent
teaching priorities, not market prices or a monetary-profit claim. Forecast
optimization may use storage earlier than a one-step greedy policy. Stage 2
favors export over charging that cannot improve future load service; stage 3
charges only when necessary for the earlier objectives or a terminal SOC floor.

- `optimal`: all required stages (three electric-only, four joint) reached an optimum and the schedule passed audit.
- `feasible`: a feasible incumbent passed audit, but not all three stages were
  proven optimal. `termination_reason` and `warnings` explain why.
- `infeasible`: GLPK proved no schedule satisfies the hard constraints. No steps.
- `timeout`: the shared limit expired without a feasible schedule. No steps.
- `cancelled`: cancellation was requested. No steps.
- `error`: bad input, missing/broken solver or failed validation. No steps.

`success` is true only for independently validated `optimal`/`feasible` schedules.
`optimal` is false for every incomplete solve. No schedule is fabricated from
zero-filled, missing, infeasible or malformed GLPK output. If a later objective
stage cannot finish, the earlier feasible incumbent can be returned; it is still
subject to the full independent audit.

## Output

Top level includes `schema_version`, `status`, `success`, `optimal`, `message`,
`errors`, `warnings`, `metadata`, `elapsed_s`, `solver_invoked`, `objective`,
`solver_stages` (bounded diagnostic logs), `validation`, `steps`, `totals`,
`initial_states` and `final_states`.

Each successful step includes:

- `time_s`, `dt_h`, `dt_s`
- `wind_mw`, `pv_mw`, `available_mw`, `generated_mw`, `produced_mw`
- `demand_mw`, `served_mw`, `unserved_mw`
- `charge_mw`, `discharge_mw`, `energy_mwh`, `soc`
- `export_mw` (alias `delivered_mw`), `curtailed_mw`, `loss_mw`
- `line_loss_mw`, `station_loss_mw`, `storage_conversion_loss_mw`,
  `self_discharge_mwh`, `storage_loss_mw`, `total_loss_mw`
- `devices` keyed by stable ID, `lines` in input order, `path_flows`, `next_states`
- `balance_error_mw`, `energy_balance_error_mwh`, `valid`, `status`, `optimal`

`energy_mwh` is total **end-of-step** stored energy, and aggregate `soc` is
capacity-weighted, not an arithmetic average. Both are zero without batteries.
Per-battery fields include beginning energy, post-self-discharge energy, ending
energy, `next_energy_mwh` alias, SOC, mode, charge/discharge and storage losses.
Electric `next_states` and `final_states` use `{id: {"energy_mwh": value}}`; thermal
inventories use `energy_mwhth` as documented below.

`loss_mw` is network (line + station) loss, consistent with existing dispatch.
Storage losses are separate; `total_loss_mw` includes them. This avoids counting
storage efficiency loss twice in terminal-power balance:

```text
available + discharge = curtailment + served + charge + boiler_electric + export + network_loss
```

`totals` integrates power fields into MWh using actual step durations. It also
contains initial/final energy, final SOC, duration and weighted unmet energy.

Before success, raw solver decisions are checked for completeness, finiteness,
bounds, integrality and constraint residuals. An independent physical pass then
reconstructs flows from directed line endpoints and audits source/load/station
balances, sending-end line caps and losses, station incoming caps, grid export,
battery mode and power bounds, fixed initial energy, energy recurrence, SOC,
terminal floors, and total power/energy balances. It reports `validation.valid`
and maximum residual, with absolute tolerance 2e-6 and relative tolerance 2e-7.
The backend never applies state itself; application-side correlation and
validation remain necessary before committing a result.

## Tests

```sh
PATH=/path/to/glpk/bin:$PATH python3 -m unittest discover \
  -s tests -p test_dispatch_solver.py -v
```

The suite exercises hand-computable dispatch, multi-step storage, losses and
network bottlenecks, explicit export connection, disconnected devices, weighted
SOC/self-discharge, hard terminal/strict-supply infeasibility, mutually exclusive
battery modes, invalid inputs, missing GLPK, real-process timeout, cancellation,
metadata correlation and CLI JSON output. Real-solver tests are skipped if GLPK
is not installed; failure-contract tests still run.


## Schema 2: joint electric/thermal stage one

This is implemented in `dispatch_solver.py` and exercised with **real GLPK** in
`tests/test_thermal_dispatch_solver.py`; it is not a post-processed electric-only
schedule. `electric_boiler`, `thermal_store`, `heat_exchanger`, and `heat_demand`
share the same mixed-integer problem with the original electricity network.
A thermal snapshot **must** contain `"schema_version": 2`. Legacy electric-only
snapshots may omit the schema or use 1; output is always schema 2. Unknown schema
versions, thermal kinds/profiles/parameters/state keys, and invalid thermal
routes fail the entire snapshot before launching a solver. Missing or failing
GLPK never causes a thermal scene to fall back to the old electric model.

Thermal device dictionaries accept `model_profile: "thermal_stage1_v1"` and
`model_profile_version: 1`; omitted profile fields mean these immutable defaults.
An explicitly different profile/version is rejected. The supported profiles are
fixed hot-water **service energy** grades, not steam or freely edited temperatures:

- `hw_primary_90_60`: water-equivalent 90/60°C boiler output, storage charge/discharge,
  exchanger hot side.
- `hw_secondary_70_40`: water-equivalent 70/40°C exchanger cold side and heat demand.

The implied circulating water and auxiliaries are included in device equivalent
efficiencies. A heat edge represents a paired supply/return service boundary,
not a hydraulic mass-flow pipe. Storage is an ideal stratified/two-zone equivalent
inventory with a fixed quality; SOC is never interpreted as tank temperature.
There is no water billing, pressure, level, steam/turbine, or cold-start model.
Both exchanger approach differences are 20 K and must be >= `min_approach_k`.
Default 5 K and all equipment defaults are teaching assumptions, not vendor
ratings or engineering approval limits.

### Device defaults and state

```text
electric_boiler:
  rated_electric_mw=2, thermal_efficiency=.98
thermal_store:
  capacity_mwhth=4, charge_mwth=2, discharge_mwth=2,
  charge_efficiency=.98, discharge_efficiency=.98,
  self_discharge_per_h=.002, initial_soc=0
  state={energy_mwhth: ...}
heat_exchanger:
  capacity_mwth=2 (hot-side input rating), transfer_efficiency=.98,
  min_approach_k=5
heat_demand:
  demand_mwth=1, priority=10
```

Efficiencies are in (0,1]; positive ratings/capacities are bounded by 10,000 MW/MWth
and 100,000 MWhth; storage power and demand can be zero. Self-discharge is in
[0,1]/h, initial SOC in [0,1], and priority is an integer in [0,1000]. Unknown
parameters, nonfinite numbers, boolean-as-number values and cross-carrier state
fields are rejected. A supplied `state.energy_mwhth` overrides `initial_soc`;
initial SOC is only a construction default. Batteries retain `energy_mwh`.

### Typed links and input steps

New heat links must contain **exactly** `from`, `to`, `from_port`, `to_port`,
`carrier`, `unit`, `grade_id`, `capacity_mwth`, and `loss_fraction`. They cannot
contain electrical capacity. Supported routes are:

```text
boiler.heat_out -> exchanger.hot_in       primary
boiler.heat_out -> thermal_store.heat_in   primary
thermal_store.heat_out -> exchanger.hot_in primary
exchanger.warm_out -> heat_demand.heat_in  secondary
```

Each heat edge has `carrier="heat_water"`, `unit="MWth"`, and
`loss_fraction=0`. Nonzero line heat losses are deliberately unsupported in this
fixed-temperature version. Duplicate same-port edges, self connections, reversed
flows, direct boiler-to-demand, storage-to-storage, serial exchangers and cycles
are rejected. Fan-out/fan-in is supported; all branches share actual node ratings
and balance equations, so no branch gets a copy of an upstream output.

A boiler's electric edge is `station.out -> boiler.ac_in`, with explicit
`from_port`, `to_port`, `carrier="electricity_ac"`, `unit="MW"`; voltage is
`AC_BUS`. Old implicit electrical ports remain valid only for old electrical
devices. The one-station-attachment rule only applies to a boiler's electrical
connection, and does not block its thermal connections.

Every step contains `heat_demand_mwth` with exactly all `heat_demand` IDs as string
keys. Boiler electric consumption must **not** be included in external
`demand_mw`; it is endogenous. Constant demand or caller-prepared thermal time
series can be represented in this backend input. This does not claim the game
can import thermal CSV; the initial game UI explicitly supports constant thermal
demand only, without reusing the renewable `power` CSV channel.

A complete direct-heating example:

```json
{
  "schema_version": 2,
  "devices": [
    {"id":0,"kind":"wind","params":{}},
    {"id":1,"kind":"station","params":{"capacity_mw":10,"loss_fraction":0}},
    {"id":2,"kind":"electric_boiler","params":{}},
    {"id":3,"kind":"heat_exchanger","params":{}},
    {"id":4,"kind":"heat_demand","params":{}}
  ],
  "links": [
    {"from":0,"to":1,"capacity_mw":10,"loss_fraction":0},
    {"from":1,"to":2,"from_port":"out","to_port":"ac_in","carrier":"electricity_ac","unit":"MW","voltage_level":"AC_BUS","capacity_mw":10,"loss_fraction":0},
    {"from":2,"to":3,"from_port":"heat_out","to_port":"hot_in","carrier":"heat_water","unit":"MWth","grade_id":"hw_primary_90_60","capacity_mwth":2,"loss_fraction":0},
    {"from":3,"to":4,"from_port":"warm_out","to_port":"heat_in","carrier":"heat_water","unit":"MWth","grade_id":"hw_secondary_70_40","capacity_mwth":2,"loss_fraction":0}
  ],
  "steps":[{"time_s":0,"dt_h":1,"available_mw":{"0":2},"demand_mw":{},"heat_demand_mwth":{"4":2}}],
  "options":{"heat_service_weight":1,"terminal_heat_soc_fraction":null,"strict_supply":false,"timeout_s":30}
}
```

Schema-2 `dt_h=0` is a pause: every exchange is fixed to zero, storage inventory
is unchanged, and there is no self-discharge. Instantaneous unmet demand remains
visible but integrates to zero; `strict_supply` applies only to positive-duration
intervals. Schema 1 preserves the historical strictly positive-duration contract.

### Joint physics and objective

Boiler activity `P` is delivered electric terminal power, bounded by its electric
rating. Its actual outgoing heat equals `.thermal_efficiency * P`; there is no
free disposal variable. Exchanger activity is hot-side input, bounded by its
rating, with outgoing heat exactly `.transfer_efficiency * input`.
`transfer_efficiency` is energy delivery fraction, **not effectiveness epsilon**;
no epsilon-NTU or hydraulic flow calculation is implemented. All power and energy
balances use these port definitions exactly once.

Thermal storage follows the battery's decay-first convention:

```text
E_decay = E_before * exp(-self_discharge_per_h * dt_h)
E_end = E_decay + (charge_efficiency * Q_charge - Q_discharge / discharge_efficiency) * dt_h
Q_charge <= charge_mwth * binary_mode
Q_discharge <= discharge_mwth * (1 - binary_mode)
0 <= E_end <= capacity_mwhth
```

Storage charge/discharge are strictly exclusive, even for a merely feasible
incumbent. Disconnected storage still decays. Inventory/headroom limits are
implied by this recurrence plus the binary mode and independently checked again.
`terminal_heat_soc_fraction`, when non-null, is an independent end-of-horizon floor
for every thermal store; `terminal_soc_fraction` still applies only to batteries.
`strict_supply` requires both electricity and heat service for active intervals.
No terminal/strict constraint is silently relaxed.

Four separately solved lexicographic stages are used in thermal scenes:

1. Minimize `sum dt_h * [(1001-priority_e)*unserved_e + heat_service_weight*(1001-priority_h)*unserved_h]`.
2. Preserve stage 1, maximize delivered renewable export MWh.
3. Preserve 1-2, minimize battery electric and thermal-store port throughput;
   each has explicit numerical weight 1 in its respective energy unit.
4. Preserve 1-3, minimize boiler electrical activity plus exchanger hot-side
   activity; each has explicit numerical weight 1. This strict final level is a
   reproducible tie-break, not an unexplained big-M or approximate epsilon term.

`heat_service_weight` defaults to 1 and must be finite and positive. It is a
**teaching service weight**, not electrical/thermal economic equivalence, not a
price and not a guarantee of strict priority ordering. An empty/full store with
no future service or terminal purpose does not make a boiler consume energy.
No heat outlet means no boiler input. Earlier objective optima are locked before
subsequent stages; raw decisions are checked against those locks too.

### Thermal reports and independent audit

`step.thermal` includes `demand_mwth`, `served_mwth`, `unserved_mwth`,
`boiler_heat_mwth`, `charge_mwth`, `discharge_mwth`, `energy_mwhth`, `soc`,
`network_loss_mwth`, `exchanger_loss_mwth`, `storage_conversion_loss_mwth`,
`storage_loss_mwth`, `self_discharge_mwhth`, `balance_error_mwth`, and
`energy_balance_error_mwhth`. Separate electric fields are `boiler_electric_mw`
and `boiler_conversion_loss_mw`. Original electrical totals retain their meanings;
`total_loss_mw` is electric network plus electric-storage loss. Do not add boiler
conversion loss again to the electrical network balance.

Per-thermal-device details include `input_mwth`, `output_mwth`, fixed profile,
and the relevant activity/loss/state fields. Boiler details include
`boiler_electric_mw`, `boiler_heat_mwth`, `boiler_conversion_loss_mw`; exchanger
includes `hot_input_mwth`, `warm_output_mwth`, `exchanger_loss_mwth` and all four
fixed temperatures. Storage includes `energy_before_mwhth`,
`energy_after_self_discharge_mwhth`, `energy_mwhth`, `next_energy_mwhth`, SOC,
`charge_mwth`, `discharge_mwth`, `mode`, `mode_binary`, and loss fields.

Heat lines report `sent_mwth`, `received_mwth`, `loss_mwth`, `capacity_mwth` and
fixed grade. Electric lines report their existing MW fields. `next_states`,
`initial_states` and `final_states` contain the correct per-kind state object:
`{id: {energy_mwh: ...}}` or `{id: {energy_mwhth: ...}}`.

`totals.thermal` integrates MWth into MWhth using actual durations and includes
`initial_energy_mwhth`, `final_energy_mwhth`, `final_soc` and
`weighted_unserved_mwhth`. `totals.boiler_electric_mwh` and
`totals.boiler_conversion_loss_mwh` remain separate. Combined stage-1 objective is
also exposed as `totals.weighted_unserved_service_energy` with the explicit
teaching weight; it is not labeled all-electric MWh.

Every incumbent is validated before acceptance: raw completeness/finiteness,
variable bounds, binaries and LP residuals; then `validate_physical_decisions`
reconstructs flows from raw decisions and original topology/parameters,
**without trusting the LP's path loss coefficients**. `validate_schedule`
independently reconstructs per-port balances, device conversion, both exchanger
approaches, typed grades, capacities, inventory recurrence, binary exclusivity,
separate terminal floors and dimensioned state fields. It recomputes aggregate
power/energy residuals rather than trusting reported zeros. Tolerance remains
abs=2e-6, rel=2e-7, applied separately to each dimensioned comparison. The result
records `validation.raw_decisions_validated=true` only after this process.

### Verified acceptance coverage

```sh
PATH=/path/to/glpk/bin:$PATH python3 -m unittest discover \
  -s tests -p 'test_*dispatch_solver.py' -v
```

The existing 19 tests are preserved unchanged; 25 thermal-specific tests cover:
A direct 2 MW -> 1.96 MWth -> 1.9208 MWth service; B shared supply and weighted
competition; C two-hour four-conversion storage -> 1.84473632 MWth service;
D isolated exact exponential decay/substeps; empty/full/pause/mutual exclusion;
fan-out/fan-in, unpowered boiler with charged storage, exchanger/line bottlenecks,
no useless heat sink, electric losses and true duration integration, battery
powering a boiler, separate terminal floors, strict/terminal infeasibility,
restored state trajectories, tampered flows/states/grades/binaries/temperatures,
a deliberately faulty LP coefficient rejected by the independent raw physical
audit, feasible-unproven status, earlier validated incumbent after later-stage
timeout, malformed input, missing/failing executables, actual-process timeout and
cancellation, and a thermal CLI JSON round-trip. Game UI/save/runtime acceptance is owned by its separate tests;
these backend checks do not by themselves claim graphical acceptance.
