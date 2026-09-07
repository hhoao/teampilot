import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/ai_history_cubit.dart';
import 'package:teampilot/cubits/app_provider_cubit.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/cli_presets_cubit.dart';
import 'package:teampilot/cubits/editor_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/cubits/launch_profile_cubit.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/cubits/plugin_cubit.dart';
import 'package:teampilot/cubits/run_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/shortcut_cubit.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_split_layout.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/cubits/workspace_landing_context_cubit.dart';
import 'package:teampilot/cubits/workspace_tools_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/landing_launch_context.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/chat/chat_page_shell.dart';
import 'package:teampilot/pages/workbench/workbench_group_host.dart';
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
import 'package:teampilot/services/plugin/plugin_repo_service.dart';
import 'package:teampilot/services/provider/config_profile_service.dart';
import 'package:teampilot/services/terminal/workspace_terminal_registry.dart';
import 'package:teampilot/services/workspace/workspace_pane_policy.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';
import 'package:teampilot/widgets/workbench/workbench_split_layout_view.dart';

import '../../support/desktop_app_harness.dart';
import '../../support/idle_run_platform.dart';
import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

String _executable() => 'flashskyai';

const _workspaceId = 'ws-narrow';
const _cwd = '/tmp/narrow-ws';

/// One logical pixel below the shell's narrow breakpoint — the widest viewport
/// that must still degrade to the focused-group-only rendering.
final Size _narrowSize = Size(
  WorkspacePanePolicy.narrowBreakpointWidth - 1,
  900,
);

/// Comfortably above the breakpoint — the split view must render in full.
final Size _wideSize = Size(WorkspacePanePolicy.narrowBreakpointWidth + 360, 900);

class _SeededAppProviderCubit extends AppProviderCubit {
  _SeededAppProviderCubit() {
    emit(const AppProviderState());
  }
}

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

AppSession _session(String id, String display, {int createdAt = 1}) {
  return AppSession(
    sessionId: id,
    workspaceId: _workspaceId,
    folders: const [WorkspaceFolder(path: _cwd)],
    display: display,
    createdAt: createdAt,
  );
}

void _registerSession(
  ChatCubit chatCubit,
  WorkbenchCubit workbenchCubit,
  AppSession session,
  String title,
) {
  chatCubit.setActiveWorkspace(_workspaceId);
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
  workbenchCubit.openSession(_workspaceId, session.sessionId);
}

/// Seeds a two-group center layout: `g0` holds A1 + A2, `g1` holds B (focused,
/// created by splitting B out to the right).
void _seedTwoGroups(ChatCubit chatCubit, WorkbenchCubit workbenchCubit) {
  _registerSession(
    chatCubit, workbenchCubit, _session('sess-a1', 'Session A1'), 'Session A1',
  );
  _registerSession(
    chatCubit, workbenchCubit, _session('sess-a2', 'Session A2'), 'Session A2',
  );
  _registerSession(
    chatCubit, workbenchCubit, _session('sess-b', 'Session B'), 'Session B',
  );
  workbenchCubit.splitTab(
    _workspaceId,
    WorkbenchTabId.session('sess-b'),
    axis: Axis.horizontal,
    before: false,
  );
}

/// Full cubit set the real [ChatPageShell] tree needs (mirrors the chat page
/// rebuild harness), pumped at a caller-chosen viewport size.
class _NarrowHarness {
  _NarrowHarness(this.chatCubit, this.workbenchCubit, this.layoutCubit);

  final ChatCubit chatCubit;
  final WorkbenchCubit workbenchCubit;
  final LayoutCubit layoutCubit;

  Future<void> pump(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(_build());
    // Session bodies animate indefinitely; settle with fixed frames instead
    // of pumpAndSettle.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Pumps a few fixed frames (never pumpAndSettle — session bodies animate).
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Re-pumps after a viewport-size change (same widget tree, new MediaQuery).
  Future<void> resize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  late final Directory appData;
  late final LaunchProfileCubit _teamCubit;
  late final EditorCubit _editorCubit;
  late final RunCubit _runCubit;
  late final SkillCubit _skillCubit;
  late final PluginCubit _pluginCubit;
  late final WorktreeCubit _worktreeCubit;
  late final MemberPresenceCubit _presenceCubit;
  late final AiHistoryCubit _aiHistoryCubit;
  late final WorkspaceToolsCubit _workspaceToolsCubit;
  late final CliPresetsCubit _cliPresetsCubit;
  late final SessionPreferencesCubit _sessionPreferencesCubit;
  late final WorkspaceLandingContextCubit _landingContextCubit;

  Widget _build() {
    return CliToolRegistryScope(
      registry: CliToolRegistry.builtIn(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<GitRepoStore>(create: (_) => GitRepoStore()),
            RepositoryProvider<WorkspaceFileTreeStore>(
              create: (_) => WorkspaceFileTreeStore(),
            ),
            RepositoryProvider<SessionRepository>.value(
              value: SessionRepository(rootDir: appData.path),
            ),
            RepositoryProvider<WorkspaceTerminalRegistry>(
              create: (_) => WorkspaceTerminalRegistry(),
            ),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: _teamCubit),
              BlocProvider.value(value: chatCubit),
              BlocProvider<AppProviderCubit>(
                create: (_) => _SeededAppProviderCubit(),
              ),
              BlocProvider.value(value: layoutCubit),
              BlocProvider.value(value: _editorCubit),
              BlocProvider.value(value: workbenchCubit),
              BlocProvider.value(value: _runCubit),
              BlocProvider.value(value: _skillCubit),
              BlocProvider.value(value: _pluginCubit),
              BlocProvider.value(value: _worktreeCubit),
              BlocProvider.value(value: _presenceCubit),
              BlocProvider(
                create: (_) => AgentAttentionCubit(pruneInterval: null),
              ),
              BlocProvider.value(value: _aiHistoryCubit),
              BlocProvider.value(value: _workspaceToolsCubit),
              BlocProvider.value(value: _cliPresetsCubit),
              BlocProvider.value(value: _sessionPreferencesCubit),
              BlocProvider(create: (_) => ShortcutCubit()),
              BlocProvider.value(value: _landingContextCubit),
            ],
            child: WorkspaceToolsScope(
              state: const WorkspaceToolsScopeState(resolving: false),
              child: Scaffold(
                body: ChatPageShell(
                  cwd: _cwd,
                  workspaceId: _workspaceId,
                  tabScopeId: _workspaceId,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<_NarrowHarness> _setUpHarness(WidgetTester tester) async {
  final appData = Directory.systemTemp.createTempSync('chat_narrow_test_');
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

  final chatCubit = ChatCubit(
    executableResolver: _executable,
    automationRepository: testAutomationRepository(),
    sessionRepository: SessionRepository(rootDir: appData.path),
  );
  addTearDown(() => chatCubit.close());
  chatCubit.ingestWorkspaceSessionSnapshot(
    workspaces: [
      Workspace(
        workspaceId: _workspaceId,
        folders: const [WorkspaceFolder(path: _cwd)],
        createdAt: 1,
      ),
    ],
    sessions: const [],
  );

  final workbenchCubit = WorkbenchCubit();
  addTearDown(() => workbenchCubit.close());

  final layoutCubit = LayoutCubit();
  addTearDown(() => layoutCubit.close());

  final editorCubit = EditorCubit(fs: LocalFilesystem());
  addTearDown(() => editorCubit.close());

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

  final runCubit = RunCubit(
    platform: IdleRunPlatform(),
    folders: const [WorkspaceFolder(path: _cwd)],
  );
  addTearDown(() => runCubit.close());

  final pluginRepo = PluginRepository();
  final pluginCubit = PluginCubit(
    repository: pluginRepo,
    installService: pluginRepo.install,
    repoService: PluginRepoService(),
  );
  addTearDown(() => pluginCubit.close());

  final skillCubit = testSkillCubit();
  addTearDown(() => skillCubit.close());

  final worktreeCubit = WorktreeCubit();
  addTearDown(() => worktreeCubit.close());

  final workspaceToolsCubit = WorkspaceToolsCubit();
  addTearDown(() => workspaceToolsCubit.close());

  final landingContextCubit = WorkspaceLandingContextCubit(
    workspaceId: _workspaceId,
    initial: const LandingLaunchContext(isPersonal: true),
  );
  addTearDown(() => landingContextCubit.close());

  return _NarrowHarness(chatCubit, workbenchCubit, layoutCubit)
    ..appData = appData
    .._teamCubit = teamCubit
    .._editorCubit = editorCubit
    .._runCubit = runCubit
    .._skillCubit = skillCubit
    .._pluginCubit = pluginCubit
    .._worktreeCubit = worktreeCubit
    .._presenceCubit = presenceCubit
    .._aiHistoryCubit = aiHistoryCubit
    .._workspaceToolsCubit = workspaceToolsCubit
    .._cliPresetsCubit = cliPresetsCubit
    .._sessionPreferencesCubit = sessionPreferencesCubit
    .._landingContextCubit = landingContextCubit;
}

void main() {
  setUp(() {
    setUpTestAppStorage();
  });

  tearDown(() {
    tearDownTestAppStorage();
  });

  testWidgets(
    'narrow viewport renders only the focused group; wide restores both',
    (tester) async {
      final harness = await _setUpHarness(tester);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      // Show the session tab strip so group tab titles are assertable.
      await harness.layoutCubit.setSessionTabBarVisible(true);
      _seedTwoGroups(harness.chatCubit, harness.workbenchCubit);
      await harness.pump(tester, _narrowSize);

      // The layout tree survives narrow mode untouched: still a SplitBranch
      // with two groups.
      final layout = harness.workbenchCubit.centerLayout(_workspaceId);
      expect(layout.root, isA<SplitBranch>());
      expect(layout.groups.length, 2);
      expect(layout.focusedGroupId, 'g1');

      // Only the focused group (g1, holding Session B) renders; no divider.
      expect(find.byType(WorkbenchGroupHost), findsOneWidget);
      expect(
        find.byKey(workbenchSplitDividerKey(const <bool>[])),
        findsNothing,
      );
      expect(find.text('Session B'), findsOneWidget);
      expect(find.text('Session A1'), findsNothing);
      expect(find.text('Session A2'), findsNothing);

      // Resize wide: both groups render again with their divider.
      await harness.resize(tester, _wideSize);

      expect(find.byType(WorkbenchGroupHost), findsNWidgets(2));
      expect(
        find.byKey(workbenchSplitDividerKey(const <bool>[])),
        findsOneWidget,
      );
      expect(find.text('Session A1'), findsOneWidget);
      expect(find.text('Session A2'), findsOneWidget);
      expect(find.text('Session B'), findsOneWidget);
      // Tree unchanged by the round trip.
      expect(
        harness.workbenchCubit.centerLayout(_workspaceId).root,
        isA<SplitBranch>(),
      );
    },
  );

  testWidgets('narrow viewport hides the split tab context-menu entries', (
    tester,
  ) async {
    final harness = await _setUpHarness(tester);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    // Tab strip is hidden by default; opt in so chips are tappable.
    await harness.layoutCubit.setSessionTabBarVisible(true);
    _seedTwoGroups(harness.chatCubit, harness.workbenchCubit);
    // Focus g0 — the multi-tab group — so it is the sole rendered group at
    // narrow width and its split entries would exist if not gated.
    harness.workbenchCubit.focusGroup(_workspaceId, 'g0');
    await harness.pump(tester, _narrowSize);

    expect(find.byType(WorkbenchGroupHost), findsOneWidget);
    expect(find.text('Session A1'), findsOneWidget);

    await tester.tap(find.text('Session A1'), buttons: kSecondaryButton);
    await harness.settle(tester);

    // The menu opened (close entries are always present) but the split entries
    // are gated off below the narrow breakpoint.
    expect(find.text('Close Others'), findsOneWidget);
    expect(find.text('Split Right'), findsNothing);
    expect(find.text('Split Down'), findsNothing);
  });

  testWidgets('wide viewport keeps the split tab context-menu entries', (
    tester,
  ) async {
    final harness = await _setUpHarness(tester);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await harness.layoutCubit.setSessionTabBarVisible(true);
    _seedTwoGroups(harness.chatCubit, harness.workbenchCubit);
    harness.workbenchCubit.focusGroup(_workspaceId, 'g0');
    await harness.pump(tester, _wideSize);

    await tester.tap(find.text('Session A1'), buttons: kSecondaryButton);
    await harness.settle(tester);

    expect(find.text('Split Right'), findsOneWidget);
    expect(find.text('Split Down'), findsOneWidget);
  });
}
