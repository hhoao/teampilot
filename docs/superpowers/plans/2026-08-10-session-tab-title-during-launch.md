# Session Tab Title During Launch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Session tabs never paint blank during launch, and compose-landing prompts produce an immediate title that survives async persistence.

**Architecture:** Two small changes: the session tab chip falls back to the existing localized `defaultNewChatSessionTitle` when `AppSession.display` is empty, and `submitWorkspaceLandingMessage` renames the staged session from the landing prompt before connect. Because persistence runs asynchronously, `_persistSessionIfNeeded` also preserves a staged display title that landed before the persist write completed.

**Tech Stack:** Flutter/Dart, flutter_bloc, shared_ui `Tp*` widgets, `SessionLaunchService` / `SessionRepository`.

## Global Constraints

- Work with, never revert, the user's uncommitted changes in `client/lib/cubits/chat/session_launch_service.dart` and `client/lib/repositories/session_repository.dart`.
- Keep the existing "first prompt wins, never overwrite a manual title" rule (`SessionPromptMetadataSync` already skips non-empty `display`).
- Reuse the l10n key `defaultNewChatSessionTitle`; do not add new copy or change `app_en.arb` / `app_zh.arb`.
- ASCII only in files created or edited.
- Every task must pass `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings` and `flutter test --exclude-tags integration` before the final commit.

---

### Task 1: Session Tab Chip Empty-Title Fallback

**Files:**
- Create: `client/test/pages/workspace_shell/workspace_shell_tab_chip_title_test.dart`
- Modify: `client/lib/pages/workspace_shell/workspace_shell_tabs.dart` (`WorkbenchStripTabChipState.build`, around lines 425-431)

**Interfaces:**
- Consumes: `ChatCubit.state.sessions` via `SessionRowContent.fromChatState(...).titleForPaint`, `context.l10n.defaultNewChatSessionTitle`.
- Produces: session tab chips paint a non-empty title even when `display` is empty. File/diff/shell/run chips are unchanged.

- [ ] **Step 1: Write the failing widget test**

Create `client/test/pages/workspace_shell/workspace_shell_tab_chip_title_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell_tabs.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('session tab paints New Chat fallback while display is empty', (
    tester,
  ) async {
    final chatCubit = testChatCubit(executableResolver: () => 'claude');
    final attention = AgentAttentionCubit(pruneInterval: null);
    addTearDown(chatCubit.close);
    addTearDown(attention.close);

    chatCubit.applyState(
      chatCubit.state.copyWith(
        sessions: [
          AppSession(
            sessionId: 'sess-1',
            workspaceId: 'ws1',
            createdAt: 1,
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TpTheme(
          data: TpThemeData.fromColorScheme(
            ColorScheme.fromSeed(seedColor: Colors.blue),
            scale: 1.0,
          ),
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ChatCubit>.value(value: chatCubit),
              BlocProvider<AgentAttentionCubit>.value(value: attention),
            ],
            child: Scaffold(
              body: WorkbenchStripTabChip(
                title: '',
                active: true,
                sessionId: 'sess-1',
                tabId: 'sess-1',
                kind: WorkbenchTabKind.session,
                onTap: () {},
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('New Chat'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd client && flutter test test/pages/workspace_shell/workspace_shell_tab_chip_title_test.dart`

Expected: FAIL — `find.text('New Chat')` finds nothing because the chip paints an empty string.

- [ ] **Step 3: Implement the fallback**

In `client/lib/pages/workspace_shell/workspace_shell_tabs.dart`, replace the `title` computation in `WorkbenchStripTabChipState.build`:

```dart
    final rawTitle = sessionId == null
        ? widget.title
        : context.select<ChatCubit, String>(
            (c) =>
                SessionRowContent.fromChatState(c.state, sessionId).titleForPaint,
          );
    final title = rawTitle.isNotEmpty
        ? rawTitle
        : context.l10n.defaultNewChatSessionTitle;
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd client && flutter test test/pages/workspace_shell/workspace_shell_tab_chip_title_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add client/test/pages/workspace_shell/workspace_shell_tab_chip_title_test.dart client/lib/pages/workspace_shell/workspace_shell_tabs.dart
git commit -m "fix(workbench): session tab fallback title while unnamed"
```

---

### Task 2: Landing Prompt Title Before Connect + Persist Preservation

**Files:**
- Modify: `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`
- Modify: `client/lib/cubits/chat/session_launch_service.dart` (`_persistSessionIfNeeded`, around line 237)
- Modify: `docs/superpowers/specs/2026-08-10-session-tab-title-during-launch-design.md` (Design section 2)
- Create: `client/test/pages/home_workspace/workspace/workspace_session_actions_test.dart`
- Modify: `client/test/services/launch/session_launch_pipeline_stable_task_id_test.dart`

**Interfaces:**
- Consumes: `ChatCubit.applyFirstPromptTitle(String, String)`, `ChatState.sessions`, `SessionRepository.renameSession(String, String)`, `SessionLaunchHost.replaceSessionSnapshot(AppSession)`.
- Produces: top-level `Future<void> applyLandingPromptTitleBestEffort({required ChatCubit chatCubit, required String sessionId, required String prompt})`; persisted `AppSession.display` preserves a staged title that was renamed before async persistence completed.

- [ ] **Step 1: Update the spec with the persistence-race detail**

In `docs/superpowers/specs/2026-08-10-session-tab-title-during-launch-design.md`, replace the "The rename is best-effort" paragraph in Design section 2 with:

```markdown
The rename is best-effort: wrap it in try/catch and log failures with
`appLogger`; a title-write failure must not block or abort the connect.
`SessionPromptMetadataSync` already skips renaming when `display` is non-empty,
so it cannot overwrite a manual title or race with the keyboard
`FirstUserLineCapture` path.

Persistence runs asynchronously after the tab is staged, so
`_persistSessionIfNeeded` also preserves a staged display title: after
`createSession` returns, if the current state already has a non-empty display
for the session and the persisted copy is empty, it calls `repo.renameSession`
and carries the title into the replaced snapshot.
```

- [ ] **Step 2: Write the failing helper test**

Create `client/test/pages/home_workspace/workspace/workspace_session_actions_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_session_actions.dart';

import '../../../support/post_frame_test_harness.dart';

class _RecordingChatCubit extends ChatCubit {
  _RecordingChatCubit({this.failRename = false})
    : super(
        executableResolver: () => 'true',
        automationRepository: testAutomationRepository(),
      );

  final bool failRename;
  final prompts = <(String, String)>[];

  @override
  Future<void> applyFirstPromptTitle(
    String sessionId,
    String firstPrompt,
  ) async {
    prompts.add((sessionId, firstPrompt));
    if (failRename) throw StateError('rename failed');
  }
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test('applyLandingPromptTitleBestEffort forwards the landing prompt', () async {
    final chat = _RecordingChatCubit();
    addTearDown(chat.close);

    await applyLandingPromptTitleBestEffort(
      chatCubit: chat,
      sessionId: 'sess-1',
      prompt: 'fix the title',
    );

    expect(chat.prompts, [('sess-1', 'fix the title')]);
  });

  test('applyLandingPromptTitleBestEffort swallows rename errors', () async {
    final chat = _RecordingChatCubit(failRename: true);
    addTearDown(chat.close);

    await expectLater(
      applyLandingPromptTitleBestEffort(
        chatCubit: chat,
        sessionId: 'sess-1',
        prompt: 'fix the title',
      ),
      completes,
    );

    expect(chat.prompts, [('sess-1', 'fix the title')]);
  });
}
```

- [ ] **Step 3: Write the failing persistence test**

In `client/test/services/launch/session_launch_pipeline_stable_task_id_test.dart`, add `renames` to `_CapturingSessionRepository`:

```dart
class _CapturingSessionRepository extends Fake implements SessionRepository {
  final createCalls = <_CreateSessionCall>[];
  final renames = <(String, String)>[];
  Completer<void>? createGate;

  @override
  Future<void> renameSession(String sessionId, String newName) async {
    renames.add((sessionId, newName));
  }
```

Also add `import 'dart:async';` at the top of the test file, and add
`await createGate?.future;` after `createCalls.add(...)` inside
`createSession` so the test can deterministically block persistence.

Then add this test inside `main()` after the existing
`persistSessionIfNeeded forwards staged members to createSession` test:

```dart
    test('persistSessionIfNeeded preserves a staged prompt title', () async {
      final workspace = Workspace(
        workspaceId: 'ws-1',
        folders: const [WorkspaceFolder(path: '/proj')],
        createdAt: 1,
        updatedAt: 1,
      );
      final team = TeamProfile(
        id: 'team-1',
        name: 'Team',
        members: const [
          TeamMemberConfig(id: 'team-lead', name: 'Lead'),
          TeamMemberConfig(id: 'builder', name: 'Builder'),
        ],
        cli: CliTool.claude,
      );
      final capturer = _CapturingSessionRepository()
        ..createGate = Completer<void>();
      final tabStore = ChatTabStore()..setActiveWorkspaceId('ws-1');
      final host = _CapturingHost(
        ChatState(workspaces: [workspace]),
        tabStore: tabStore,
        lifecycle: SessionLifecycleService(loadPresets: () => const []),
        sessionRepository: capturer,
      );
      final service = SessionLaunchService(host);

      const fixedSessionId = 'sess-title-cccccccccccccccc';
      final status = await service.requestCreateAndOpenSession(
        SessionCreateRequest(
          workspace: workspace,
          isPersonal: false,
          team: team,
          member: team.members.first,
          repo: capturer,
          fixedSessionId: fixedSessionId,
        ),
      );
      expect(status, SessionOpenStatus.opened);
      expect(host.appended, hasLength(1));

      await _waitUntil(() => capturer.createCalls.isNotEmpty);

      // Simulate the landing-prompt rename landing before async persistence.
      final provisional = host.appended.single;
      host.applyState(
        host.state.copyWith(
          sessions: [
            provisional.copyWith(display: 'Fix the landing title'),
          ],
        ),
      );

      capturer.createGate!.complete();
      await _waitUntil(() => host.replaced.isNotEmpty);

      final persisted = host.replaced.single;
      expect(persisted.display, 'Fix the landing title');
      expect(
        capturer.renames,
        contains((
          'sess-title-cccccccccccccccc',
          'Fix the landing title',
        )),
      );
    });
```

- [ ] **Step 4: Run both new tests to verify they fail**

Run:

```bash
cd client && flutter test test/pages/home_workspace/workspace/workspace_session_actions_test.dart
cd client && flutter test test/services/launch/session_launch_pipeline_stable_task_id_test.dart
```

Expected: helper test FAILS with "applyLandingPromptTitleBestEffort is not defined"; persistence test FAILS because `persisted.display` is empty.

- [ ] **Step 5: Implement the helper and move the rename before connect**

In `client/lib/pages/home_workspace/workspace/workspace_session_actions.dart`, add this top-level function after `buildOpenExistingSessionRequest`:

```dart
/// Best-effort rename of an untitled session from the landing prompt, before
/// connect/delivery. A title-write failure must not block the launch.
Future<void> applyLandingPromptTitleBestEffort({
  required ChatCubit chatCubit,
  required String sessionId,
  required String prompt,
}) async {
  try {
    await chatCubit.applyFirstPromptTitle(sessionId, prompt);
  } on Object catch (error, stackTrace) {
    appLogger.e(
      'applyLandingPromptTitleBestEffort',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
```

In `submitWorkspaceLandingMessage`, after the `if (session == null) { ... }` block and before `final memberId = await _resolveLandingMemberId(`, insert:

```dart
  await applyLandingPromptTitleBestEffort(
    chatCubit: chatCubit,
    sessionId: session.sessionId,
    prompt: trimmed,
  );
```

Remove the later post-delivery rename inside the `try` block:

```dart
    // Landing inject bypasses FirstUserLineCapture (keyboard path only).
    await chatCubit.applyFirstPromptTitle(session.sessionId, trimmed);
```

- [ ] **Step 6: Implement the persist preservation**

In `client/lib/cubits/chat/session_launch_service.dart`, in `_persistSessionIfNeeded`, after the `appLogger.d(...)` createSession log and before `tab.persistedSession = persisted;`, replace the tail with:

```dart
    var persistedWithTitle = persisted;
    final stagedTitle = _state()
        .sessions
        .where((s) => s.sessionId == session.sessionId)
        .firstOrNull
        ?.display
        .trim();
    if (stagedTitle != null &&
        stagedTitle.isNotEmpty &&
        persistedWithTitle.display.trim().isEmpty) {
      await repo.renameSession(session.sessionId, stagedTitle);
      persistedWithTitle = persistedWithTitle.copyWith(display: stagedTitle);
    }
    tab.persistedSession = persistedWithTitle;
    _h.replaceSessionSnapshot(persistedWithTitle);
    return persistedWithTitle;
```

- [ ] **Step 7: Run both new tests to verify they pass**

Run:

```bash
cd client && flutter test test/pages/home_workspace/workspace/workspace_session_actions_test.dart
cd client && flutter test test/services/launch/session_launch_pipeline_stable_task_id_test.dart
```

Expected: both PASS.

- [ ] **Step 8: Run analyze and the full non-integration suite**

Run:

```bash
cd client && flutter analyze --no-fatal-infos --no-fatal-warnings
cd client && flutter test --exclude-tags integration
```

Expected: analyze reports no fatal errors/warnings; the full suite passes.

- [ ] **Step 9: Commit**

```bash
git add docs/superpowers/specs/2026-08-10-session-tab-title-during-launch-design.md client/lib/pages/home_workspace/workspace/workspace_session_actions.dart client/lib/cubits/chat/session_launch_service.dart client/test/pages/home_workspace/workspace/workspace_session_actions_test.dart client/test/services/launch/session_launch_pipeline_stable_task_id_test.dart
git commit -m "feat(chat): title session from landing prompt before connect"
```
