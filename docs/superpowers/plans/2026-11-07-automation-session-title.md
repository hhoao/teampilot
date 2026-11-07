# 定时任务会话标题 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `launchPrompt` 定时任务可以为新建 Session 设置自定义标题；留空时用任务名称自动命名，且永不覆盖已有标题。

**Architecture:** `Automation.sessionTitle` 随任务持久化；dispatcher 解析出标题后同时写入创建请求的 `emptyDisplayTitleFallback`（团队会话创建即落盘、Tab 立刻可见）并调用注入的 `applySessionTitle`（个人会话落盘，内部复用"display 为空才改名"守卫）。

**Tech Stack:** Flutter / Dart、flutter_bloc、TpForm / shared_ui、ARB l10n、`tool/run_tests.dart` 测试入口。

## Global Constraints

- 自动命名来源固定为 `Automation.name`；自定义 `sessionTitle` 优先；标题为空字符串时视为未设置。
- 只命名 `display` 为空的 Session；已有标题（含用户手动改名、复用会话已有标题）不得覆盖。
- 仅 `AutomationAction.launchPrompt` 生效；`scheduledMessage` / `runCommand` 不显示字段、不重命名、保存时 `sessionTitle` 为 null。
- 禁止直接 `flutter test`；测试一律 `cd client && dart run tool/run_tests.dart <路径>`。
- l10n 只改 `client/lib/l10n/app_en.arb` 与 `app_zh.arb`，然后运行 `cd client && flutter gen-l10n` 生成 `app_localizations*.dart`。
- 诊断日志用 `appLogger.w`，禁止 `print`。
- 重命名失败必须 best-effort：只记日志，不影响 `AutomationRunStatus.completed`。
- 提交步骤仅在用户明确授权提交时执行；未授权时跳过 commit，改动留在工作区。

---

### Task 1: Automation 模型新增 `sessionTitle`

**Files:**
- Modify: `client/lib/models/automation.dart`
- Test: `client/test/models/automation_test.dart`

**Interfaces:**
- Consumes: 现有 `Automation` 构造器 / `copyWith` / `toJson` / `fromJson`。
- Produces: `Automation.sessionTitle`（`String?`）、`Automation.copyWith(sessionTitle:, clearSessionTitle:)`；JSON 字段 `sessionTitle`（仅 launchPrompt 且非空时写出）。

- [ ] **Step 1: Write the failing tests**

在 `client/test/models/automation_test.dart` 的 `main()` 内追加：

```dart
  test('launchPrompt round-trips sessionTitle and clears it', () {
    final a = Automation(
      id: 'launch-title',
      name: 'Daily digest',
      action: AutomationAction.launchPrompt,
      workspaceId: 'ws1',
      isPersonal: true,
      presetId: 'preset-1',
      message: 'summarize inbox',
      sessionTitle: 'Inbox digest',
      preset: AutomationSchedulePreset.daily,
      hourMinute: '09:00',
      timezone: 'UTC',
      dtstartMs: 1,
      createdAtMs: 1,
      updatedAtMs: 1,
    );

    final back = Automation.fromJson(a.toJson());
    expect(back.sessionTitle, 'Inbox digest');
    expect(back, a);

    final cleared = back.copyWith(clearSessionTitle: true);
    expect(cleared.sessionTitle, isNull);
  });

  test('non-launchPrompt does not persist sessionTitle', () {
    final a = Automation(
      id: 'msg-title',
      name: 'Reset',
      action: AutomationAction.scheduledMessage,
      workspaceId: 'ws1',
      sessionId: 's1',
      message: '/clear',
      sessionTitle: 'ignored',
      preset: AutomationSchedulePreset.hourly,
      minute: 0,
      hourMinute: '09:00',
      timezone: 'UTC',
      dtstartMs: 1,
      enabled: true,
      createdAtMs: 1,
      updatedAtMs: 2,
    );

    expect(a.toJson().containsKey('sessionTitle'), isFalse);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/models/automation_test.dart`
Expected: FAIL — `Automation` 没有 `sessionTitle` 具名参数（编译错误）。

- [ ] **Step 3: Add the field and plumbing**

`client/lib/models/automation.dart`：

1. 构造器在 `required this.name,` 后加：

```dart
    this.sessionTitle,
```

2. 在 `final String name;` 后加：

```dart
  /// Optional display title for sessions created by this launchPrompt.
  ///
  /// Empty/null means "use [name]".
  final String? sessionTitle;
```

3. `fromJson` 在 `name:` 行后加：

```dart
      sessionTitle: json['sessionTitle'] as String?,
```

4. `copyWith` 参数在 `String? name,` 后加：

```dart
    String? sessionTitle,
    bool clearSessionTitle = false,
```

5. `copyWith` 返回体在 `name: name ?? this.name,` 后加：

```dart
      sessionTitle: clearSessionTitle
          ? null
          : (sessionTitle ?? this.sessionTitle),
```

6. `toJson` 的 `if (isLaunchPrompt) ...{` 块内，在 `if (reuseSession)` 前加：

```dart
        if (sessionTitle != null && sessionTitle!.isNotEmpty)
          'sessionTitle': sessionTitle,
```

7. `operator ==` 在 `name == other.name &&` 后加：

```dart
            sessionTitle == other.sessionTitle &&
```

8. `hashCode` 的 `Object.hashAll` 列表中在 `name,` 后加：

```dart
    sessionTitle,
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/models/automation_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Commit (only if authorized)**

```bash
git add client/lib/models/automation.dart client/test/models/automation_test.dart
git commit -m "feat(automation): add optional session title"
```

---

### Task 2: 重命名通道 `applySessionTitle`

**Files:**
- Modify: `client/lib/services/chat/launch/session/session_prompt_metadata_sync.dart`
- Modify: `client/lib/services/chat/launch/session_launch_service.dart`
- Modify: `client/lib/cubits/chat_cubit.dart`
- Test: `client/test/services/chat/launch/session_prompt_metadata_sync_test.dart`

**Interfaces:**
- Consumes: `SessionLaunchHost.renameSession(SessionRepository, String, String)`、`ChatDataSnapshot.sessions`、`AppSession.display`。
- Produces:
  - `SessionPromptMetadataSync.applySessionTitle(String sessionId, String title) → Future<void>`
  - `SessionLaunchService.applySessionTitle(String sessionId, String title) → Future<void>`
  - `ChatCubit.applySessionTitle(String sessionId, String title) → Future<void>`

- [ ] **Step 1: Write the failing tests**

在 `client/test/services/chat/launch/session_prompt_metadata_sync_test.dart` 的 `main()` 内追加：

```dart
  test('applySessionTitle renames an untitled session', () async {
    await sync.applySessionTitle('sess-1', '  Inbox digest  ');

    expect(host.renames, [('sess-1', 'Inbox digest')]);
  });

  test('applySessionTitle skips an already titled session', () async {
    host.state = ChatState(sessions: [session(display: 'Manual title')]);

    await sync.applySessionTitle('sess-1', 'Inbox digest');

    expect(host.renames, isEmpty);
  });

  test('applySessionTitle ignores blank titles', () async {
    await sync.applySessionTitle('sess-1', '   ');

    expect(host.renames, isEmpty);
  });

  test('applySessionTitle skips an unknown session', () async {
    await sync.applySessionTitle('missing', 'Inbox digest');

    expect(host.renames, isEmpty);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/session_prompt_metadata_sync_test.dart`
Expected: FAIL — `applySessionTitle` 未定义（编译错误）。

- [ ] **Step 3: Implement the rename seam**

`client/lib/services/chat/launch/session/session_prompt_metadata_sync.dart`：

1. 在 `applyFirstPromptTitle` 之后新增：

```dart
  /// Renames [sessionId] to [title] only when it has no display title yet.
  ///
  /// Manual renames, reused sessions that already carry a title, and
  /// builder sessions with a persisted title are left untouched.
  Future<void> applySessionTitle(String sessionId, String title) async {
    if (sessionId.startsWith('local-')) return;
    if (_host.isClosed) return;
    final repo = _host.sessionRepository;
    if (repo == null) return;
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    AppSession? session;
    for (final s in _state().sessions) {
      if (s.sessionId == sessionId) {
        session = s;
        break;
      }
    }
    if (session == null || session.display.trim().isNotEmpty) return;
    await _host.renameSession(repo, sessionId, trimmed);
  }
```

2. `applyFirstPromptTitle` 简化为（repo 空检查下沉到 `applySessionTitle`）：

```dart
  Future<void> applyFirstPromptTitle(
    String sessionId,
    String firstPrompt, {
    bool allowTeamGeneration = false,
  }) async {
    if (sessionId.startsWith('local-')) return;
    await _maybeAutoRenameFromFirstPrompt(
      sessionId,
      firstPrompt,
      allowTeamGeneration: allowTeamGeneration,
    );
  }
```

3. 将 `_maybeAutoRenameFromFirstPrompt` 改为以下完整实现（去掉 `repo` 参数，复用 `applySessionTitle`）：

```dart
  Future<void> _maybeAutoRenameFromFirstPrompt(
    String sessionId,
    String firstPrompt, {
    bool allowTeamGeneration = false,
  }) async {
    if (_host.isClosed) return;
    AppSession? session;
    for (final s in _state().sessions) {
      if (s.sessionId == sessionId) {
        session = s;
        break;
      }
    }
    if (session == null) return;
    // Builder kickoff is an app-owned envelope, not an operator title source.
    if (session.purpose == SessionPurpose.teamGeneration &&
        !allowTeamGeneration) {
      return;
    }
    final title = deriveSessionTitleFromFirstPrompt(firstPrompt);
    if (title.isEmpty) return;
    await applySessionTitle(sessionId, title);
  }
```

`client/lib/services/chat/launch/session_launch_service.dart`，在 `applyFirstPromptTitle` 之后加：

```dart
  /// Automation / explicit path: name an untitled session.
  Future<void> applySessionTitle(String sessionId, String title) =>
      _promptMetadata.applySessionTitle(sessionId, title);
```

`client/lib/cubits/chat_cubit.dart`，在 `applyFirstPromptTitle` 之后加：

```dart
  /// Automation / explicit path: name an untitled session.
  Future<void> applySessionTitle(String sessionId, String title) =>
      _launchService.applySessionTitle(sessionId, title);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/chat/launch/session_prompt_metadata_sync_test.dart`
Expected: `All tests passed!`（原有 `applyFirstPromptTitle` 测试也应继续通过）

- [ ] **Step 5: Commit (only if authorized)**

```bash
git add client/lib/services/chat/launch/session/session_prompt_metadata_sync.dart \
  client/lib/services/chat/launch/session_launch_service.dart \
  client/lib/cubits/chat_cubit.dart \
  client/test/services/chat/launch/session_prompt_metadata_sync_test.dart
git commit -m "feat(chat): add explicit untitled-session rename seam"
```

---

### Task 3: Dispatcher 解析标题 + 创建请求 + 注入

**Files:**
- Modify: `client/lib/services/automation/automation_dispatcher.dart`
- Modify: `client/lib/app/app_shell.dart`
- Test: `client/test/services/automation/automation_dispatcher_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `Automation.sessionTitle`、Task 2 的 `ChatCubit.applySessionTitle`。
- Produces:
  - `AutomationDispatcher({..., Future<void> Function(String sessionId, String title)? applySessionTitle})`
  - `String _resolvedSessionTitle(Automation automation)`（内部）
  - `Future<void> _applyLaunchTitle(Automation automation, AppSession session)`（内部）
  - 两种 `SessionCreateRequest` 均带 `emptyDisplayTitleFallback: _resolvedSessionTitle(automation)`。

- [ ] **Step 1: Write the failing tests**

在 `client/test/services/automation/automation_dispatcher_test.dart` 的 `main()` 外、现有 helper 之后加：

```dart
Automation _launchTitleAutomation({
  String name = 'Daily digest',
  String? sessionTitle,
  bool isPersonal = true,
  String? teamId,
}) {
  return Automation(
    id: 'launch-title',
    name: name,
    action: AutomationAction.launchPrompt,
    workspaceId: 'ws1',
    isPersonal: isPersonal,
    presetId: isPersonal ? 'preset-1' : null,
    teamId: isPersonal ? null : teamId,
    message: 'summarize inbox',
    sessionTitle: sessionTitle,
    preset: AutomationSchedulePreset.daily,
    hourMinute: '09:00',
    timezone: 'UTC',
    dtstartMs: 1,
    enabled: true,
    nextRunAtMs: 1,
    createdAtMs: 1,
    updatedAtMs: 1,
  );
}
```

在 `main()` 内追加：

```dart
  test('launchPrompt names a new session from the automation name', () async {
    final layout = WorkspaceLayout(
      teampilotRoot: testHomeStorage.paths.basePath,
      fs: testHomeStorage.fs,
    );
    final repo = AutomationRepository(fs: testHomeStorage.fs, layout: layout);
    final workspace = Workspace(workspaceId: 'ws1', createdAt: 1);
    SessionCreateRequest? captured;
    final renames = <(String, String)>[];

    final dispatcher = AutomationDispatcher(
      repository: repo,
      scheduleCalculator: AutomationScheduleCalculator(),
      sessionRepository: _FakeSessionRepository(const []),
      busGateway: _RecordingBusGateway(),
      requestOpenSession: (_) async => SessionOpenStatus.opened,
      requestCreateAndOpenSession: (request) async {
        captured = request;
        return SessionOpenStatus.opened;
      },
      workspaceById: (_) => workspace,
      teamById: (_) => null,
      sessionById: (sessionId, workspaceId) => AppSession(
        sessionId: sessionId,
        workspaceId: workspaceId,
        createdAt: 1,
      ),
      applySessionTitle: (sessionId, title) async {
        renames.add((sessionId, title));
      },
      nowMs: () => 100,
    );

    await dispatcher.dispatch(_launchTitleAutomation());

    expect(captured!.emptyDisplayTitleFallback, 'Daily digest');
    expect(renames, [(captured!.fixedSessionId!, 'Daily digest')]);
  });

  test('launchPrompt prefers the custom session title', () async {
    final layout = WorkspaceLayout(
      teampilotRoot: testHomeStorage.paths.basePath,
      fs: testHomeStorage.fs,
    );
    final repo = AutomationRepository(fs: testHomeStorage.fs, layout: layout);
    final workspace = Workspace(workspaceId: 'ws1', createdAt: 1);
    SessionCreateRequest? captured;
    final renames = <(String, String)>[];

    final dispatcher = AutomationDispatcher(
      repository: repo,
      scheduleCalculator: AutomationScheduleCalculator(),
      sessionRepository: _FakeSessionRepository(const []),
      busGateway: _RecordingBusGateway(),
      requestOpenSession: (_) async => SessionOpenStatus.opened,
      requestCreateAndOpenSession: (request) async {
        captured = request;
        return SessionOpenStatus.opened;
      },
      workspaceById: (_) => workspace,
      teamById: (_) => null,
      sessionById: (sessionId, workspaceId) => AppSession(
        sessionId: sessionId,
        workspaceId: workspaceId,
        createdAt: 1,
      ),
      applySessionTitle: (sessionId, title) async {
        renames.add((sessionId, title));
      },
      nowMs: () => 100,
    );

    await dispatcher.dispatch(
      _launchTitleAutomation(sessionTitle: '  Inbox digest  '),
    );

    expect(captured!.emptyDisplayTitleFallback, 'Inbox digest');
    expect(renames, [(captured!.fixedSessionId!, 'Inbox digest')]);
  });

  test('team launchPrompt passes the resolved title to session create', () async {
    final layout = WorkspaceLayout(
      teampilotRoot: testHomeStorage.paths.basePath,
      fs: testHomeStorage.fs,
    );
    final repo = AutomationRepository(fs: testHomeStorage.fs, layout: layout);
    final workspace = Workspace(workspaceId: 'ws1', createdAt: 1);
    final team = TeamProfile(
      id: 'team-1',
      name: 'Team',
      members: const [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
    );
    SessionCreateRequest? captured;

    final dispatcher = AutomationDispatcher(
      repository: repo,
      scheduleCalculator: AutomationScheduleCalculator(),
      sessionRepository: _FakeSessionRepository(const []),
      busGateway: _RecordingBusGateway(),
      requestOpenSession: (_) async => SessionOpenStatus.opened,
      requestCreateAndOpenSession: (request) async {
        captured = request;
        return SessionOpenStatus.opened;
      },
      workspaceById: (_) => workspace,
      teamById: (id) => id == 'team-1' ? team : null,
      sessionById: (sessionId, workspaceId) => AppSession(
        sessionId: sessionId,
        workspaceId: workspaceId,
        sessionTeam: 'team-1',
        createdAt: 1,
      ),
      applySessionTitle: (_, __) async {},
      nowMs: () => 100,
    );

    await dispatcher.dispatch(
      _launchTitleAutomation(
        sessionTitle: 'Inbox digest',
        isPersonal: false,
        teamId: 'team-1',
      ),
    );

    expect(captured!.emptyDisplayTitleFallback, 'Inbox digest');
  });

  test('scheduledMessage never applies a session title', () async {
    final layout = WorkspaceLayout(
      teampilotRoot: testHomeStorage.paths.basePath,
      fs: testHomeStorage.fs,
    );
    final repo = AutomationRepository(fs: testHomeStorage.fs, layout: layout);
    final session = AppSession(
      sessionId: 'sess-1',
      workspaceId: 'ws1',
      sessionTeam: 'team-1',
      createdAt: 1,
    );
    final workspace = Workspace(workspaceId: 'ws1', createdAt: 1);
    final team = TeamProfile(
      id: 'team-1',
      name: 'Team',
      members: const [TeamMemberConfig(id: 'team-lead', name: 'Lead')],
    );
    final renames = <(String, String)>[];

    final dispatcher = AutomationDispatcher(
      repository: repo,
      scheduleCalculator: AutomationScheduleCalculator(),
      sessionRepository: _FakeSessionRepository([session]),
      busGateway: _RecordingBusGateway(),
      requestOpenSession: (_) async => SessionOpenStatus.opened,
      requestCreateAndOpenSession: (_) async => SessionOpenStatus.opened,
      workspaceById: (_) => workspace,
      teamById: (id) => id == 'team-1' ? team : null,
      applySessionTitle: (sessionId, title) async {
        renames.add((sessionId, title));
      },
      nowMs: () => 100,
    );

    await dispatcher.dispatch(
      _scheduledMessageAutomation(sessionId: 'sess-1'),
    );

    expect(renames, isEmpty);
  });

  test('session title failure does not fail the run', () async {
    final layout = WorkspaceLayout(
      teampilotRoot: testHomeStorage.paths.basePath,
      fs: testHomeStorage.fs,
    );
    final repo = AutomationRepository(fs: testHomeStorage.fs, layout: layout);
    final workspace = Workspace(workspaceId: 'ws1', createdAt: 1);

    final dispatcher = AutomationDispatcher(
      repository: repo,
      scheduleCalculator: AutomationScheduleCalculator(),
      sessionRepository: _FakeSessionRepository(const []),
      busGateway: _RecordingBusGateway(),
      requestOpenSession: (_) async => SessionOpenStatus.opened,
      requestCreateAndOpenSession: (_) async => SessionOpenStatus.opened,
      workspaceById: (_) => workspace,
      teamById: (_) => null,
      sessionById: (sessionId, workspaceId) => AppSession(
        sessionId: sessionId,
        workspaceId: workspaceId,
        createdAt: 1,
      ),
      applySessionTitle: (_, __) async => throw StateError('rename failed'),
      nowMs: () => 100,
    );

    final result = await dispatcher.dispatch(_launchTitleAutomation());

    expect(result.run.status, AutomationRunStatus.completed);
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_dispatcher_test.dart`
Expected: FAIL — `AutomationDispatcher` 没有 `applySessionTitle` 具名参数（编译错误）。

- [ ] **Step 3: Implement dispatcher changes**

`client/lib/services/automation/automation_dispatcher.dart`：

1. 构造器参数在 `AutomationSessionLookup? sessionById,` 后加：

```dart
    Future<void> Function(String sessionId, String title)? applySessionTitle,
```

2. 初始化列表在 `_sessionById = sessionById,` 后加：

```dart
       _applySessionTitle = applySessionTitle,
```

3. 字段在 `final AutomationSessionLookup? _sessionById;` 后加：

```dart
  final Future<void> Function(String sessionId, String title)?
  _applySessionTitle;
```

4. 在 `_inFlight` 方法之后加：

```dart
  String _resolvedSessionTitle(Automation automation) {
    final custom = automation.sessionTitle?.trim() ?? '';
    return custom.isNotEmpty ? custom : automation.name.trim();
  }

  /// Best-effort rename of a launchPrompt session that has no title yet.
  Future<void> _applyLaunchTitle(
    Automation automation,
    AppSession session,
  ) async {
    if (!automation.isLaunchPrompt) return;
    final title = _resolvedSessionTitle(automation);
    if (title.isEmpty) return;
    final apply = _applySessionTitle;
    if (apply == null) return;
    try {
      await apply(session.sessionId, title);
    } on Object catch (error, stackTrace) {
      appLogger.w(
        '[automations] session title failed ${automation.id} '
        'session=${session.sessionId}: $error',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
```

5. `_dispatchMessage` 中，`if (session == null) { ... }` 块结束后、`final memberId = ...` 前加：

```dart
    await _applyLaunchTitle(automation, session);
```

6. `_createSessionForLaunchPrompt` 开头 `final workspace = ...; if (workspace == null) return null;` 之后加：

```dart
    final resolvedTitle = _resolvedSessionTitle(automation);
```

7. 个人分支 `SessionCreateRequest(...)` 加参数（放在 `workingDirectory` 后）：

```dart
          emptyDisplayTitleFallback: resolvedTitle,
```

8. 团队分支 `SessionCreateRequest(...)` 同样在 `workingDirectory` 后加：

```dart
          emptyDisplayTitleFallback: resolvedTitle,
```

`client/lib/app/app_shell.dart` 的 `AutomationDispatcher(...)` 构造中，`sessionById:` 参数后加：

```dart
      applySessionTitle: chatCubit.applySessionTitle,
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/services/automation/automation_dispatcher_test.dart`
Expected: `All tests passed!`

- [ ] **Step 5: Commit (only if authorized)**

```bash
git add client/lib/services/automation/automation_dispatcher.dart \
  client/lib/app/app_shell.dart \
  client/test/services/automation/automation_dispatcher_test.dart
git commit -m "feat(automation): name launched sessions from task title or name"
```

---

### Task 4: 编辑器字段 + l10n

**Files:**
- Modify: `client/lib/pages/automations/automation_editor_form_body.dart`
- Modify: `client/lib/pages/automations/automation_editor_dialog.dart`
- Modify: `client/lib/l10n/app_en.arb`
- Modify: `client/lib/l10n/app_zh.arb`
- Generated (via gen-l10n): `client/lib/l10n/app_localizations.dart`、`app_localizations_en.dart`、`app_localizations_zh.dart`
- Test: `client/test/pages/automations/automation_editor_dialog_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `Automation.sessionTitle`。
- Produces: 表单字段 id `sessionTitle`、TextField key `automationSessionTitleField`；l10n `automationsSessionTitle` / `automationsSessionTitleHint`。

- [ ] **Step 1: Add l10n keys**

`client/lib/l10n/app_en.arb`，在 `"automationsMessage": "Message",` 后加：

```json
  "automationsSessionTitle": "Session title",
  "automationsSessionTitleHint": "Leave empty to use the automation name.",
```

`client/lib/l10n/app_zh.arb`，在 `"automationsMessage": "消息",` 后加：

```json
  "automationsSessionTitle": "会话标题",
  "automationsSessionTitleHint": "留空则使用定时任务名称。",
```

运行：`cd client && flutter gen-l10n`
Expected: 无错误，`client/lib/l10n/app_localizations*.dart` 出现两个新 getter。

- [ ] **Step 2: Write the failing widget tests**

`client/test/pages/automations/automation_editor_dialog_test.dart`：

1. 在 `scheduled message editor shows core fields only` 的断言区加：

```dart
    expect(find.text(l10n.automationsSessionTitle), findsNothing);
```

2. 在 `simple launch prompt shows landing-aligned fields` 的断言区加：

```dart
    expect(find.text(l10n.automationsSessionTitle), findsOneWidget);
    expect(find.text(l10n.automationsSessionTitleHint), findsOneWidget);
```

3. 在 `main()` 内新增保存测试：

```dart
  testWidgets('launch prompt saves the custom session title', (tester) async {
    final setup = testAutomationSetup();
    final chatCubit = _chatCubitWithWorkspace();
    final cliPresetsCubit = _cliPresetsCubitWithPreset();
    addTearDown(setup.cubit.close);
    addTearDown(chatCubit.close);
    addTearDown(cliPresetsCubit.close);

    await tester.pumpWidget(
      RepositoryProvider<HomeStorage>.value(
        value: testHomeStorage,
        child: _host(
          cubit: setup.cubit,
          chatCubit: chatCubit,
          cliPresetsCubit: cliPresetsCubit,
          child: AutomationEditorDialog(
            initial: sampleAutomation(id: 'edit-title', workspaceId: 'ws1'),
            workspaceId: 'ws1',
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final l10n = AppLocalizations.of(
      tester.element(find.byType(AutomationEditorDialog)),
    );

    await tester.enterText(
      find.byKey(const Key('automationSessionTitleField')),
      '  Inbox digest  ',
    );
    await tester.tap(find.text(l10n.save));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final persisted = await setup.repo.listForWorkspace('ws1');
    expect(persisted.single.sessionTitle, 'Inbox digest');
  });
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd client && dart run tool/run_tests.dart test/pages/automations/automation_editor_dialog_test.dart`
Expected: FAIL — launchPrompt 断言找不到 `automationsSessionTitle` 文本；保存测试找不到 `automationSessionTitleField`。

- [ ] **Step 4: Implement the form field**

`client/lib/pages/automations/automation_editor_form_body.dart`：

1. 构造器在 `this.messageController,` 后加：

```dart
    this.sessionTitleController,
```

2. 字段在 `final TextEditingController messageController;` 后加：

```dart
  final TextEditingController? sessionTitleController;
```

3. 在 `if (kind != AutomationEditorKind.runCommand) ...[ ... ]` 的 message 块之后、`if (kind == AutomationEditorKind.runCommand) ...[` 之前插入：

```dart
        if (kind == AutomationEditorKind.launchPrompt) ...[
          const SizedBox(height: 12),
          TpFormField<String>(
            id: 'sessionTitle',
            initialValue: sessionTitleController?.text ?? '',
            label: Text(l10n.automationsSessionTitle),
            description: Text(l10n.automationsSessionTitleHint),
            layoutStyle: TpFormFieldLayoutStyle.inline,
            labelWidth: kAutomationEditorFormLabelWidth,
            builder: (state) {
              return TextField(
                key: const Key('automationSessionTitleField'),
                controller: sessionTitleController,
                focusNode: state.focusNode,
                onChanged: state.didChange,
              );
            },
          ),
        ],
```

`client/lib/pages/automations/automation_editor_dialog.dart`：

1. 状态字段在 `late final TextEditingController _messageCtl;` 后加：

```dart
  late final TextEditingController _sessionTitleCtl;
```

2. `initState` 在 `_messageCtl = ...` 后加：

```dart
    _sessionTitleCtl = TextEditingController(
      text: initial?.sessionTitle ?? '',
    );
```

3. `dispose` 在 `_messageCtl.dispose();` 后加：

```dart
    _sessionTitleCtl.dispose();
```

4. `_save` 中 `final message = _messageCtl.text.trim();` 后加：

```dart
    final sessionTitle = _isScheduledMessage || _isRunCommand
        ? null
        : _sessionTitleCtl.text.trim();
```

5. 非 runCommand 分支的 `Automation(...)` 构造中，`message: message,` 后加：

```dart
      sessionTitle: sessionTitle == null || sessionTitle.isEmpty
          ? null
          : sessionTitle,
```

6. `build` 中传给 `AutomationEditorFormBody` 的参数，在 `messageController: _messageCtl,` 后加：

```dart
            sessionTitleController: _sessionTitleCtl,
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd client && dart run tool/run_tests.dart test/pages/automations/automation_editor_dialog_test.dart`
Expected: `All tests passed!`

- [ ] **Step 6: Commit (only if authorized)**

```bash
git add client/lib/pages/automations/automation_editor_form_body.dart \
  client/lib/pages/automations/automation_editor_dialog.dart \
  client/lib/l10n/app_en.arb client/lib/l10n/app_zh.arb \
  client/lib/l10n/app_localizations.dart \
  client/lib/l10n/app_localizations_en.dart \
  client/lib/l10n/app_localizations_zh.dart \
  client/test/pages/automations/automation_editor_dialog_test.dart
git commit -m "feat(automation): add custom session title field"
```

---

### Task 5: 全量验证

**Files:** 无新增改动。

- [ ] **Step 1: Analyze**

Run: `cd client && flutter analyze --no-fatal-infos --no-fatal-warnings`
Expected: `No issues found!`

- [ ] **Step 2: Targeted suites**

Run:

```bash
cd client && dart run tool/run_tests.dart \
  test/models/automation_test.dart \
  test/services/chat/launch/session_prompt_metadata_sync_test.dart \
  test/services/automation/automation_dispatcher_test.dart \
  test/pages/automations/automation_editor_dialog_test.dart
```

Expected: `All tests passed!`

- [ ] **Step 3: Full suite (background, once before claiming done)**

Run: `cd client && dart run tool/run_tests.dart`
Expected: `All tests passed!`；若有与本次无关的既有失败，记录文件名与失败信息并单独报告。

- [ ] **Step 4: Commit (only if authorized, and only if earlier commits were skipped)**

```bash
git status
git add client/lib client/test docs/superpowers
git commit -m "feat(automation): support custom session titles for launch prompts"
```
