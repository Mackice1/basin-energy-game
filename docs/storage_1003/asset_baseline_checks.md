本文件含阶段开发记录；当前阶段一最终验证以[验收说明](ACCEPTANCE.md)为准。后续计划不表示已实现。

# Asset baseline checks

On 2026-10-21, `test_older_assets_preserved` and `test_preview_inventory`
were reproduced against untouched `energy_v23_20261021/Basin02` using
`python3 -B` and selected read-only unittest methods. The recorded before/after
hashes are identical: see
`evidence/expanded_storage/validation/baseline_asset_failure_evidence.json`.
Before the repair, the development copy's preview GLB, Rankine manifest, test,
legacy receipt and V22 authorization map were also byte-identical to that source.

The old preview receipt records SHA-256
`37ee52446bf1d58141f1c6e7056ab81e730c75912737100602a5eb6253939f2e`;
the authoritative source and development copy both contain
`fe1f6526c5c106cf0acd561dff598a3d52d79dc1b5d2fcd42168405b465370fc`.
`tests/storage_1003_baseline_asset_hashes.json` records only that inherited
`tower_station_preview.glb` transition, not a new model change. The test requires
the exact one-asset keyset and `before`/`after` fields, compares `before` to the
unchanged legacy receipt, and compares `after` to the current file's SHA-256.
The legacy receipt and `tests/v22_authorized_model_hashes.json` remain unchanged;
every other asset retains its existing exact-hash checks.

The inherited manifest's upper Y bound is `25.000001907348633` m rather than
exactly `25` m: a difference of approximately 1.91 micrometres, consistent with
float32 export precision. Only this preview bounds comparison now permits an
absolute `1e-5` m (10 micrometres) difference per coordinate. It still requires
two three-coordinate corners, finite coordinates and the expected bounds;
inventory, area, commissioning and port assertions are unchanged.

The full Python discovery log after the repair is
`evidence/expanded_storage/validation/python_full_after_asset_fix.log`.
Result: 153 tests passed in 3.516 s, with no skips, failures or errors.
Command, from the development copy only:

```sh
PATH=/path/to/local/tool \
BASIN_GLPK=/path/to/local/tool \
  python3 -B -m unittest discover -s tests -p 'test_*.py' -v
```

No baseline files, GLBs, manifests, live saves, GUI state or publication targets
were changed by this repair.
