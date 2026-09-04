import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_history_cubit.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/plugin_cubit.dart';
import 'package:teampilot/cubits/run_cubit.dart';
import 'package:teampilot/cubits/shortcut_cubit.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/cubits/workspace_landing_context_cubit.dart';
import 'package:teampilot/cubits/workspace_tools_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/landing_launch_context.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/chat/chat_page_shell.dart';
import 'package:teampilot/pages/chat/chat_page_shell_probe.dart';
import 'package:teampilot/repositories/cli_presets_repository.dart';
import 'package:teampilot/repositories/plugin_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry_scope.dart';
import 'package:teampilot/services/file_tree/workspace_file_tree_store.dart';
import 'package:teampilot/services/git/git_repo_store.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/session/ai_history_loader.dart';
import 'package:teampilot/services/storage/app_storage.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/storage/runtime_context_registry.dart';
import 'package:teampilot/services/terminal/terminal_transport_factory.dart';
import 'package:teampilot/services/plugin/plugin_repo_service.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';

import '../support/desktop_app_harness.dart';
import '../support/idle_run_platform.dart';
import '../support/in_memory_filesystem.dart';
import '../support/post_frame_test_harness.dart';

String _executable() => 'flashskyai';

class _SeededAppProviderCubit extends AppProviderCubit {
  _SeededAppProviderCubit() {
    emit(const AppProviderState());
  }
}

ChatPageStructuralBodyProbeState _structuralProbe(WidgetTester tester) {
  return tester.state<ChatPageStructuralBodyProbeState>(
    find.byKey(ChatPageShellKeys.structuralBodyProbe),
  );
}

Widget _chatPageShell({bool wrapCliRegistry = false}) {
  const shell = ChatPageShell(
    cwd: '/tmp/personal-workspace',
    workspaceId: 'personal-test',
    tabScopeId: 'personal-test',
  );
  if (!wrapCliRegistry) return shell;
  return CliToolRegistryScope(
    registry: CliToolRegistry.builtIn(),
    child: shell,
  );
}

/// `SessionChatView` binds a History seat through the pod's HistoryStore when
/// pods own one; the pre-pod fallback reads [AiHistoryCubit] from context. The
/// rebuild tests render a session body (fed into the bar), so the harness must
/// provide the cubit or the first build throws ProviderNotFoundException.
AiHistoryCubit _testAiHistoryCubit() {
  return AiHistoryCubit(
    loader: AiHistoryLoader(
      resolveWorkContext: (launchCtx, {String? memberId}) async {
        final basePath = AppStorage.paths.basePath;
        return RuntimeContext(
          target: RuntimeTarget.local(),
          filesystem: LocalFilesystem(
            pathContext: AppPaths.pathContextForDataRoot(basePath),
          ),
          home: basePath,
          cwd: basePath,
          appDataRoot: basePath,
          paths: AppPaths(basePath),
        );
      },
    ),
  );
}

void _openSessionTab(
  ChatCubit chatCubit,
  WorkbenchCubit workbenchCubit,
  AppSession session,
  String title,
) {
  chatCubit.setActiveWorkspace('personal-test');
  if (!chatCubit.state.sessions.any((s) => s.sessionId == session.sessionId)) {
    chatCubit.ingestWorkspaceSessionSnapshot(
      workspaces: chatCubit.state.workspaces,
      sessions: [...chatCubit.state.sessions, session],
    );
  }
  chatCubit.tabStore.registerSession(
    ChatTab(
      info: ChatTabInfo(id: session.sessionId, title: title, subtitle: ''),
      cliTeamName: session.sessionId,
    ),
  );
  workbenchCubit.openSession('personal-test', session.sessionId);
}

void main() {
  setUp(() {
    setUpTestAppStorage();
  });

  tearDown(() {
    tearDownTestAppStorage();
  });

  testWidgets(
    'structural body does not rebuild when only busySessionIds changes',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final appData = Directory.systemTemp.createTempSync('chat_rebuild_test_');
      addTearDown(() {
        if (appData.existsSync()) appData.deleteSync(recursive: true);
      });

      final teamCubit = LaunchProfileCubit(
        repository: LaunchProfileRepository(rootDir: appData.path),
        sessionRepository: SessionRepository(rootDir: appData.path),
        executableResolver: _executable,
        appDataBasePath: appData.path,
        configProfileService: ConfigProfileService(basePath: appData.path),
      );
      addTearDown(() => teamCubit.close());

      final sessionRepo = SessionRepository(rootDir: appData.path);
      final chatCubit = ChatCubit(
        executableResolver: _executable,
        automationRepository: testAutomationRepository(),
        sessionRepository: sessionRepo,
      );
      addTearDown(() => chatCubit.close());

      final layoutCubit = LayoutCubit();
      addTearDown(() => layoutCubit.close());

      final editorCubit = EditorCubit(fs: LocalFilesystem());
      addTearDown(() => editorCubit.close());

      final workbenchCubit = WorkbenchCubit();
      addTearDown(() => workbenchCubit.close());

      final runCubit = RunCubit(
        platform: IdleRunPlatform(),
        folders: const [WorkspaceFolder(path: '/tmp/personal-workspace')],
      );
      addTearDown(() => runCubit.close());

      final skillCubit = testSkillCubit();
      addTearDown(() => skillCubit.close());

      final pluginRepo = PluginRepository();
      final pluginCubit = PluginCubit(
        repository: pluginRepo,
        installService: pluginRepo.install,
        repoService: PluginRepoService(),
      );
      addTearDown(() => pluginCubit.close());

      final worktreeCubit = WorktreeCubit();
      addTearDown(() => worktreeCubit.close());

      final presenceCubit = MemberPresenceCubit();
      chatCubit.bindPresenceCubit(presenceCubit);
      addTearDown(() => presenceCubit.close());

      final aiHistoryCubit = _testAiHistoryCubit();
      addTearDown(() => aiHistoryCubit.close());

      final cliPresetsCubit = CliPresetsCubit(
        repository: CliPresetsRepository(
          fs: InMemoryFilesystem(),
          presetsPath: '/cli-presets.json',
        ),
      );
      cliPresetsCubit.emit(
        const CliPresetsState(status: CliPresetsLoadStatus.ready),
      );
      addTearDown(() => cliPresetsCubit.close());

      final sessionPreferencesCubit =
          (await tester.runAsync(testSessionPreferencesCubit))!;
      addTearDown(() => sessionPreferencesCubit.close());

      chatCubit.ingestWorkspaceSessionSnapshot(
        workspaces: [
          Workspace(
            workspaceId: 'personal-test',
            folders: [WorkspaceFolder(path: '/tmp/personal-workspace')],
            createdAt: 1,
          ),
        ],
        sessions: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<GitRepoStore>(create: (_) => GitRepoStore()),
              RepositoryProvider<WorkspaceFileTreeStore>(
                create: (_) => WorkspaceFileTreeStore(),
              ),
              RepositoryProvider<SessionRepository>.value(value: sessionRepo),
              RepositoryProvider<WorkspaceTerminalRegistry>(
                create: (_) => WorkspaceTerminalRegistry(),
              ),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: teamCubit),
                BlocProvider.value(value: chatCubit),
                BlocProvider<AppProviderCubit>(
                  create: (_) => _SeededAppProviderCubit(),
                ),
                BlocProvider.value(value: layoutCubit),
                BlocProvider.value(value: editorCubit),
                BlocProvider.value(value: workbenchCubit),
                BlocProvider.value(value: runCubit),
                BlocProvider.value(value: skillCubit),
                BlocProvider.value(value: pluginCubit),
                BlocProvider.value(value: worktreeCubit),
                BlocProvider.value(value: presenceCubit),
                BlocProvider(
                  create: (_) => AgentAttentionCubit(pruneInterval: null),
                ),
                BlocProvider.value(value: aiHistoryCubit),
                BlocProvider.value(value: WorkspaceToolsCubit()),
                BlocProvider.value(value: cliPresetsCubit),
                BlocProvider.value(value: sessionPreferencesCubit),
                BlocProvider(create: (_) => ShortcutCubit()),
                BlocProvider(
                  create: (_) => WorkspaceLandingContextCubit(
                    workspaceId: 'personal-test',
                    initial: const LandingLaunchContext(isPersonal: true),
                  ),
                ),
              ],
              child: WorkspaceToolsScope(
                state: const WorkspaceToolsScopeState(resolving: false),
                child: Scaffold(
                  body: _chatPageShell(),
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final countAfterSettle = _structuralProbe(tester).buildCount;

      chatCubit.updateWorkingSessionsForTest({'sess-1'});
      await tester.pump();

      expect(_structuralProbe(tester).buildCount, countAfterSettle);
    },
  );

  testWidgets(
    'structural body does not rebuild when only session display/title changes',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final appData = Directory.systemTemp.createTempSync('chat_rebuild_test_');
      addTearDown(() {
        if (appData.existsSync()) appData.deleteSync(recursive: true);
      });

      final teamCubit = LaunchProfileCubit(
        repository: LaunchProfileRepository(rootDir: appData.path),
        sessionRepository: SessionRepository(rootDir: appData.path),
        executableResolver: _executable,
        appDataBasePath: appData.path,
        configProfileService: ConfigProfileService(basePath: appData.path),
      );
      addTearDown(() => teamCubit.close());

      final sessionRepo = SessionRepository(rootDir: appData.path);
      final chatCubit = ChatCubit(
        executableResolver: _executable,
        automationRepository: testAutomationRepository(),
        sessionRepository: sessionRepo,
      );
      addTearDown(() => chatCubit.close());

      final layoutCubit = LayoutCubit();
      addTearDown(() => layoutCubit.close());

      final editorCubit = EditorCubit(fs: LocalFilesystem());
      addTearDown(() => editorCubit.close());

      final workbenchCubit = WorkbenchCubit();
      addTearDown(() => workbenchCubit.close());

      final runCubit = RunCubit(
        platform: IdleRunPlatform(),
        folders: const [WorkspaceFolder(path: '/tmp/personal-workspace')],
      );
      addTearDown(() => runCubit.close());

      final skillCubit = testSkillCubit();
      addTearDown(() => skillCubit.close());

      final pluginRepo = PluginRepository();
      final pluginCubit = PluginCubit(
        repository: pluginRepo,
        installService: pluginRepo.install,
        repoService: PluginRepoService(),
      );
      addTearDown(() => pluginCubit.close());

      final worktreeCubit = WorktreeCubit();
      addTearDown(() => worktreeCubit.close());

      final presenceCubit = MemberPresenceCubit();
      chatCubit.bindPresenceCubit(presenceCubit);
      addTearDown(() => presenceCubit.close());

      final aiHistoryCubit = _testAiHistoryCubit();
      addTearDown(() => aiHistoryCubit.close());

      final cliPresetsCubit = CliPresetsCubit(
        repository: CliPresetsRepository(
          fs: InMemoryFilesystem(),
          presetsPath: '/cli-presets.json',
        ),
      );
      cliPresetsCubit.emit(
        const CliPresetsState(status: CliPresetsLoadStatus.ready),
      );
      addTearDown(() => cliPresetsCubit.close());

      final sessionPreferencesCubit =
          (await tester.runAsync(testSessionPreferencesCubit))!;
      addTearDown(() => sessionPreferencesCubit.close());

      chatCubit.ingestWorkspaceSessionSnapshot(
        workspaces: [
          Workspace(
            workspaceId: 'personal-test',
            folders: [WorkspaceFolder(path: '/tmp/personal-workspace')],
            createdAt: 1,
          ),
        ],
        sessions: const [],
      );

      // The session tab strip is hidden by default (90f08f6d3); this test
      // asserts on tab titles, so opt the layout back in.
      await layoutCubit.setSessionTabBarVisible(true);

      _openSessionTab(
        chatCubit,
        workbenchCubit,
        AppSession(
          sessionId: 'sess-1',
          workspaceId: 'personal-test',
          folders: const [WorkspaceFolder(path: '/tmp/personal-workspace')],
          display: 'Old title',
          createdAt: 1,
        ),
        'Old title',
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<GitRepoStore>(create: (_) => GitRepoStore()),
              RepositoryProvider<WorkspaceFileTreeStore>(
                create: (_) => WorkspaceFileTreeStore(),
              ),
              RepositoryProvider<SessionRepository>.value(value: sessionRepo),
              RepositoryProvider<WorkspaceTerminalRegistry>(
                create: (_) => WorkspaceTerminalRegistry(),
              ),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: teamCubit),
                BlocProvider.value(value: chatCubit),
                BlocProvider<AppProviderCubit>(
                  create: (_) => _SeededAppProviderCubit(),
                ),
                BlocProvider.value(value: layoutCubit),
                BlocProvider.value(value: editorCubit),
                BlocProvider.value(value: workbenchCubit),
                BlocProvider.value(value: runCubit),
                BlocProvider.value(value: skillCubit),
                BlocProvider.value(value: pluginCubit),
                BlocProvider.value(value: worktreeCubit),
                BlocProvider.value(value: presenceCubit),
                BlocProvider(
                  create: (_) => AgentAttentionCubit(pruneInterval: null),
                ),
                BlocProvider.value(value: aiHistoryCubit),
                BlocProvider.value(value: WorkspaceToolsCubit()),
                BlocProvider.value(value: cliPresetsCubit),
                BlocProvider.value(value: sessionPreferencesCubit),
                BlocProvider(create: (_) => ShortcutCubit()),
                BlocProvider(
                  create: (_) => WorkspaceLandingContextCubit(
                    workspaceId: 'personal-test',
                    initial: const LandingLaunchContext(isPersonal: true),
                  ),
                ),
              ],
              child: WorkspaceToolsScope(
                state: const WorkspaceToolsScopeState(resolving: false),
                child: Scaffold(
                  body: _chatPageShell(wrapCliRegistry: true),
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Verify initial session is visible.
      expect(find.text('Old title'), findsOneWidget);

      final session = chatCubit.state.sessions.first;
      chatCubit.emit(
        chatCubit.state.copyWith(
          sessions: [session.copyWith(display: 'Renamed title')],
        ),
      );
      await tester.pump();

      // Display rename should NOT cause the structural body to lose the probe
      // (the probe key must still be in the tree).
      expect(find.byKey(chatPageStructuralBodyProbeKey), findsOneWidget);
    },
  );

  testWidgets('structural body rebuilds when open tab ids change', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final appData = Directory.systemTemp.createTempSync('chat_rebuild_test_');
    addTearDown(() {
      if (appData.existsSync()) appData.deleteSync(recursive: true);
    });

    final teamCubit = LaunchProfileCubit(
      repository: LaunchProfileRepository(rootDir: appData.path),
      sessionRepository: SessionRepository(rootDir: appData.path),
      executableResolver: _executable,
      appDataBasePath: appData.path,
      configProfileService: ConfigProfileService(basePath: appData.path),
    );
    addTearDown(() => teamCubit.close());

    final sessionRepo = SessionRepository(rootDir: appData.path);
    final chatCubit = ChatCubit(
      executableResolver: _executable,
      automationRepository: testAutomationRepository(),
      sessionRepository: sessionRepo,
    );
    addTearDown(() => chatCubit.close());

    final layoutCubit = LayoutCubit();
    addTearDown(() => layoutCubit.close());

    final editorCubit = EditorCubit(fs: LocalFilesystem());
    addTearDown(() => editorCubit.close());

    final workbenchCubit = WorkbenchCubit();
    addTearDown(() => workbenchCubit.close());

    final runCubit = RunCubit(
      platform: IdleRunPlatform(),
      folders: const [WorkspaceFolder(path: '/tmp/personal-workspace')],
    );
    addTearDown(() => runCubit.close());

    final skillCubit = testSkillCubit();
    addTearDown(() => skillCubit.close());

    final pluginRepo = PluginRepository();
    final pluginCubit = PluginCubit(
      repository: pluginRepo,
      installService: pluginRepo.install,
      repoService: PluginRepoService(),
    );
    addTearDown(() => pluginCubit.close());

    final worktreeCubit = WorktreeCubit();
    addTearDown(() => worktreeCubit.close());

    final presenceCubit = MemberPresenceCubit();
    chatCubit.bindPresenceCubit(presenceCubit);
    addTearDown(() => presenceCubit.close());

    final aiHistoryCubit = _testAiHistoryCubit();
    addTearDown(() => aiHistoryCubit.close());

    final cliPresetsCubit = CliPresetsCubit(
      repository: CliPresetsRepository(
        fs: InMemoryFilesystem(),
        presetsPath: '/cli-presets.json',
      ),
    );
    cliPresetsCubit.emit(
      const CliPresetsState(status: CliPresetsLoadStatus.ready),
    );
    addTearDown(() => cliPresetsCubit.close());

    final sessionPreferencesCubit =
        (await tester.runAsync(testSessionPreferencesCubit))!;
    addTearDown(() => sessionPreferencesCubit.close());

    chatCubit.ingestWorkspaceSessionSnapshot(
      workspaces: [
        Workspace(
          workspaceId: 'personal-test',
          folders: [WorkspaceFolder(path: '/tmp/personal-workspace')],
          createdAt: 1,
        ),
      ],
      sessions: const [],
    );

    _openSessionTab(
      chatCubit,
      workbenchCubit,
      AppSession(
        sessionId: 'sess-1',
        workspaceId: 'personal-test',
        folders: const [WorkspaceFolder(path: '/tmp/personal-workspace')],
        display: 'Session one',
        createdAt: 1,
      ),
      'Session one',
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<GitRepoStore>(create: (_) => GitRepoStore()),
            RepositoryProvider<WorkspaceFileTreeStore>(
              create: (_) => WorkspaceFileTreeStore(),
            ),
            RepositoryProvider<SessionRepository>.value(value: sessionRepo),
            RepositoryProvider<WorkspaceTerminalRegistry>(
              create: (_) => WorkspaceTerminalRegistry(),
            ),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: teamCubit),
              BlocProvider.value(value: chatCubit),
              BlocProvider<AppProviderCubit>(
                create: (_) => _SeededAppProviderCubit(),
              ),
              BlocProvider.value(value: layoutCubit),
              BlocProvider.value(value: editorCubit),
              BlocProvider.value(value: workbenchCubit),
              BlocProvider.value(value: runCubit),
              BlocProvider.value(value: skillCubit),
              BlocProvider.value(value: pluginCubit),
              BlocProvider.value(value: worktreeCubit),
              BlocProvider.value(value: presenceCubit),
              BlocProvider(
                create: (_) => AgentAttentionCubit(pruneInterval: null),
              ),
              BlocProvider.value(value: aiHistoryCubit),
              BlocProvider.value(value: WorkspaceToolsCubit()),
              BlocProvider.value(value: cliPresetsCubit),
              BlocProvider.value(value: sessionPreferencesCubit),
              BlocProvider(create: (_) => ShortcutCubit()),
              BlocProvider(
                create: (_) => WorkspaceLandingContextCubit(
                  workspaceId: 'personal-test',
                  initial: const LandingLaunchContext(isPersonal: true),
                ),
              ),
            ],
            child: WorkspaceToolsScope(
              state: const WorkspaceToolsScopeState(resolving: false),
              child: Scaffold(
                body: _chatPageShell(wrapCliRegistry: true),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    _openSessionTab(
      chatCubit,
      workbenchCubit,
      AppSession(
        sessionId: 'sess-2',
        workspaceId: 'personal-test',
        folders: const [WorkspaceFolder(path: '/tmp/personal-workspace')],
        display: 'Session two',
        createdAt: 2,
      ),
      'Session two',
    );
    await tester.pump();
    // The bar-driven structural rebuild propagates over a couple of frames
    // (the workbench emit rebuilds the inner shell, then the body beneath it),
    // so settle with a short frame budget instead of a single pump.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // Verify the structural body is still intact after opening a second tab.
    expect(find.byKey(chatPageStructuralBodyProbeKey), findsOneWidget);
  });

  testWidgets(
    'structural body does not rebuild when only lastOpenedWorkspaceId changes',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final appData = Directory.systemTemp.createTempSync('chat_rebuild_test_');
      addTearDown(() {
        if (appData.existsSync()) appData.deleteSync(recursive: true);
      });

      final teamCubit = LaunchProfileCubit(
        repository: LaunchProfileRepository(rootDir: appData.path),
        sessionRepository: SessionRepository(rootDir: appData.path),
        executableResolver: _executable,
        appDataBasePath: appData.path,
        configProfileService: ConfigProfileService(basePath: appData.path),
      );
      addTearDown(() => teamCubit.close());

      final sessionRepo = SessionRepository(rootDir: appData.path);
      final chatCubit = ChatCubit(
        executableResolver: _executable,
        automationRepository: testAutomationRepository(),
        sessionRepository: sessionRepo,
      );
      addTearDown(() => chatCubit.close());

      final layoutCubit = LayoutCubit();
      addTearDown(() => layoutCubit.close());

      final editorCubit = EditorCubit(fs: LocalFilesystem());
      addTearDown(() => editorCubit.close());

      final workbenchCubit = WorkbenchCubit();
      addTearDown(() => workbenchCubit.close());

      final runCubit = RunCubit(
        platform: IdleRunPlatform(),
        folders: const [WorkspaceFolder(path: '/tmp/personal-workspace')],
      );
      addTearDown(() => runCubit.close());

      final skillCubit = testSkillCubit();
      addTearDown(() => skillCubit.close());

      final pluginRepo = PluginRepository();
      final pluginCubit = PluginCubit(
        repository: pluginRepo,
        installService: pluginRepo.install,
        repoService: PluginRepoService(),
      );
      addTearDown(() => pluginCubit.close());

      final worktreeCubit = WorktreeCubit();
      addTearDown(() => worktreeCubit.close());

      final presenceCubit = MemberPresenceCubit();
      chatCubit.bindPresenceCubit(presenceCubit);
      addTearDown(() => presenceCubit.close());

      final aiHistoryCubit = _testAiHistoryCubit();
      addTearDown(() => aiHistoryCubit.close());

      final cliPresetsCubit = CliPresetsCubit(
        repository: CliPresetsRepository(
          fs: InMemoryFilesystem(),
          presetsPath: '/cli-presets.json',
        ),
      );
      cliPresetsCubit.emit(
        const CliPresetsState(status: CliPresetsLoadStatus.ready),
      );
      addTearDown(() => cliPresetsCubit.close());

      final sessionPreferencesCubit =
          (await tester.runAsync(testSessionPreferencesCubit))!;
      addTearDown(() => sessionPreferencesCubit.close());

      chatCubit.ingestWorkspaceSessionSnapshot(
        workspaces: [
          Workspace(
            workspaceId: 'personal-test',
            folders: [WorkspaceFolder(path: '/tmp/personal-workspace')],
            createdAt: 1,
          ),
        ],
        sessions: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<GitRepoStore>(create: (_) => GitRepoStore()),
              RepositoryProvider<WorkspaceFileTreeStore>(
                create: (_) => WorkspaceFileTreeStore(),
              ),
              RepositoryProvider<SessionRepository>.value(value: sessionRepo),
              RepositoryProvider<WorkspaceTerminalRegistry>(
                create: (_) => WorkspaceTerminalRegistry(),
              ),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider.value(value: teamCubit),
                BlocProvider.value(value: chatCubit),
                BlocProvider<AppProviderCubit>(
                  create: (_) => _SeededAppProviderCubit(),
                ),
                BlocProvider.value(value: layoutCubit),
                BlocProvider.value(value: editorCubit),
                BlocProvider.value(value: workbenchCubit),
                BlocProvider.value(value: runCubit),
                BlocProvider.value(value: skillCubit),
                BlocProvider.value(value: pluginCubit),
                BlocProvider.value(value: worktreeCubit),
                BlocProvider.value(value: presenceCubit),
                BlocProvider(
                  create: (_) => AgentAttentionCubit(pruneInterval: null),
                ),
                BlocProvider.value(value: aiHistoryCubit),
                BlocProvider.value(value: WorkspaceToolsCubit()),
                BlocProvider.value(value: cliPresetsCubit),
                BlocProvider.value(value: sessionPreferencesCubit),
                BlocProvider(create: (_) => ShortcutCubit()),
                BlocProvider(
                  create: (_) => WorkspaceLandingContextCubit(
                    workspaceId: 'personal-test',
                    initial: const LandingLaunchContext(isPersonal: true),
                  ),
                ),
              ],
              child: WorkspaceToolsScope(
                state: const WorkspaceToolsScopeState(resolving: false),
                child: Scaffold(
                  body: _chatPageShell(),
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      final countAfterSettle = _structuralProbe(tester).buildCount;

      await layoutCubit.setLastOpenedWorkspaceId('other-workspace');
      await tester.pump();

      expect(_structuralProbe(tester).buildCount, countAfterSettle);
    },
  );
}
