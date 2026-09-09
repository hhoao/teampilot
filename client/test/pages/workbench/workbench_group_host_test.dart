import 'dart:io';

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
import 'package:teampilot/cubits/shortcut_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/cubits/skill_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
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
import 'package:teampilot/pages/workbench/workbench_group_host.dart';
import 'package:teampilot/pages/workspace_shell/workspace_shell.dart';
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
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';
import 'package:teampilot/widgets/workbench/workbench_split_layout_view.dart';
import 'package:teampilot/widgets/workbench/workbench_tab_drag.dart';

import '../../support/desktop_app_harness.dart';
import '../../support/idle_run_platform.dart';
import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

String _executable() => 'flashskyai';

const _workspaceId = 'ws-split';
const _cwd = '/tmp/split-ws';

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

/// Seeds a two-group center layout:
/// - left group `g0`: sessions A1 + A2, in landing (activeId == null);
/// - right group `g1`: session B active and focused.
void _seedTwoGroups(ChatCubit chatCubit, WorkbenchCubit workbenchCubit) {
  chatCubit.setActiveWorkspace(_workspaceId);
  _registerSession(
    chatCubit, workbenchCubit, _session('sess-a1', 'Session A1'), 'Session A1',
  );
  _registerSession(
    chatCubit, workbenchCubit, _session('sess-a2', 'Session A2'), 'Session A2',
  );
  _registerSession(
    chatCubit, workbenchCubit, _session('sess-b', 'Session B'), 'Session B',
  );
  // Split B out into a sibling group to the right.
  workbenchCubit.splitTab(
    _workspaceId,
    WorkbenchTabId.session('sess-b'),
    axis: Axis.horizontal,
    before: false,
  );
  // g0 (left) enters landing while keeping its tabs; g1 stays focused.
  workbenchCubit.focusGroup(_workspaceId, 'g0');
  workbenchCubit.enterLanding(_workspaceId);
  workbenchCubit.focusGroup(_workspaceId, 'g1');
}

/// Minimal mirror of ChatPageShell's split-view wiring around
/// [WorkbenchGroupHost], with an injected lightweight landing pane.
class _SplitHost extends StatelessWidget {
  const _SplitHost({
    required this.chatCubit,
    required this.workbenchCubit,
    required this.editorCubit,
  });

  final ChatCubit chatCubit;
  final WorkbenchCubit workbenchCubit;
  final EditorCubit editorCubit;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WorkbenchCubit, WorkbenchState>(
      bloc: workbenchCubit,
      builder: (context, state) {
        final layout = workbenchCubit.centerLayout(_workspaceId);
        return WorkbenchTabDragHost(
          child: WorkbenchSplitLayoutView(
            layout: layout,
            splitEnabled: true,
            onGroupFocused: (id) => workbenchCubit.focusGroup(_workspaceId, id),
            onResizeCommit: (commits) =>
                workbenchCubit.commitSplitResizeBatch(
                  _workspaceId,
                  commits: commits,
                ),
            groupBuilder: (context, groupId, strip) => WorkbenchGroupHost(
              workspace: Workspace(
                workspaceId: _workspaceId,
                folders: const [WorkspaceFolder(path: _cwd)],
                createdAt: 1,
              ),
              workspaceId: _workspaceId,
              tabScopeId: _workspaceId,
              cwd: _cwd,
              groupId: groupId,
              strip: strip,
              routeActive: true,
              chatState: chatCubit.state,
              runtimeTabs: chatCubit.tabStore.tabsForWorkspace(_workspaceId),
              editorBucket: editorCubit.state.bucket(_workspaceId),
              shellTitles: const {},
              showTabBar: true,
              splitEnabled: true,
              landingBuilder: (context, strip) => ColoredBox(
                key: const Key('group-host-landing-marker'),
                color: const Color(0xFF101010),
                child: const Center(child: Text('group-host-landing-marker')),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One seeded environment per test: all cubits the workbench group host tree
/// needs, mirroring the chat page rebuild harness.
class GroupHostHarness {
  GroupHostHarness(this.chatCubit, this.workbenchCubit, this.editorCubit);

  final ChatCubit chatCubit;
  final WorkbenchCubit workbenchCubit;
  final EditorCubit editorCubit;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      CliToolRegistryScope(
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
                BlocProvider.value(value: _layoutCubit),
                BlocProvider.value(value: editorCubit),
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
                  body: _SplitHost(
                    chatCubit: chatCubit,
                    workbenchCubit: workbenchCubit,
                    editorCubit: editorCubit,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  // Initialized by [setUpHarness]; closed via addTearDown there.
  late final Directory appData;
  late final LaunchProfileCubit _teamCubit;
  late final LayoutCubit _layoutCubit;
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
}

Future<GroupHostHarness> setUpHarness(WidgetTester tester) async {
  final appData = Directory.systemTemp.createTempSync('group_host_test_');
  addTearDown(() {
    if (appData.existsSync()) appData.deleteSync(recursive: true);
  });

  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
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

  final layoutCubit = LayoutCubit();
  addTearDown(() => layoutCubit.close());
  final worktreeCubit = WorktreeCubit();
  addTearDown(() => worktreeCubit.close());
  final workspaceToolsCubit = WorkspaceToolsCubit();
  addTearDown(() => workspaceToolsCubit.close());
  final landingContextCubit = WorkspaceLandingContextCubit(
    workspaceId: _workspaceId,
    initial: const LandingLaunchContext(isPersonal: true),
  );
  addTearDown(() => landingContextCubit.close());

  return GroupHostHarness(chatCubit, workbenchCubit, editorCubit)
    ..appData = appData
    .._teamCubit = teamCubit
    .._layoutCubit = layoutCubit
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

  testWidgets('renders one WorkspaceShell tab bar per group', (tester) async {
    final harness = await setUpHarness(tester);
    _seedTwoGroups(harness.chatCubit, harness.workbenchCubit);
    await harness.pump(tester);

    // One shell (tab bar host) per group leaf.
    expect(find.byType(WorkspaceShell), findsNWidgets(2));
    // Group-scoped tab bars: left group shows A1 + A2, right group shows B.
    expect(find.text('Session A1'), findsOneWidget);
    expect(find.text('Session A2'), findsOneWidget);
    expect(find.text('Session B'), findsOneWidget);
  });

  testWidgets('landing shows in the group whose activeId is null', (
    tester,
  ) async {
    final harness = await setUpHarness(tester);
    _seedTwoGroups(harness.chatCubit, harness.workbenchCubit);
    await harness.pump(tester);

    // g0 (left) is in landing over its two tabs → the group's landing pane
    // renders exactly once; g1 keeps its session body.
    expect(find.byKey(const Key('group-host-landing-marker')), findsOneWidget);
    expect(
      harness.workbenchCubit.centerLayout(_workspaceId).groups['g0']!.activeId,
      isNull,
    );
    expect(
      harness.workbenchCubit.centerLayout(_workspaceId).groups['g1']!.activeId,
      WorkbenchTabId.session('sess-b'),
    );
  });

  testWidgets('tapping a group body focuses that group in the cubit', (
    tester,
  ) async {
    final harness = await setUpHarness(tester);
    _seedTwoGroups(harness.chatCubit, harness.workbenchCubit);
    await harness.pump(tester);

    expect(harness.workbenchCubit.centerFocusedGroupId(_workspaceId), 'g1');

    // Tap the left group's landing pane → g0 gains focus.
    await tester.tap(
      find.byKey(const Key('group-host-landing-marker')),
      warnIfMissed: false,
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(harness.workbenchCubit.centerFocusedGroupId(_workspaceId), 'g0');
  });

  testWidgets('selecting a tab activates it and focuses its group', (
    tester,
  ) async {
    final harness = await setUpHarness(tester);
    _seedTwoGroups(harness.chatCubit, harness.workbenchCubit);
    await harness.pump(tester);

    expect(harness.workbenchCubit.centerFocusedGroupId(_workspaceId), 'g1');

    await tester.tap(find.text('Session A1'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(harness.workbenchCubit.centerFocusedGroupId(_workspaceId), 'g0');
    expect(
      harness.workbenchCubit.centerActiveId(_workspaceId),
      WorkbenchTabId.session('sess-a1'),
    );
  });
}
