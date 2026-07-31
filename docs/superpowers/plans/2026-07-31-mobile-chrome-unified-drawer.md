# Mobile Chrome + Unified Workspace Drawer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On mobile, clear the title-bar trailing tools, move settings/notifications into sidebar footers, and replace dual left/right overlays with one Chat/Tools unified workspace drawer.

**Architecture:** `LayoutCubit` gains in-memory `mobileDrawerMode` (`chat`|`tools`) plus open/close/switch helpers that map to existing `sidebarVisible` / `rightToolsVisible` intents. Narrow drawer **open** is derived from those overlay intents (so legacy `setSidebarVisible(true)` still opens the drawer). Narrow `WorkspaceIdeShell` renders a single `MobileWorkspaceDrawerHost` instead of dual `PaneOverlayHost` slides. Title-bar hamburger always shows on mobile: home → `TpSidebarScope`; workspace → LayoutCubit helpers.

**Tech Stack:** Flutter/Dart, `flutter_bloc`, `shared_ui` (`TpSidebar*`, `TpIconButton`), existing `NotificationBellButton` / `showWorkspaceSettingsDialog`, l10n ARB.

**Spec:** `docs/superpowers/specs/2026-07-31-mobile-chrome-unified-drawer-design.md`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/cubits/layout_cubit.dart` | `MobileDrawerMode`, open/close/switch helpers; non-persisted mode |
| `client/test/cubits/layout_cubit_mobile_drawer_test.dart` | Cubit mapping tests |
| `client/lib/pages/home_workspace/home_workspace_title_bar.dart` | Hide mobile trailing; always-show hamburger with home vs workspace routing |
| `client/test/pages/home_workspace/home_workspace_title_bar_test.dart` | Desktop still has tools; mobile trailing empty |
| `client/test/pages/home_workspace/home_narrow_drawer_test.dart` | Update `homeSidebarTriggerVisible` expectations |
| `client/lib/pages/home_workspace/home_workspace_sidebar.dart` | Mobile Providers row + trailing 🔔⚙ |
| `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart` | `embedFooter` flag; omit manage footer when false |
| `client/lib/pages/workspace_ide/mobile_workspace_drawer_host.dart` | Unified overlay: Switch + body + shell footer |
| `client/lib/pages/workspace_ide/workspace_ide_shell.dart` | Narrow path uses unified host |
| `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart` | Pass `embedFooter: !(isMobile)` into `WorkspaceSidebar` |
| `client/lib/utils/ui/app_keys.dart` | Keys for switch / drawer if needed |
| `client/test/pages/workspace_ide/mobile_workspace_drawer_host_test.dart` | Switch / dismiss / footer widget tests |
| `client/test/pages/workspace_ide/workspace_ide_shell_smoke_test.dart` | **Must update** for unified drawer (replaces dual `PaneOverlayHost` assertions) |

**Locked implementer rules:**

1. **Desktop / wide unchanged** — no title-bar trailing hide; keep dual docked panes. Narrow uses `MobileWorkspaceDrawerHost` (not dual-slide `PaneOverlayHost`).
2. **Mobile title bar trailing is empty** — no SSH selector, pane toggles, bell, settings, `trailingActions` (Run).
3. **Hamburger always on mobile** — `homeSidebarTriggerVisible` → `isMobile` only.
4. **Hamburger routing** — `activeTabKey == null` → `TpSidebarScope.toggleSidebar`; else → `LayoutCubit.openMobileWorkspaceDrawer()` (never open home library drawer on workspace).
5. **Drawer shell owns footer** — 工作区管理 + 🔔⚙. Single `WorkspaceSidebar` instance: `embedFooter: !(TpSidebarScope.maybeOf(context)?.isMobile ?? false)` in `workspace_split_pane.dart` (mobile keeps manage footer off the sidebar body; drawer shell owns it; desktop docked keeps sidebar footer).
6. **Drawer open is derived from existing overlay intents on narrow** — `open = (overlayLeft && !narrowLeftSuppressed) || overlayRight`. Do **not** make `setSidebarVisible` / `setRightToolsVisible` desktop-aware of a drawer flag. `mobileDrawerMode` is session memory for which body to show and which intents `openMobileWorkspaceDrawer` restores. Hamburger/switch/dismiss go through helpers that mutate prefs (+ mode). Smoke tests that call `setSidebarVisible(true)` still open the unified drawer because `overlayLeft` becomes true.
7. **Do not delete** SSH/Termux runtime or `/config/ssh-profiles`; only remove title-bar entry on mobile.
8. **Do not commit** unless the user explicitly asks.
9. Reuse l10n: `appRailChat` / `openRightTools` for Switch labels.

**LayoutCubit mapping (narrow UI):**

| UI | Prefs / mode |
|----|----------------|
| closed | `sidebarVisible=false`; right tools off; clear `narrowLeftSuppressed` as needed; **keep** `mobileDrawerMode` |
| open + chat | mode=chat; `sidebarVisible=true`; `narrowLeftSuppressed=false`; right tools off |
| open + tools | mode=tools; right tools on via landing override when `composeLanding`, else `rightToolsVisible`; sidebar overlay off (`sidebarVisible=false`) |
| switch | update mode + flip intents; stay open |
| `setSidebarVisible(true)` (smoke / legacy) | opens chat body (overlayLeft); IdeShell may `setMobileDrawerMode(chat)` when applying narrow open if mode was tools with left-only — or simply show chat body whenever left intent wins |
| right-tools visible (legacy) | opens tools body |

`mobileDrawerMode` is **session memory only**, never written to `LayoutRepository`. No separate `mobileDrawerOpen` flag required if derivation above is used.

---

### Task 1: `LayoutCubit` mobile drawer mode API

**Files:**
- Modify: `client/lib/cubits/layout_cubit.dart`
- Create: `client/test/cubits/layout_cubit_mobile_drawer_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/layout_cubit.dart';

void main() {
  test('openMobileWorkspaceDrawer defaults to chat', () async {
    final cubit = LayoutCubit();
    addTearDown(cubit.close);
    // Pretend prefs loaded
    await cubit.setSidebarVisible(false);
    await cubit.setRightToolsVisible(false);

    cubit.openMobileWorkspaceDrawer();

    expect(cubit.state.mobileDrawerMode, MobileDrawerMode.chat);
    expect(cubit.state.preferences.sidebarVisible, isTrue);
    expect(cubit.state.preferences.rightToolsVisible, isFalse);
  });

  test('setMobileDrawerMode tools flips intents without losing mode memory on close', () async {
    final cubit = LayoutCubit();
    addTearDown(cubit.close);
    cubit.openMobileWorkspaceDrawer();
    await cubit.setMobileDrawerMode(MobileDrawerMode.tools, composeLanding: false);

    expect(cubit.state.mobileDrawerMode, MobileDrawerMode.tools);
    expect(cubit.state.preferences.rightToolsVisible, isTrue);

    cubit.closeMobileWorkspaceDrawer(composeLanding: false);
    expect(cubit.state.preferences.sidebarVisible, isFalse);
    expect(cubit.state.preferences.rightToolsVisible, isFalse);
    expect(cubit.state.mobileDrawerMode, MobileDrawerMode.tools);

    cubit.openMobileWorkspaceDrawer(composeLanding: false);
    expect(cubit.state.mobileDrawerMode, MobileDrawerMode.tools);
    expect(cubit.state.preferences.rightToolsVisible, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/cubits/layout_cubit_mobile_drawer_test.dart`

Expected: FAIL — `MobileDrawerMode` / methods missing

- [ ] **Step 3: Minimal implementation**

Add to `layout_cubit.dart`:

```dart
enum MobileDrawerMode { chat, tools }

// On LayoutState:
final MobileDrawerMode mobileDrawerMode; // default chat; never persisted

/// CRITICAL: open / mode / close helpers must update sidebar + right-tools
/// (and landing override) in **one** `emit` / one `_save` preferences snapshot.
/// Sequential `setSidebarVisible` then `setRightToolsVisible` creates a frame
/// where both are false → derived `open=false` → drawer flash-closes on switch.

void openMobileWorkspaceDrawer({bool composeLanding = false}) {
  // Single emit: mode intents + clearNarrowLeftSuppressed
}
Future<void> setMobileDrawerMode(
  MobileDrawerMode mode, {
  bool composeLanding = false,
}) async {
  // Single emit: new mode + mutually exclusive sidebar/right-tools/landing
}
void closeMobileWorkspaceDrawer({bool composeLanding = false}) {
  // Single emit: both sides off; keep mobileDrawerMode
}

/// Right-tools slice inside that single snapshot:
/// - composeLanding == true → landingRightToolsOverride
/// - else → preferences.rightToolsVisible
/// Mirror existing `toggleRightTools` semantics.
```

Add tests:
1. `setMobileDrawerMode(tools)` → never observe an intermediate state where both sidebar and right-tools are false while mode is switching (assert final state; if using a stream listener, assert no open=false gap — or document single-emit and assert final prefs only).
2. `setMobileDrawerMode(tools, composeLanding: true)` sets `landingRightToolsOverride == true`.

Do **not** add `mobileDrawerOpen` — IdeShell derives open from overlay intents (see Task 6).

Include `mobileDrawerMode` in `props` / `copyWith`.

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd client && flutter test test/cubits/layout_cubit_mobile_drawer_test.dart`

- [ ] **Step 5: Commit only if user asks**

---

### Task 2: Title bar — hide mobile trailing; always-show routed hamburger

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_title_bar.dart`
- Modify: `client/test/pages/home_workspace/home_narrow_drawer_test.dart`
- Modify: `client/test/pages/home_workspace/home_workspace_title_bar_test.dart`

- [ ] **Step 1: Update unit expectation for trigger visibility**

In `home_narrow_drawer_test.dart`, change:

```dart
test('home sidebar trigger on all mobile tabs', () {
  expect(homeSidebarTriggerVisible(isMobile: true, activeTabKey: 'ws-a'), isTrue);
  expect(homeSidebarTriggerVisible(isMobile: true, activeTabKey: null), isTrue);
  expect(homeSidebarTriggerVisible(isMobile: false, activeTabKey: null), isFalse);
});
```

- [ ] **Step 2: Run — expect FAIL**

Run: `cd client && flutter test test/pages/home_workspace/home_narrow_drawer_test.dart`

- [ ] **Step 3: Implement visibility + trailing hide + trigger routing**

```dart
bool homeSidebarTriggerVisible({
  required bool isMobile,
  required String? activeTabKey, // keep param for call-site compat; unused
}) => isMobile;
```

In `HomeTitleBar` build when `compactChrome` / `isMobile`:

- Skip entire trailing tool `ConstrainedBox` children (or render empty `SizedBox.shrink()`).
- Replace bare `TpSidebarTrigger` with a small private widget / inline `TpIconButton`:

```dart
onTap: () {
  final composeLanding = context.read<ChatCubit>().state.newChatActive;
  final layout = context.read<LayoutCubit>();
  if (widget.activeTabKey == null) {
    TpSidebarScope.of(context).toggleSidebar();
    return;
  }
  // MUST match IdeShell narrow open derivation (extract shared helper in Task 6):
  // open = (sidebarVisible && !narrowLeftSuppressed) || effectiveRightTools
  final right = composeLanding
      ? (layout.state.landingRightToolsOverride ?? false)
      : layout.state.preferences.rightToolsVisible;
  final open =
      (layout.state.preferences.sidebarVisible &&
          !layout.state.narrowLeftSuppressed) ||
      right;
  if (open) {
    layout.closeMobileWorkspaceDrawer(composeLanding: composeLanding);
  } else {
    layout.openMobileWorkspaceDrawer(composeLanding: composeLanding);
  }
}
```

Put the open-derivation in a small top-level helper e.g. `mobileWorkspaceDrawerOpenFromLayout(...)` used by title bar **and** IdeShell so suppressed-left + tools-open still toggles closed.

- [ ] **Step 4: Widget test — mobile trailing empty; desktop still has toggles**

Extend `home_workspace_title_bar_test.dart` with a narrow mobile pump (`TpSidebarProvider` + physical size 400×800) asserting:

- `find.byType(WorkspaceShellPaneVisibilityToggles)` → nothing
- `find.byType(NotificationBellButton)` → nothing in title bar
- `find.byType(TpSidebarTrigger)` or menu icon → one

Keep existing wide test that expects pane toggles when workspace active.

- [ ] **Step 5: Run tests**

```bash
cd client && flutter test \
  test/pages/home_workspace/home_narrow_drawer_test.dart \
  test/pages/home_workspace/home_workspace_title_bar_test.dart
```

Expected: PASS

---

### Task 3: Home sidebar mobile footer — Providers + 🔔⚙

**Files:**
- Modify: `client/lib/pages/home_workspace/home_workspace_sidebar.dart`
- Create or extend: `client/test/pages/home_workspace/home_sidebar_mobile_footer_test.dart`

- [ ] **Step 1: Failing widget test**

Pump `HomeSidebar` under `TpSidebarProvider` at mobile width with `NotificationCubit` + `ProgressActivityCubit`. Assert Providers key present and `NotificationBellButton` findsOneWidget; settings icon present.

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement**

When `isMobileDrawer`, change bottom section from solo `_ProvidersButton` to:

```dart
Row(
  children: [
    Expanded(child: _ProvidersButton(...)),
    NotificationBellButton(),
    TpIconButton( /* settings gear → showWorkspaceSettingsDialog */ ),
  ],
)
```

Keep desktop as centered `_ProvidersButton` only.

- [ ] **Step 4: Run — PASS**

---

### Task 4: `WorkspaceSidebar.embedFooter`

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_sidebar.dart`
- Test: assert manage tile absent when `embedFooter: false` (small widget test or unit via pump with fake workspace — follow existing workspace sidebar test patterns if any; otherwise add focused test)

- [ ] **Step 1: Add parameter**

```dart
class WorkspaceSidebar extends StatefulWidget {
  const WorkspaceSidebar({
    required this.workspace,
    required this.tabScopeId,
    this.embedFooter = true,
    super.key,
  });
  final bool embedFooter;
}
```

When `!embedFooter`, omit Divider + `_SidebarActionTile` manage block at bottom.

- [ ] **Step 2: Default call sites unchanged (`embedFooter: true`)

- [ ] **Step 3: Test + PASS**

---

### Task 5: `MobileWorkspaceDrawerHost`

**Files:**
- Create: `client/lib/pages/workspace_ide/mobile_workspace_drawer_host.dart`
- Create: `client/test/pages/workspace_ide/mobile_workspace_drawer_host_test.dart`
- Modify: `client/lib/utils/ui/app_keys.dart` (optional keys)

- [ ] **Step 1: Failing test — switch swaps body; footer always visible**

Pump host with fake `chatBody` / `toolsBody` Text markers, `LayoutCubit`, open=true, mode=chat. Expect chat marker + footer label. Tap Tools segment → tools marker; footer still there. Tap scrim → `onDismiss` called.

- [ ] **Step 2: Implement host**

API sketch:

```dart
class MobileWorkspaceDrawerHost extends StatelessWidget {
  const MobileWorkspaceDrawerHost({
    required this.child,
    required this.width,
    required this.open,
    required this.mode,
    required this.chatBody,
    required this.toolsBody,
    required this.onDismiss,
    required this.onModeChanged,
    required this.onOpenWorkspaceManagement,
    super.key,
  });
  // single left (or full-bleed fraction) overlay + scrim
}
```

UI:

- Top: `SegmentedButton<MobileDrawerMode>` or two `Tp` chips using `appRailChat` / `openRightTools`
- Body: `mode == chat ? chatBody : toolsBody`
- Footer: manage row + `NotificationBellButton` + settings button
- Animation: reuse duration ~200ms similar to `PaneOverlayHost`

Do **not** slide from opposite sides.

- [ ] **Step 3: Run — PASS**

---

### Task 6: Wire `WorkspaceIdeShell` + `workspace_split_pane` + smoke tests

**Files:**
- Modify: `client/lib/pages/workspace_ide/workspace_ide_shell.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart`
- Modify: `client/test/pages/workspace_ide/workspace_ide_shell_smoke_test.dart` (**required**)

- [ ] **Step 1: `embedFooter` at assembly site**

In `workspace_split_pane.dart`:

```dart
left: WorkspaceSidebar(
  workspace: widget.workspace,
  tabScopeId: widget.tabScopeId,
  embedFooter: !(TpSidebarScope.maybeOf(context)?.isMobile ?? false),
),
```

- [ ] **Step 2: Narrow host in `_buildPaneHost`**

When `effective.isNarrow`, use `MobileWorkspaceDrawerHost` instead of dual-slide `PaneOverlayHost`.

Extract shared helpers (same file as LayoutCubit or small `mobile_workspace_drawer.dart`):

```dart
bool mobileWorkspaceDrawerOpen({
  required bool sidebarVisible,
  required bool narrowLeftSuppressed,
  required bool rightToolsEffective,
}) =>
    (sidebarVisible && !narrowLeftSuppressed) || rightToolsEffective;

MobileDrawerMode mobileWorkspaceDrawerMode({
  required bool rightToolsEffective,
  required MobileDrawerMode remembered,
}) =>
    rightToolsEffective ? MobileDrawerMode.tools : MobileDrawerMode.chat;
```

Wire host:

```dart
final rightEffective = composeLanding
    ? (layoutState.landingRightToolsOverride ?? false)
    : effective.overlayRight; // or prefs — match WorkspacePanePolicy
final open = mobileWorkspaceDrawerOpen(
  sidebarVisible: effective.overlayLeft,
  narrowLeftSuppressed: layoutState.narrowLeftSuppressed,
  rightToolsEffective: rightEffective,
);

MobileWorkspaceDrawerHost(
  open: open,
  mode: mobileWorkspaceDrawerMode(
    rightToolsEffective: rightEffective,
    remembered: layoutState.mobileDrawerMode,
  ),
  ...
  onOpenWorkspaceManagement: widget.onOpenWorkspaceManagement,
  child: MultiPane(...),
);
```

Add `onOpenWorkspaceManagement` callback to `WorkspaceIdeShell`; `workspace_split_pane.dart` supplies the same navigate-to-manage logic currently in `WorkspaceSidebar._openWorkspaceManagement` (extract a top-level helper e.g. `openWorkspaceManagementRoute(context, workspace)`).

Wide path: keep current docked `MultiPane` without mobile drawer host (or pass `open: false` / skip host). Prefer: only wrap with `MobileWorkspaceDrawerHost` when narrow; wide can keep `PaneOverlayHost` with `showLeft/showRight: false` as today, or drop overlay host entirely when always false — match existing wide behavior.

- [ ] **Step 3: Rewrite smoke test expectations**

Update `workspace_ide_shell_smoke_test.dart`:

- Replace assertions on dual overlays / `Positioned(right: 0)` with `MobileWorkspaceDrawerHost` (or host key).
- `setSidebarVisible(true)` → drawer open, **chat** body visible.
- Right-tools visible → drawer open, **tools** body visible.
- Dismiss / `setSidebarVisible(false)` → drawer closed.
- Remove expectations that left and right overlays can appear as independent opposing slides.

- [ ] **Step 4: Run smoke + host tests**

```bash
cd client && flutter test \
  test/pages/workspace_ide/mobile_workspace_drawer_host_test.dart \
  test/pages/workspace_ide/workspace_ide_shell_smoke_test.dart
```

Expected: PASS

- [ ] **Step 5: Analyze touched files**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/cubits/layout_cubit.dart \
  lib/pages/home_workspace/home_workspace_title_bar.dart \
  lib/pages/home_workspace/home_workspace_sidebar.dart \
  lib/pages/home_workspace/workspace/workspace_sidebar.dart \
  lib/pages/home_workspace/workspace/workspace_split_pane.dart \
  lib/pages/workspace_ide/mobile_workspace_drawer_host.dart \
  lib/pages/workspace_ide/workspace_ide_shell.dart
```

---

### Task 7: Regression pass

- [ ] **Step 1: Run focused suite**

```bash
cd client && flutter test \
  test/cubits/layout_cubit_mobile_drawer_test.dart \
  test/pages/home_workspace/home_narrow_drawer_test.dart \
  test/pages/home_workspace/home_workspace_title_bar_test.dart \
  test/pages/workspace_ide/mobile_workspace_drawer_host_test.dart \
  test/pages/workspace_ide/workspace_ide_shell_smoke_test.dart
```

Expected: all PASS

- [ ] **Step 2: Quick desktop sanity** — wide title bar still shows pane toggles + bell + settings (covered by existing title bar test)

- [ ] **Step 3: Stop** — do not commit unless user asks

---

## Out of scope (do not implement)

- Persisting `mobileDrawerMode`
- New Termux/SSH title-bar replacement control
- Redesign of right-tools internals
- Home Chat/Tools switch
