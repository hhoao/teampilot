# Landing Hide Right Tools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On compose landing, hide the right tools pane by default (effective-only), allow a temporary open that does not persist, and restore `rightToolsVisible` when compose clears.

**Architecture:** Extend `WorkspacePanePolicy.effective` so compose landing uses `landingRightToolsOverride ?? false` as the right intent. Store the override as non-persisted state on `LayoutCubit`. Wire `WorkspaceIdeShell` + visibility chip + `toggleSecondarySidebar` to branch on workspace-scoped `composeActive`; clear the override when compose flips to false.

**Tech Stack:** Flutter, `flutter_bloc`, existing `LayoutCubit` / `WorkspacePanePolicy` / `WorkspaceIdeShell`, Dart unit + widget tests.

**Spec:** `docs/superpowers/specs/2026-07-11-landing-hide-right-tools-design.md`

---

## File map

| File | Role |
|------|------|
| `client/lib/services/workspace/workspace_pane_policy.dart` | Compose right-intent = override ?? false |
| `client/test/services/workspace/workspace_pane_policy_test.dart` | Policy TDD |
| `client/lib/cubits/layout_cubit.dart` | Ephemeral override + compose-aware toggle |
| `client/test/cubits/layout_cubit_zoom_test.dart` (or new sibling) | Cubit TDD for override |
| `client/lib/services/commands/layout_command_registrar.dart` | Pass `composeLanding` into toggle |
| `client/lib/app/app_shell.dart` | Supply `() => chatCubit.state.composeActive` |
| `client/test/services/commands/layout_command_registrar_test.dart` | Command landing vs session |
| `client/lib/pages/workspace_ide/workspace_ide_shell.dart` | Pass compose + override into policy; clear on exit |
| `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart` | Pass `composeLanding`; feed effective right into `RightToolsPanel` |
| `client/lib/widgets/right_tools/right_tools_panel.dart` | Only if adding explicit `contentVisible` (optional; prefer copyWith at call site) |
| `client/lib/pages/workspace_shell/workspace_shell_tabs.dart` | Chip uses effective visibility + compose branch |
| `client/test/smoke/app_shell_smoke_test.dart` | Landing: right tools not hit-testable |
| Related specs | Doc deltas from design |

---

### Task 1: `WorkspacePanePolicy` compose right-intent

**Files:**
- Modify: `client/lib/services/workspace/workspace_pane_policy.dart`
- Modify: `client/test/services/workspace/workspace_pane_policy_test.dart`

- [ ] **Step 1: Replace the v1 “compose ≡ session” test with landing default-hide cases**

In `workspace_pane_policy_test.dart`, remove/replace `compose and session visibility match in v1` with:

```dart
test('compose landing defaults right hidden even when prefs visible', () {
  final e = WorkspacePanePolicy.effective(
    preferences: prefs,
    viewportWidth: 1200,
    composeLanding: true,
  );
  expect(e.dockRight, isFalse);
  expect(e.dockLeft, isTrue);
  expect(e.dockBottom, isTrue);
});

test('compose landing + override true docks right', () {
  final e = WorkspacePanePolicy.effective(
    preferences: prefs,
    viewportWidth: 1200,
    composeLanding: true,
    landingRightToolsOverride: true,
  );
  expect(e.dockRight, isTrue);
});

test('session ignores landing override', () {
  final e = WorkspacePanePolicy.effective(
    preferences: prefs.copyWith(rightToolsVisible: false),
    viewportWidth: 1200,
    composeLanding: false,
    landingRightToolsOverride: true,
  );
  expect(e.dockRight, isFalse);
});

test('narrow compose + override null → no right overlay', () {
  final e = WorkspacePanePolicy.effective(
    preferences: prefs,
    viewportWidth: 700,
    composeLanding: true,
  );
  expect(e.isNarrow, isTrue);
  expect(e.dockRight, isFalse);
  expect(e.overlayRight, isFalse);
});

test('narrow compose + override true → overlayRight', () {
  final e = WorkspacePanePolicy.effective(
    preferences: prefs,
    viewportWidth: 700,
    composeLanding: true,
    landingRightToolsOverride: true,
  );
  expect(e.overlayRight, isTrue);
});
```

- [ ] **Step 2: Run tests — expect FAIL**

Run: `cd client && flutter test test/services/workspace/workspace_pane_policy_test.dart`

Expected: FAIL — `landingRightToolsOverride` missing / compose still matches session.

- [ ] **Step 3: Implement policy**

Update `WorkspacePanePolicy.effective`:

```dart
static WorkspacePaneEffective effective({
  required LayoutPreferences preferences,
  required double viewportWidth,
  bool composeLanding = false,
  bool? landingRightToolsOverride,
}) {
  final rightIntent = composeLanding
      ? (landingRightToolsOverride ?? false)
      : preferences.rightToolsVisible;
  final narrow = viewportWidth < narrowBreakpointWidth;
  if (!narrow) {
    return WorkspacePaneEffective(
      isNarrow: false,
      dockLeft: preferences.sidebarVisible,
      dockRight: rightIntent,
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
    overlayRight: rightIntent,
  );
}
```

Remove the `// v1: composeLanding unused…` comment.

- [ ] **Step 4: Run tests — expect PASS**

Run: `cd client && flutter test test/services/workspace/workspace_pane_policy_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/workspace/workspace_pane_policy.dart \
  client/test/services/workspace/workspace_pane_policy_test.dart
git commit -m "$(cat <<'EOF'
feat(layout): hide right tools by default on compose landing

EOF
)"
```

---

### Task 2: `LayoutCubit` ephemeral override + compose-aware toggle

**Files:**
- Modify: `client/lib/cubits/layout_cubit.dart`
- Modify: `client/test/cubits/layout_cubit_zoom_test.dart` (extend the view-toggles group) **or** Create: `client/test/cubits/layout_cubit_landing_right_tools_test.dart`

- [ ] **Step 1: Write failing cubit tests**

```dart
test('landing override does not change persisted rightToolsVisible', () async {
  final repo = _RecordingLayoutRepository(
    const LayoutPreferences(rightToolsVisible: true),
  );
  final cubit = LayoutCubit(repository: repo);
  addTearDown(cubit.close);
  await cubit.load();

  cubit.setLandingRightToolsOverride(true);
  expect(cubit.state.landingRightToolsOverride, isTrue);
  expect(cubit.state.preferences.rightToolsVisible, isTrue);
  expect(repo.saveCount, 0); // load may save once — assert no *extra* save after override
});

test('toggleRightTools on compose flips override only', () async {
  final cubit = LayoutCubit();
  addTearDown(cubit.close);
  final intent = cubit.state.preferences.rightToolsVisible;

  await cubit.toggleRightTools(composeLanding: true);
  expect(cubit.state.landingRightToolsOverride, isTrue); // null treated as false
  expect(cubit.state.preferences.rightToolsVisible, intent);

  await cubit.toggleRightTools(composeLanding: true);
  expect(cubit.state.landingRightToolsOverride, isFalse);
  expect(cubit.state.preferences.rightToolsVisible, intent);
});

test('toggleRightTools on session still flips prefs', () async {
  final cubit = LayoutCubit();
  addTearDown(cubit.close);
  final initial = cubit.state.preferences.rightToolsVisible;
  await cubit.toggleRightTools(composeLanding: false);
  expect(cubit.state.preferences.rightToolsVisible, !initial);
  expect(cubit.state.landingRightToolsOverride, isNull);
});

test('clearLandingRightToolsOverride sets null', () {
  final cubit = LayoutCubit();
  addTearDown(cubit.close);
  cubit.setLandingRightToolsOverride(true);
  cubit.clearLandingRightToolsOverride();
  expect(cubit.state.landingRightToolsOverride, isNull);
});
```

Use a tiny fake/recording `LayoutRepository` if one already exists in tests; otherwise a local stub that counts `save` calls. Adjust `saveCount` assertion to match real `load()` behavior (if `load` never saves, `saveCount == 0` after override is enough).

- [ ] **Step 2: Run tests — expect FAIL**

Run: `cd client && flutter test test/cubits/layout_cubit_landing_right_tools_test.dart`  
(or the updated zoom test file)

- [ ] **Step 3: Implement `LayoutState` + APIs**

```dart
class LayoutState extends Equatable {
  const LayoutState({
    this.preferences = const LayoutPreferences(),
    this.isLoading = true,
    this.landingRightToolsOverride,
  });

  final LayoutPreferences preferences;
  final bool isLoading;
  /// Compose-only temporary right-tools visibility; never persisted.
  final bool? landingRightToolsOverride;

  LayoutState copyWith({
    LayoutPreferences? preferences,
    bool? isLoading,
    bool? landingRightToolsOverride,
    bool clearLandingRightToolsOverride = false,
  }) {
    return LayoutState(
      preferences: preferences ?? this.preferences,
      isLoading: isLoading ?? this.isLoading,
      landingRightToolsOverride: clearLandingRightToolsOverride
          ? null
          : (landingRightToolsOverride ?? this.landingRightToolsOverride),
    );
  }

  @override
  List<Object?> get props =>
      [preferences, isLoading, landingRightToolsOverride];
}
```

Cubit methods (emit only for override paths — no `_save`):

```dart
void setLandingRightToolsOverride(bool visible) {
  emit(state.copyWith(landingRightToolsOverride: visible));
}

void clearLandingRightToolsOverride() {
  emit(state.copyWith(clearLandingRightToolsOverride: true));
}

Future<void> toggleRightTools({bool composeLanding = false}) {
  if (composeLanding) {
    final effective = state.landingRightToolsOverride ?? false;
    setLandingRightToolsOverride(!effective);
    return Future.value();
  }
  return setRightToolsVisible(!state.preferences.rightToolsVisible);
}
```

Keep existing `setRightToolsVisible` as the persist path.

Update any existing `toggleRightTools()` call sites that relied on zero-arg — default `composeLanding: false` preserves session behavior.

- [ ] **Step 4: Run tests — expect PASS**

Also re-run: `cd client && flutter test test/cubits/layout_cubit_zoom_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/cubits/layout_cubit.dart \
  client/test/cubits/layout_cubit_landing_right_tools_test.dart \
  client/test/cubits/layout_cubit_zoom_test.dart
git commit -m "$(cat <<'EOF'
feat(layout): ephemeral landing override for right tools toggle

EOF
)"
```

---

### Task 3: Command registrar compose landing callback

**Files:**
- Modify: `client/lib/services/commands/layout_command_registrar.dart`
- Modify: `client/lib/app/app_shell.dart` (where `registerLayoutCommands` is called — ~748)
- Modify: `client/test/services/commands/layout_command_registrar_test.dart`

- [ ] **Step 1: Write failing registrar test**

```dart
test('toggleSecondarySidebar on compose flips override not prefs', () async {
  final composeBus = CommandBus();
  var compose = true;
  registerLayoutCommands(
    composeBus,
    layout,
    uiZoomBaseline: () => baseline,
    composeLanding: () => compose,
  );
  final intent = layout.state.preferences.rightToolsVisible;

  composeBus.invoke(CommandIds.toggleSecondarySidebar);
  await Future<void>.delayed(Duration.zero);

  expect(layout.state.landingRightToolsOverride, isTrue);
  expect(layout.state.preferences.rightToolsVisible, intent);
});
```

Keep `setUp`’s default registration with `composeLanding: () => false` (or omit) so existing session tests stay green.

- [ ] **Step 2: Run test — expect FAIL** (missing named param)

- [ ] **Step 3: Wire registrar + bootstrap**

```dart
void registerLayoutCommands(
  CommandBus bus,
  LayoutCubit layout, {
  required double Function() uiZoomBaseline,
  bool Function()? composeLanding,
}) {
  final isCompose = composeLanding ?? () => false;
  // ...
  bus.register(
    CommandIds.toggleSecondarySidebar,
    () => layout.toggleRightTools(composeLanding: isCompose()),
  );
}
```

**Required bootstrap order:** today `registerLayoutCommands` is ~line 748 and `ChatCubit(...)` is ~777 in `app_shell.dart`. **Move** the `registerLayoutCommands` call to immediately after `chatCubit` is constructed (keep a single registration), then:

```dart
registerLayoutCommands(
  commandBus,
  layoutCubit,
  uiZoomBaseline: () => uiZoomBaseline.value,
  composeLanding: () => chatCubit.state.composeActive,
);
```

In the new compose registrar test, use a **fresh** `CommandBus` (do not double-register on the shared `setUp` bus).

- [ ] **Step 4: Run registrar tests — expect PASS**

Run: `cd client && flutter test test/services/commands/layout_command_registrar_test.dart`

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/commands/layout_command_registrar.dart \
  client/lib/app/app_shell.dart \
  client/test/services/commands/layout_command_registrar_test.dart
git commit -m "$(cat <<'EOF'
feat(commands): compose-aware secondary sidebar toggle

EOF
)"
```

---

### Task 4: Shell policy inputs + clear override on compose exit

**Files:**
- Modify: `client/lib/pages/workspace_ide/workspace_ide_shell.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart`
- Modify: `client/lib/pages/workspace_ide/workspace_ide_pane_sync.dart` only if snapshot helpers need the new args (prefer keeping snapshot factory taking already-computed `WorkspacePaneEffective`)
- Test: extend `client/test/pages/workspace_ide/workspace_ide_pane_sync_test.dart` and/or `workspace_ide_shell_smoke_test.dart` if there is a cheap hook; otherwise cover via Task 6 smoke

- [ ] **Step 1: Add `composeLanding` to `WorkspaceIdeShell`**

```dart
class WorkspaceIdeShell extends StatefulWidget {
  const WorkspaceIdeShell({
    required this.left,
    required this.center,
    required this.right,
    required this.bottom,
    this.composeLanding = false,
    this.terminalHold,
    super.key,
  });

  final bool composeLanding;
  // ...
}
```

- [ ] **Step 2: Pass compose + override into policy — and seed controllers from the same effective right**

**Critical:** `initState` currently seeds `_rightId` with `prefs.rightToolsVisible` and sets `_applied` from policy **without** `composeLanding`. If you only update `_applied` to the compose-hidden snapshot, `_requestSync` short-circuits (`_sameAsApplied`) and the `PaneController` stays `visible: true` — right tools still take width on landing.

In `initState`, compute one effective snapshot and seed **both** `_applied` and `PaneEntry.visible` from it:

```dart
final layoutState = context.read<LayoutCubit>().state;
final prefs = layoutState.preferences;
final effective = WorkspacePanePolicy.effective(
  preferences: prefs,
  viewportWidth: WorkspacePanePolicy.narrowBreakpointWidth,
  composeLanding: widget.composeLanding,
  landingRightToolsOverride: layoutState.landingRightToolsOverride,
);
// ...
PaneEntry(
  id: _rightId,
  visible: effective.dockRight, // NOT prefs.rightToolsVisible
  initialSize: PaneSize.pixel(prefs.rightToolsWidth),
  minSize: PaneSize.pixel(LayoutPreferences.minRightToolsWidth),
),
// left/bottom still from prefs / effective.dockLeft|dockBottom as appropriate
_applied = WorkspaceIdePaneSnapshot.from(
  preferences: prefs,
  effective: effective,
);
```

Use `effective.dockLeft` / `effective.dockBottom` for left/bottom entry `visible` for consistency (wide init assumes non-narrow breakpoint width, same as today).

Also update `_snapshotFor` and `build`’s `LayoutBuilder` to pass `composeLanding` + override into `WorkspacePanePolicy.effective`.

In `build`, rebuild when override OR prefs change:

```dart
listenWhen: (a, b) =>
  _relevantPrefsChanged(a.preferences, b.preferences) ||
  a.landingRightToolsOverride != b.landingRightToolsOverride,
```

Same for `buildWhen`. When `widget.composeLanding` changes, `didUpdateWidget` already rebuilds; ensure that path also `_requestSync`s a fresh snapshot (clear override first when exiting compose — Step 3).

- [ ] **Step 3: Clear override when compose exits**

In `WorkspaceIdeShellState`:

```dart
@override
void didUpdateWidget(covariant WorkspaceIdeShell oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (oldWidget.composeLanding && !widget.composeLanding) {
    context.read<LayoutCubit>().clearLandingRightToolsOverride();
  }
  if (oldWidget.composeLanding != widget.composeLanding) {
    _requestSync(_snapshotFor(context.read<LayoutCubit>().state.preferences));
  }
}
```

Clear **before** sync so the session snapshot does not briefly keep a temporary `true` override.
- [ ] **Step 4: Wire from `WorkspaceSplitPane`**

```dart
import '../../../utils/workspace_compose_active.dart';

// inside build, where WorkspaceIdeShell is constructed:
final composeLanding = workspaceComposeActive(
  context.watch<ChatCubit>(),
  widget.tabScopeId,
);

return WorkspaceIdeShell(
  composeLanding: composeLanding,
  // ...
);
```

Use `context.select` / `watch` so compose flips rebuild the shell. Prefer:

```dart
final composeLanding = context.select<ChatCubit, bool>(
  (c) => workspaceComposeActive(c, widget.tabScopeId),
);
```

- [ ] **Step 5: Pass effective visibility into `RightToolsPanel`**

`RightToolsPanel.build` early-returns `SizedBox.shrink()` when `!preferences.rightToolsVisible` (`right_tools_panel.dart` ~109). Shell docking alone is not enough: landing + prefs `false` + override `true` would show an empty pane.

In `_WorkspaceRightToolsPane` (`workspace_split_pane.dart`), pass prefs with **effective** right visibility:

```dart
final composeLanding = workspaceComposeActive(
  context.watch<ChatCubit>(),
  tabScopeId,
);
final layoutState = context.watch<LayoutCubit>().state;
final effectiveRight = composeLanding
    ? (layoutState.landingRightToolsOverride ?? false)
    : layoutState.preferences.rightToolsVisible;
return RightToolsPanel(
  preferences: layoutState.preferences.copyWith(
    rightToolsVisible: effectiveRight,
  ),
  // ...other args unchanged
);
```

Alternatively add an explicit `contentVisible` param on `RightToolsPanel` and gate on that — same behavior, slightly clearer; prefer the smallest diff.

- [ ] **Step 6: Overlay dismiss branches on compose**

In shell `onDismissRight`:

```dart
onDismissRight: () {
  final layout = context.read<LayoutCubit>();
  if (widget.composeLanding) {
    layout.setLandingRightToolsOverride(false);
  } else {
    layout.setRightToolsVisible(false);
  }
},
```

- [ ] **Step 7: Manual/widget sanity (optional in this task)**

Run: `cd client && flutter test test/pages/workspace_ide/`

Fix compile breaks from new required named params in tests constructing `WorkspaceIdeShell`.

- [ ] **Step 8: Commit**

```bash
git add client/lib/pages/workspace_ide/workspace_ide_shell.dart \
  client/lib/pages/home_workspace/workspace/workspace_split_pane.dart \
  client/lib/widgets/right_tools/right_tools_panel.dart \
  client/test/pages/workspace_ide/
git commit -m "$(cat <<'EOF'
feat(ide): apply landing right-tools policy in WorkspaceIdeShell

EOF
)"
```

---

### Task 5: Visibility chip uses effective right state

**Files:**
- Modify: `client/lib/pages/workspace_shell/workspace_shell_tabs.dart`

- [ ] **Step 1: Update `WorkspaceShellRightToolsVisibilityToggle`**

The chip sits in workspace chrome with access to `ChatCubit` + `LayoutCubit`. Reflect **effective** visibility and branch the tap:

```dart
@override
Widget build(BuildContext context) {
  final l10n = context.l10n;
  final cs = Theme.of(context).colorScheme;
  final composeLanding = context.select<ChatCubit, bool>(
    (c) => c.state.composeActive, // chrome is for the active workspace
  );
  return BlocBuilder<LayoutCubit, LayoutState>(
    buildWhen: (a, b) =>
        a.preferences.rightToolsVisible != b.preferences.rightToolsVisible ||
        a.landingRightToolsOverride != b.landingRightToolsOverride,
    builder: (context, state) {
      final visible = composeLanding
          ? (state.landingRightToolsOverride ?? false)
          : state.preferences.rightToolsVisible;
      return AppIconButton(
        key: AppKeys.rightToolsVisibilityButton,
        icon: Icons.vertical_split_outlined,
        tooltip: visible
            ? l10n.rightToolsPanelHidden
            : l10n.rightToolsPanelVisible,
        color: visible ? cs.primary : cs.onSurfaceVariant,
        backgroundColor: visible
            ? cs.primaryContainer.withValues(alpha: 0.45)
            : Colors.transparent,
        onTap: () => context.read<LayoutCubit>().toggleRightTools(
              composeLanding: composeLanding,
            ),
      );
    },
  );
}
```

Add `import` for `ChatCubit`. If this widget is also used outside a `ChatCubit` provider, use `context.read` carefully or `BlocBuilder` with `BlocProvider.maybeOf` — grep call sites; workspace shell should always have chat.

- [ ] **Step 2: Analyze**

Run: `cd client && flutter analyze lib/pages/workspace_shell/workspace_shell_tabs.dart --no-fatal-infos --no-fatal-warnings`

- [ ] **Step 3: Commit**

```bash
git add client/lib/pages/workspace_shell/workspace_shell_tabs.dart
git commit -m "$(cat <<'EOF'
feat(ui): compose-aware right tools visibility chip

EOF
)"
```

---

### Task 6: Smoke + acceptance tests

**Files:**
- Modify: `client/test/smoke/app_shell_smoke_test.dart`
- Optionally Create: `client/test/pages/workspace_ide/workspace_ide_landing_right_tools_test.dart` if smoke is too coarse

- [ ] **Step 1: Update smoke expectations**

On first workspace open (compose landing), right tools stay mounted but not docked. Prefer hit-testable finder:

```dart
expect(find.text(l10n.workspaceChatLandingInputHint), findsOneWidget);
expect(
  find.byKey(AppKeys.rightToolsPanel).hitTestable(),
  findsNothing,
);

// after connectWorkspaceSession + pumps:
expect(
  find.byKey(AppKeys.rightToolsPanel).hitTestable(),
  findsOneWidget,
);
```

Remove/adjust the old “IDE shell mounts right tools (default visible)” comment and the pre-connect `findsOneWidget` / `fileTreePanel` assertions that assumed docked tools on landing.

If `.hitTestable()` is flaky with `DeferredMountShell`, alternatively:

1. Pump past deferred frames (`pumpPhaseTransitions` already helps).
2. Or assert via `LayoutCubit` + policy: after landing paint, `WorkspacePanePolicy.effective(..., composeLanding: true).dockRight == false` while prefs still `rightToolsVisible == true`.

- [ ] **Step 2: Run smoke test**

Run: `cd client && flutter test test/smoke/app_shell_smoke_test.dart`

Expected: PASS.

- [ ] **Step 3: Add a focused widget test (recommended)**

Pump a minimal harness with `LayoutCubit` (prefs right visible) + `WorkspaceIdeShell(composeLanding: true, …)` and assert right pane not hit-testable; set override true; assert visible; set `composeLanding: false` via `pumpWidget` update; assert clear + prefs restored dock.

Also cover **prefs `rightToolsVisible: false` + landing override `true`**: panel content must not be `SizedBox.shrink()` (guards the Task 4 Step 5 gate).

- [ ] **Step 4: Full gate**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test --exclude-tags integration`

- [ ] **Step 5: Commit**

```bash
git add client/test/smoke/app_shell_smoke_test.dart \
  client/test/pages/workspace_ide/workspace_ide_landing_right_tools_test.dart
git commit -m "$(cat <<'EOF'
test(layout): cover landing default-hide for right tools

EOF
)"
```

---

### Task 7: Related spec deltas

**Files:**
- Modify: `docs/superpowers/specs/2026-07-10-workspace-panes-ide-shell-design.md` (Compose landing vs session section ~119–128)
- Modify: `docs/superpowers/specs/2026-07-10-workbench-center-tabs-design.md` (right-tools-during-compose note)

- [ ] **Step 1: Update panes IDE shell design**

Replace compose≡session right-tools row with: compose defaults right hidden; temporary override; left/bottom unchanged; link to `2026-07-11-landing-hide-right-tools-design.md`.

- [ ] **Step 2: Update workbench center tabs note**

Amend “right tools stay available during compose” to: reachable via temporary reveal, not shown by default; link the landing-hide spec.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-07-10-workspace-panes-ide-shell-design.md \
  docs/superpowers/specs/2026-07-10-workbench-center-tabs-design.md
git commit -m "$(cat <<'EOF'
docs: align pane specs with landing right-tools default hide

EOF
)"
```

---

## Manual check (after Task 6)

1. Open a workspace → compose landing → right tools hidden; left sidebar still visible.
2. Click Tools chip → right tools open; prefs unchanged after restart would still default-hide on next landing (override not persisted).
3. Submit / open a session → right tools follow previous `rightToolsVisible` (usually visible).
4. Shortcut for secondary sidebar on landing toggles temporary only.
5. Narrow window: landing hide; temporary open uses overlay; dismiss clears override without flipping prefs.

---

## Execution notes

- Do **not** change `LayoutPreferences.rightToolsVisible` default.
- Do **not** write override through `LayoutRepository`.
- `ShortcutContext.inCompose` is **focus-in-compose-field**, not `ChatCubit.composeActive` — commands must use the explicit `composeLanding` callback, not `ShortcutContext.inCompose`.
