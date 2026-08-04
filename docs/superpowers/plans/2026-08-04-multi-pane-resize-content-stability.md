# MultiPane Resize Content Stability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop `MultiPane` from re-invoking `paneBuilder` on every size/resize notify so sidebar drag only updates slot sizes (industry SplitView/sash pattern).

**Architecture:** Add a private `_StablePaneContent` StatefulWidget that caches the last `paneBuilder` output and rebuilds it only when `paneId`, `animationProgress`, or `paneBuilder` identity changes. Wire it on pixel, fraction, and maximize paths. Clear/remount content when `MultiPane`’s `controller` or `paneBuilder` is replaced.

**Tech Stack:** Flutter / Dart (`panes` package), `flutter_test`

**Spec:** `docs/superpowers/specs/2026-08-04-multi-pane-resize-content-stability-design.md`

---

## File map

| File | Role |
|------|------|
| `client/packages/panes/test/widget_test.dart` | Failing then passing tests: resize stability, show/hide once, maximize invalidate |
| `client/packages/panes/lib/src/multi_pane.dart` | `_StablePaneContent` + use it in `_buildPanes`; remount on controller/`paneBuilder` swap |

No app (`WorkspaceIdeShell`) or `PaneController` API changes.

---

### Task 1: Failing tests for resize / visibility / maximize stability

**Files:**
- Modify: `client/packages/panes/test/widget_test.dart`

- [ ] **Step 1: Add resize + show/hide + maximize builder-count tests**

Append inside the existing `group('MultiPane', () { ... })` (after the animation-tick test is fine):

```dart
    testWidgets(
      'paneBuilder is not invoked again on resize deltas',
      (tester) async {
        final controller = PaneController(
          entries: [
            PaneEntry(id: 'a', initialSize: PaneSize.pixel(100)),
            PaneEntry(id: 'b', initialSize: PaneSize.fraction(1.0)),
            PaneEntry(id: 'c', initialSize: PaneSize.pixel(120)),
          ],
        );
        final builds = <String, int>{'a': 0, 'b': 0, 'c': 0};

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 400,
                child: MultiPane(
                  direction: Axis.horizontal,
                  controller: controller,
                  paneBuilder: (context, id, progress) {
                    builds[id] = (builds[id] ?? 0) + 1;
                    return Container(key: Key('pane_$id'));
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final afterLayout = Map<String, int>.from(builds);
        expect(afterLayout['a'], greaterThan(0));
        expect(afterLayout['b'], greaterThan(0));
        expect(afterLayout['c'], greaterThan(0));

        controller.beginResize('a', adjacentPaneId: 'b');
        await tester.pump();
        for (var i = 0; i < 5; i++) {
          controller.resize(
            paneId: 'a',
            delta: 4,
            containerSize: 800,
            resizerThickness: 1,
            adjacentPaneId: 'b',
          );
          await tester.pump();
        }
        controller.endResize('a', adjacentPaneId: 'b');
        await tester.pump();

        expect(
          builds,
          afterLayout,
          reason: 'size-only notifies must reuse pane content',
        );

        // Right-edge style: resize pixel pane next to fraction.
        final beforeRight = Map<String, int>.from(builds);
        controller.beginResize('c', adjacentPaneId: 'b');
        await tester.pump();
        controller.resize(
          paneId: 'c',
          delta: -8,
          containerSize: 800,
          resizerThickness: 1,
          adjacentPaneId: 'b',
        );
        await tester.pump();
        controller.endResize('c', adjacentPaneId: 'b');
        await tester.pump();
        expect(builds, beforeRight);
      },
    );

    testWidgets(
      'paneBuilder runs once on hide, not on size-tween ticks',
      (tester) async {
        final controller = PaneController(
          entries: [
            PaneEntry(id: 'a', initialSize: PaneSize.pixel(100)),
            PaneEntry(id: 'b', initialSize: PaneSize.fraction(1.0)),
          ],
        );
        var buildsA = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MultiPane(
                direction: Axis.horizontal,
                controller: controller,
                animationDuration: const Duration(milliseconds: 200),
                paneBuilder: (context, id, progress) {
                  if (id == 'a') buildsA++;
                  return Container(key: Key('pane_$id'));
                },
              ),
            ),
          ),
        );
        await tester.pump(); // start; do not settle open animation fully

        final afterFirst = buildsA;
        expect(afterFirst, greaterThan(0));

        controller.hide('a');
        await tester.pump(); // apply visibility → progress 0; builder once
        final afterHide = buildsA;
        expect(afterHide, greaterThan(afterFirst));

        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          buildsA,
          afterHide,
          reason: 'hide size tween must not re-invoke paneBuilder',
        );
      },
    );

    testWidgets(
      'maximize then restore re-invokes paneBuilder',
      (tester) async {
        final controller = PaneController(
          entries: [
            PaneEntry(id: 'a', initialSize: PaneSize.pixel(100)),
            PaneEntry(id: 'b', initialSize: PaneSize.fraction(1.0)),
          ],
        );
        var buildsB = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MultiPane(
                direction: Axis.horizontal,
                controller: controller,
                paneBuilder: (context, id, progress) {
                  if (id == 'b') buildsB++;
                  return Container(key: Key('pane_$id'));
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final baseline = buildsB;

        controller.maximize('b');
        await tester.pump();
        expect(buildsB, greaterThan(baseline));

        final afterMax = buildsB;
        controller.restore();
        await tester.pump();
        expect(buildsB, greaterThan(afterMax));
      },
    );
```

- [ ] **Step 2: Run tests — expect resize test FAIL**

Run:

```bash
cd client/packages/panes && flutter test test/widget_test.dart --name "paneBuilder is not invoked again on resize"
```

Expected: FAIL — `builds` grows on each `resize` / `pump` (current `MultiPane` calls `paneBuilder` every `setState`).

- [ ] **Step 3: Commit failing tests**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/packages/panes/test/widget_test.dart
git commit -m "$(cat <<'EOF'
test(panes): expect MultiPane content stable across resize

EOF
)"
```

---

### Task 2: Implement `_StablePaneContent` and wire MultiPane

**Files:**
- Modify: `client/packages/panes/lib/src/multi_pane.dart`

- [ ] **Step 1: Add `_StablePaneContent` at bottom of `multi_pane.dart` (before or after `ResizerWrapper`)**

```dart
/// Caches [paneBuilder] output so size-only [MultiPane] rebuilds do not
/// reconstruct pane content (resize / animation ticks).
class _StablePaneContent extends StatefulWidget {
  const _StablePaneContent({
    super.key,
    required this.paneId,
    required this.animationProgress,
    required this.paneBuilder,
  });

  final String paneId;
  final double animationProgress;
  final PaneBuilder paneBuilder;

  @override
  State<_StablePaneContent> createState() => _StablePaneContentState();
}

class _StablePaneContentState extends State<_StablePaneContent> {
  Widget? _child;

  @override
  void didUpdateWidget(covariant _StablePaneContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paneId != widget.paneId ||
        oldWidget.animationProgress != widget.animationProgress ||
        oldWidget.paneBuilder != widget.paneBuilder) {
      _child = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _child ??= widget.paneBuilder(
      context,
      widget.paneId,
      widget.animationProgress,
    );
  }
}
```

- [ ] **Step 2: Remount content when controller or paneBuilder is replaced**

In `_MultiPaneState`:

```dart
  /// Bumped when content must drop cached pane widgets.
  int _contentEpoch = 0;

  @override
  void didUpdateWidget(MultiPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_rebuild);
      widget.controller.addListener(_rebuild);
      _contentEpoch++;
    }
    if (oldWidget.paneBuilder != widget.paneBuilder) {
      _contentEpoch++;
    }
  }

  Widget _paneContent(
    BuildContext context,
    String paneId,
    double animationProgress,
  ) {
    return _StablePaneContent(
      key: ValueKey<String>('stable-$paneId-$_contentEpoch'),
      paneId: paneId,
      animationProgress: animationProgress,
      paneBuilder: widget.paneBuilder,
    );
  }
```

- [ ] **Step 3: Replace direct `paneBuilder` calls in `_buildPanes`**

Maximize branch:

```dart
    if (widget.controller.maximizedPaneId case final maxId?) {
      return SizedBox.expand(
        child: _paneContent(context, maxId, 1.0),
      );
    }
```

Pixel `TweenAnimationBuilder.child`:

```dart
            child: _paneContent(
              context,
              entry.id,
              isVisible ? 1.0 : 0.0,
            ),
```

Fraction `Expanded` child:

```dart
                child: _paneContent(context, entry.id, 1.0),
```

Do **not** change resizer / `SizedBox` / tween duration logic.

- [ ] **Step 4: Run all MultiPane widget tests**

```bash
cd client/packages/panes && flutter test test/widget_test.dart
```

Expected: PASS (including new resize / hide / maximize tests and existing animation-tick + LayoutBuilder tests).

- [ ] **Step 5: Commit implementation**

```bash
cd /home/hhoa/git/hhoa/teampilot
git add client/packages/panes/lib/src/multi_pane.dart client/packages/panes/test/widget_test.dart
git commit -m "$(cat <<'EOF'
perf(panes): keep MultiPane content stable across resize

EOF
)"
```

---

### Task 3: Optional package README note + verify suite

**Files:**
- Modify (optional, short): `client/packages/panes/README.md` — one sentence under MultiPane that content is stable across size changes / drag
- Test: full panes package tests

- [ ] **Step 1: Run full panes tests**

```bash
cd client/packages/panes && flutter test
```

Expected: all PASS.

- [ ] **Step 2: If README updated, commit**

```bash
git add client/packages/panes/README.md
git commit -m "$(cat <<'EOF'
docs(panes): note MultiPane content stability on resize

EOF
)"
```

---

## Manual check (not blocking CI)

With right tools + file tree open in TeamPilot profile/debug:

1. Left sash drag — Rebuild Stats should not mass-rebuild `FileTreeNode`.
2. Right sash drag — no rebuild storm; remaining cost is layout of the resizing pane.

---

## Execution handoff

After this plan is approved, implement via **subagent-driven-development** (recommended) or **executing-plans**.
