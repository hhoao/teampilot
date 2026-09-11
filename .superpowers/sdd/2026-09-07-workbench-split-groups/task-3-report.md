# Task 3 Report: `WorkbenchSplitLayoutView` — shared recursive split renderer

**Status: DONE.** All 9 new widget tests pass; related existing suites (Task 1
layout reducer, Task 2 cubit, tab strip) still pass; `flutter analyze` reports
no issues in the new files.

## Files

- Created: `client/lib/widgets/workbench/workbench_split_layout_view.dart`
- Created: `client/test/widgets/workbench/workbench_split_layout_view_test.dart`
- Commit: `feat(workbench): shared recursive split layout renderer`

## What I built

### Public interface (exact names Tasks 5/6 consume)

```dart
typedef SplitGroupBuilder =
    Widget Function(BuildContext context, String groupId, TabStrip strip);

class WorkbenchSplitLayoutView extends StatefulWidget {
  const WorkbenchSplitLayoutView({
    required this.layout,
    required this.groupBuilder,
    this.holdHandle,              // WorkspaceTerminalHoldHandle?
    this.splitEnabled = true,
    this.onResizeCommit,          // void Function(List<bool> path, double fraction)?
    this.onGroupFocused,          // void Function(String groupId)?
    this.onDividerDoubleTap,      // VoidCallback?
    this.minGroupExtent = 240,
    this.focusedGroupIdOverride,  // String?
    this.onPtyHoldBegin,          // VoidCallback? — injectable hold bracket
    this.onPtyHoldEnd,            // VoidCallback? — injectable hold bracket
    super.key,
  });
}

class SplitGroupFocusFrame extends StatelessWidget {
  const SplitGroupFocusFrame({required this.focused, required this.child, super.key});
  // 2px colorScheme.primary border overlay (IgnorePointer + Positioned.fill
  // DecoratedBox) when focused; plain child otherwise.
}

/// Divider gesture-handle key for the branch at [path] (root = empty path).
Key workbenchSplitDividerKey(List<bool> path);
```

`onPtyHoldBegin` / `onPtyHoldEnd` are the controller-resolved injectable
brackets: when null, drags default to `holdHandle?.beginPtyHold()` /
`holdHandle?.endPtyHold(flush: true)` (holdHandle stays the primary param).
Tests record bracket order with them.

### Widget structure

```
WorkbenchSplitLayoutView (StatefulWidget — owns the drag state machine)
├─ !splitEnabled            → _LeafView(focusedGroupIdOverride ?? focusedGroupId)
├─ maximizedGroupId != null → _LeafView(maximizedGroupId)          [splitEnabled only]
└─ _buildNode(root, path=[])
   ├─ SplitLeaf  → _LeafView: GestureDetector(translucent, onTap → onGroupFocused)
   │               wrapping ClipRect(groupBuilder(context, id, strip))
   └─ SplitBranch → _BranchView
      ├─ LayoutBuilder: captures the branch's main-axis extent → reported to the
      │   root State's `_branchExtents` map (keyed by encoded path)
      ├─ ValueListenableBuilder<_SplitDragSession?> over the root's drag notifier;
      │   `child:` holds the static (pre-drag) panes so non-dragged branches never
      │   rebuild during a drag; the dragged branch rebuilds with the live fraction
      ├─ Row/Column: [SizedBox(firstExtent, first), 1px visual divider, Expanded(second)]
      └─ Stack child: Positioned 12px hit strip centered on the divider (clamped
          into bounds) holding _Divider
          = MouseRegion(resizeColumn/resizeRow) → GestureDetector(opaque,
            onPanStart/Update/End/Cancel + onDoubleTap), keyed by
            workbenchSplitDividerKey(path)
```

Drag state machine lives in the root State:

- **start** — `_beginDrag(path, branch.firstFraction)` seeds an immutable
  `_SplitDragSession {path, startFraction, fraction, delta}` into a
  `ValueNotifier<_SplitDragSession?>` and fires `onPtyHoldBegin ?? beginPtyHold`.
- **update** — accumulates pointer delta along the branch axis; live fraction =
  `(startFraction * content + delta) / content` clamped so each side keeps
  `minGroupExtent` of the branch's extent captured from the last layout pass
  (`minFraction = clamp(minGroupExtent / content, 0, 0.5)`; a host too small to
  honor the minimum collapses to 0.5).
- **end** — fires `onResizeCommit(path, fraction)` exactly once with the resized
  branch's path (root-down `List<bool>`, `true` = second child; empty = root),
  then `onPtyHoldEnd ?? endPtyHold(flush: true)`. Cancel ends the hold without
  committing.

Divider styling follows `resizable_split_view.dart`: 1px visual line in
`colorScheme.outlineVariant` (alpha 0.5 dark / 0.6 light) with a wider 12px
opaque hit strip. (The brief's "6px visual" note conflicts with its own
"follow the existing constants in that file for visual thickness" — I followed
the existing convention: 1px visual, hit area the wider one.)

### Notes / decisions

- Nothing keys on lifetime-uniqueness of group ids; dividers are keyed by
  branch *path*, which is positional and stable across id recycling.
- `!splitEnabled` takes precedence over `maximizedGroupId` (the brief scopes
  maximize to `splitEnabled` mode). An override naming a dead group falls back
  to the focused group, then the leftmost leaf; a stale `maximizedGroupId`
  falls through to the full tree.
- Unbounded/degenerate hosts (extent ≤ divider) render an even, non-draggable
  split instead of throwing.
- Live-fraction rebuilds are confined: `ValueListenableBuilder.child` keeps
  every non-dragged branch untouched during a drag.
- The hit strip's offset is clamped into the stack bounds because `Positioned`
  asserts on negative offsets (a 1px divider at a 0.05 fraction would otherwise
  produce a negative left).

## Tests (`client/test/widgets/workbench/workbench_split_layout_view_test.dart`)

Host: `MaterialApp/Scaffold/Center/SizedBox(500x400)` so divider math is
deterministic. Layout seed: g0 seeded with s1, s2 added, then
`split(tab: s2, horizontal, before: false)` → g0 | g1.

1. `renders one group builder output per leaf` — both `group-g0` and the second
   group's builder output appear once.
2. `splitEnabled false renders only focused group` — only g1; no divider key.
3. `splitEnabled false honors focusedGroupIdOverride` — override wins over
   `focusedGroupId: 'g0'`.
4. `maximizedGroupId renders only that group` — only g0; no divider key.
5. `divider drag commits once on end and brackets pty hold` — drag +40px:
   holds `['begin','end']`, exactly one commit with path `[]`, fraction
   `closeTo((0.5*499+40)/499, 0.01)` (500px host − 1px divider = 499 content).
6. `divider drag clamps to minGroupExtent` — drag +600px with
   `minGroupExtent: 100` commits `closeTo(1 - 100/499, 0.002)`.
7. `nested branch drag reports its own path` — 3-group layout (g0 | [g1 / g2]
   vertical); dragging the nested divider commits path `[true]` and
   `closeTo((0.5*399+30)/399, 0.01)`.
8. `tap in group reports focus` — tap on `group-g0` fires
   `onGroupFocused('g0')`.
9. `double-tap divider fires onDividerDoubleTap` — two taps 100ms apart on the
   divider fire it once; the test pumps 500ms afterward so the double-tap
   recognizer's deadline timer doesn't outlive the test.

Brief adaptations applied: `find.textWidget` → local variable + `find.text`;
the skeleton's `find.byType(GestureDetector).first` (order-fragile) →
`find.byKey(workbenchSplitDividerKey(...))` via the exported key helper; the
skeleton's invalid `TabStripReducer().add(...)` record used as a strip →
destructured `.$1`. The double-tap tap uses `warnIfMissed: false` because the
opaque 12px strip intentionally sits above the leaf's translucent detector.

## Commands run (all sequential, via run_tests)

```
cd client && dart run tool/run_tests.dart test/widgets/workbench/workbench_split_layout_view_test.dart
  → 00:01 +9: All tests passed!   (after fixes; intermediate failures below)
cd client && dart run tool/run_tests.dart test/cubits/workbench/workbench_split_layout_test.dart
  → 00:00 +46: All tests passed!
cd client && dart run tool/run_tests.dart test/cubits/workbench/workbench_cubit_test.dart test/cubits/workbench/tab_strip_test.dart
  → 00:00 +60: All tests passed!
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
  → 351 pre-existing project-wide issues; 0 in the new files
  (grep for workbench_split_layout_view in analyzer output: no matches)
```

### Issues hit while implementing (all fixed)

1. **Unbounded cross-axis on the hit strip** — `Positioned(left, top, width)`
   without the opposite anchor gives the child an unbounded height constraint;
   `SizedBox.expand` inside `_Divider` exploded (`infinite size during layout`).
   Fixed by anchoring both cross-axis edges (`top:0,bottom:0` /
   `left:0,right:0`).
2. **Units bug in the live clamp** — I clamped the first pane's *pixel* extent
   against *fraction* bounds, so every drag committed `maxFraction`. Fixed to
   clamp `firstExtent / content`.
3. **Double-tap deadline timer** — the recognizer's 40ms timer outlived the
   widget test (`A Timer is still pending`); fixed by pumping 500ms at the end
   of the double-tap test.
