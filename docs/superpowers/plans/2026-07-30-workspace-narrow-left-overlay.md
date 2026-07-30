# Workspace Narrow Left Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make workspace narrow left session rail use `PaneOverlayHost` + `LayoutCubit` like the right tools overlay, with ephemeral enter-narrow suppress so the center is not covered on first paint.

**Architecture:** Restore `WorkspacePanePolicy.overlayLeft` from `sidebarVisible`. Drive `PaneOverlayHost.showLeft` with `overlayLeft && !LayoutState.narrowLeftSuppressed`. Own suppress on `LayoutCubit` (non-persisted, like `landingRightToolsOverride`) so title-bar toggle and IdeShell share state. Delete `_WorkspaceMobileSidebarHost`. Toggle uses effective visibility only.

**Tech Stack:** Flutter, `flutter_bloc`, existing `PaneOverlayHost` / `WorkspaceIdeShell` / `LayoutCubit`.

**Spec:** `docs/superpowers/specs/2026-07-30-workspace-narrow-left-overlay-design.md`

---

## File map

| File | Role |
|------|------|
| `client/lib/cubits/layout_cubit.dart` | Add `narrowLeftSuppressed` + set/clear APIs |
| `client/test/cubits/layout_cubit_narrow_left_suppress_test.dart` | Cubit unit tests (new) |
| `client/lib/services/workspace/workspace_pane_policy.dart` | Narrow `overlayLeft: preferences.sidebarVisible` |
| `client/test/services/workspace/workspace_pane_policy_test.dart` | Update narrow expectations |
| `client/lib/pages/workspace_ide/workspace_ide_shell.dart` | Wire left overlay; enter-narrow suppress; delete `_WorkspaceMobileSidebarHost` |
| `client/lib/pages/workspace_shell/workspace_shell_tabs.dart` | Toggle uses effectiveOpen + clear suppress |
| `client/test/pages/workspace_ide/workspace_ide_shell_smoke_test.dart` | Narrow left overlay + suppress + prefs preserved |
| `client/test/pages/workspace_ide/workspace_ide_pane_sync_test.dart` | Snapshot/intent if assertions mention overlayLeft |

---

### Task 1: LayoutCubit ephemeral `narrowLeftSuppressed`

**Files:**
- Create: `client/test/cubits/layout_cubit_narrow_left_suppress_test.dart`
- Modify: `client/lib/cubits/layout_cubit.dart`

- [x] **Step 1: Write the failing tests**
- [x] **Step 2: Run test to verify it fails**
- [x] **Step 3: Implement on `LayoutState` / `LayoutCubit`**
- [x] **Step 4: Run tests — pass**
- [x] **Step 5: Commit** (skipped — user did not request commits)
---

### Task 2: Policy — narrow `overlayLeft` from prefs

**Files:**
- Modify: `client/lib/services/workspace/workspace_pane_policy.dart`
- Modify: `client/test/services/workspace/workspace_pane_policy_test.dart`

- [x] **Step 1: Update failing / incorrect assertions**
- [x] **Step 2: Run policy tests — expect FAIL on the updated assertion until Step 3**
- [x] **Step 3: Implement policy**
- [x] **Step 4: Run policy tests — pass**
- [x] **Step 5: Commit** (skipped)
---

### Task 3: IdeShell — PaneOverlayHost left + enter-narrow suppress; remove TpSidebar host

**Files:**
- Modify: `client/lib/pages/workspace_ide/workspace_ide_shell.dart`
- Modify: `client/test/pages/workspace_ide/workspace_ide_shell_smoke_test.dart`
- Check: `client/test/pages/workspace_ide/workspace_ide_pane_sync_test.dart`

- [ ] **Step 1: Write / update failing smoke tests**

Replace TpSidebar/`openMobile` expectations with overlay behavior:

1. **First narrow pump** (`sidebarVisible: true` default): `find.text('left')` nothing; prefs still `sidebarVisible: true`; `narrowLeftSuppressed == true` after settle.
2. **Clear suppress + set visible**: left text appears under `PaneOverlayHost`.
3. **Dismiss left** (scrim tap): `sidebarVisible: false`, left gone, suppress cleared.
4. **Right open while left suppressed**: right overlay still works; right prefs unchanged by suppress.
5. **wide → narrow → wide** with `sidebarVisible: true`: after return to wide, left docks (`find.text('left')` visible as docked pane / dockLeft intent).
6. **Leave narrow and re-enter**: suppress applies again (`find.text('left')` nothing on re-enter).
7. Keep center-identity / right-width tests unless they break.

Helper pattern (adapt existing `pumpShell`):

```dart
testWidgets('narrow first paint suppresses left without clearing prefs', (
  tester,
) async {
  final layout = await pumpShell(tester, size: const Size(600, 900));
  expect(find.text('left'), findsNothing);
  expect(layout.state.preferences.sidebarVisible, isTrue);
  expect(layout.state.narrowLeftSuppressed, isTrue);
});

testWidgets('narrow left opens after clear suppress', (tester) async {
  final layout = await pumpShell(tester, size: const Size(600, 900));
  layout.clearNarrowLeftSuppressed();
  await layout.setSidebarVisible(true);
  await tester.pumpAndSettle();
  expect(find.text('left'), findsOneWidget);
});
```

Remove tests that call `sidebarScope(tester).setOpenMobile(...)`.

- [ ] **Step 2: Run smoke tests — expect FAIL**

```bash
cd client && flutter test test/pages/workspace_ide/workspace_ide_shell_smoke_test.dart
```

- [ ] **Step 3: Implement shell**

In `_onViewportSize` (and any path that first observes narrow), **before** `setState` that would show left:

```dart
if (!was.isNarrow && now.isNarrow) {
  context.read<LayoutCubit>().setNarrowLeftSuppressed(true);
} else if (was.isNarrow && !now.isNarrow) {
  context.read<LayoutCubit>().clearNarrowLeftSuppressed();
}
```

Also handle **first size report** when seed width was wide (840) and real width is narrow — that is `!was.isNarrow && now.isNarrow`.

Update `_buildPaneHost`:

```dart
final layoutState = context.read<LayoutCubit>().state; // or watch where build already has it
final fractionWidth = TpTheme.of(context).sidebarTheme
    .resolveMobileDrawerWidth(MediaQuery.sizeOf(context).width);
final showLeft = effective.isNarrow &&
    effective.overlayLeft &&
    !layoutState.narrowLeftSuppressed;

return PaneOverlayHost(
  showLeft: showLeft,
  showRight: effective.overlayRight,
  leftWidth: effective.isNarrow ? fractionWidth : prefs.sidebarWidth,
  rightWidth: effective.isNarrow ? fractionWidth : prefs.rightToolsWidth,
  onDismissLeft: () {
    context.read<LayoutCubit>().setSidebarVisible(false);
    context.read<LayoutCubit>().clearNarrowLeftSuppressed();
  },
  onDismissRight: () { /* unchanged */ },
  left: effective.isNarrow
      ? WorkspaceIdePaneChrome(child: widget.left)
      : null,
  right: WorkspaceIdePaneChrome(child: widget.right),
  child: MultiPane(...),
);
```

Ensure build **rebuilds** when `narrowLeftSuppressed` changes (`BlocBuilder` / existing listener must include that field in `buildWhen` or watch full state).

**Delete** entire `_WorkspaceMobileSidebarHost` class and the narrow `return _WorkspaceMobileSidebarHost(...)` wrapper — always return `PaneOverlayHost`.

Sync `_relevantPrefsChanged` / listeners if needed so suppress flips rebuild the host.

Zero-flash rule: set suppress in `_onViewportSize` **synchronously before** `setState` that flips `_narrow` / overlay flags. Do not rely on post-frame-only suppress.

- [ ] **Step 4: Run smoke + pane sync tests — pass**

```bash
cd client && flutter test \
  test/pages/workspace_ide/workspace_ide_shell_smoke_test.dart \
  test/pages/workspace_ide/workspace_ide_pane_sync_test.dart
```

- [ ] **Step 5: Commit** (if requested)

```bash
git commit -m "$(cat <<'EOF'
feat(workspace): narrow left session rail via PaneOverlayHost

EOF
)"
```

---

### Task 4: Title-bar sidebar toggle — effectiveOpen

**Files:**
- Modify: `client/lib/pages/workspace_shell/workspace_shell_tabs.dart` (`WorkspaceShellSidebarVisibilityToggle`)
- Add or extend a small widget test if one exists; otherwise cover via smoke + a focused test under `client/test/pages/workspace_shell/` if easy to pump with `LayoutCubit` only.

- [ ] **Step 1: Write failing toggle behavior test**

Pump with the same `AppLocalizations` / `TpTheme` pattern as `client/test/pages/home_workspace/home_workspace_title_bar_test.dart` (or nearest title-bar harness). Provide `BlocProvider<LayoutCubit>` + `WorkspaceShellSidebarVisibilityToggle` only (no IdeShell required).

Assert:
1. `sidebarVisible: true` + `narrowLeftSuppressed: true` → button muted / not “effective open”; tap → suppress cleared, `sidebarVisible` stays true.
2. Then tap again → `sidebarVisible: false`.

Do not extract a helper instead of pumping the widget.

- [ ] **Step 2: Run — FAIL** (still has `TpSidebarScope.toggleSidebar` branch)

- [ ] **Step 3: Implement toggle**

```dart
return BlocBuilder<LayoutCubit, LayoutState>(
  buildWhen: (a, b) =>
      a.preferences.sidebarVisible != b.preferences.sidebarVisible ||
      a.narrowLeftSuppressed != b.narrowLeftSuppressed,
  builder: (context, state) {
    final effectiveOpen =
        state.preferences.sidebarVisible && !state.narrowLeftSuppressed;
    return TpIconButton(
      key: AppKeys.sidebarVisibilityButton,
      icon: Icons.view_sidebar_outlined,
      tooltip: effectiveOpen
          ? l10n.sidebarPanelHidden
          : l10n.sidebarPanelVisible,
      color: effectiveOpen ? cs.primary : cs.onSurfaceVariant,
      backgroundColor: Colors.transparent,
      onTap: () {
        final layout = context.read<LayoutCubit>();
        if (effectiveOpen) {
          layout.setSidebarVisible(false);
          layout.clearNarrowLeftSuppressed();
        } else {
          layout.clearNarrowLeftSuppressed();
          layout.setSidebarVisible(true);
        }
      },
    );
  },
);
```

Remove all `TpSidebarScope` usage from this widget.

- [ ] **Step 4: Run toggle + smoke tests — pass**

- [ ] **Step 5: Commit** (if requested)

```bash
git commit -m "$(cat <<'EOF'
fix(workspace): sidebar toggle uses effective overlay visibility

EOF
)"
```

---

### Task 5: Regression + cleanup verification

**Files:** none new — run suites

- [ ] **Step 1: Run focused suites**

```bash
cd client && flutter test \
  test/cubits/layout_cubit_narrow_left_suppress_test.dart \
  test/services/workspace/workspace_pane_policy_test.dart \
  test/pages/workspace_ide/workspace_ide_shell_smoke_test.dart \
  test/pages/workspace_ide/workspace_ide_pane_sync_test.dart \
  test/pages/home_workspace/home_narrow_drawer_test.dart \
  test/pages/home_workspace/home_overlay_active_drawer_test.dart
```

Expected: all pass. Home TpSidebar tests must still pass (unchanged).

- [ ] **Step 2: Grep for leftover workspace openMobile bridge**

```bash
rg -n "_WorkspaceMobileSidebarHost|openMobile.*sidebarVisible|sidebarVisible.*openMobile" client/lib/pages/workspace_ide client/lib/pages/workspace_shell
```

Expected: no matches for the deleted host / bridge.

- [ ] **Step 3: Update spec status line** to note implemented (optional doc-only).

- [ ] **Step 4: Final commit** (if requested) for any leftover test/doc fixes.

---

## Out of scope (do not do)

- Home `TpSidebar` / edge drag changes
- System-back / `PopScope` on `PaneOverlayHost`
- Reverting shared_ui overlay-ownership fix
- Persisting `narrowLeftSuppressed`
