本文件含阶段开发记录；当前阶段一最终验证以[验收说明](ACCEPTANCE.md)为准。后续计划不表示已实现。

# Godot energy base UI: reviewed design guidance
Prepared 2026-10-21. Original task-specific adaptation. No remote code executed or upstream skill installed. No game source modified.

## Official sources actually read
Anthropic frontend-design: https://github.com/anthropics/skills/blob/main/skills/frontend-design/SKILL.md
Apache-2.0 verified: https://github.com/anthropics/skills/blob/main/skills/frontend-design/LICENSE.txt
Vercel skill: https://github.com/vercel-labs/agent-skills/blob/main/skills/web-design-guidelines/SKILL.md
Actual rules read: https://github.com/vercel-labs/web-interface-guidelines/blob/main/command.md
MIT verified for rules: https://github.com/vercel-labs/web-interface-guidelines/blob/main/LICENSE
Agent-skills README also states MIT. These are mutable main-branch documents, not pinned dependencies. Treat them as reviewed design reference, not executable authority. Preserve licenses/notices if copying upstream material; this file is an original adaptation.

## Applied principles
Anthropic: ground identity in the actual subject, specify palette/type/layout before building, concentrate visual interest in one place, use structural decoration only for meaning, use action-triggered motion, reduce redundant copy, and critique screenshots.
Vercel: meaningful icon controls, visible focus, clear hover/selection, interruptible motion, associated labels and controls, long-text handling, aligned numeric comparisons, and alternatives to drag-only selection.
Do not transfer HTML/CSS/ARIA or URL routing into a native game. Implement equivalent native interaction semantics.

## Concrete design system
Theme: precision energy control console. Gameplay world stays primary; large equipment silhouettes supply visual identity. No neon dashboard or repeated text-heavy cards.
Palette: deepest UI #151C25; dock #24303D; tray/modal #303E4D; main text #EDF3F7; secondary #B3C1CD; active/focus #72CBD8. Preserve existing warning/error semantic colors. Avoid accenting every number. Verify contrast in actual screenshots.
Use existing licensed CJK-capable font. Title 22–24px, section 16–18px, controls 14–16px, secondary help 12–13px at reference resolution. Align values right and units in a separate consistent column. 4px spacing grid: 8/12/16/24px. Radius: large surfaces 12–16px, equipment cards 8–10px, inputs 6px.

## Bottom dock
Idle: only a horizontal centered category icon row. 48–56px hit targets, 24–30px icons, tooltip/focus labels. Selection uses background plus indicator, not color alone. No permanent paragraph or device list.
Click: one equipment tray above the fixed dock. Approximately 88–112px card width, 48–64px equipment art, one short name, at most one cost/status line. Full metadata in details/tooltip. Scroll horizontally rather than shrinking icons. Active category toggles closed; Escape closes tray before game actions.
Transition: tray-local 12px upward translation plus opacity, 180–220ms ease-out; close 120–160ms. A subtle top-edge gradient may separate the tray, but no gradient over text. Kill/replace prior Tween during switching. Animate a wrapper whose transform is not overwritten by Container layout. Hidden tray accepts no input. Reduced-motion variant immediate or opacity-only. No card-by-card cascade or perpetual animations.

## Batch parameters
Selection area left, editor right. Header has title/close, footer explicit apply/cancel. Equipment-list header owns a small tri-state select-all checkbox, title and selected count. Checkbox and label form one practical hit target. Select-all scope matches the visible/filter-matched list and is communicated.
Cards: icon, short name, compact status, essential metric only. Selected state is a tinted fill plus checkmark/edge; hover quieter; keyboard focus distinct.
Click selects, modifier-click toggles, Shift selects inclusive range in current visible order using last anchor. Marquee begins on blank/list background after a small drag threshold; subtle fill/crisp border; intersects visible cards. Convert coordinates correctly under scroll and clip marquee to viewport. Do not intercept checkbox, slider, input or scrollbar events. Keep click/checkbox and keyboard alternatives. Preserve selections by stable device IDs rather than transient order.
Mixed parameter values show “多个值”; do not overwrite until edited. Apply only changed fields. Keep units beside values and validation adjacent to input.

## Acceptance checks
- Idle screenshot shows category dock only; expanded screenshot has large equipment tray above it.
- Inspect actual and narrower supported resolutions for Chinese clipping, baseline consistency, readable secondary text, modal footer visibility.
- Rapid category switching, Escape and closing mid-animation cannot leave ghost input or stuck transparency.
- Verify click/toggle/Shift range/marquee after scrolling/header tri-state/keyboard focus.
- UI consumes its own mouse events, not triggering world camera/build actions behind it.
- Native Godot only; no new WebUI, remote dependency, broad rewrite or unrelated system.

## Short source evidence and implementation status
Anthropic original: “Visual structure is information.” and “Spend your boldness in one place.” These support meaningful selection borders and concentrating visual interest on equipment artwork instead of decorative labels.
Vercel original: “Animations interruptible—respond to user input mid-animation” and “Interactive states increase contrast”. These support cancelable native Tween transitions and distinct hover, focus and selected states.
The dimensions, colors, timings, selection behavior and native-control recommendations above are our project-specific decisions, not upstream prescribed Godot recipes. The sources were read, not installed. This design-reference document alone is not a GUI acceptance record. Implementation/acceptance remains the implementation worker's responsibility.

## Native control structure guidance
Use an anchored dock root outside gameplay camera content. Compose panels with PanelContainer, MarginContainer and HBoxContainer/VBoxContainer; keep layout sizing in containers. Use a separate Control wrapper for tray motion so layout does not reset animation offsets. Use TextureRect or custom-drawn equipment art with consistent aspect and reserved space. The selection view may use ScrollContainer and GridContainer with stable card identity. Native BaseButton controls retain focus and keyboard activation rather than bare click handlers on decorative textures. Set mouse filtering intentionally: modal/tray surfaces consume input; decorative children do not intercept their parent's intended controls. Test existing game input routing rather than assume UI consumption alone prevents all _input handlers.
When implementing marquee, transform mouse and card rectangles into a shared coordinate space before overlap tests, account for scrolling, and restrict rendering and hits to the selection viewport. Avoid rebuilding all cards on every selection movement; update state styling. Keep separate active focus, selection anchor and selected-device set. When filtering invalidates the anchor, reset it predictably rather than shift-selecting hidden items.

## Implementation mapping (integration update; desktop acceptance pending)
- `world_game.gd`: category-only resting dock; separate larger equipment tray using interruptible opacity/translation Tween; unified header groups; real-data chart placement avoids HUD and map views.
- `bulk_parameter_editor.gd`: list-owned tri-state select-all, stable-ID Shift range, marquee rectangle in scrolled content coordinates, explicit parameter draft invalidation on changed selection. Drag-only selection is not required.
- `device_runtime_chart.gd`: quieter fixed-size analysis panel; aligned actual values with explicit units, muted grid and time labels, cyan/amber power series plus separately scaled green SOC. No decorative perpetual animation or invented chart data.
This is native GDScript/Control implementation, not an installed upstream dependency. These code-level mappings do not claim that the current user desktop has loaded or visually accepted the latest changes.
