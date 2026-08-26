# Reference Session Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a “引用会话” action to both Session menus that opens the workspace Landing and prefills `审查并继续完成该会话: <完整 Session 目录路径>` while retaining the Landing’s current launch configuration.

**Architecture:** Store the optional Landing prefill on the per-workspace Workbench `TabStrip`, propagate it through `WorkspaceSplitPane` → `WorkspaceChatPane` → `WorkspaceChatLanding`, and let the existing `UnboundComposeBody` controller replace its text when the prefill changes. Centralize path resolution and Landing navigation in `workspace_session_actions.dart`, then call that helper from both menu surfaces.

**Tech Stack:** Flutter/Dart, `flutter_bloc`, `shared_ui` action menus, `SessionRepositoryFs`/`WorkspaceLayout`, Flutter widget tests, ARB localization.

## Global Constraints

- Add or change cross-route controls only through existing shared UI primitives; do not add a generic control under `client/lib/widgets/`.
- Edit localization source in `client/lib/l10n/app_en.arb` and `client/lib/l10n/app_zh.arb`; regenerate generated localization output with the repository tool instead of hand-editing generated source.
- Use `SessionRepository.fs().layout.sessionDir(workspaceId, sessionId)` so native, WSL, and SSH storage contexts produce their own canonical path format.
- Do not modify the source Session, copy its runtime/configuration, or automatically submit the new conversation.
- Preserve unrelated dirty worktree changes; stage only files belonging to this feature in each commit.
- Before completion run `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings && dart run tool/run_tests.dart`.

---

### Task 1: Add Landing prefill state to the Workbench navigation API

**Files:**
- Modify: `client/lib/cubits/workbench/tab_strip.dart`
- Modify: `client/lib/cubits/workbench/workbench_cubit.dart`
- Modify: `client/lib/cubits/chat/session_launch_host.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`
- Modify: `client/lib/services/workbench/workbench_chat_bridge.dart`
- Test: `client/test/cubits/workbench/tab_strip_test.dart`
- Test: `client/test/services/workbench/workbench_strip_navigator_test.dart`

**Interfaces:**
- Consumes: the existing per-workspace `TabStrip` center state and `ChatWorkbenchPort.enterLanding` bridge.
- Produces: `TabStrip.landingInitialText`, `WorkbenchCubit.enterLanding(String workspaceId, {String? initialText})`, `ChatWorkbenchPort.enterLanding(String workspaceId, {String? initialText})`, and `ChatCubit.enterNewChat(String workspaceId, {String? initialText})`.

- [ ] **Step 1: Write failing reducer and cubit tests**

Add these assertions to the existing Workbench tests:

```dart
test('enterLanding stores the initial text while retaining open tabs', () {
  final (withTab, _) = r.add(empty, _s1, preview: false);
  final landing = r.enterLanding(
    withTab,
    initialText: '审查并继续完成该会话: /data/session',
  );

  expect(landing.activeId, isNull);
  expect(landing.order, [_s1]);
  expect(
    landing.landingInitialText,
    '审查并继续完成该会话: /data/session',
  );
});

test('enterLanding updates prefill while Landing is already active', () {
  final workbench = WorkbenchCubit()..enterLanding('ws-1');
  workbench.enterLanding(
    'ws-1',
    initialText: '审查并继续完成该会话: /data/session-2',
  );

  expect(
    workbench.state.bar('ws-1').center.landingInitialText,
    '审查并继续完成该会话: /data/session-2',
  );
});
```

- [ ] **Step 2: Run the focused tests to verify they fail**

```bash
cd client && flutter test test/cubits/workbench/tab_strip_test.dart test/services/workbench/workbench_strip_navigator_test.dart
```

Expected: FAIL because `TabStrip.landingInitialText` and the new optional Landing arguments do not exist.

- [ ] **Step 3: Implement the minimal Workbench state and bridge changes**

Extend `TabStrip` with an optional field and include it in equality:

```dart
static const Object _unset = Object();

const TabStrip({
  this.order = const [],
  this.activeId,
  this.previewIds = const {},
  this.landingInitialText,
});

final String? landingInitialText;

TabStrip copyWith({
  List<WorkbenchTabId>? order,
  Object? activeId = _unset,
  Set<WorkbenchTabId>? previewIds,
  Object? landingInitialText = _unset,
}) => TabStrip(
  order: order ?? this.order,
  activeId: activeId == _unset ? this.activeId : activeId as WorkbenchTabId?,
  previewIds: previewIds ?? this.previewIds,
  landingInitialText: landingInitialText == _unset
      ? this.landingInitialText
      : landingInitialText as String?,
);

@override
List<Object?> get props => [order, activeId, previewIds, landingInitialText];
```

Make `TabStripReducer.enterLanding` accept `initialText` and write it into the returned strip. Update `WorkbenchCubit.enterLanding` with these rules: when Landing is active, a null argument is a no-op and a non-null argument replaces the current prefill; when switching from a session to Landing, null clears the prior prefill.

Add the same optional named argument to `ChatWorkbenchPort.enterLanding`, `WorkbenchChatBridge.enterLanding`, `ChatCubit.enterNewChat`, and forward it through each call. Existing callers that omit the argument must keep their current behavior.

- [ ] **Step 4: Run the focused tests and verify they pass**

Run the command from Step 2. Expected: PASS, including the existing test that entering Landing retains open tabs.

- [ ] **Step 5: Commit the Workbench state change**

```bash
git add client/lib/cubits/workbench/tab_strip.dart client/lib/cubits/workbench/workbench_cubit.dart client/lib/cubits/chat/session_launch_host.dart client/lib/cubits/chat_cubit.dart client/lib/services/workbench/workbench_chat_bridge.dart client/test/cubits/workbench/tab_strip_test.dart client/test/services/workbench/workbench_strip_navigator_test.dart
git commit -m "feat: carry landing prefill through workbench"
```

### Task 2: Propagate and refresh Landing input text

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_split_pane.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_ide_center.dart`
- Modify: `client/lib/pages/home_workspace/workspace/workspace_chat_pane.dart`
- Modify: `client/lib/pages/home_workspace/workspace/unbound_compose_body.dart`
- Modify: `client/test/pages/home_workspace/workspace/workspace_chat_landing_initial_text_test.dart`

**Interfaces:**
- Consumes: `WorkbenchCubit`’s `TabStrip.landingInitialText` and the API from Task 1.
- Produces: `WorkspaceChatPane.initialText` and a Landing input that replaces its controller value when a new non-empty prefill arrives.

- [ ] **Step 1: Add a failing widget test for prefill replacement**

Extend the Landing test so the same mounted compose receives a new prefill:

```dart
await tester.pumpWidget(landing('first reference'));
await tester.pumpAndSettle();
expect(_composeField(tester).controller!.text, 'first reference');

await tester.pumpWidget(landing('second reference'));
await tester.pump();

expect(_composeField(tester).controller!.text, 'second reference');
```

Keep the existing assertion that an initial prefill does not hydrate an old cached Landing draft.

- [ ] **Step 2: Run the focused widget test to verify it fails**

```bash
cd client && flutter test test/pages/home_workspace/workspace/workspace_chat_landing_initial_text_test.dart
```

Expected: FAIL because `UnboundComposeBody` currently seeds `initialText` only during `initState`.

- [ ] **Step 3: Thread the value through the workspace center**

In `WorkspaceSplitPane`, select the active workspace’s Landing prefill alongside `composeLanding`, then pass it to `buildWorkspaceIdeCenter`. Update the helper signature:

```dart
Widget buildWorkspaceIdeCenter({
  required bool newChat,
  required Workspace workspace,
  required Widget chatPage,
  String? initialText,
}) {
  if (newChat) {
    return WorkspaceChatPane(
      workspace: workspace,
      initialText: initialText,
    );
  }
  return chatPage;
}
```

Add the optional `initialText` field to `WorkspaceChatPane` and pass it to `WorkspaceChatLanding`. Do not change the existing `WorkspaceChatPane` submit or draft persistence flow.

- [ ] **Step 4: Replace the compose controller when the prefill changes**

Add this logic to `_UnboundComposeBodyState.didUpdateWidget` after the existing workspace checks:

```dart
final nextInitialText = widget.initialText;
if (oldWidget.initialText != nextInitialText &&
    nextInitialText != null &&
    nextInitialText.isNotEmpty) {
  _controller.value = TextEditingValue(
    text: nextInitialText,
    selection: TextSelection.collapsed(offset: nextInitialText.length),
  );
}
```

When `initialText` becomes null, leave the current controller text unchanged so normal Landing draft behavior remains intact. The existing controller listener will persist a newly applied reference text through the current draft cache mechanism.

- [ ] **Step 5: Run the focused widget test and verify it passes**

Run the command from Step 2. Expected: PASS, including cache, initial seed, and replacement assertions.

- [ ] **Step 6: Commit the Landing propagation change**

```bash
git add client/lib/pages/home_workspace/workspace/workspace_split_pane.dart client/lib/pages/home_workspace/workspace/workspace_ide_center.dart client/lib/pages/home_workspace/workspace/workspace_chat_pane.dart client/lib/pages/home_workspace/workspace/unbound_compose_body.dart client/test/pages/home_workspace/workspace/workspace_chat_landing_initial_text_test.dart
git commit -m "feat: refresh landing compose prefill"
```

### Task 3: Implement the shared Session reference action and menu entries

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`
- Modify: `client/lib/widgets/sidebar_session_tile.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Test: `client/test/pages/home_workspace/workspace/workspace_session_actions_test.dart`
- Test: `client/test/widgets/sidebar_session_tile_test.dart`

**Interfaces:**
- Consumes: `AppSession`, `SessionRepository.fs()`, `WorkspaceLayout.sessionDir`, `showWorkspaceComposeLanding`, and Task 1’s `ChatCubit.enterNewChat` path.
- Produces: `referenceWorkspaceSession(BuildContext context, AppSession session)` and menu value `reference` in both Session menu surfaces.

- [ ] **Step 1: Add failing tests for the action contract and menu labels**

In `workspace_session_actions_test.dart`, add a test host with a `ChatCubit`, `SessionRepository(rootDir: '/teampilot')`, `WorkbenchCubit`, and `WorkbenchChatBridge`, then assert:

```dart
await referenceWorkspaceSession(context, session);

expect(
  workbench.state.bar('ws1').center.landingInitialText,
  '审查并继续完成该会话: /teampilot/workspace/workspaces/ws1/sessions/sess-1',
);
```

In `sidebar_session_tile_test.dart`, open the secondary-click menu and assert a `TpActionMenuPopupItem<String>` with `value == 'reference'` and the localized label `引用会话`. Move the pointer over the tile, open the overflow icon, and assert the same label is present in the hover menu.

- [ ] **Step 2: Run the focused tests to verify they fail**

```bash
cd client && flutter test test/pages/home_workspace/workspace/workspace_session_actions_test.dart test/widgets/sidebar_session_tile_test.dart
```

Expected: FAIL because the shared action, localization key, and menu entries do not exist.

- [ ] **Step 3: Add the localization entries**

Add these keys near the existing conversation actions:

```json
// app_en.arb
"referenceConversation": "Reference conversation",
"referenceConversationFailed": "Failed to prepare conversation reference",
```

```json
// app_zh.arb
"referenceConversation": "引用会话",
"referenceConversationFailed": "准备会话引用失败",
```

Run `cd client && flutter gen-l10n` after editing the ARB files; do not hand-edit generated localization Dart files.

- [ ] **Step 4: Implement the shared reference action**

Add this public helper to `workspace_session_actions.dart`:

```dart
Future<void> referenceWorkspaceSession(
  BuildContext context,
  AppSession session,
) async {
  final chat = context.read<ChatCubit>();
  try {
    final fs = await context.read<SessionRepository>().fs();
    final path = fs.layout.sessionDir(
      session.workspaceId,
      session.sessionId,
    );
    final workspace = chat.state.workspaces
        .where((item) => item.workspaceId == session.workspaceId)
        .firstOrNull;
    if (!context.mounted || workspace == null) {
      throw StateError('workspace not found: ${session.workspaceId}');
    }
    await showWorkspaceComposeLanding(
      context,
      workspace,
      tabScopeId: session.workspaceId,
      initialText: '审查并继续完成该会话: $path',
    );
  } on Object catch (error, stackTrace) {
    appLogger.e(
      'referenceWorkspaceSession',
      error: error,
      stackTrace: stackTrace,
    );
    if (context.mounted) {
      AppToast.show(
        context,
        message: context.l10n.referenceConversationFailed,
        variant: TpToastVariant.error,
      );
    }
  }
}
```

Import `AppSession`, `SessionRepository`, `appLogger`, and `AppToast` if not already available in the file. Update `showWorkspaceComposeLanding` to accept `String? initialText` and forward it to `chat.enterNewChat(tabScopeId, initialText: initialText)`.

- [ ] **Step 5: Add both menu entries and route them to the helper**

In `SidebarSessionTile._contextMenuItems`, insert:

```dart
TpActionMenuPopupItem(
  value: 'reference',
  icon: Icons.format_quote_rounded,
  label: l10n.referenceConversation,
),
```

Handle it in `_handleContextAction`:

```dart
case 'reference':
  await referenceWorkspaceSession(context, session);
```

Add the corresponding `TpActionMenuItem` to the hover overflow menu, using the same icon, label, and callback:

```dart
TpActionMenuItem(
  icon: Icons.format_quote_rounded,
  label: l10n.referenceConversation,
  menuController: controller,
  onTap: () => unawaited(
    referenceWorkspaceSession(context, session),
  ),
),
```

- [ ] **Step 6: Add the failure-path test and run focused tests**

Create a `SessionRepository` test double whose `fs()` throws `StateError('storage unavailable')`. Invoke `referenceWorkspaceSession` inside a mounted test host and assert that it completes without throwing, the Workbench remains on its prior active tab, and `referenceConversationFailed` is shown. Then run:

```bash
cd client && flutter test test/pages/home_workspace/workspace/workspace_session_actions_test.dart test/widgets/sidebar_session_tile_test.dart test/pages/home_workspace/workspace/workspace_chat_landing_initial_text_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit the menu and action change**

```bash
git add client/lib/pages/home_workspace/workspace/workspace_session_actions.dart client/lib/widgets/sidebar_session_tile.dart client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb client/lib/l10n/app_localizations.dart client/lib/l10n/app_localizations_en.dart client/lib/l10n/app_localizations_zh.dart client/test/pages/home_workspace/workspace/workspace_session_actions_test.dart client/test/widgets/sidebar_session_tile_test.dart
git commit -m "feat: add reference session action"
```

If the localization generator updates a different tracked generated file set, stage only the files reported by `git status` for that generation step.

### Task 4: Full verification and regression review

**Files:**
- No new source files.
- Review all files changed by Tasks 1–3 and the generated localization output.

**Interfaces:**
- Consumes: the completed menu, Workbench, Landing, and localization changes.
- Produces: verified feature behavior with no unrelated worktree modifications staged.

- [ ] **Step 1: Run formatting and static analysis on changed Dart files**

```bash
cd client && dart format lib/cubits/workbench/tab_strip.dart lib/cubits/workbench/workbench_cubit.dart lib/cubits/chat/session_launch_host.dart lib/cubits/chat_cubit.dart lib/services/workbench/workbench_chat_bridge.dart lib/pages/home_workspace/workspace/workspace_split_pane.dart lib/pages/home_workspace/workspace/workspace_ide_center.dart lib/pages/home_workspace/workspace/workspace_chat_pane.dart lib/pages/home_workspace/workspace/unbound_compose_body.dart lib/pages/home_workspace/workspace/workspace_session_actions.dart lib/widgets/sidebar_session_tile.dart test/cubits/workbench/tab_strip_test.dart test/services/workbench/workbench_strip_navigator_test.dart test/pages/home_workspace/workspace/workspace_chat_landing_initial_text_test.dart test/pages/home_workspace/workspace/workspace_session_actions_test.dart test/widgets/sidebar_session_tile_test.dart
flutter analyze --no-fatal-infos --no-fatal-warnings
```

Expected: formatter reports no unformatted files and analyzer exits successfully.

- [ ] **Step 2: Run the complete repository test command**

```bash
cd client && dart run tool/run_tests.dart
```

Expected: the repository test runner completes successfully, including the focused tests and existing Workbench/Landing regression tests.

- [ ] **Step 3: Check the final diff and worktree scope**

```bash
git diff --check HEAD~3..HEAD
git status --short
```

Expected: no whitespace errors; only the feature commits are represented in the feature diff, while pre-existing dirty files remain untouched and unstaged.

## Plan Self-Review

- Spec coverage: menu labels, both menu surfaces, canonical backend-aware Session path, exact `审查并继续完成该会话: ` prefix, Landing navigation, current Landing launch configuration, unchanged source Session, failure toast, and focused/full tests are all assigned above.
- Placeholder scan: no implementation task relies on `TODO`, `TBD`, or unspecified validation behavior. Angle brackets only describe the user-visible path placeholder in the feature text.
- Type consistency: `initialText` is consistently nullable from `WorkbenchCubit` through `ChatWorkbenchPort`, `ChatCubit`, `showWorkspaceComposeLanding`, `WorkspaceChatPane`, and `WorkspaceChatLanding`; `referenceWorkspaceSession` returns `Future<void>` and is awaited by the context menu or launched with `unawaited` by the hover menu.
