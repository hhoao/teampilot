# Workspace Panes IDE Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace nested workspace `ResizableSplitView` hosts with an app-owned `WorkspaceIdeShell` backed by `panes` (`MultiPane`), full-bleed bottom terminal, `LayoutCubit` as sole layout intent, medium Islands chrome, and a single narrow/wide policy.

**Architecture:** Pure `WorkspacePanePolicy` computes effective docked/overlay visibility from prefs + viewport. `WorkspaceIdeShell` owns pane controllers, syncs drag-end sizes back to `LayoutCubit`, holds PTY resize during drag, and mounts existing sidebar / center workbench / right tools / terminal builders. Prefer nested `MultiPane` (horizontal row over full-bleed bottom) over `IdeLayout` if `IdeLayout` nests bottom under center only.

**Tech Stack:** Flutter / Dart, `flutter_bloc`, `panes: ^1.3.0`, existing `LayoutCubit` / `LayoutPreferences`, `TerminalLayoutCoordinator`.

**Spec:** [docs/superpowers/specs/2026-07-10-workspace-panes-ide-shell-design.md](../specs/2026-07-10-workspace-panes-ide-shell-design.md)

**Constraints:** No `WorkbenchCubit` semantic changes. No panes `TabbedPane` for center tabs. No panes `save()`/`load()` as persistence. Do not mix this PR series with center-tabs identity work.

---

## File map (target)

| File | Responsibility |
|------|----------------|
| `client/lib/services/workspace/workspace_pane_policy.dart` | Pure effective layout from prefs + width (+ optional route context) |
| `client/lib/pages/workspace_ide/workspace_ide_shell.dart` | Shell widget: controllers, builders, overlay host, PTY hold |
| `client/lib/pages/workspace_ide/workspace_ide_pane_sync.dart` | Prefs/effective → controller sizes/visibility; drag-end → cubit |
| `client/lib/pages/workspace_ide/workspace_ide_pane_chrome.dart` | Islands gutter + rounded panel wrapper + `PaneTheme` |
| `client/lib/pages/workspace_ide/pane_overlay_host.dart` | Narrow left/right overlay by pane id |
| `client/lib/models/layout_preferences.dart` | Add `sidebarVisible`; keep size clamps |
| `client/lib/cubits/layout_cubit.dart` | `setSidebarVisible` |
| `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart` | Bind scope + mount `WorkspaceIdeShell` (drop local sidebar split) |
| `client/lib/pages/chat/chat_page_shell.dart` | Center-only content; remove split/drawer geometry |
| `client/lib/pages/workspace_shell/workspace_shell.dart` | Remove `WorkspaceShellMainWithTerminal` wrap (terminal moves to IdeShell) |
| Delete after cutover | `right_tools_host.dart`; `WorkspaceShellMainWithTerminal` / center-column helpers if unused |
| `client/pubspec.yaml` | `panes: ^1.3.0` |

---

### Task 1: Spike panes geometry + add dependency

**Files:**
- Modify: `client/pubspec.yaml`
- Optional throwaway: `client/tool/panes_spike/` or a temporary widget behind a debug flag (delete before merge if not needed)

- [ ] **Step 1: Add dependency**

```yaml
# client/pubspec.yaml — under dependencies:
  panes: ^1.3.0
```

Run: `cd client && flutter pub get`

Expected: resolves `panes` 1.3.x

- [ ] **Step 2: Spike checklist (document findings in PR / commit message)**

Verify against spec success criteria:

1. Can build **full-bleed bottom** under left+center+right using nested `MultiPane` (vertical: top row + bottom)?
2. Does `IdeLayout` nest bottom under center only? If yes, **do not use `IdeLayout` for production shell** — use `MultiPane` tree only.
3. Does hiding a pane dispose its child `State`? If yes, shell must keep children mounted (Offstage / size-zero / custom visibility) while syncing controller.
4. Are there drag start/end or size-change callbacks usable for PTY hold + drag-end cubit commit?
5. Pick narrow breakpoint constant (candidate **840.0** logical px) and write it into `WorkspacePanePolicy` in Task 2.

If (1) or (3) fails unacceptably: keep shell/policy APIs in later tasks but implement geometry with nested `ResizableSplitView` instead of panes (spec fallback). Still add `panes` only if used.

- [ ] **Step 3: Commit**

```bash
git add client/pubspec.yaml client/pubspec.lock
git commit -m "$(cat <<'EOF'
chore: add panes dependency for workspace IDE shell

EOF
)"
```

**Recommended order:** complete **Task 3** (`sidebarVisible`) before Task 2 tests compile cleanly; Task 1 spike can run anytime before Task 5.

---

### Task 2: `WorkspacePanePolicy` (TDD)

**Files:**
- Create: `client/lib/services/workspace/workspace_pane_policy.dart`
- Create: `client/test/services/workspace/workspace_pane_policy_test.dart`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/layout_preferences.dart';
import 'package:teampilot/services/workspace/workspace_pane_policy.dart';

void main() {
  const prefs = LayoutPreferences(
    sidebarVisible: true,
    rightToolsVisible: true,
    workspaceTerminalVisible: true,
  );

  test('wide docks all intent-visible panes', () {
    final e = WorkspacePanePolicy.effective(
      preferences: prefs,
      viewportWidth: 1200,
    );
    expect(e.isNarrow, isFalse);
    expect(e.dockLeft, isTrue);
    expect(e.dockRight, isTrue);
    expect(e.dockBottom, isTrue);
    expect(e.overlayLeft, isFalse);
    expect(e.overlayRight, isFalse);
  });

  test('narrow undocks sides; intent keeps overlay eligibility', () {
    final e = WorkspacePanePolicy.effective(
      preferences: prefs,
      viewportWidth: 700,
    );
    expect(e.isNarrow, isTrue);
    expect(e.dockLeft, isFalse);
    expect(e.dockRight, isFalse);
    expect(e.overlayLeft, isTrue);
    expect(e.overlayRight, isTrue);
    expect(e.dockBottom, isTrue); // bottom still follows intent when not forced
  });

  test('narrow + hidden intent → no overlay eligibility', () {
    final e = WorkspacePanePolicy.effective(
      preferences: prefs.copyWith(
        sidebarVisible: false,
        rightToolsVisible: false,
      ),
      viewportWidth: 700,
    );
    expect(e.overlayLeft, isFalse);
    expect(e.overlayRight, isFalse);
  });

  test('compose and session visibility match in v1', () {
    final session = WorkspacePanePolicy.effective(
      preferences: prefs,
      viewportWidth: 1200,
      composeLanding: false,
    );
    final compose = WorkspacePanePolicy.effective(
      preferences: prefs,
      viewportWidth: 1200,
      composeLanding: true,
    );
    expect(compose.dockLeft, session.dockLeft);
    expect(compose.dockRight, session.dockRight);
    expect(compose.dockBottom, session.dockBottom);
  });
}
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `cd client && flutter test test/services/workspace/workspace_pane_policy_test.dart`

Expected: FAIL until `sidebarVisible` (Task 3) and this library exist. **Do Task 3 first if needed**, then return.

- [ ] **Step 3: Implement policy**

```dart
import '../../models/layout_preferences.dart';

class WorkspacePaneEffective {
  const WorkspacePaneEffective({
    required this.isNarrow,
    required this.dockLeft,
    required this.dockRight,
    required this.dockBottom,
    required this.overlayLeft,
    required this.overlayRight,
  });

  final bool isNarrow;
  final bool dockLeft;
  final bool dockRight;
  final bool dockBottom;
  final bool overlayLeft;
  final bool overlayRight;
}

abstract final class WorkspacePanePolicy {
  /// Logical px; confirm/adjust in Task 1 spike.
  static const double narrowBreakpointWidth = 840;

  static WorkspacePaneEffective effective({
    required LayoutPreferences preferences,
    required double viewportWidth,
    bool composeLanding = false,
  }) {
    // v1: composeLanding unused for visibility (spec: compose≡session).
    // v1: LayoutPreset mapping not implemented (extension point only).
    final narrow = viewportWidth < narrowBreakpointWidth;
    if (!narrow) {
      return WorkspacePaneEffective(
        isNarrow: false,
        dockLeft: preferences.sidebarVisible,
        dockRight: preferences.rightToolsVisible,
        dockBottom: preferences.workspaceTerminalVisible,
        overlayLeft: false,
        overlayRight: false,
      );
    }
    return WorkspacePaneEffective(
      isNarrow: true,
      dockLeft: false,
      dockRight: false,
      dockBottom: preferences.workspaceTerminalVisible,
      overlayLeft: preferences.sidebarVisible,
      overlayRight: preferences.rightToolsVisible,
    );
  }
}
```

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd client && flutter test test/services/workspace/workspace_pane_policy_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/workspace/workspace_pane_policy.dart \
  client/test/services/workspace/workspace_pane_policy_test.dart
git commit -m "$(cat <<'EOF'
feat: add WorkspacePanePolicy for IDE shell breakpoints

EOF
)"
```

---

### Task 3: `sidebarVisible` + prefs round-trip

**Files:**
- Modify: `client/lib/models/layout_preferences.dart`
- Modify: `client/lib/cubits/layout_cubit.dart`
- Modify: `client/test/models/layout_preferences_default_test.dart`

- [ ] **Step 1: Extend failing/default test**

```dart
test('sidebarVisible defaults true and round-trips', () {
  expect(const LayoutPreferences().sidebarVisible, isTrue);
  final parsed = LayoutPreferences.fromJson(const {'sidebarVisible': false});
  expect(parsed.sidebarVisible, isFalse);
  expect(parsed.toJson()['sidebarVisible'], isFalse);
});
```

- [ ] **Step 2: Run — expect FAIL**

Run: `cd client && flutter test test/models/layout_preferences_default_test.dart`

- [ ] **Step 3: Add field everywhere `LayoutPreferences` constructs / copies / JSON**

- Constructor default `sidebarVisible = true`
- `fromJson`: `json['sidebarVisible'] as bool? ?? true`
- `copyWith` / `withAtLeastOneToolVisible` / `toJson` / `props` if Equatable
- `LayoutCubit.setSidebarVisible(bool visible)`

- [ ] **Step 4: Run tests PASS + analyze prefs/cubit**

Run: `cd client && flutter test test/models/layout_preferences_default_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/models/layout_preferences.dart \
  client/lib/cubits/layout_cubit.dart \
  client/test/models/layout_preferences_default_test.dart
git commit -m "$(cat <<'EOF'
feat: persist sidebarVisible in layout preferences

EOF
)"
```

---

### Task 4: Pane sync helper (TDD, no widgets)

**Files:**
- Create: `client/lib/pages/workspace_ide/workspace_ide_pane_sync.dart`
- Create: `client/test/pages/workspace_ide/workspace_ide_pane_sync_test.dart`

Goal: pure/easy-to-test mapping from `(LayoutPreferences, WorkspacePaneEffective)` → desired sizes + dock flags, and a small “pending drag size” holder that only exposes `commit` values on drag end (no Flutter).

- [ ] **Step 1: Failing test — breakpoint does not invent intent writes**

```dart
test('effective narrow docks false while prefs intent stays true', () {
  const prefs = LayoutPreferences(
    sidebarVisible: true,
    rightToolsVisible: true,
    sidebarWidth: 260,
    rightToolsWidth: 320,
    workspaceTerminalHeight: 220,
  );
  final effective = WorkspacePanePolicy.effective(
    preferences: prefs,
    viewportWidth: 700,
  );
  final snapshot = WorkspaceIdePaneSnapshot.from(
    preferences: prefs,
    effective: effective,
  );
  expect(snapshot.dockLeft, isFalse);
  expect(snapshot.intentSidebarVisible, isTrue);
  expect(snapshot.sidebarWidth, 260);
});
```

- [ ] **Step 2: Implement `WorkspaceIdePaneSnapshot` (+ optional `WorkspaceIdeDragCommit`)**

Keep file free of `panes` imports if possible so unit tests stay light; shell applies snapshot to controllers.

- [ ] **Step 3: Tests PASS + commit**

```bash
git commit -m "$(cat <<'EOF'
feat: add WorkspaceIdePaneSnapshot for shell sync

EOF
)"
```

---

### Task 5: `WorkspaceIdeShell` wide layout cutover

**Files:**
- Create: `client/lib/pages/workspace_ide/workspace_ide_shell.dart`
- Create: `client/lib/pages/workspace_ide/workspace_ide_pane_chrome.dart` (minimal chrome OK; polish in Task 7)
- Modify: `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart`
- Modify: `client/lib/pages/chat/chat_page_shell.dart`
- Modify: `client/lib/pages/workspace_shell/workspace_shell.dart` — **required:** remove the only production wrap of `WorkspaceShellMainWithTerminal` (~line 159) so center content is tab chrome + body only; otherwise bottom stays under center and you get a double terminal when shell also mounts bottom
- Modify: `client/lib/pages/workspace_shell/workspace_shell_layout.dart` — delete or stop exporting terminal wrappers once unused
- Drop unused ctor params from `WorkspaceShell` if terminal cwd/id only existed for that wrap (`workspaceTerminalWorkingDirectory`, `workspaceWorkspaceId`)
- Test: `client/test/pages/workspace_ide/workspace_ide_shell_smoke_test.dart`

- [ ] **Step 1: Implement shell structure**

`WorkspaceIdeShell` responsibilities:

1. `LayoutBuilder` → `WorkspacePanePolicy.effective`
2. Own `PaneController`s for nested `MultiPane`:
   - **Vertical** root: `mainRow` (flex) + `bottom` (pixel height from prefs when `dockBottom`)
   - **Horizontal** `mainRow`: `left` | `center` | `right` with sizes from prefs when docked
3. Builders:
   - left → existing `WorkspaceSidebar`
   - center → thinned `ChatPage` / `WorkspaceShell` **without** embedded terminal
   - right → `RightToolsPanel`
   - bottom → `WorkspaceTerminalPanel` with `ValueKey('workspace-terminal-$workspaceId')`
4. On size drag end → `LayoutCubit.setSidebarWidth` / `setRightToolsWidth` / `setWorkspaceTerminalHeight`
5. **PTY hold (required by spec):** add optional `onSplitDragStart`/`onSplitDragEnd` (or equivalent) on `WorkspaceTerminalPanel` that forward to its private `TerminalLayoutCoordinator`. Wire shell drag start/end to those callbacks. Do not ship without this wiring.
6. Wrap regions in `WorkspaceIdePaneChrome` + `PaneTheme` from `Theme.of(context).colorScheme`

If panes hide disposes children: keep builder subtrees mounted and only change controller visibility / flex.

**Transition note:** until Task 6, narrow widths undock left/right with no overlay yet — accept temporarily missing side panes on narrow, **or** keep `_ChatPageDrawerLayout` only for right tools until Task 6 (do not run drawer + docked right together).

- [ ] **Step 2: Thin `ChatPageShell` + strip terminal from `WorkspaceShell`**

- Remove `_ChatPageSplitLayout`’s `RightToolsHost` when parent is `WorkspaceIdeShell`
- Change `workspace_shell.dart` so `child` is shown directly under tabs (no `WorkspaceShellMainWithTerminal`)
- Pass right-tools + terminal builders **up** into `WorkspaceIdeShell` from `WorkspaceSplitPane`

Suggested constructor shape:

```dart
WorkspaceIdeShell(
  workspace: workspace,
  tabScopeId: tabScopeId,
  cwd: cwd,
  left: (...),
  center: (...),
  right: (...),
  bottom: (...),
)
```

- [ ] **Step 3: Wire `sidebarWidth` from prefs**

In shell (not local-only state): initial left size = `preferences.sidebarWidth`; drag end calls `setSidebarWidth`.

- [ ] **Step 4: Smoke test**

```dart
testWidgets('toggling right tools keeps bottom terminal key', (tester) async {
  // Pump shell with fake panels using ValueKey on bottom.
  // Toggle LayoutCubit.setRightToolsVisible(false/true).
  // Expect find.byKey(bottomKey) still matches same element / key.
});
```

Use lightweight placeholders instead of real PTY if needed.

- [ ] **Step 5: Manual check**

Run app: open workspace → show terminal → resize → toggle right tools → confirm terminal session survives and spans full width under sides. Grep: no remaining `WorkspaceShellMainWithTerminal(` call sites.

- [ ] **Step 6: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: cut over workspace page to WorkspaceIdeShell

EOF
)"
```

---

### Task 6: Narrow overlays + delete drawer fork

**Files:**
- Create: `client/lib/pages/workspace_ide/pane_overlay_host.dart`
- Modify: `client/lib/pages/workspace_ide/workspace_ide_shell.dart`
- Modify: `client/lib/pages/chat/chat_page_shell.dart` — delete `_ChatPageDrawerLayout` path
- Modify: `client/lib/services/app/platform_utils.dart` — stop using `useRightToolsAsDrawer` for workspace shell (keep only if other callers need it)
- Modify: workspace chrome / `WorkspaceShellTabRowTrailing` (or shell app bar) — **add left-sidebar open control** for narrow (and optionally wide hide/show); today there is **no** sidebar visibility toggle. Add l10n strings (en/zh ARB) mirroring `WorkspaceShellRightToolsVisibilityToggle`; optional `AppKeys` if useful for tests.

- [ ] **Step 1: Overlay behavior (spec-locked)**

- When `effective.overlayRight` is true and intent wants right available: showing right tools opens overlay (same entry as today’s visibility toggle → `setRightToolsVisible(true)`); dismiss → `setRightToolsVisible(false)` on explicit dismiss
- When `effective.overlayLeft` is true: **new** control calls `setSidebarVisible(true)` and presents left overlay; dismiss → `setSidebarVisible(false)`
- Wide path: `setRightToolsVisible` / `setSidebarVisible` map directly to docked panes (sidebar toggle is new UI; default remains visible)

- [ ] **Step 2: Remove `useRightToolsAsDrawer(context)` branch from `chat_page_shell.dart`**

- [ ] **Step 3: Policy tests already cover narrow; add one overlay smoke if cheap**

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: use pane overlays for narrow workspace layout

EOF
)"
```

---

### Task 7: Islands chrome + delete dead hosts

**Files:**
- Modify: `client/lib/pages/workspace_ide/workspace_ide_pane_chrome.dart`
- Delete: `client/lib/pages/chat/right_tools_host.dart` (and fix imports)
- Clean: `client/lib/pages/workspace_shell/workspace_shell_layout.dart` if unused
- Grep for `RightToolsHost`, `WorkspaceShellCenterColumnWithTerminal`, `ResizableSplitView` in workspace path

- [ ] **Step 1: Medium Islands**

- Shared gutter ~8px around IDE content
- Rounded clip (~8–12 radius) per pane surface
- `PaneTheme` / `PaneThemeData` from `ColorScheme` (resizer + hover) — no Fleet hard-coded dark palette
- Do not restyle `WorkspaceShell` tab chips via panes `TabbedPane`

- [ ] **Step 2: Delete dead code; `flutter analyze`**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`

- [ ] **Step 3: Targeted tests + broader non-integration suite if feasible**

Run:

```bash
cd client && flutter test \
  test/services/workspace/workspace_pane_policy_test.dart \
  test/pages/workspace_ide/ \
  test/models/layout_preferences_default_test.dart
```

- [ ] **Step 4: Commit**

```bash
git commit -m "$(cat <<'EOF'
feat: Islands chrome for workspace IDE shell and remove old split hosts

EOF
)"
```

---

## Verification (before claiming done)

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  && flutter test --exclude-tags integration
```

Manual: wide full-bleed terminal; toggle right without PTY loss; narrow overlay open/dismiss; sizes persist across restart (`sidebarWidth`, `rightToolsWidth`, terminal height; terminal visibility still starts hidden per existing `LayoutCubit.load` behavior).

---

## Execution notes

- If Task 1 proves panes unsuitable, implement Tasks 5–7 geometry with nested `ResizableSplitView` behind the same `WorkspaceIdeShell` + policy APIs; skip or remove `panes` dependency.
- Do not change `WorkbenchCubit` tab order/active/preview semantics in any task.
