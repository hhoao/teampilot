# Terminal Switch Partial-Render Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the embedded terminal from briefly painting only part of its text when the user switches Session members / terminal tabs.

**Architecture:** The root cause is that the host **remounts** the `TerminalView` on every member/tab switch (the subtree is keyed by session/entry identity), which throws away render-layer state that is logically owned by the *viewport*, not the *engine*: the `GlyphCache` (font-keyed, content-agnostic) and the laid-out `_cols/_rows` geometry. A fresh `TerminalView` starts with an empty `GlyphCache`, and its painter rasterizes at most `maxBuildsPerFrame = 128` glyphs per frame — so the first frame of a glyph-rich (CJK / colorized) screen paints backgrounds plus the first 128 glyphs, leaving the rest blank until warmup frames fill them in. The fix makes the host **reuse the same `TerminalView` and swap only the `engine`/`controller` props** — exactly the engine-swap path the submodule already implements (`TerminalViewState.didUpdateWidget`, commit `d2fb4d0`). On engine swap the `GlyphCache` is *not* disposed (only `textStyle` changes dispose it), so it stays warm across switches and the partial-render disappears. No core submodule change is required; an optional follow-up makes the engine-swap viewport resize synchronous to remove a residual one-frame "content too small" flash.

**Tech Stack:** Flutter, `flutter_bloc`, `flutter_alacritty` (vendored submodule under `client/packages/flutter_alacritty`), `flutter_test`.

---

## Background / evidence (read before starting)

- Glyph budget: [glyph_cache.dart](../../../client/packages/flutter_alacritty/lib/render/glyph_cache.dart) — `maxBuildsPerFrame = 128`; `tryGet` returns `null` when the per-frame budget is exhausted.
- Painter skips null glyphs and schedules a warmup frame: [terminal_painter.dart:190-201,226](../../../client/packages/flutter_alacritty/lib/render/terminal_painter.dart#L190-L226).
- `GlyphCache` lives on `TerminalViewState`, created in `initState` ([terminal_view.dart:287](../../../client/packages/flutter_alacritty/lib/ui/terminal_view.dart#L287)); on engine swap it is **not** rebuilt — only `textStyle` change disposes it ([terminal_view.dart:356-366](../../../client/packages/flutter_alacritty/lib/ui/terminal_view.dart#L356-L366)).
- Engine swap is already handled: bell re-subscribe + grid-listener rewire + viewport sync ([terminal_view.dart:314-325](../../../client/packages/flutter_alacritty/lib/ui/terminal_view.dart#L314-L325)). `_engine`/`_grid` are **getters** over `widget.engine` ([terminal_view.dart:201,262](../../../client/packages/flutter_alacritty/lib/ui/terminal_view.dart#L201)), so the painter reads the swapped-in engine immediately.
- `_syncViewportToHost` resizes the engine **post-frame** ([terminal_view.dart:801-808](../../../client/packages/flutter_alacritty/lib/ui/terminal_view.dart#L801-L808)) — source of the residual one-frame flash (Task 4).
- Host remount points:
  - chat workbench: `AnimatedSwitcher` child keyed by `ValueKey(session.hashCode)` ([chat_workbench.dart:260-263](../../../client/lib/pages/chat_workbench.dart#L260-L263)).
  - workspace panel: `TerminalView(key: ValueKey(entry.id))` ([workspace_terminal_panel.dart:333-335](../../../client/lib/widgets/workspace_terminal_panel.dart#L333-L335)).
- Each member is a distinct `TerminalSession` (`tab.memberShells[selectedMemberId]`, [chat_cubit.dart:264-267](../../../client/lib/cubits/chat_cubit.dart#L264-L267)) → switching members changes `session.hashCode` → remount.

## File structure

| File | Responsibility | Change |
|------|----------------|--------|
| `client/packages/flutter_alacritty/lib/ui/terminal_view.dart` | Terminal view widget/state | Add `glyphCacheForTest` hook (Task 1); optional synchronous swap resize (Task 4) |
| `client/packages/flutter_alacritty/test/terminal_view_glyph_cache_swap_test.dart` | Submodule contract test | Create (Task 1); extend (Task 4) |
| `client/lib/pages/chat/chat_workbench_terminal.dart` | Chat-workbench terminal helpers | Add `chatWorkbenchTerminalViewKey` helper (Task 2) |
| `client/lib/pages/chat_workbench.dart` | Chat workbench shell | Use stable key from helper (Task 2) |
| `client/test/pages/chat_workbench_terminal_key_test.dart` | Key-helper unit test | Create (Task 2) |
| `client/lib/widgets/workspace_terminal_panel.dart` | Workspace terminal panel | Stable shared key + export it (Task 3) |
| `client/test/widgets/workspace_terminal_view_key_test.dart` | Workspace key reuse test | Create (Task 3) |

---

## Task 1: Lock the load-bearing contract — engine swap preserves the glyph cache

The entire fix relies on: *swapping the `engine` prop on a stable `TerminalView` does NOT rebuild the `GlyphCache`.* This is a guard/contract test. On the current submodule it **passes** (the swap branch never touches `_glyphs`); its job is to fail loudly if a future submodule change makes the swap dispose/recreate the cache.

**Files:**
- Modify: `client/packages/flutter_alacritty/lib/ui/terminal_view.dart` (add test hook near the other `@visibleForTesting` getters around line 264-274)
- Create: `client/packages/flutter_alacritty/test/terminal_view_glyph_cache_swap_test.dart`

- [ ] **Step 1: Add the glyph-cache test hook**

In `terminal_view.dart`, next to the existing `@visibleForTesting` getters (after `linkOverlayForTest` at line 274), add:

```dart
  @visibleForTesting
  GlyphCache get glyphCacheForTest => _glyphs;
```

Ensure `GlyphCache` is imported (it is used by `_glyphs`/`_newGlyphCache`; the type is already in scope via `render/glyph_cache.dart`). If not already imported, add:

```dart
import '../render/glyph_cache.dart';
```

- [ ] **Step 2: Write the contract test**

Create `client/packages/flutter_alacritty/test/terminal_view_glyph_cache_swap_test.dart`:

```dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_alacritty/config/terminal_config.dart';
import 'package:flutter_alacritty/engine/terminal_engine.dart';
import 'package:flutter_alacritty/render/mirror_grid.dart';
import 'package:flutter_alacritty/ui/terminal_view.dart';

import 'fake_binding.dart';

// Puts non-space text on row 0 so the painter actually rasterizes glyphs
// (spaces are skipped by the painter, so a blank grid never fills the cache).
class _TextFakeBinding extends FakeBinding {
  _TextFakeBinding(this.rowText);
  final String rowText;

  GridUpdate _snapshot() {
    const cols = 80, rows = 24;
    final codepoints = Int32List(cols)..fillRange(0, cols, 32);
    for (var i = 0; i < rowText.length && i < cols; i++) {
      codepoints[i] = rowText.codeUnitAt(i);
    }
    LineCells line(int i, Int32List cps) => LineCells(
          line: i,
          codepoints: cps,
          fg: Int32List(cols)..fillRange(0, cols, 0xD8D8D8),
          bg: Int32List(cols)..fillRange(0, cols, 0x181818),
          flags: Uint16List(cols),
          hyperlinkId: Int32List(cols),
        );
    return GridUpdate(
      full: true,
      rows: rows,
      columns: cols,
      lines: [
        line(0, codepoints),
        for (var i = 1; i < rows; i++)
          line(i, Int32List(cols)..fillRange(0, cols, 32)),
      ],
      cursorRow: 0,
      cursorCol: 0,
      cursorVisible: false,
      modeFlags: modeFlags,
    );
  }

  @override
  GridUpdate fullSnapshotSearched() => _snapshot();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'engine swap on a stable TerminalView preserves the glyph cache '
      '(no remount, no rebuild)', (tester) async {
    final binding1 = _TextFakeBinding('HELLO_WORLD_GLYPHS');
    final engine1 = TerminalEngine.fromBinding(
      binding1,
      config: TerminalConfig.defaults(),
      schedule: (_) {},
    );
    final binding2 = _TextFakeBinding('SECOND_ENGINE_TEXT');
    final engine2 = TerminalEngine.fromBinding(
      binding2,
      config: TerminalConfig.defaults(),
      schedule: (_) {},
    );
    addTearDown(() {
      engine1.dispose();
      engine2.dispose();
    });

    final engineNotifier = ValueNotifier<TerminalEngine>(engine1);
    addTearDown(engineNotifier.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<TerminalEngine>(
          valueListenable: engineNotifier,
          builder: (context, engine, _) => TerminalView(engine),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Prime engine1's grid from fullSnapshotSearched() via a throwaway click,
    // then pump so the painter rasterizes row-0 glyphs into the cache.
    final topLeft = tester.getTopLeft(find.byType(CustomPaint).first);
    final g = await tester.startGesture(topLeft + const Offset(2, 2));
    await g.up();
    await tester.pump();

    final stateBefore = tester.state<TerminalViewState>(find.byType(TerminalView));
    final cacheBefore = stateBefore.glyphCacheForTest;
    final lenBefore = cacheBefore.length;
    expect(lenBefore, greaterThan(0),
        reason: 'painting row-0 text should populate the glyph cache');

    // SWAP the engine — the host changes only the engine prop on the same view.
    engineNotifier.value = engine2;
    await tester.pump();

    final stateAfter = tester.state<TerminalViewState>(find.byType(TerminalView));
    expect(identical(stateAfter, stateBefore), isTrue,
        reason: 'engine swap must reuse the State (no remount)');
    expect(identical(stateAfter.glyphCacheForTest, cacheBefore), isTrue,
        reason: 'engine swap must NOT rebuild the GlyphCache — this warm cache '
            'is what prevents partial-text on member/tab switch');
    expect(stateAfter.glyphCacheForTest.length, greaterThanOrEqualTo(lenBefore),
        reason: 'previously rasterized glyphs must still be cached after swap');
  });
}
```

- [ ] **Step 3: Run the test — expect PASS (guard locks current behavior)**

Run: `cd client/packages/flutter_alacritty && flutter test test/terminal_view_glyph_cache_swap_test.dart`
Expected: PASS. (If it FAILS, the submodule's swap path is disposing the cache — stop and investigate before touching the host.)

- [ ] **Step 4: Commit**

```bash
git -C client/packages/flutter_alacritty add lib/ui/terminal_view.dart test/terminal_view_glyph_cache_swap_test.dart
git -C client/packages/flutter_alacritty commit -m "test(alacritty): lock glyph-cache survival across engine swap

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

> NOTE: `client/packages/flutter_alacritty` is a git submodule with its own history. Commit there first, then commit the submodule pointer bump in the superproject at the end (Task 5).

---

## Task 2: Chat workbench — reuse the running terminal across member/session switches

Replace the identity-based `ValueKey(session.hashCode)` with a **view-state** key so that switching between two *running* members keeps the same `AnimatedSwitcher` child (and thus the same `TerminalView` element → engine swap, warm cache). Loading / running / placeholder still animate between each other.

**Files:**
- Modify: `client/lib/pages/chat/chat_workbench_terminal.dart` (add helper near `bindChatWorkbenchTerminalController`, line 202)
- Modify: `client/lib/pages/chat_workbench.dart:262-263`
- Create: `client/test/pages/chat_workbench_terminal_key_test.dart`

- [ ] **Step 1: Write the failing unit test for the key helper**

Create `client/test/pages/chat_workbench_terminal_key_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/pages/chat/chat_workbench_terminal.dart';

void main() {
  group('chatWorkbenchTerminalViewKey', () {
    test('running key is stable and independent of session identity', () {
      // Two different running sessions must yield the SAME key so the
      // AnimatedSwitcher reuses the TerminalView element (engine swap) instead
      // of remounting it and rebuilding the glyph cache.
      final a = chatWorkbenchTerminalViewKey(loading: false, running: true);
      final b = chatWorkbenchTerminalViewKey(loading: false, running: true);
      expect(a, equals(b));
    });

    test('loading, running, and placeholder keys are distinct', () {
      final loading = chatWorkbenchTerminalViewKey(loading: true, running: false);
      final running = chatWorkbenchTerminalViewKey(loading: false, running: true);
      final placeholder =
          chatWorkbenchTerminalViewKey(loading: false, running: false);
      expect(loading, isNot(equals(running)));
      expect(running, isNot(equals(placeholder)));
      expect(loading, isNot(equals(placeholder)));
    });

    test('loading takes precedence over running', () {
      final loading = chatWorkbenchTerminalViewKey(loading: true, running: true);
      final running = chatWorkbenchTerminalViewKey(loading: false, running: true);
      expect(loading, isNot(equals(running)));
    });
  });
}
```

- [ ] **Step 2: Run the test — expect FAIL (helper does not exist)**

Run: `cd client && flutter test test/pages/chat_workbench_terminal_key_test.dart`
Expected: FAIL — compile error, `chatWorkbenchTerminalViewKey` undefined.

- [ ] **Step 3: Implement the helper**

In `client/lib/pages/chat/chat_workbench_terminal.dart`, add above `bindChatWorkbenchTerminalController` (line 202):

```dart
/// Key for the `AnimatedSwitcher` terminal child in the chat workbench.
///
/// The running terminal uses a STABLE key (independent of which session/member
/// is shown) so switching members reuses the same `TerminalView` element. That
/// triggers the submodule's engine-swap path (`didUpdateWidget`) instead of a
/// remount, keeping the glyph cache and viewport geometry warm — otherwise a
/// freshly mounted `TerminalView` paints partial text while its empty glyph
/// cache warms up over several frames. Loading / placeholder keep their own
/// keys so transitions to/from them still cross-fade.
Key chatWorkbenchTerminalViewKey({
  required bool loading,
  required bool running,
}) {
  if (loading) return const ValueKey('chat-terminal-loading');
  if (running) return const ValueKey('chat-terminal-running');
  return const ValueKey('chat-terminal-placeholder');
}
```

- [ ] **Step 4: Run the test — expect PASS**

Run: `cd client && flutter test test/pages/chat_workbench_terminal_key_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Wire the helper into the workbench**

In `client/lib/pages/chat_workbench.dart`, replace the keyed `Container` at lines 262-263. Change:

```dart
          child: Container(
            key: ValueKey(session.hashCode),
```

to:

```dart
          child: Container(
            key: chatWorkbenchTerminalViewKey(
              loading: sessionConnectInProgress,
              running: session.isRunning,
            ),
```

`chatWorkbenchTerminalViewKey` is already importable: `chat_workbench.dart` already imports `chat/chat_workbench_terminal.dart` (it uses `ChatWorkbenchRunningTerminal` / `bindChatWorkbenchTerminalController`). If analyze reports it missing, add:

```dart
import 'chat/chat_workbench_terminal.dart';
```

- [ ] **Step 6: Analyze + run the suite touching chat workbench**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/pages/chat_workbench.dart lib/pages/chat/chat_workbench_terminal.dart`
Expected: No new errors.

Run: `cd client && flutter test test/pages/chat_workbench_terminal_key_test.dart test/pages/chat_page_personal_test.dart test/pages/chat_page_rebuild_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add client/lib/pages/chat/chat_workbench_terminal.dart client/lib/pages/chat_workbench.dart client/test/pages/chat_workbench_terminal_key_test.dart
git commit -m "fix(chat): reuse running terminal view across member switches

Key the AnimatedSwitcher child by view state, not session identity, so
switching members swaps the engine on a stable TerminalView (warm glyph
cache) instead of remounting it and painting partial text.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Workspace terminal panel — reuse the terminal view across tab switches

Same fix for the workspace terminal panel: replace the per-entry `ValueKey(entry.id)` with a single stable key so switching entries swaps the engine on a reused `TerminalView`.

**Files:**
- Modify: `client/lib/widgets/workspace_terminal_panel.dart:333-335`
- Create: `client/test/widgets/workspace_terminal_view_key_test.dart`

- [ ] **Step 1: Write the failing element-reuse test**

Create `client/test/widgets/workspace_terminal_view_key_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/widgets/workspace_terminal_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'kWorkspaceTerminalViewKey keeps the TerminalView element across an '
      'engine swap (no remount)', (tester) async {
    final engine1 = TerminalEngine(config: TerminalConfig.defaults());
    final engine2 = TerminalEngine(config: TerminalConfig.defaults());
    addTearDown(() {
      engine1.dispose();
      engine2.dispose();
    });

    final engineNotifier = ValueNotifier<TerminalEngine>(engine1);
    addTearDown(engineNotifier.dispose);

    // Mirror the panel's keying: a TerminalView under the shared stable key,
    // swapping only the engine prop. With a per-entry key this would remount
    // and `identical(before, after)` would fail.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<TerminalEngine>(
          valueListenable: engineNotifier,
          builder: (context, engine, _) => TerminalView(
            engine,
            key: kWorkspaceTerminalViewKey,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final before = tester.element(find.byType(TerminalView));
    engineNotifier.value = engine2;
    await tester.pump();
    final after = tester.element(find.byType(TerminalView));

    expect(identical(before, after), isTrue,
        reason: 'a stable key must reuse the TerminalView element on engine '
            'swap so the glyph cache stays warm (no partial-text flash)');
  });
}
```

- [ ] **Step 2: Run the test — expect FAIL (constant does not exist)**

Run: `cd client && flutter test test/widgets/workspace_terminal_view_key_test.dart`
Expected: FAIL — compile error, `kWorkspaceTerminalViewKey` undefined.

- [ ] **Step 3: Add the stable key constant and use it**

In `client/lib/widgets/workspace_terminal_panel.dart`, add a top-level constant near the top of the file (after the imports, before the first class):

```dart
/// Stable key for the workspace terminal's `TerminalView`. Shared across all
/// entries so switching tabs swaps the engine on a reused view (warm glyph
/// cache) instead of remounting and painting partial text. See
/// `chatWorkbenchTerminalViewKey` for the chat-workbench counterpart.
const Key kWorkspaceTerminalViewKey = ValueKey('workspace-terminal-view');
```

Then in `_WorkspaceTerminalView.build` (lines 333-335), change:

```dart
      child: TerminalView(
        entry.session.engine,
        key: ValueKey(entry.id),
```

to:

```dart
      child: TerminalView(
        entry.session.engine,
        key: kWorkspaceTerminalViewKey,
```

Note: each entry carries its own `entry.controller`; the submodule's `didUpdateWidget` controller branch ([terminal_view.dart:328-332](../../../client/packages/flutter_alacritty/lib/ui/terminal_view.dart#L328-L332)) re-attaches the swapped-in controller without disposing the host-owned old one — no extra change needed.

- [ ] **Step 4: Run the test — expect PASS**

Run: `cd client && flutter test test/widgets/workspace_terminal_view_key_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings lib/widgets/workspace_terminal_panel.dart`
Expected: No new errors.

- [ ] **Step 6: Commit**

```bash
git add client/lib/widgets/workspace_terminal_panel.dart client/test/widgets/workspace_terminal_view_key_test.dart
git commit -m "fix(workspace): reuse terminal view across tab switches

Use a shared stable key so switching workspace terminal tabs swaps the
engine on a reused TerminalView (warm glyph cache) instead of remounting.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4 (OPTIONAL): Remove the residual one-frame "content too small" flash

**Do this only if, after Tasks 2-3, switching to a member/tab whose engine was started in the background still shows a one-frame flash where content paints in a smaller-than-full region.** This is Cause A: on engine swap `_syncViewportToHost` resizes the engine *post-frame*, so the swap frame paints the incoming engine's stale background grid (e.g. 80×24) before it is resized. Verify manually first (below) — if not visible, skip this task.

**Files:**
- Modify: `client/packages/flutter_alacritty/lib/ui/terminal_view.dart:314-325`
- Modify: `client/packages/flutter_alacritty/test/terminal_view_glyph_cache_swap_test.dart`

- [ ] **Step 1: Write the failing test — engine reaches full geometry on the swap frame**

Append to `client/packages/flutter_alacritty/test/terminal_view_glyph_cache_swap_test.dart` (inside `main`):

```dart
  testWidgets(
      'engine swap resizes the incoming engine to the live viewport geometry',
      (tester) async {
    final engine1 = TerminalEngine(config: TerminalConfig.defaults());
    final engine2 = TerminalEngine(config: TerminalConfig.defaults());
    addTearDown(() {
      engine1.dispose();
      engine2.dispose();
    });

    final engineNotifier = ValueNotifier<TerminalEngine>(engine1);
    addTearDown(engineNotifier.dispose);

    // A small, fixed viewport so the laid-out grid is well under the engine's
    // 80x24 background default — the resize is then observable.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 200,
            height: 120,
            child: ValueListenableBuilder<TerminalEngine>(
              valueListenable: engineNotifier,
              builder: (context, engine, _) => TerminalView(engine),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final state = tester.state<TerminalViewState>(find.byType(TerminalView));
    final cols = state.viewportColsForTest;
    final rows = state.viewportRowsForTest;
    expect(cols, lessThan(80),
        reason: 'sanity: the small viewport must compute fewer than 80 cols');

    // Swap to a background engine still at its default size; after one frame the
    // incoming engine must already be at the viewport geometry (synchronous
    // resize), not a frame behind.
    engineNotifier.value = engine2;
    await tester.pump();

    expect(engine2.gridForView.columns, cols,
        reason: 'swapped-in engine must be resized to the viewport synchronously '
            'so its first painted frame uses the full grid, not 80x24');
    expect(engine2.gridForView.rows, rows);
  });
```

Add the geometry hooks to `terminal_view.dart` next to the other `@visibleForTesting` getters:

```dart
  @visibleForTesting
  int get viewportColsForTest => _cols;

  @visibleForTesting
  int get viewportRowsForTest => _rows;
```

> Confirm `engine.gridForView` exposes `columns`/`rows` (it is the `MirrorGrid` the painter reads — see `grid.columns`/`grid.rows` usage in [terminal_painter.dart:113](../../../client/packages/flutter_alacritty/lib/render/terminal_painter.dart#L113)). If `gridForView` is not yet populated for a never-painted engine, assert against `engine.cols`/`engine.rows` instead (whichever the engine exposes for its term size) — pick the accessor that reflects `engine.resize(...)`.

- [ ] **Step 2: Run the test — expect FAIL (resize is post-frame)**

Run: `cd client/packages/flutter_alacritty && flutter test test/terminal_view_glyph_cache_swap_test.dart`
Expected: the new test FAILS — `engine2` is still at 80 cols after one frame because `_syncViewportToHost` deferred the resize to a post-frame callback.

- [ ] **Step 3: Make the engine-swap resize synchronous**

In `terminal_view.dart`, inside the engine-swap branch (replace the `_syncViewportToHost(_cols, _rows);` call at line 324). Change:

```dart
      // TeamPilot-style hosts swap engines per member while the view keeps the
      // same layout cols/rows. _ensureSizing would skip onViewportResize, leaving
      // a PTY started in the background at 80×24 while the painter is full-screen.
      _syncViewportToHost(_cols, _rows);
```

to:

```dart
      // TeamPilot-style hosts swap engines per member while the view keeps the
      // same layout cols/rows. Resize the incoming engine to the live viewport
      // SYNCHRONOUSLY so its first painted frame uses the full grid instead of
      // the size it was started at in the background (e.g. 80×24). Only the host
      // notification is deferred to post-frame (it may call setState).
      if (_cols > 0 && _rows > 0) {
        _engine.resize(columns: _cols, rows: _rows);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          widget.onViewportResize?.call(_cols, _rows);
        });
      }
```

- [ ] **Step 4: Run the test — expect PASS, and re-run the whole submodule suite**

Run: `cd client/packages/flutter_alacritty && flutter test test/terminal_view_glyph_cache_swap_test.dart`
Expected: both tests PASS.

Run: `cd client/packages/flutter_alacritty && flutter test`
Expected: PASS — in particular `terminal_view_callback_test.dart` ("bell after engine swap still flashes") and any first-layout / font-zoom resize tests must remain green.

- [ ] **Step 5: Commit**

```bash
git -C client/packages/flutter_alacritty add lib/ui/terminal_view.dart test/terminal_view_glyph_cache_swap_test.dart
git -C client/packages/flutter_alacritty commit -m "fix(alacritty): resize incoming engine synchronously on engine swap

Removes the one-frame small-grid flash when a host swaps to an engine
started in the background at 80x24. Host notification stays post-frame.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Full verification + submodule pointer bump

**Files:** none new — runs the full gates and records any submodule pointer change.

- [ ] **Step 1: Full analyze + test (host)**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`
Expected: analyze clean of new issues; all tests PASS.

- [ ] **Step 2: Full submodule test (only if Task 1 or Task 4 changed the submodule)**

Run: `cd client/packages/flutter_alacritty && flutter test`
Expected: PASS.

- [ ] **Step 3: Manual golden-path verification (CI cannot render glyph warmup)**

Launch the app (`cd client && flutter run -d windows`, or the platform you use). Then:
1. Team mode: open a team session with ≥2 members producing glyph-rich / CJK output. Rapidly switch the selected member back and forth. **Expected:** the terminal shows full text immediately on each switch — no frame where only part of the characters are present.
2. Workspace terminal panel: open ≥2 terminal tabs with content, switch between them. **Expected:** no partial-text flash.
3. If Task 4 was implemented: switch to a member whose CLI was started in the background and not yet viewed. **Expected:** no one-frame "content too small" flash.
4. Sanity: connect → loading → running and running → disconnect (placeholder) still transition correctly (these keep their own keys and may cross-fade).

- [ ] **Step 4: Bump the submodule pointer (only if the submodule was committed in Task 1/4)**

```bash
git add client/packages/flutter_alacritty
git commit -m "chore: bump flutter_alacritty for terminal-swap render fixes

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-review checklist (done while writing — re-verify before execution)

- **Spec coverage:** Cause B (empty glyph cache on remount) → Tasks 2 & 3 (reuse view) guarded by Task 1's contract test. Cause A (post-frame resize, one-frame small grid) → optional Task 4. Verification → Task 5. ✅
- **No placeholders:** every code step shows full code and exact commands. ✅
- **Type/name consistency:** `chatWorkbenchTerminalViewKey(loading:, running:)`, `kWorkspaceTerminalViewKey`, `glyphCacheForTest`, `viewportColsForTest`/`viewportRowsForTest` used identically in their defining task and any referencing task. ✅
- **Submodule discipline:** submodule (`client/packages/flutter_alacritty`) is committed in its own repo first (Tasks 1, 4), pointer bumped in superproject last (Task 5). ✅
- **Risk note:** Tasks 2-3 alter the `AnimatedSwitcher` transition — switching between two running members/tabs no longer cross-fades (it swaps in place). This is intended; if a cross-fade is later desired it must be implemented as an overlay, never by remounting the engine view (that reintroduces the bug).
