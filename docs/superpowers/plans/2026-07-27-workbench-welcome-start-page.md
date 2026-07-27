# Workbench Welcome / Start Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a workbench welcome/start page (logo + actionable shortcuts) and a landing ← control that leaves compose with tabs retained and no selection.

**Architecture:** Derive center mode as `compose | welcome | tab` from `newChatActive` × `activeTabId`. Compose stays on the existing `newChatActive` IDE-center path; welcome replaces the `WorkbenchBody` null-active landing fallback. Landing ← calls `dismissNewChat` + `WorkbenchCubit.clearActive` (never `exitNewChat`).

**Tech Stack:** Flutter / `flutter_bloc`; `CommandBus`, `ShortcutCubit`, `formatKeyChord`, `titleForCommand`; `TeamPilotBrandLogo`; l10n ARB.

**Spec:** `docs/superpowers/specs/2026-07-27-workbench-welcome-start-page-design.md`

## Global Constraints

- No backward compatibility for `activeTabId == null` ⇒ compose landing.
- Welcome is **only** the landing ← target in v1; open workspace / New conversation still enter compose.
- Landing ← must use `dismissNewChat` + `clearActive`, not `exitNewChat`.
- Welcome shortcut rows always `CommandBus.invoke`; global shortcut `when` gates stay on the dispatcher only.
- Curated welcome commands (exact order): `sessionNewTab`, `togglePanel`, `toggleSidebar`, `workspaceSearch`, `showCheatsheet`.
- Unbound chords: muted `shortcutsNotSet` (reuse existing l10n), row still tappable.
- Edit `app_en.arb` / `app_zh.arb` only for new strings; after ARB changes run `dart run tool/gen_warmup_glyphs.dart` from `client/`.

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/services/workbench/workbench_center_mode.dart` | `WorkbenchCenterMode` enum + `resolveWorkbenchCenterMode` + curated command ids |
| `client/test/services/workbench/workbench_center_mode_test.dart` | Mode truth table + curated list tests |
| `client/lib/pages/workbench/workbench_welcome_page.dart` | Centered logo + tappable shortcut rows |
| `client/test/pages/workbench/workbench_welcome_page_test.dart` | Row tap → `CommandBus.invoke`; unbound label |
| `client/lib/pages/workbench/workbench_body.dart` | `active == null` → `WorkbenchWelcomePage` (delete `WorkspaceChatPane` fallback) |
| `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart` | Top-leading back button |
| `client/lib/utils/ui/app_keys.dart` | Keys for back button + welcome page |
| `client/lib/l10n/app_en.arb` / `app_zh.arb` | Back tooltip |
| `client/test/pages/home_workspace/workspace/workspace_chat_landing_back_test.dart` | Back wiring smoke (or cubit-level nav test) |

---

### Task 1: Center mode helper + curated command ids

**Files:**
- Create: `client/lib/services/workbench/workbench_center_mode.dart`
- Create: `client/test/services/workbench/workbench_center_mode_test.dart`

**Interfaces:**
- Produces:
  - `enum WorkbenchCenterMode { compose, welcome, tab }`
  - `WorkbenchCenterMode resolveWorkbenchCenterMode({required bool newChatActive, required Object? activeTabId})` — treat any non-null `activeTabId` as tab mode (call sites pass `WorkbenchTabId?`)
  - `const List<String> kWorkbenchWelcomeCommandIds`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/commands/command_ids.dart';
import 'package:teampilot/services/workbench/workbench_center_mode.dart';

void main() {
  group('resolveWorkbenchCenterMode', () {
    test('compose wins even when activeTabId is set', () {
      expect(
        resolveWorkbenchCenterMode(newChatActive: true, activeTabId: 'x'),
        WorkbenchCenterMode.compose,
      );
    });

    test('welcome when not compose and active is null', () {
      expect(
        resolveWorkbenchCenterMode(newChatActive: false, activeTabId: null),
        WorkbenchCenterMode.welcome,
      );
    });

    test('tab when not compose and active is set', () {
      expect(
        resolveWorkbenchCenterMode(newChatActive: false, activeTabId: 's1'),
        WorkbenchCenterMode.tab,
      );
    });
  });

  group('kWorkbenchWelcomeCommandIds', () {
    test('exact curated order', () {
      expect(kWorkbenchWelcomeCommandIds, [
        CommandIds.sessionNewTab,
        CommandIds.togglePanel,
        CommandIds.toggleSidebar,
        CommandIds.workspaceSearch,
        CommandIds.showCheatsheet,
      ]);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/services/workbench/workbench_center_mode_test.dart`

Expected: FAIL — library / symbols not found.

- [ ] **Step 3: Write minimal implementation**

Create `client/lib/services/workbench/workbench_center_mode.dart`:

```dart
import '../commands/command_ids.dart';

enum WorkbenchCenterMode { compose, welcome, tab }

/// Single source of truth for workspace center chrome/body.
WorkbenchCenterMode resolveWorkbenchCenterMode({
  required bool newChatActive,
  required Object? activeTabId,
}) {
  if (newChatActive) return WorkbenchCenterMode.compose;
  if (activeTabId == null) return WorkbenchCenterMode.welcome;
  return WorkbenchCenterMode.tab;
}

/// Fixed welcome shortcut rows (labels via [titleForCommand]).
const List<String> kWorkbenchWelcomeCommandIds = [
  CommandIds.sessionNewTab,
  CommandIds.togglePanel,
  CommandIds.toggleSidebar,
  CommandIds.workspaceSearch,
  CommandIds.showCheatsheet,
];
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/services/workbench/workbench_center_mode_test.dart`

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add client/lib/services/workbench/workbench_center_mode.dart \
  client/test/services/workbench/workbench_center_mode_test.dart
git commit -m "$(cat <<'EOF'
feat(workbench): add center mode resolver and welcome command ids

EOF
)"
```

---

### Task 2: WorkbenchWelcomePage UI

**Files:**
- Create: `client/lib/pages/workbench/workbench_welcome_page.dart`
- Create: `client/test/pages/workbench/workbench_welcome_page_test.dart`
- Modify: `client/lib/utils/ui/app_keys.dart` (add `workbenchWelcomePage`, `workbenchWelcomeCommandRow` helper or keyed by id)

**Interfaces:**
- Consumes: `kWorkbenchWelcomeCommandIds`, `CommandBus`, `ShortcutCubit`, `titleForCommand`, `formatKeyChord`, `shortcutsNotSet`
- Produces: `WorkbenchWelcomePage` widget

- [ ] **Step 1: Add AppKeys**

In `app_keys.dart`:

```dart
static const workbenchWelcomePage = Key('workbench-welcome-page');
static Key workbenchWelcomeCommandRow(String commandId) =>
    Key('workbench-welcome-command-$commandId');
```

- [ ] **Step 2: Write the failing widget test**

Pump a minimal `MaterialApp` with `RepositoryProvider<CommandBus>`, `BlocProvider<ShortcutCubit>` (loaded empty overrides so defaults apply, or override one id to `[]` for unbound). Use `TpTheme` / app localizations the same way other widget tests in `client/test/` do — copy the localization wrapper from an existing shortcuts/cheatsheet test if present; otherwise use `AppLocalizations.delegate` + `TpTheme`.

```dart
testWidgets('tapping a row invokes CommandBus', (tester) async {
  final bus = CommandBus();
  var invoked = '';
  bus.register(CommandIds.togglePanel, () => invoked = CommandIds.togglePanel);

  await tester.pumpWidget(/* providers + WorkbenchWelcomePage() */);
  await tester.tap(find.byKey(AppKeys.workbenchWelcomeCommandRow(CommandIds.togglePanel)));
  await tester.pump();
  expect(invoked, CommandIds.togglePanel);
});

testWidgets('unbound command shows shortcutsNotSet', (tester) async {
  final cubit = ShortcutCubit();
  await cubit.unbind(CommandIds.showCheatsheet);
  // pump with that cubit…
  expect(find.textContaining(/* shortcutsNotSet from l10n */), findsWidgets);
});
```

Adapt finders to whatever l10n string `shortcutsNotSet` resolves to in the test locale (en: check ARB).

- [ ] **Step 3: Run test to verify it fails**

Run: `cd client && flutter test test/pages/workbench/workbench_welcome_page_test.dart`

Expected: FAIL — missing page / keys.

- [ ] **Step 4: Implement WorkbenchWelcomePage**

Create `workbench_welcome_page.dart`:

- Root: `KeyedSubtree(key: AppKeys.workbenchWelcomePage)` / `ColoredBox` + centered column.
- Large `TeamPilotBrandLogo(size: 96, color: onSurface.withValues(alpha: 0.35))` (or similar muted mono).
- Below: fixed width (~360–420) list over `kWorkbenchWelcomeCommandIds`.
- Each row: `InkWell` / `Tp`-friendly tap target, `key: AppKeys.workbenchWelcomeCommandRow(id)`, left `titleForCommand`, right chord chips mirroring `_CheatsheetRow` / `_ChordChip` from `shortcut_cheatsheet_dialog.dart` (inline private widgets OK; do not export cheatsheet privates).
- Empty chords → `Text(l10n.shortcutsNotSet, style: muted)`.
- `onTap: () => context.read<CommandBus>().invoke(id)`.
- Watch `ShortcutCubit` so rebinds update keycaps.

- [ ] **Step 5: Run test to verify it passes**

Run: `cd client && flutter test test/pages/workbench/workbench_welcome_page_test.dart`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add client/lib/pages/workbench/workbench_welcome_page.dart \
  client/test/pages/workbench/workbench_welcome_page_test.dart \
  client/lib/utils/ui/app_keys.dart
git commit -m "$(cat <<'EOF'
feat(workbench): add welcome page with actionable shortcut rows

EOF
)"
```

---

### Task 3: Wire welcome into WorkbenchBody (break null → landing)

**Files:**
- Modify: `client/lib/pages/workbench/workbench_body.dart`
- Modify / add tests that asserted null-active compose if any; otherwise add a focused body/mode wiring note in cubit navigation test (Task 4)

**Interfaces:**
- Consumes: `WorkbenchWelcomePage`, `resolveWorkbenchCenterMode` (optional assert — body can branch on `active == null` alone because compose never mounts this widget)
- Produces: null-active body is welcome only

- [ ] **Step 1: Replace null branch**

In `workbench_body.dart`, replace:

```dart
if (active == null) {
  return WorkspaceChatPane(workspace: workspace);
}
```

with:

```dart
if (active == null) {
  return const WorkbenchWelcomePage();
}
```

Remove unused `WorkspaceChatPane` import if no longer needed.

Compose continues to mount only via `buildWorkspaceIdeCenter(newChat: true)` → `WorkspaceChatPane` in `workspace_ide_center.dart` / split pane — do **not** change that path in this task except to confirm it still gates on `workspaceNewChatActive`.

- [ ] **Step 2: Grep for stale assumptions**

Run: `cd client && rg -n "active == null|WorkspaceChatPane" lib/pages/workbench lib/pages/home_workspace/workspace/workspace_ide_center.dart`

Expected: body no longer references `WorkspaceChatPane`; ide center still does for compose.

- [ ] **Step 3: Run related unit tests**

Run: `cd client && flutter test test/services/workbench/ test/cubits/workbench_cubit_test.dart`

Expected: PASS (fix any test that assumed null → landing if present).

- [ ] **Step 4: Commit**

```bash
git add client/lib/pages/workbench/workbench_body.dart
git commit -m "$(cat <<'EOF'
feat(workbench): show welcome page when no tab is selected

EOF
)"
```

---

### Task 4: Landing ← back to welcome

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart`
- Modify: `client/lib/utils/ui/app_keys.dart` — add `workspaceChatLandingBackButton`
- Modify: `client/lib/l10n/app_en.arb`, `client/lib/l10n/app_zh.arb`
- Create: `client/test/cubits/chat/landing_back_to_welcome_test.dart` (logic-focused) and/or widget test

**Interfaces:**
- Consumes: `ChatCubit.dismissNewChat()`, `WorkbenchCubit.clearActive(workspaceId)`
- Produces: back control on landing

- [ ] **Step 1: Add l10n keys**

`app_en.arb`:

```json
"workspaceChatLandingBackToStart": "Back to start"
```

`app_zh.arb`:

```json
"workspaceChatLandingBackToStart": "返回启动页"
```

Place near other `workspaceChatLanding*` keys. Run codegen the repo already uses for l10n (Flutter gen-l10n on build / `flutter gen-l10n` if required), then:

```bash
cd client && dart run tool/gen_warmup_glyphs.dart
```

- [ ] **Step 2: Add AppKey**

```dart
static const workspaceChatLandingBackButton =
    Key('workspace-chat-landing-back-button');
```

- [ ] **Step 3: Write failing navigation test**

Prefer a cubit/store test that mirrors the back action without full landing pump:

```dart
test('dismissNewChat + clearActive yields welcome mode inputs', () async {
  // Arrange: enterNewChat on workspace with existing workbench tabs / active tab
  // Act: cubit.dismissNewChat(); workbench.clearActive(workspaceId);
  // Assert:
  //   !chat.state.newChatActive
  //   workbench.activeTabId(workspaceId) == null
  //   workbench.tabOrder(workspaceId) unchanged
  //   resolveWorkbenchCenterMode(...) == welcome
});

test('empty tabs: dismiss + clearActive stays welcome not forced compose', () {
  // Arrange: newChatActive, empty tab order
  // Act: dismissNewChat + clearActive
  // Assert: welcome mode; newChatActive false (unlike exitNewChat empty-tab re-enter)
});
```

Use existing chat/workbench test harness patterns (`setUpTestAppStorage` if needed). Look at `client/test/cubits/chat_cubit_test.dart` enterNewChat tests for setup.

- [ ] **Step 4: Run test to verify arrange/act expectations fail or action missing**

Run: `cd client && flutter test test/cubits/chat/landing_back_to_welcome_test.dart`

Expected: FAIL until wiring exists / assertions document desired behavior (implement helpers under test that call the same two methods the button will call).

- [ ] **Step 5: Wire landing UI**

In `WorkspaceChatLanding.build`, wrap the existing `ColoredBox` → `SizedBox.expand` tree in a `Stack`:

```dart
Stack(
  children: [
    // existing ColoredBox / scroll content
    Positioned(
      top: spacing.md,
      left: spacing.md,
      child: TpIconButton(
        key: AppKeys.workspaceChatLandingBackButton,
        icon: Icons.arrow_back,
        tooltip: l10n.workspaceChatLandingBackToStart,
        backgroundColor: Colors.transparent,
        onTap: () {
          final workspaceId = widget.workspace.workspaceId;
          context.read<ChatCubit>().dismissNewChat();
          context.read<WorkbenchCubit>().clearActive(workspaceId);
        },
      ),
    ),
  ],
)
```

Import `WorkbenchCubit` and `AppKeys`. Match existing `TpIconButton` API used in the title bar (icon vs iconWidget — follow current `TpIconButton` signature in shared_ui).

- [ ] **Step 6: Run tests**

```bash
cd client && flutter test test/cubits/chat/landing_back_to_welcome_test.dart \
  test/services/workbench/workbench_center_mode_test.dart
```

Expected: PASS

- [ ] **Step 7: Commit**

```bash
git add client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart \
  client/lib/utils/ui/app_keys.dart \
  client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations*.dart \
  client/lib/l10n/warmup_glyphs.g.dart \
  client/test/cubits/chat/landing_back_to_welcome_test.dart
git commit -m "$(cat <<'EOF'
feat(landing): add back control to return to workbench welcome

EOF
)"
```

(Only add generated l10n/glyph files if the tools actually modified them.)

---

### Task 5: Verification sweep

**Files:**
- Touch only if Task 3/4 greps find broken tests or imports

- [ ] **Step 1: Analyze**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no new errors in touched files.

- [ ] **Step 2: Unit tests (non-integration)**

```bash
cd client && flutter test --exclude-tags integration \
  test/services/workbench/ \
  test/pages/workbench/ \
  test/cubits/chat/landing_back_to_welcome_test.dart \
  test/cubits/workbench_cubit_test.dart
```

Expected: PASS

- [ ] **Step 3: Manual checklist (record in commit body or leave for reviewer)**

1. Open workspace → compose landing appears.
2. Create or open a session tab, enter New conversation → landing; ← → welcome with tabs visible, none selected; center shows logo + 5 shortcut rows.
3. Click a tab → session restores; New conversation again → landing; ← with **no** other tabs → welcome, not forced back to compose.
4. On welcome, click “New Session Tab” / `sessionNewTab` row → compose.
5. Click “Toggle Terminal Panel” / search / sidebar / cheatsheet rows → commands fire.
6. Unbind a welcome command in Settings → row shows unbound label, tap still invokes.

- [ ] **Step 4: Final commit if any fixups**

```bash
git add -u
git commit -m "$(cat <<'EOF'
fix(workbench): polish welcome start page after verification

EOF
)"
```

Skip empty commit if clean.

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Center modes compose \| welcome \| tab | Task 1 |
| Curated executable commands + unbound label | Task 1–2 |
| `WorkbenchWelcomePage` UI | Task 2 |
| Remove null → landing | Task 3 |
| Compose only via `newChatActive` path | Task 3 (preserve ide center) |
| Landing ← → dismiss + clearActive | Task 4 |
| Keep tab order / clear selection | Task 4 tests |
| Empty tabs ← → welcome not compose | Task 4 tests |
| Open workspace still compose | unchanged; Task 5 manual |
| l10n back tooltip | Task 4 |
| No Open Browser | omitted from curated list |

## Self-review notes

- No TBD placeholders.
- `resolveWorkbenchCenterMode` uses `Object?` so tests need not construct `WorkbenchTabId`; production passes `WorkbenchTabId?`.
- Landing back must not call `exitNewChat`.
- `shortcutsNotSet` reused for unbound — no extra ARB unless product wants distinct copy later.
