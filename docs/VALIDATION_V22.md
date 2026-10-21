# V22 validation provenance

## Earlier reported results, not a new run

The V22 delivery reported:

- 89/89 Godot test scripts covered, with zero failed scripts or `SCRIPT ERROR` in the recorded regression.
- 88 scripts rerun after the final UI changes; the longer `test_tower_day_night_world.gd` run through 33,000 simulated seconds was retained from the earlier integrated pass. This is not a claim that all 89 ran again after the last UI edit.
- 446,012 printed Godot assertions, many of them per-vertex/geometric checks rather than distinct features.
- 127/127 Python tests passed, zero skipped, including actual GLPK execution.
- 11/11 native GUI checks passed, as reported for the earlier integrated V22 delivery. This is separate from the headless regression.

These results describe the earlier V22 verification. They were not rerun when the public staging copy was prepared on **2026-10-21**. No new performance, full native-interaction or export-platform validation was performed for that preparation.

## Reproduction prerequisites

Install Godot 4.6.3 Standard, Python 3.9+, and GLPK 5.0. Import the project before running Godot scripts. Python tests can be invoked from the project root with:

```sh
python3 -m unittest discover -s tests -p 'test_*.py' -v
```

The solver must be available to the tests. Godot uses `BASIN_GLPK` and `BASIN_PYTHON`, but several historical test scripts explicitly assign a former cloud solver path. Inspect those scripts before reproducing them on another machine. The generic `tools/run_v21_regression.py` is retained unchanged as a historical aggregate runner, not represented as a fully portable clean-clone CI configuration.

Some restart/native GUI tests read saved states produced by earlier capture scripts. Those historical runtime states are deliberately absent from the public copy. Recreate the corresponding capture/save step locally before running its dependent restart test. The necessary generated-output directories are retained through empty marker files.

The two fixed synthetic cross-language GLPK input/result pairs and legacy asset hash receipt are retained because tests directly consume them. Diagnostic solver log fields were removed from the result fixtures; model inputs, candidate decisions and all validation values are unchanged. No player save is included with these fixtures.

## Known boundaries

- Existing terrain `Image.load_from_file` export warnings and a deprecated interpolation call were present in the earlier report. A source/editor run is not export-package certification.
- Cloud software rendering was not a substitute for a real-GPU performance acceptance test.
- The native checks do not prove every possible input flow, device combination or operating system is correct.
- Historical documents retain their own stage-specific results. They must not override the more precise current scope above.
