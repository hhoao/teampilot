import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/session_groups_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/session_group.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/session_group_section.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/utils/session/app_session_sort.dart';
import 'package:teampilot/widgets/sidebar_session_tile.dart';

import '../../../support/post_frame_test_harness.dart';

final _workspace = Workspace(
  workspaceId: 'ws-1',
  folders: const [WorkspaceFolder(path: '/tmp/ws-1')],
  createdAt: 1,
);

AppSession _session(String id, {int createdAt = 1}) => AppSession(
  sessionId: id,
  workspaceId: 'ws-1',
  display: id,
  createdAt: createdAt,
  updatedAt: createdAt,
);

Future<SessionGroupsCubit> _readyGroupsCubit(
  WidgetTester tester,
  List<SessionGroup> groups,
) async {
  final cubit = SessionGroupsCubit();
  // Repository reads use real dart:io; under testWidgets they only complete
  // inside runAsync.
  await tester.runAsync(() => cubit.load(_workspace.workspaceId));
  // Tests start from an explicit group list instead of pre-seeding files.
  cubit.emit(cubit.state.copyWith(groups: groups));
  return cubit;
}

void main() {
  late ChatCubit chatCubit;
  late AutomationCubit automationCubit;
  late AgentAttentionCubit attentionCubit;
  late SessionGroupsCubit groupsCubit;

  setUp(() {
    setUpTestAppStorage();
    chatCubit = testChatCubit(executableResolver: () => 'claude');
    automationCubit = testAutomationCubit();
    attentionCubit = AgentAttentionCubit(pruneInterval: null);
  });

  tearDown(() async {
    if (!chatCubit.isClosed) await chatCubit.close();
    if (!automationCubit.isClosed) await automationCubit.close();
    if (!attentionCubit.isClosed) await attentionCubit.close();
    if (!groupsCubit.isClosed) await groupsCubit.close();
    tearDownTestAppStorage();
  });

  Future<void> pumpSection(
    WidgetTester tester, {
    required List<AppSession> sessions,
    required List<SessionGroup> groups,
  }) async {
    chatCubit.emit(chatCubit.state.copyWith(sessions: sessions));
    groupsCubit = await _readyGroupsCubit(tester, groups);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<SessionRepository>.value(
                value: SessionRepository(),
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
                width: 280,
                child: SessionGroupSection(
                  group: groups.first,
                  workspace: _workspace,
                  tabScopeId: 'tab-1',
                  sessionSort: AppSessionSort.recentlyUpdated,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Trailing header actions are hover-revealed; synthesize a mouse hover over
  /// the header row so the "+" button mounts.
  Future<void> hoverHeader(WidgetTester tester, String label) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(find.text(label)));
    addTearDown(gesture.removePointer);
    await tester.pump();
  }

  testWidgets('renders sorted member rows and header count', (tester) async {
    await pumpSection(
      tester,
      sessions: [_session('old', createdAt: 1), _session('new', createdAt: 5)],
      groups: const [
        SessionGroup(id: 'g1', name: '待办', sessionIds: ['old', 'new']),
      ],
    );

    expect(find.text('待办'), findsOneWidget);
    expect(find.textContaining('2'), findsWidgets); // member count
    final tiles = tester.widgetList<SidebarSessionTile>(
      find.byType(SidebarSessionTile),
    ).map((t) => t.session.sessionId).toList();
    expect(tiles, ['new', 'old']); // recentlyUpdated sort
  });

  testWidgets('collapse header hides rows; expand restores them', (
    tester,
  ) async {
    await pumpSection(
      tester,
      sessions: [_session('a')],
      groups: const [
        SessionGroup(id: 'g1', name: 'G', sessionIds: ['a']),
      ],
    );

    await tester.tap(find.text('G'));
    await tester.pump();
    expect(find.byType(SidebarSessionTile), findsNothing);
    expect(groupsCubit.state.groupById('g1')!.collapsed, isTrue);

    await tester.tap(find.text('G'));
    await tester.pump();
    expect(find.byType(SidebarSessionTile), findsOneWidget);
  });

  testWidgets('caps at eight rows with a More toggle', (tester) async {
    await pumpSection(
      tester,
      sessions: [
        for (var i = 0; i < 12; i++)
          _session('s$i', createdAt: 20 - i),
      ],
      groups: [
        SessionGroup(
          id: 'g1',
          name: 'Big',
          sessionIds: [for (var i = 0; i < 12; i++) 's$i'],
        ),
      ],
    );

    expect(find.byType(SidebarSessionTile), findsNWidgets(8));
    expect(find.text('More'), findsOneWidget);

    await tester.tap(find.text('More'));
    await tester.pump();
    expect(find.byType(SidebarSessionTile), findsNWidgets(10));
    expect(find.text('Show less'), findsOneWidget);
  });

  testWidgets('expanded empty group shows placeholder', (tester) async {
    await pumpSection(
      tester,
      sessions: [_session('a')],
      groups: const [SessionGroup(id: 'g1', name: 'Empty')],
    );

    expect(find.text('No conversations'), findsOneWidget);
  });

  testWidgets('header + opens add dialog; checking adds membership', (
    tester,
  ) async {
    await pumpSection(
      tester,
      sessions: [_session('a'), _session('b')],
      groups: const [SessionGroup(id: 'g1', name: 'G', sessionIds: [])],
    );

    await hoverHeader(tester, 'G');
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(CheckboxListTile, 'a'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(groupsCubit.state.groupById('g1')!.containsSession('a'), isTrue);
    expect(groupsCubit.state.groupById('g1')!.containsSession('b'), isFalse);
  });
}
