#!/usr/bin/env python3
"""Regenerate the six schema-7 real-GLPK fixtures for the Godot cross-language audit.

From the project root:
    python3 tests/export_expanded_storage_crosslanguage.py --glpsol /path/to/glpsol
    godot --headless --path . --script res://tests/test_expanded_storage_crosslanguage.gd

The default destination is evidence/expanded_storage/validation. Use --output-dir
for isolated verification. All six solves and independent audits must succeed
before any fixture is written. Existing live/save state is never read or changed.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile

from test_expanded_storage_optimizer import NEW_STORAGE, ROOT, backend, electric_case, solid_case


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--glpsol", default=os.environ.get("BASIN_GLPK", "glpsol"),
                        help="Real GLPK executable (default: BASIN_GLPK or glpsol on PATH)")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "evidence/expanded_storage/validation",
                        help="Destination for {kind}_request.json and {kind}_result.json")
    args = parser.parse_args(argv)
    executable = shutil.which(args.glpsol)
    if not executable:
        print(f"Cannot generate fixtures: GLPK executable not found: {args.glpsol}", file=sys.stderr)
        return 2
    fixtures = []
    try:
        for kind in NEW_STORAGE:
            snapshot = solid_case() if kind == "solid_thermal_store" else electric_case(kind)
            result = backend.solve(snapshot, glpsol=executable)
            if not (result.get("success") and result.get("solver_invoked") and result.get("status") == "optimal"
                    and result.get("validation", {}).get("raw_decisions_validated")):
                raise RuntimeError(f"{kind}: {result.get('status')}: {result.get('message')}; {result.get('errors', [])}")
            audit = backend.validate_schedule(backend.normalize(snapshot), result["steps"])
            if not audit["valid"]:
                raise RuntimeError(f"{kind}: independent audit rejected the generated schedule: {audit['errors']}")
            # Serialize before touching the destination, rejecting nonfinite data.
            request_json = json.dumps(snapshot, indent=2, allow_nan=False)+"\n"
            result_json = json.dumps(result, indent=2, allow_nan=False)+"\n"
            fixtures.append((kind, request_json, result_json, audit["max_residual"]))
        output = args.output_dir.resolve()
        output.mkdir(parents=True, exist_ok=True)
        # Stage complete bytes, then replace individual files atomically. No failed
        # or partial solver schedule can overwrite an existing accepted fixture.
        with tempfile.TemporaryDirectory(prefix=".expanded_storage_", dir=output) as staging:
            for kind, request_json, result_json, _ in fixtures:
                for suffix, contents in (("request", request_json), ("result", result_json)):
                    (Path(staging)/f"{kind}_{suffix}.json").write_text(contents, encoding="utf-8")
            for staged in Path(staging).iterdir():
                os.replace(staged, output/staged.name)
        print(json.dumps({"success": True, "solver": executable, "output_dir": str(output),
                          "fixtures": [{"kind": kind, "steps": 2, "status": "optimal", "max_residual": residual}
                                       for kind, _, _, residual in fixtures]}, indent=2, allow_nan=False))
        return 0
    except (OSError, ValueError, TypeError, RuntimeError) as exc:
        print(f"Cannot generate fixtures: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
