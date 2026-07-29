# Ask AI Single Compose Card Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Selection Ask AI open as one compact compose card (full landing toolbar kept) instead of a titled `TpDialog` wrapping the full `WorkspaceChatLanding` page chrome.

**Architecture:** Add a `showLandingChrome` flag on `WorkspaceChatLanding` (default `true`). When `false`, render only the compose card (no back button, no project/worktree header, no full-bleed centered landing shell). Slim `_SelectionAskAiDialog` to a header-less `TpDialog` that hosts compose-only landing plus a dismiss `×`. Submit path stays unchanged.

**Tech Stack:** Flutter / `flutter_bloc`; `TpDialog` / `TpIconButton` from `shared_ui`; existing `WorkspaceChatLanding` + `WorkspaceChatLandingComposeCard`; `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-07-28-selection-ask-ai-single-compose-card-design.md`

## Global Constraints

- Product shape is **B**: keep mode / model / expert / attach / enhance / voice / send; do **not** build Cursor ultra-minimal bar.
- Stay on `showDialog` (no selection-anchored Overlay).
- Do **not** redesign the primary chat-pane landing layout (`showLandingChrome: true` path unchanged visually).
- Do **not** change FAB / menu entry points or AI context formatters.
- Working directory still from draft resolver / `WorktreeCubit.pathForNewSession` (no in-dialog path pickers when chrome is off).
- Submit remains `persistLandingDraft` → `submitWorkspaceLandingMessage` → pop on session opened.
- Before claiming done: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && flutter test test/services/selection_ai test/pages/home_workspace/workspace/workspace_chat_landing_initial_text_test.dart`

---

## File map

| File | Responsibility |
|------|----------------|
| `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart` | Add `showLandingChrome` (default `true`); compose-only branch in `build` |
| `client/lib/services/selection_ai/selection_ask_ai.dart` | Header-less compact dialog; `showLandingChrome: false`; dismiss `×` |
| `client/test/pages/home_workspace/workspace/workspace_chat_landing_chrome_test.dart` | Chrome on/off widget tests |
| `client/test/services/selection_ai/selection_ask_ai_test.dart` | Assert no header title; compose-only; dismiss; keep WorktreeCubit / router tests |

---

### Task 1: `WorkspaceChatLanding.showLandingChrome`

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart`
- Create: `client/test/pages/home_workspace/workspace/workspace_chat_landing_chrome_test.dart`
- Test harness patterns: `client/test/pages/home_workspace/workspace/workspace_chat_landing_initial_text_test.dart`

**Interfaces:**
- Consumes: existing `WorkspaceChatLanding` ctor fields
- Produces:
  - `WorkspaceChatLanding(..., {bool showLandingChrome = true})`
  - When `showLandingChrome == false`: build tree contains `WorkspaceChatLandingComposeCard`, does **not** contain `AppKeys.workspaceChatLandingBackButton` or `WorkspaceLandingHeaderRow`

- [ ] **Step 1: Write the failing chrome tests**

Create `client/test/pages/home_workspace/workspace/workspace_chat_landing_chrome_test.dart` by copying the provider setup from `workspace_chat_landing_initial_text_test.dart`, then:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/plugin_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_chat_landing.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_chat_landing_compose_card.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_landing_selectors.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/commands/command_bus.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../../support/post_frame_test_harness.dart';

// Reuse the same _Mock* + _stubCubit helpers as initial_text_test.

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  Future<void> pumpLanding(
    WidgetTester tester, {
    required bool showLandingChrome,
  }) async {
    final workspace = Workspace(workspaceId: 'workspace-1', createdAt: 1);
    // ... same MultiBlocProvider + CliToolRegistryScope + MaterialApp + TpTheme
    // as initial_text_test, body:
    // WorkspaceChatLanding(
    //   workspace: workspace,
    //   showLandingChrome: showLandingChrome,
    //   onSubmit: (_, __) {},
    // )
    await tester.pumpWidget(/* harness */);
    await tester.pump(); // allow deferred compose mount frames
    await tester.pump();
  }

  testWidgets('default chrome shows back + header row + compose', (tester) async {
    await pumpLanding(tester, showLandingChrome: true);
    expect(find.byKey(AppKeys.workspaceChatLandingBackButton), findsOneWidget);
    expect(find.byType(WorkspaceLandingHeaderRow), findsOneWidget);
    expect(find.byType(WorkspaceChatLandingComposeCard), findsOneWidget);
  });

  testWidgets('compose-only hides back + header row, keeps compose', (tester) async {
    await pumpLanding(tester, showLandingChrome: false);
    expect(find.byKey(AppKeys.workspaceChatLandingBackButton), findsNothing);
    expect(find.byType(WorkspaceLandingHeaderRow), findsNothing);
    expect(find.byType(WorkspaceChatLandingComposeCard), findsOneWidget);
  });
}
```

Wire the harness fully (do not leave `// ...` in the real file — copy providers from `workspace_chat_landing_initial_text_test.dart`).

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
cd client && flutter test test/pages/home_workspace/workspace/workspace_chat_landing_chrome_test.dart
```

Expected: FAIL — `showLandingChrome` is not a defined parameter (compile error), or compose-only assertions fail if only partially stubbed.

- [ ] **Step 3: Add `showLandingChrome` and compose-only build branch**

In `workspace_chat_landing.dart`:

1. Add to the widget:

```dart
const WorkspaceChatLanding({
  required this.workspace,
  required this.onSubmit,
  this.isSubmitting = false,
  this.disabled = false,
  this.initialText,
  this.showLandingChrome = true,
  super.key,
});

final bool showLandingChrome;
```

2. In `build`, after computing labels / `slashBundle` / etc., extract the existing `WorkspaceChatLandingComposeCard(...)` into a local `final composeCard = WorkspaceChatLandingComposeCard(...);` (same args as today).

3. When `!widget.showLandingChrome`, return the listeners wrapping only:

```dart
return BlocListener<LaunchProfileCubit, LaunchProfileState>(
  // same listenWhen / listener as today
  child: BlocListener<WorktreeCubit, WorktreeState>(
    // same as today
    child: composeCard,
  ),
);
```

Do **not** wrap compose-only in `ColoredBox` + `SizedBox.expand` + centered scroll + `WorkspaceLandingHeaderRow` + back `Positioned`.

4. When `widget.showLandingChrome` is true, keep the existing `Stack` / header / back button tree, using the same `composeCard` local.

- [ ] **Step 4: Run chrome tests to verify they pass**

```bash
cd client && flutter test test/pages/home_workspace/workspace/workspace_chat_landing_chrome_test.dart test/pages/home_workspace/workspace/workspace_chat_landing_initial_text_test.dart
```

Expected: PASS (initialText still works with default chrome).

- [ ] **Step 5: Commit**

```bash
git add \
  client/lib/pages/home_workspace/workspace/workspace_chat_landing.dart \
  client/test/pages/home_workspace/workspace/workspace_chat_landing_chrome_test.dart
git commit -m "$(cat <<'EOF'
feat: add compose-only chrome mode to workspace chat landing

Allow Ask AI to embed WorkspaceChatLanding without the full landing
page shell (back button and project/worktree header).
EOF
)"
```

---

### Task 2: Slim Ask AI dialog shell + update tests

**Files:**
- Modify: `client/lib/services/selection_ai/selection_ask_ai.dart`
- Modify: `client/test/services/selection_ai/selection_ask_ai_test.dart`

**Interfaces:**
- Consumes: `WorkspaceChatLanding(showLandingChrome: false, …)` from Task 1
- Produces: `_SelectionAskAiDialog` with no `TpDialogHeader`, no `SizedBox(height: 600)`, dismiss control that `Navigator.pop`s

- [ ] **Step 1: Update Ask AI tests to the new chrome (fail first)**

In `selection_ask_ai_test.dart`, replace assertions that expect the title string with compose-only expectations.

For both widget tests that currently do `expect(find.text('Ask AI…'), findsOneWidget);`:

```dart
expect(find.text('Ask AI…'), findsNothing);
expect(find.byType(TpDialogHeader), findsNothing);
expect(find.byType(WorkspaceChatLanding), findsOneWidget);
expect(find.byType(WorkspaceChatLandingComposeCard), findsOneWidget);
expect(find.byKey(AppKeys.workspaceChatLandingBackButton), findsNothing);
expect(find.byType(WorkspaceLandingHeaderRow), findsNothing);
```

Add imports:

```dart
import 'package:teampilot/pages/home_workspace/workspace/workspace_chat_landing_compose_card.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_landing_selectors.dart';
import 'package:teampilot/utils/ui/app_keys.dart';
```

Add a new test (same harness as the WorktreeCubit inheritance test):

```dart
testWidgets('Ask AI dialog dismiss control closes the dialog', (tester) async {
  // same pump + Open tap as WorktreeCubit test
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();

  expect(find.byType(WorkspaceChatLanding), findsOneWidget);

  await tester.tap(find.byKey(const Key('selection-ask-ai-dismiss')));
  await tester.pumpAndSettle();

  expect(find.byType(WorkspaceChatLanding), findsNothing);
});
```

- [ ] **Step 2: Run Ask AI tests to verify they fail**

```bash
cd client && flutter test test/services/selection_ai/selection_ask_ai_test.dart
```

Expected: FAIL — still finds `Ask AI…` / `TpDialogHeader`; dismiss key missing.

- [ ] **Step 3: Implement compact dialog UI**

Replace `_SelectionAskAiDialogState.build` in `selection_ask_ai.dart` with:

```dart
@override
Widget build(BuildContext context) {
  final spacing = context.tpSpacing;
  return TpDialog(
    maxWidth: 880,
    // Content-driven height; no fixed 600px landing frame.
    scrollable: true,
    contentPadding: EdgeInsets.all(spacing.md),
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        WorkspaceChatLanding(
          workspace: widget.workspace,
          initialText: widget.initialText,
          isSubmitting: _submitting,
          showLandingChrome: false,
          onSubmit: (message, draft) => unawaited(_submit(message, draft)),
        ),
        Positioned(
          top: 0,
          right: 0,
          child: TpIconButton(
            key: const Key('selection-ask-ai-dismiss'),
            icon: Icons.close_rounded,
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            backgroundColor: Colors.transparent,
            onTap: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    ),
  );
}
```

Keep `_submit` / `openComposeDialog` / WorktreeCubit capture unchanged.

Ensure `selection_ask_ai.dart` already imports (or add) what `TpIconButton` / `context.tpSpacing` need via `shared_ui`.

- [ ] **Step 4: Run Ask AI + landing tests**

```bash
cd client && flutter test \
  test/services/selection_ai/selection_ask_ai_test.dart \
  test/pages/home_workspace/workspace/workspace_chat_landing_chrome_test.dart \
  test/pages/home_workspace/workspace/workspace_chat_landing_initial_text_test.dart
```

Expected: PASS.

- [ ] **Step 5: Analyze touched packages and commit**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings \
  lib/services/selection_ai/selection_ask_ai.dart \
  lib/pages/home_workspace/workspace/workspace_chat_landing.dart \
  test/services/selection_ai/selection_ask_ai_test.dart \
  test/pages/home_workspace/workspace/workspace_chat_landing_chrome_test.dart
```

Expected: no errors.

```bash
git add \
  client/lib/services/selection_ai/selection_ask_ai.dart \
  client/test/services/selection_ai/selection_ask_ai_test.dart
git commit -m "$(cat <<'EOF'
fix: show Ask AI as a single compose card dialog

Drop the titled landing-page shell and embed compose-only
WorkspaceChatLanding with a dismiss control.
EOF
)"
```

---

### Task 3: Verification sweep

**Files:** none new (run only)

- [ ] **Step 1: Run selection_ai + landing regression tests**

```bash
cd client && flutter test test/services/selection_ai test/pages/home_workspace/workspace/workspace_chat_landing_initial_text_test.dart test/pages/home_workspace/workspace/workspace_chat_landing_chrome_test.dart
```

Expected: all PASS.

- [ ] **Step 2: Broader analyze on touched libs**

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: no new errors in touched files.

- [ ] **Step 3: Manual smoke (if a desktop build is available)**

1. Select text in file editor → Ask AI → one card, no「用 AI 提问…」title, no back/header row.
2. Confirm toolbar chips still work; dismiss `×` closes.
3. Submit opens a new session with prefilled context delivered.
4. Main chat landing (new chat) still shows back + project/worktree header.

If no interactive build in this environment, note that in the handoff and rely on widget tests.

- [ ] **Step 4: Commit only if Step 1–2 produced extra fixes; otherwise done**

No empty commit.

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Single compose surface / no nested landing page | Task 1 + 2 |
| No `TpDialogHeader` title | Task 2 |
| Close via `×` | Task 2 |
| Hide back + repo/worktree row | Task 1 |
| Keep full compose toolbar | Task 1 (compose card unchanged) |
| `showDialog` retained | Task 2 |
| Submit path unchanged | Task 2 (no `_submit` rewrite) |
| cwd via draft / WorktreeCubit | unchanged code path |
| Tests updated | Task 1 + 2 + 3 |
| Primary landing layout unchanged | Task 1 default `showLandingChrome: true` |
