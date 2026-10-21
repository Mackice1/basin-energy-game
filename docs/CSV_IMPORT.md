# CSV data import

The import module accepts measured/forecast device power or one weather variable at a time. It is a deterministic input layer, not an interpolation or data-cleaning tool. It never assigns data to a device, edits simulation state, saves files, or adds output itself. The scene/controller owns application, replacement, undo, persistence, and the source-priority decision.

## In-game workflow

1. Open **CSV Import** and choose a UTF-8 CSV (maximum 8 MiB, 100,000 data rows). Comma, semicolon, and tab separators are supported. The first record must contain unique, nonempty column headers.
2. Choose the target field: direct power, wind speed, irradiance, or ambient temperature.
3. Select an existing device. Weather may instead target **Global weather**. Direct power always requires one device ID.
4. Map the time and value columns. Select the time and value units explicitly. Column names and numerical magnitudes do not silently determine units.
5. Click **Preview**. The preview shows the binding, converted units, sample count, time/value ranges, source filename/hash, and first six converted samples.
6. Click **Apply import** to commit, or **Cancel** to discard. Changing any mapping invalidates the preview and disables Apply until a new successful preview. Failed file selection/validation also invalidates previously staged data. Repeated Apply cannot commit the same staged import twice.

Loading, mapping, or previewing does not mutate simulation state. The dialog emits one `applied(series)` signal only for an explicit successful Apply; the controller then replaces the existing import for the same field/binding. It must not append the series to a sum of sources.

## Fields and units

| Field key | Imported units | Stored unit | Accepted model domain |
| --- | --- | --- | --- |
| `power` | `kW`, `MW` | kW | 0 to the selected device's rated kW (generic API hard cap: 1,000,000,000 kW) |
| `wind_ms` | `m/s`, `km/h` (`kmh` alias) | m/s | 0–100 m/s |
| `irradiance_wm2` | `W/m2`, `kW/m2` | W/m² | 0–2,000 W/m² |
| `temp_c` | `C`, `K` | °C | −90–70 °C |

The weather domains are explicit simulation validation limits, not universal physical limits. The parser also accepts `W/m²`, `W/m^2`, `kW/m²`, `kW/m^2`, `°C`, and `degC`. It converts MW × 1,000, km/h ÷ 3.6, kW/m² × 1,000, and K − 273.15. A legitimate zero remains zero. Values beyond a domain or current device cap are rejected, never silently clamped.

A weather file can contain all three weather columns, plus unrelated columns. Import each desired variable separately using the same time mapping. Unmapped cells are ignored; mapped time/value cells are mandatory. A single import does not silently import or infer the other weather variables.

## Time and sampling policy

- `s`, `min`, and `h` are elapsed simulation time, converted to seconds. A first sample at hour 2 starts at simulation second 7,200; it is **not** shifted to zero.
- `iso_utc` accepts `YYYY-MM-DDTHH:MM:SS[.ffffff]Z` or the UTC suffix `+00:00`. The first timestamp becomes simulation time zero; the exact UTC origin remains stored and shown in Preview. All imports should use the same starting UTC instant when calendar synchronization is intended. Different origins are not silently synchronized.
- Non-UTC offsets, missing timezone suffixes, impossible calendar dates, and leap seconds are rejected. Fractional seconds support at most six digits. IEEE-754 precision still applies at extreme historical/future years.
- Times must be finite, nonnegative after the stated origin rule, and strictly increasing. Duplicate timestamps, out-of-order rows, blank mapped values, NaN/infinity, malformed CSV, and numeric overflow/underflow are rejected. No sorting, deduplication, interpolation, imputation, or resampling takes place.
- The elapsed simulation-domain limit is ten Julian years (315,576,000 seconds).
- Sampling uses **zero-order hold**: sample i applies from its timestamp up to, but excluding, the next timestamp. At the final timestamp the final value is valid. Any time before the first or after the final timestamp returns `no_data`; a single-sample file is valid only at that exact time.
- There is **no extrapolation**. An active selected input returning `no_data` must pause the simulation with an explicit data-range message. It must not become zero or silently fall through to a built-in model.
- The controller must integrate zero-order-held power over time correctly, including when a simulation timestep crosses one or more sample boundaries. `sample()` returns a point value, not the integral over an arbitrary timestep.

## Required source priority

Per device, choose one direct imported power series if present; it overrides weather-derived/built-in generation. Otherwise use applicable imported weather fields (device-specific before global, if both exist), and use built-in defaults only for weather fields without an assigned import. Do not sum direct power and modeled power, or global and device weather. The direct-power canonical unit is **kW**; a controller/model that uses **MW** must divide by 1,000 once at its input boundary.

Only selected/consumed inputs determine no-data pauses. For example, an expired weather series does not pause a device whose direct power import overrides all weather. A selected imported weather field that is outside its data range does pause its consuming device instead of silently using the fallback weather value. Replacing/removing assigned inputs and any related undo behavior belong to the controller.

## Parser API

Load `res://scripts/series_import.gd`, a stateless `RefCounted` script. No global class registration is required.

```gdscript
const Import = preload("res://scripts/series_import.gd")
var mapping = {
    "time_column": "elapsed_h",   # header name OR zero-based column index
    "value_column": "wind_ms",
    "time_unit": "h",            # s | min | h | iso_utc
    "value_unit": "m/s",
    "field": "wind_ms",          # power | wind_ms | irradiance_wm2 | temp_c
    "target_device": "",         # empty = global weather, prohibited for power
    "delimiter": ","             # optional; comma is the default
}
var result = Import.parse(csv_text, mapping, {"source_name": "weather.csv"})
if result.ok:
    var series = result.series
    var point = Import.sample(series, simulation_seconds)
    if point.status == "ok":
        print(point.value)
    elif point.status == "no_data":
        # Pause and explain the finite range. Do not fill or fall back.
        pass
```

`parse(text: String, mapping: Dictionary, config: Dictionary = {}) -> Dictionary` always returns `ok`, `errors`, and `series`. Rejected input has an empty series. Config supports `source_name`, `min_value`, `max_value` in canonical units, and `max_power_kw` for the current device's rated power. Configured limits may narrow, but cannot expand, the hard field domains.

`inspect_csv(text: String, delimiter: String = ",") -> Dictionary` returns `ok/errors/series` plus `headers` and `records` on success. This only decodes CSV and checks headers/file limits; it is not numeric validation. Records include their original first line number for diagnostics.

`sample(series: Dictionary, t_s: float) -> Dictionary` returns:

- `{status: "ok", value: float, sample_time_s: float, index: int}`
- `{status: "no_data", reason: String, start_s: float, end_s: float}`
- `{status: "invalid", reason: String}`

`validate_series(series: Dictionary) -> Array[String]` is the strict saved-data validation entrypoint. An empty result means valid. It checks schema, canonical units, binding format, finite samples, ordering/duplicates, data/domain limits, metadata consistency, sampling policy, source hash, and a full reparse of the original CSV/mapping. Call it once during load or assignment, not every frame. `sample()` performs lightweight defensive checks and is not a substitute for load validation. The controller must additionally verify that the bound device exists, accepts the chosen field, and has a valid current rating. A newly staged direct-power import is checked against that current rating. If the user lowers a device rating after import, existing measured values remain intact and loadable; Model.solve clips the accepted terminal power to the new rating and separately reports nameplate clipping. Loading must validate the original import bounds and provenance, rather than silently rewriting measurements or rejecting an otherwise valid save solely because of that later derating.

## Dialog API

```gdscript
const ImportWindow = preload("res://scripts/import_dialog.gd")
var dialog = ImportWindow.new()
add_child(dialog)
dialog.setup([
    {"id": "wind_001", "name": "Wind 01", "kind": "wind", "rated_kw": 6000.0}
])
dialog.applied.connect(apply_series_to_scene)
dialog.cancelled.connect(on_import_cancelled)
dialog.open()
```

`setup(device_options: Array)` copies the supplied device dictionaries. Parents should pass eligible devices and provide rated kW for each generating device. `open()` shows the dialog. `stage_import(text, mapping, config)` validates/stages without assignment and supports tests or a future clipboard adapter. `apply_import()` commits the current valid candidate by emitting a copied series and clearing the candidate. `cancel_import()` clears the candidate and closes the dialog. The parent decides whether to pause while the window is open.

## Stored series

Everything is JSON-serializable: strings, booleans, numbers, arrays, and dictionaries. No Node, Resource, Callable, or binary packed arrays are stored. Fields include:

- `schema_version`, `kind`, `field`, `target_device`, canonical `unit`
- `time_unit` (`s`), original `time_mode`, `time_origin_utc`
- `interpolation` (`zero_order_hold`), `outside_range` (`no_data`)
- `start_s`, `end_s`, `count`, `min_value`, `max_value`, effective `bounds`
- `samples`: ordered `[{"t": seconds, "value": canonical_value}, ...]`
- `mapping`: resolved header names, units, field, target ID, delimiter
- `source`: filename/label, original CSV text, UTF-8 byte count, row count, SHA-256 hash

A filename is stored, never a required absolute path. A restored save therefore does not depend on the original CSV still existing on disk. Original CSV is retained for audit/validation; avoid importing sensitive unrelated columns because unused columns remain in the saved source text.

## Included examples

- `templates/power_kw.csv`: map `elapsed_s` / `power_kw`, time `s`, value `kW`, direct power, bind to an eligible device rated at least 1,500 kW.
- `templates/weather.csv`: map `elapsed_h` and one of `wind_ms` / `irradiance_wm2` / `temp_c`, time `h`, corresponding value unit. Repeat for any other desired field.
- `templates/weather_iso_utc.csv`: UTC times plus km/h, kW/m², and Kelvin examples. Select each value unit explicitly.

These are illustrative synthetic data, not a site-specific engineering forecast.

## Tests

Run with Godot 4.6 standard edition:

```sh
godot --headless --path . --script tests/test_series_import.gd
```

The suite verifies successful parsing/conversion, zero-order hold and strict outside-range behavior, finite/blank/duplicate/order/bound/date/CSV errors, ignored weather columns, JSON roundtrips, tampered saved data, staging without emission, cancellation, double Apply, invalidation after mapping changes, failed previews, and failed file selection. It can run independently from the main terrain scene.
