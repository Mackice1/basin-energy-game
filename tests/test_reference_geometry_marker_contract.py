"""Explicit flow-icon/reference incompatibility never silently changes old geometry."""
import copy
import json
import subprocess
import tempfile
from pathlib import Path
import unittest
from test_site_layout_solver import layout, backend, GODOT, ROOT
from test_air_storage_capacity_geometry import isolated_env, compare

class ReferenceGeometryMarkerTests(unittest.TestCase):
    def test_explicit_old_geometry_is_rejected_but_missing_is_new_default(self):
        item={"id":1,"kind":"battery_flow","params":copy.deepcopy(backend.SCHEMA_12_DEFAULTS["battery_flow"]),"site_geometry_profile":layout.SITE_GEOMETRY_PROFILE}
        self.assertTrue(layout.assess_device(item)["operable"])
        for profile in ["flow_process_v2","flow_icon_v1","unknown",None,True]:
            item["geometry_profile"]=profile
            before=copy.deepcopy(item)
            result=layout.assess_device(item)
            self.assertEqual(result["operable"],profile=="flow_process_v2")
            if profile!="flow_process_v2":self.assertEqual(result["issues"][0]["code"],"incompatible_geometry_profile")
            self.assertEqual(item,before)
        item.pop("site_geometry_profile");item["geometry_profile"]="flow_icon_v1"
        self.assertTrue(layout.validate_for_model([item])["operable"])
        self.assertFalse(layout.validate_for_model([item])["applied"])
        self.assertTrue(layout.assess_device(item)["needs_migration"])

    @unittest.skipUnless(GODOT,"Godot required")
    def test_same_cases_match_godot(self):
        with tempfile.TemporaryDirectory(prefix="flow-marker-parity-") as directory:
            run=subprocess.run([GODOT,"--headless","--path",str(ROOT),"--script","tests/test_reference_geometry_marker_contract.gd"],env=isolated_env(Path(directory)),text=True,capture_output=True,timeout=90)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertNotIn("SCRIPT ERROR",run.stderr)
        rows=json.loads(next(line[len("FLOW_MARKER_CASES "):] for line in run.stdout.splitlines() if line.startswith("FLOW_MARKER_CASES ")))
        for row in rows:compare(self,row["result"],layout.assess_device(row["device"]))
