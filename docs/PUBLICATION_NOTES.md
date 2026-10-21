# Public-source preparation

This copy was prepared on 2026-10-21 from the integrated V22 source tree for repository management. Preparation did not change runnable scripts, game configuration, physical model values, bundled plugin binaries or game/Blender assets.

## Included

Game and test source; scenes; source import settings; generated terrain needed at runtime; models and textures; Blender sources; configuration and sample CSVs; model assumptions and historical Markdown documentation; third-party binaries, source archive and license files.

For tests, the compact fixed synthetic day/night GLPK request/result pairs and the legacy GLB hash receipt remain under `evidence/tower_stage/validation/`. The original Xorg dummy-display configuration is retained for historical native QA launchers. These are not private player saves.

## Intentionally omitted

- `.godot/`, Python bytecode caches and machine metadata.
- Runtime logs, recorded telemetry, save-state snapshots and solver-run artifacts, except the explicitly listed synthetic regression fixtures.
- Historical screenshots, videos, studio preview renders and bulky evidence archives.
- A stale `.orig` script backup.

Historical Markdown documents may still mention or link to those omitted artifacts. They describe the original development history, not files promised by the public repository. The prior root README is preserved as `docs/HISTORY_README.md`, with its relative Markdown links adjusted for the move.

Diagnostic log fields were removed from the two retained solver result fixtures without changing their inputs, decisions or numerical results. Host-specific paths in historical prose are sanitized when encountered. Executable source is preserved byte-for-byte; some historical launcher/test scripts therefore still contain generic former-cloud filesystem defaults. They are portability limitations, not credentials, and should be reviewed before execution elsewhere.

The ignore file guards generated outputs and local saves against accidental future commits. It cannot replace reviewing future changes for confidential data. No new original-code or original-asset license was added.
