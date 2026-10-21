# V20 original Rankine equipment and tower preview geometry

Generator: `tools/build_rankine_assets.py`.
Editable source: `rankine_assets.blend` (five separate scenes, individually named editable parts).
Runtime outputs: five self-contained `assets/models/*.glb` files, one scene each, no external texture dependency.
Manifest: `assets/models/rankine_asset_manifest.json`.

All authoring coordinates are metres. The glTF export root is exactly 0.1 world units per metre; Godot equipment roots remain unit-scale. Interior/exterior views never rescale physical equipment. All dimensions below are original teaching envelopes and capacity assumptions, not vendor CAD, certified engineering sizing, pressure-vessel ratings, or clearance approval.

| Module | Envelope, x × z × height | Reference rating per complete module |
|---|---|---|
| Oil-heated steam generator | 4 × 2.5 × 3 m | 0.1 MWth |
| Small steam turbine-generator | 4 × 2.5 × 2.2 m | 0.05 kg/s water/steam |
| Dry air-cooled condenser | 6 × 4 × 4.2 m | 0.08 MWth heat rejection |
| Feedwater pump | 2 × 1.2 × 1.5 m | 0.05 kg/s water/steam |

Capacity/rating increases add ceil(requested/reference) complete, fixed-size modules. Each aggregate still has one port set and one simulation limit; visual copies create no extra capacity or mass. Module spacing is 2 m and external maintenance margin is 2 m, both teaching assumptions. The implementation uses whole module envelopes and rejects oversized placements rather than shrinking the equipment.

The steam generator visibly separates the hot oil manifold, feedwater inlet and live-steam dome/riser. The turbine and coupled generator are distinct casings. The condenser has a condensate shell/hotwell and an explicit two-fan air-cooling bank, not a cooling-water supply or a useful hot-water output. The feedwater pump has distinct motor, volute, suction and pressure discharge. Water/steam ports use kg/s with fixed-state grade identifiers; oil ports use MWth and AC ports use MW.

## Independent tower-station preview

- Site rectangle: 160 × 160 m = 25,600 m².
- Usable interior rectangle: 120 × 120 m = 14,400 m², contained within the site, never added to site area.
- Full site collision circle: radius sqrt(80² + 80²) = 113.137085 m = 11.3137085 world.
- Receiver tower top: exactly 25 m above grade.
- 32 individually modelled heliostats, each a complete 4 × 4 m reflective face: total aperture 512 m².
- Four rows of eight mirrors, centre spacings 12 m east-west and 14 m north-south; mirror centres 3 m above grade. Tower is at (0, 30) m in plan.
- Static illustration uses a normal between overhead sun and the receiver direction, solely to make the preview legible. No actual tracking, optical performance, shading guarantee or power output is claimed.
- Site, layout and mirror count are teaching assumptions, not an engineered CSP design.
- No named energy ports, no runtime, no commissioned state and zero energy output.
- Preview-specific muted sand ground, blue-gray reflectors and darker tower steel preserve contrast under the runtime lighting. These material changes do not change geometry; a view from the receiver side exposes the actual mirror faces.

`EquipmentVisual.create("tower_station_preview", {}, prefer_blender_assets)` builds the full exterior. Passing `{"preview_interior": true}` removes only the `ExteriorSite` slab/fence group. `WorkingPreview`, all 32 physical mirrors, the 25 m tower and their exact transforms remain unchanged within the 120 m rectangle. Both imported and procedural backends obey this contract.

## Verification

- `tests/test_rankine_geometry.gd`: default and three-module layouts, exact unit scale, fixed module sizes, manifest/GLB anchor coordinates, typed carriers/grades/units, above-ground bounds, preview/restore and aggregate port ownership.
- `tests/test_tower_preview_geometry.gd`: both backends and both exterior/interior variants; exact mirror mesh count, physical site/height bounds, zero ports and no runtime/output.
- `tests/test_rankine_assets.py`: isolated embedded GLBs, authored root scale, preview inventory, manifest and old-asset preservation where available.

Run Godot with writable HOME/XDG cache/data directories in restricted containers. Studio renders are illustrative review images; the actual imported runtime geometry is independently checked by the Godot tests.
