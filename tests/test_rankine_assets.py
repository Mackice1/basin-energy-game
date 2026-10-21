"""Binary/manifest audit for V20 originals and the V20.1 tower preview. Run: python tests/test_rankine_assets.py."""
import hashlib
import math
import json
import struct
import unittest
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / 'assets/models'
KINDS = ('steam_generator', 'steam_turbine', 'steam_condenser', 'feedwater_pump', 'tower_station_preview')
PORTS = {
    'steam_generator': {'oil_in', 'ac_in', 'feed_in', 'steam_out'},
    'steam_turbine': {'steam_in', 'exhaust_out', 'ac_out'},
    'steam_condenser': {'exhaust_in', 'condensate_out', 'ac_in'},
    'feedwater_pump': {'condensate_in', 'feed_out', 'ac_in'},
    'tower_station_preview': set(),
}

def glb_json(path):
    raw = path.read_bytes()
    magic, version, size = struct.unpack_from('<4sII', raw)
    assert (magic, version, size) == (b'glTF', 2, len(raw))
    length, kind = struct.unpack_from('<I4s', raw, 12)
    assert kind == b'JSON'
    return json.loads(raw[20:20+length])

class RankineAssets(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.manifest = json.loads((MODELS/'rankine_asset_manifest.json').read_text())

    def test_five_isolated_embedded_scenes(self):
        self.assertEqual(set(self.manifest['assets']), set(KINDS))
        for kind in KINDS:
            with self.subTest(kind=kind):
                asset = glb_json(MODELS/(kind+'.glb'))
                self.assertEqual(len(asset['scenes']), 1)
                self.assertEqual(asset['scenes'][0]['name'], kind)
                self.assertEqual(asset['scene'], 0)
                self.assertTrue(all('uri' not in b for b in asset['buffers']))
                self.assertFalse(asset.get('images'))
                roots = asset['scenes'][0]['nodes']
                self.assertEqual(len(roots), 1)
                root = asset['nodes'][roots[0]]
                self.assertTrue(all(abs(v-.1) < 1e-7 for v in root['scale']))
                self.assertTrue(root['extras']['visual_only'])
                self.assertEqual(root['extras']['capacity_added'], 0)
                self.assertEqual({n['name'][5:] for n in asset['nodes'] if n.get('name','').startswith('Port_')}, PORTS[kind])
                self.assertEqual(set(self.manifest['assets'][kind]['ports']), PORTS[kind])
                self.assertEqual(self.manifest['assets'][kind]['bytes'], (MODELS/(kind+'.glb')).stat().st_size)

    def test_preview_inventory(self):
        asset = glb_json(MODELS/'tower_station_preview.glb')
        nodes = asset['nodes']
        self.assertEqual(len([n for n in nodes if n.get('name','').startswith('Heliostat')]), 100)
        mirrors = [n for n in nodes if n.get('name','').startswith('MirrorSurface')]
        self.assertEqual(len(mirrors), 100)
        for node in mirrors:
            self.assertIn('mesh', node)
            primitive = asset['meshes'][node['mesh']]['primitives'][0]
            access = asset['accessors'][primitive['attributes']['POSITION']]
            dimensions = sorted(b-a for a,b in zip(access['min'],access['max']))
            self.assertAlmostEqual(dimensions[1], 4, places=5)
            self.assertAlmostEqual(dimensions[2], 4, places=5)
        definition = self.manifest['assets']['tower_station_preview']
        self.assertEqual(definition['bounds_m'], [[-80,0,-80],[80,25,80]])
        self.assertEqual(definition['mirror_aperture_area_m2'], 100*4*4)
        self.assertFalse(definition['commissioned'])
        self.assertEqual(definition['energy_ports'], [])

    def test_ring_reflection_and_nonoverlap(self):
        asset = glb_json(MODELS/'tower_station_preview.glb')
        nodes = asset['nodes']
        definition = self.manifest['assets']['tower_station_preview']
        self.assertEqual(definition['tracking_mode'], 'fixed_teaching_snapshot_not_realtime')
        centers = [n['extras']['mirror_center_m'] for n in nodes if n.get('name','').startswith('Heliostat')]
        counts = [0,0,0,0]
        sun = definition['sun_direction']
        def unit(v):
            length = math.sqrt(sum(x*x for x in v))
            return [x/length for x in v]
        def distance(a,b):
            return math.sqrt(sum((x-y)**2 for x,y in zip(a,b)))
        for i, center in enumerate(centers):
            radius = math.hypot(center[0],center[2])
            ring = min(range(4),key=lambda k:abs(radius-[18,30,42,54][k]))
            counts[ring] += 1
            self.assertAlmostEqual(radius,[18,30,42,54][ring],places=4)
            self.assertGreaterEqual(abs(center[2]),5)
            self.assertLess(abs(center[0])+math.sqrt(8.01),60)
            self.assertLess(abs(center[2])+math.sqrt(8.01),60)
            # Conservative reflector sphere clears the 8x8 m tower foundation
            # and the relocated service roof (14.2x8.2 m around 48,48).
            tower_distance = math.hypot(max(abs(center[0])-4,0),max(abs(center[2])-4,0))
            building_distance = math.hypot(max(abs(center[0]-48)-7.1,0),max(abs(center[2]-48)-4.1,0))
            self.assertGreater(tower_distance,math.sqrt(8.01))
            self.assertGreater(building_distance,math.sqrt(8.01))
            for other in centers[:i]:
                self.assertGreater(distance(center,other),2*math.sqrt(8.01))
        self.assertEqual(counts,[14,20,30,36])
        for node in nodes:
            if not node.get('name','').startswith('MirrorSurface'): continue
            center = node['translation']
            # Exported glTF quaternion rotates local +Y to the reflector normal.
            x,y,z,w = node['rotation']
            normal = [2*(x*y-z*w),1-2*(x*x+z*z),2*(y*z+x*w)]
            target = unit([-center[0],24-center[1],-center[2]])
            expected = unit([a+b for a,b in zip(sun,target)])
            self.assertLess(distance(normal,expected),1e-5)
            dot = sum(a*b for a,b in zip(sun,normal))
            reflected = [-a+2*dot*b for a,b in zip(sun,normal)]
            self.assertLess(distance(reflected,target),1e-5)
        receiver = next(n for n in nodes if n.get('name') == 'DarkReceiver')
        self.assertAlmostEqual(receiver['translation'][0],0)
        self.assertAlmostEqual(receiver['translation'][2],0)

    def test_metric_bounds_and_source(self):
        for kind in KINDS:
            with self.subTest(kind=kind):
                record = self.manifest['assets'][kind]
                self.assertEqual(record['world_units_per_meter'], .1)
                self.assertTrue((ROOT/record['source']).is_file())
                lower,upper = record['bounds_m']
                self.assertGreaterEqual(lower[1], -1e-6)
                if 'unit_dimensions_m' in record:
                    size = record['unit_dimensions_m']
                    self.assertLessEqual(upper[0]-lower[0],size[0]+1e-6)
                    self.assertLessEqual(upper[1],size[1]+1e-6)
                    self.assertLessEqual(upper[2]-lower[2],size[2]+1e-6)

    def test_older_assets_preserved(self):
        # V22 explicitly replaces these five visual models; retain the old
        # receipt and verify both the authorized old and new exact hashes.
        authorized = json.loads((ROOT/'tests/v22_authorized_model_hashes.json').read_text())
        self.assertEqual(set(authorized), {f'assets/models/{name}.glb' for name in ('electric_boiler', 'heat_exchanger', 'thermal_station', 'thermal_store', 'wind_turbine')})
        def verify(relative, old_hash):
            actual = hashlib.sha256((ROOT/relative).read_bytes()).hexdigest()
            if relative in authorized:
                self.assertEqual(old_hash, authorized[relative]['before'])
                self.assertEqual(actual, authorized[relative]['after'])
            else:
                self.assertEqual(actual, old_hash)
        archives = list((ROOT.parents[1]/'v19_backup_verify').glob('*.zip'))
        if not archives:
            baseline = ROOT.parent/'V20_1_FROZEN_SOURCE_MANIFEST.json'
            receipt = ROOT/'evidence/tower_stage/validation/legacy_glb_hashes.json'
            if not baseline.exists() and not receipt.exists():
                self.skipTest('No frozen asset reference available.')
            entries = ([e for e in json.loads(baseline.read_text())['files'] if e['path'].startswith('assets/models/') and e['path'].endswith('.glb')] if baseline.exists() else json.loads(receipt.read_text()))
            self.assertGreaterEqual(len(entries),16)
            for entry in entries:
                verify(entry['path'], entry['sha256'])
            return
        with zipfile.ZipFile(archives[0]) as archive:
            entries = [n for n in archive.namelist() if '/assets/models/' in n and n.endswith('.glb')]
            self.assertGreaterEqual(len(entries),11)
            for entry in entries:
                relative = entry[entry.index('assets/models/'):]
                with self.subTest(previous_asset=relative):
                    verify(relative, hashlib.sha256(archive.read(entry)).hexdigest())

if __name__ == '__main__':
    unittest.main(verbosity=2)
