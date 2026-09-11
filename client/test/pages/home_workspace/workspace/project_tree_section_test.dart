import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/session_groups_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/project_tree_section.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/utils/session/session_project_grouping.dart';
import 'package:teampilot/widgets/sidebar_session_tile.dart';

import '../../../support/post_frame_test_harness.dart';

final _workspace = Workspace(
  workspaceId: 'ws-1',
  folders: const [WorkspaceFolder(path: '/tmp/ws-1')],
  createdAt: 1,
);

AppSession _session(String id, String path) => AppSession(
  sessionId: id,
  workspaceId: 'ws-1',
  folders: [WorkspaceFolder(path: path)],
  display: id,
  createdAt: 1,
  updatedAt: 1,
);

void main() {
  late ChatCubit chatCubit;
  late AutomationCubit automationCubit;
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
    attentionCubit = AgentAttentionCubit(pruneInterval: null);
    groupsCubit = SessionGroupsCubit(storage: testHomeStorage);
  });

  tearDown(() async {
    if (!chatCubit.isClosed) await chatCubit.close();
    if (!automationCubit.isClosed) await automationCubit.close();
    if (!attentionCubit.isClosed) await attentionCubit.close();
    if (!groupsCubit.isClosed) await groupsCubit.close();
    tearDownTestAppStorage();
  });

  Future<void> pumpProjectTree(
    WidgetTester tester,
    List<ProjectSessionGroup> groups,
  ) async {
    await tester.runAsync(() => groupsCubit.load(_workspace.workspaceId));
    chatCubit.emit(
      chatCubit.state.copyWith(
        sessions: [for (final group in groups) ...group.sessions],
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<SessionRepository>.value(
                value: sessionRepository,
              ),
            ],
            child: MultiBlocProvider(
              providers: [
                BlocProvider<ChatCubit>.value(value: chatCubit),
                BlocProvider<AutomationCubit>.value(value: automationCubit),
                BlocProvider<AgentAttentionCubit>.value(value: attentionCubit),
                BlocProvider<SessionGroupsCubit>.value(value: groupsCubit),
              ],
              child: SizedBox(
                width: 320,
                height: 1000,
                child: ProjectTreeSection(
                  groups: groups,
                  workspace: _workspace,
                  tabScopeId: 'ws-1',
                  highlightSessionId: null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  final groups = [
    ProjectSessionGroup(
      projectPath: '/tmp/huji',
      label: 'huji',
      sessions: [_session('a', '/tmp/huji')],
    ),
    const ProjectSessionGroup(
      projectPath: null,
      label: '',
      sessions: [],
      isOther: true,
    ),
  ];

  testWidgets('renders project nodes and session children', (tester) async {
    await pumpProjectTree(tester, groups);

    expect(find.text('huji'), findsOneWidget);
    expect(find.byType(SidebarSessionTile), findsOneWidget);
    expect(find.text('Other'), findsNothing);
  });

  testWidgets('collapsing a project hides only its children', (tester) async {
    await pumpProjectTree(tester, groups);

    await tester.tap(find.byKey(const ValueKey('project-tree-node-/tmp/huji')));
    await tester.pump();

    expect(find.text('huji'), findsOneWidget);
    expect(find.byType(SidebarSessionTile), findsNothing);
  });

  testWidgets('renders Other only when it has sessions', (tester) async {
    final withOther = [
      groups.first,
      ProjectSessionGroup(
        projectPath: null,
        label: '',
        sessions: [_session('orphan', '/tmp/elsewhere')],
        isOther: true,
      ),
    ];
    await pumpProjectTree(tester, withOther);

    expect(find.text('Other'), findsOneWidget);
    expect(find.byType(SidebarSessionTile), findsNWidgets(2));
  });
}
