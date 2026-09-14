import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/cubits/session_groups_cubit.dart';
import 'package:teampilot/cubits/shortcut_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_sidebar.dart';
import 'package:teampilot/pages/home_workspace/workspace/worktree_group_section.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/storage/runtime_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_context.dart';
import 'package:teampilot/services/workspace/workspace_tools_scope.dart';
import 'package:teampilot/widgets/sidebar_session_tile.dart';

import '../../../support/post_frame_test_harness.dart';
import 'package:teampilot/services/storage/home_storage.dart';

final _workspace = Workspace(
  workspaceId: 'ws-1',
  folders: const [WorkspaceFolder(path: '/tmp/huji')],
  createdAt: 1,
);

AppSession _session(String id) => AppSession(
  sessionId: id,
  workspaceId: 'ws-1',
  folders: const [WorkspaceFolder(path: '/tmp/huji')],
  display: id,
  createdAt: 1,
  updatedAt: 1,
);

void main() {
  late ChatCubit chatCubit;
  late AutomationCubit automationCubit;
  late WorktreeCubit worktreeCubit;
  late AgentAttentionCubit attentionCubit;
  late SessionGroupsCubit groupsCubit;
  late SessionRepository sessionRepository;

  setUp(() {
    setUpTestAppStorage();
    sessionRepository = SessionRepository(storage: testHomeStorage);
    chatCubit = testChatCubit(
      executableResolver: () => 'claude',
      sessionRepository: sessionRepository,
    );
    automationCubit = testAutomationCubit();
    worktreeCubit = WorktreeCubit(storage: testHomeStorage);
    attentionCubit = AgentAttentionCubit(pruneInterval: null);
    groupsCubit = SessionGroupsCubit(storage: testHomeStorage);
  });

  tearDown(() async {
    if (!chatCubit.isClosed) await chatCubit.close();
    if (!automationCubit.isClosed) await automationCubit.close();
    if (!worktreeCubit.isClosed) await worktreeCubit.close();
    if (!attentionCubit.isClosed) await attentionCubit.close();
    if (!groupsCubit.isClosed) await groupsCubit.close();
    tearDownTestAppStorage();
  });

  Future<void> pumpSidebar(
    WidgetTester tester, {
    List<AppSession>? sessions,
    bool markSessionsHydrated = false,
    bool seedManualGroup = false,
    bool resolvedWorktreeTools = false,
    bool settle = true,
  }) async {
    // Repository reads use real dart:io; under testWidgets they only complete
    // inside runAsync.
    await tester.runAsync(() => groupsCubit.load(_workspace.workspaceId));
    if (seedManualGroup) groupsCubit.createGroup('Hydrating');
    if (resolvedWorktreeTools) {
      // This is the resolved single-project/empty-worktree state that drove
      // the old sidebar's conditional worktree controls and header.
      worktreeCubit.emit(
        WorktreeState(
          repoPath: _workspace.firstFolderPath,
          currentWorktreePath: _workspace.firstFolderPath,
        ),
      );
    }
    final sidebarSessions = sessions ?? [_session('a'), _session('b')];
    chatCubit.emit(
      chatCubit.state.copyWith(
        workspaces: markSessionsHydrated
            ? [_workspace]
            : chatCubit.state.workspaces,
        sessions: sidebarSessions,
      ),
    );
    if (markSessionsHydrated) {
      chatCubit.dataStore.markWorkspacesSessionsHydrated([
        _workspace.workspaceId,
      ]);
    }
    SizedBox _sidebar() => SizedBox(
      width: 320,
      height: 1000,
      child: WorkspaceSidebar(workspace: _workspace, tabScopeId: 'ws-1'),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<HomeStorage>.value(value: testHomeStorage),
              RepositoryProvider<SessionRepository>.value(
                value: sessionRepository,
              ),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ChatCubit>(create: (_) => chatCubit),
                BlocProvider(
                  create: (_) => MemberPresenceCubit(storage: testHomeStorage),
                ),
                BlocProvider<WorkbenchCubit>(create: (_) => WorkbenchCubit()),
                BlocProvider<AutomationCubit>.value(value: automationCubit),
                BlocProvider<WorktreeCubit>.value(value: worktreeCubit),
                BlocProvider<AgentAttentionCubit>.value(value: attentionCubit),
                BlocProvider<SessionGroupsCubit>.value(value: groupsCubit),
                BlocProvider(
                  create: (_) => ShortcutCubit(storage: testHomeStorage),
                ),
              ],
              child: resolvedWorktreeTools
                  ? WorkspaceToolsScope(
                      state: WorkspaceToolsScopeState(
                        tools: WorkspaceToolsContext(
                          targetId: 'local',
                          context: testHomeStorage.context,
                        ),
                        roots: [_workspace.firstFolderPath],
                        effectiveFolders: _workspace.folders,
                        resolving: false,
                      ),
                      child: _sidebar(),
                    )
                  : _sidebar(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    if (settle) await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('created group renders above the list with its members', (
    tester,
  ) async {
    await pumpSidebar(tester);
    expect(find.byType(SidebarSessionTile), findsNWidgets(2)); // main list

    groupsCubit.createGroup('待办');
    groupsCubit.addSession(groupsCubit.state.groups.single.id, 'a');
    // Cubit notifications reach listeners asynchronously; two pumps let the
    // emission land on the following frame (same as sibling sidebar suites).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    // Member 'a' now appears twice: manual block + main list (tag-style).
    expect(find.byType(SidebarSessionTile), findsNWidgets(3));
    expect(find.text('待办'), findsOneWidget);
  });

  testWidgets('opens in groups mode', (tester) async {
    await pumpSidebar(tester);

    expect(
      find.byKey(const ValueKey('workspace-sidebar-view-switcher')),
      findsOneWidget,
    );
    expect(find.text('Groups'), findsOneWidget);
    expect(find.text('Project tree'), findsOneWidget);
    expect(find.byTooltip('New group'), findsOneWidget);
  });

  testWidgets('groups mode shows the empty conversations state', (
    tester,
  ) async {
    await pumpSidebar(tester, sessions: const [], markSessionsHydrated: true);

    expect(find.text('No conversations in this workspace yet'), findsOneWidget);
    expect(find.byType(ReorderableListView), findsNothing);
  });

  testWidgets('manual groups remain visible while sessions hydrate', (
    tester,
  ) async {
    await pumpSidebar(
      tester,
      sessions: const [],
      seedManualGroup: true,
      settle: false,
    );

    expect(find.text('Hydrating'), findsOneWidget);
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('switches to project tree without changing sessions', (
    tester,
  ) async {
    await pumpSidebar(tester, resolvedWorktreeTools: true);

    final toolsScope = tester.widget<WorkspaceToolsScope>(
      find.byType(WorkspaceToolsScope),
    );
    expect(toolsScope.state.isReady, isTrue);
    expect(toolsScope.state.tools?.context.mode, StorageBackendMode.native);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('workspace-sidebar-view-switcher')),
        matching: find.text('Project tree'),
      ),
    );
    await tester.pump();

    expect(find.text('huji'), findsOneWidget);
    expect(find.text('待办'), findsNothing);
    expect(find.byTooltip('New group'), findsNothing);
    expect(find.byType(WorktreeGroupSection), findsNothing);
    expect(find.byTooltip('Refresh worktrees'), findsNothing);
    expect(find.byTooltip('New worktree'), findsNothing);
    expect(chatCubit.state.sessions, hasLength(2));
  });

  testWidgets('switching back restores manual groups', (tester) async {
    await pumpSidebar(tester);
    groupsCubit.createGroup('待办');
    await tester.pump();

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('workspace-sidebar-view-switcher')),
        matching: find.text('Project tree'),
      ),
    );
    await tester.pump();
    expect(find.text('待办'), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('workspace-sidebar-view-switcher')),
        matching: find.text('Groups'),
      ),
    );
    await tester.pump();
    expect(find.text('待办'), findsOneWidget);
  });

  testWidgets('collapsing a manual block hides only block rows', (
    tester,
  ) async {
    await pumpSidebar(tester);
    groupsCubit.createGroup('G');
    groupsCubit.addSession(groupsCubit.state.groups.single.id, 'a');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    await tester.tap(find.text('G'));
    await tester.pump();
    // Block rows hidden; main list untouched.
    expect(find.byType(SidebarSessionTile), findsNWidgets(2));
  });

  testWidgets('+ header button opens create dialog and creates group', (
    tester,
  ) async {
    await pumpSidebar(tester);

    await tester.tap(find.byTooltip('New group'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '待办');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(groupsCubit.state.groups.single.name, '待办');
    expect(find.text('待办'), findsOneWidget);
  });
}
