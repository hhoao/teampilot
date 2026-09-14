import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/chat/model/chat_tab.dart';
import 'package:teampilot/cubits/chat/model/chat_tab_info.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/cubits/session_groups_cubit.dart';
import 'package:teampilot/cubits/shortcut_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_tab.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_sidebar.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_sidebar_row_metrics.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/widgets/sidebar_session_tile.dart';

import '../../../support/post_frame_test_harness.dart';
import 'package:teampilot/services/storage/home_storage.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

final _workspace = Workspace(
  workspaceId: 'ws-1',
  folders: const [WorkspaceFolder(path: '/tmp/ws-1')],
  createdAt: 1,
);

AppSession _session(String id) => AppSession(
  sessionId: id,
  workspaceId: 'ws-1',
  folders: const [WorkspaceFolder(path: '/tmp/ws-1')],
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
  late WorkbenchCubit workbenchCubit;

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
    workbenchCubit = WorkbenchCubit();
  });

  tearDown(() async {
    if (!chatCubit.isClosed) await chatCubit.close();
    if (!automationCubit.isClosed) await automationCubit.close();
    if (!worktreeCubit.isClosed) await worktreeCubit.close();
    if (!attentionCubit.isClosed) await attentionCubit.close();
    if (!groupsCubit.isClosed) await groupsCubit.close();
    if (!workbenchCubit.isClosed) await workbenchCubit.close();
    tearDownTestAppStorage();
  });

  Future<void> pumpSidebar(
    WidgetTester tester, {
    List<String> ids = const ['a', 'b'],
    double height = 1000,
    bool embedFooter = true,
  }) async {
    await tester.runAsync(() => groupsCubit.load(_workspace.workspaceId));
    chatCubit.emit(
      chatCubit.state.copyWith(sessions: [for (final id in ids) _session(id)]),
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
                BlocProvider<ChatCubit>.value(value: chatCubit),
                BlocProvider(
                  create: (_) => MemberPresenceCubit(storage: testHomeStorage),
                ),
                BlocProvider<WorkbenchCubit>.value(value: workbenchCubit),
                BlocProvider<AutomationCubit>.value(value: automationCubit),
                BlocProvider<WorktreeCubit>.value(value: worktreeCubit),
                BlocProvider<AgentAttentionCubit>.value(value: attentionCubit),
                BlocProvider<SessionGroupsCubit>.value(value: groupsCubit),
                BlocProvider(
                  create: (_) => ShortcutCubit(storage: testHomeStorage),
                ),
              ],
              child: SizedBox(
                width: 320,
                height: height,
                child: WorkspaceSidebar(
                  workspace: _workspace,
                  tabScopeId: 'ws-1',
                  embedFooter: embedFooter,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('split layout renders open sessions grouped by column', (
    tester,
  ) async {
    workbenchCubit
      ..openSession('ws-1', 'a')
      ..openSession('ws-1', 'b')
      ..splitTab(
        'ws-1',
        WorkbenchTabId.session('b'),
        axis: Axis.horizontal,
        before: false,
      );
    await pumpSidebar(tester);

    // Two split sub-sections, each with its divider and tiles.
    expect(
      find.byKey(const ValueKey('workspace-running-split-g0')),
      findsOneWidget,
    );
    final second = workbenchCubit.centerLayout('ws-1').leafGroupIds.last;
    expect(
      find.byKey(ValueKey('workspace-running-split-$second')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workspace-running-session-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workspace-running-session-b')),
      findsOneWidget,
    );
    final sidebar = tester.getRect(find.byType(WorkspaceSidebar));
    final footer = tester.getRect(
      find.byKey(AppKeys.homeWorkspaceWorkspaceManagementTile),
    );
    expect(footer.bottom, closeTo(sidebar.bottom - 18, 0.1));
  });

  testWidgets('running session strip stays bounded in a short sidebar', (
    tester,
  ) async {
    final ids = [for (var i = 0; i < 8; i++) 'session-$i'];
    for (final id in ids) {
      workbenchCubit.openSession('ws-1', id);
    }

    await pumpSidebar(tester, ids: ids, height: 400);

    expect(
      find.byKey(const ValueKey('workspace-sidebar-view-switcher')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'running session strip does not reserve empty space without footer',
    (tester) async {
      workbenchCubit
        ..openSession('ws-1', 'a')
        ..openSession('ws-1', 'b')
        ..splitTab(
          'ws-1',
          WorkbenchTabId.session('b'),
          axis: Axis.horizontal,
          before: false,
        );
      await pumpSidebar(tester, embedFooter: false);

      final viewport = tester.getRect(
        find.ancestor(
          of: find.byKey(const ValueKey('workspace-running-split-g0')),
          matching: find.byType(ListView),
        ),
      );
      final lastTile = tester.getRect(
        find.byKey(const ValueKey('workspace-running-session-b')),
      );
      expect(viewport.bottom, closeTo(lastTile.bottom, 0.1));
    },
  );

  testWidgets('running session strip hugs content with footer', (tester) async {
    workbenchCubit
      ..openSession('ws-1', 'a')
      ..openSession('ws-1', 'b')
      ..splitTab(
        'ws-1',
        WorkbenchTabId.session('b'),
        axis: Axis.horizontal,
        before: false,
      );
    await pumpSidebar(tester);

    final viewport = tester.getRect(
      find.ancestor(
        of: find.byKey(const ValueKey('workspace-running-split-g0')),
        matching: find.byType(ListView),
      ),
    );
    final lastTile = tester.getRect(
      find.byKey(const ValueKey('workspace-running-session-b')),
    );
    expect(viewport.bottom, closeTo(lastTile.bottom, 0.1));
  });

  testWidgets('single group stays flat without column dividers', (
    tester,
  ) async {
    workbenchCubit.openSession('ws-1', 'a');
    await pumpSidebar(tester);

    expect(
      find.byKey(const ValueKey('workspace-running-split-g0')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('workspace-running-session-a')),
      findsOneWidget,
    );
  });

  testWidgets('preview sessions render in the open strip with italic title', (
    tester,
  ) async {
    workbenchCubit
      ..openSession('ws-1', 'a')
      ..openSession('ws-1', 'b', preview: true)
      ..openSession('ws-1', 'c');
    await pumpSidebar(tester);

    // The preview tab 'b' surfaces in the flat open strip next to pinned tabs.
    expect(
      find.byKey(const ValueKey('workspace-running-session-a')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('workspace-running-session-b')),
      findsOneWidget,
    );
    // Preview and pinned tiles render identically (no italic distinction
    // anymore — the state lives on the workbench tab strip).
    expect(
      find.byKey(const ValueKey('workspace-running-session-b')),
      findsOneWidget,
    );
  });

  testWidgets('each group marks the session it is currently showing', (
    tester,
  ) async {
    workbenchCubit
      ..openSession('ws-1', 'a')
      ..openSession('ws-1', 'b')
      ..splitTab(
        'ws-1',
        WorkbenchTabId.session('b'),
        axis: Axis.horizontal,
        before: false,
      );
    // Focused = the new group showing 'b'. g0 shows 'a'.
    await pumpSidebar(tester);

    // 'b' (focused group's active) is the primary highlight.
    final tileB = tester.widget<SidebarSessionTile>(
      find.byKey(const ValueKey('workspace-running-session-b')),
    );
    expect(tileB.highlightSessionId, 'b');
    // 'a' (unfocused group's active) has NO secondary tile fill — the
    // "what each column shows" cue lives on the indicator bar alone: g0's
    // active tile carries a MEDIUM (4px) bar, not the faint 3px one.
    final g0Indicator = find
        .byKey(const ValueKey('workspace-running-group-indicator-g0'))
        .evaluate()
        .single;
    expect((g0Indicator.renderObject as RenderBox).size.width, 4);
    // And the focused group's active tile gets the widest bar (5px).
    final second = workbenchCubit.centerLayout('ws-1').leafGroupIds.last;
    final secondIndicator = find
        .byKey(ValueKey('workspace-running-group-indicator-$second'))
        .evaluate()
        .single;
    expect((secondIndicator.renderObject as RenderBox).size.width, 5);
  });

  testWidgets(
    'unfocused group active renders a medium indicator vs faint siblings',
    (tester) async {
      workbenchCubit
        ..openSession('ws-1', 'a')
        ..openSession('ws-1', 'b')
        ..openSession('ws-1', 'c')
        // g0 [a, b, c], active = a after explicit activation.
        ..activate('ws-1', WorkbenchTabId.session('a'))
        ..splitTab(
          'ws-1',
          WorkbenchTabId.session('b'),
          axis: Axis.horizontal,
          before: false,
        ); // g0 [a, c] | g1 [b], focused g1
      await pumpSidebar(tester, ids: const ['a', 'b', 'c']);

      // Indicator width encodes the role: focused-group active (5) >
      // unfocused-group active (4) > non-active sibling (3).
      final g0Indicators = find
          .byKey(const ValueKey('workspace-running-group-indicator-g0'))
          .evaluate()
          .toList();
      // g0 has two tiles: 'a' (its active) and 'c' (sibling).
      expect(g0Indicators.length, 2);
      final widths = [
        (g0Indicators.first.renderObject as RenderBox).size.width,
        (g0Indicators.last.renderObject as RenderBox).size.width,
      ]..sort();
      expect(widths.first, 3);
      expect(widths.last, 4);

      // The focused group g1's active 'b' carries the widest bar.
      final g1Indicator = find.byKey(
        const ValueKey('workspace-running-group-indicator-g1'),
      );
      expect(tester.getSize(g1Indicator).width, 5);
    },
  );

  testWidgets('tapping a group indicator focuses that group', (tester) async {
    workbenchCubit
      ..openSession('ws-1', 'a')
      ..openSession('ws-1', 'b')
      ..splitTab(
        'ws-1',
        WorkbenchTabId.session('b'),
        axis: Axis.horizontal,
        before: false,
      );
    await pumpSidebar(tester);

    final layoutBefore = workbenchCubit.centerLayout('ws-1');
    final focusedBefore = layoutBefore.focusedGroupId;

    // One indicator per tile, keyed by its split group.
    final g0Indicator = find.byKey(
      const ValueKey('workspace-running-group-indicator-g0'),
    );
    expect(g0Indicator, findsOneWidget);
    await tester.tap(g0Indicator);
    await tester.pump();

    final layoutAfter = workbenchCubit.centerLayout('ws-1');
    expect(layoutAfter.focusedGroupId, isNot(focusedBefore));
  });

  testWidgets(
    'split group indicator height matches the session tile paint height',
    (tester) async {
      workbenchCubit
        ..openSession('ws-1', 'a')
        ..openSession('ws-1', 'b')
        ..splitTab(
          'ws-1',
          WorkbenchTabId.session('b'),
          axis: Axis.horizontal,
          before: false,
        );
      await pumpSidebar(tester);

      final indicator = find.byKey(
        const ValueKey('workspace-running-group-indicator-g0'),
      );
      expect(indicator, findsOneWidget);
      // Solo tile in the group: paint height only (no following row gap).
      expect(tester.getSize(indicator).height, kWorkspaceSidebarRowPaintHeight);
    },
  );

  testWidgets('same-group indicators abut across the inter-row gap', (
    tester,
  ) async {
    workbenchCubit
      ..openSession('ws-1', 'a')
      ..openSession('ws-1', 'b')
      ..openSession('ws-1', 'c')
      ..activate('ws-1', WorkbenchTabId.session('a'))
      ..splitTab(
        'ws-1',
        WorkbenchTabId.session('b'),
        axis: Axis.horizontal,
        before: false,
      ); // g0 [a, c] | g1 [b]
    await pumpSidebar(tester, ids: const ['a', 'b', 'c']);

    final indicators = find
        .byKey(const ValueKey('workspace-running-group-indicator-g0'))
        .evaluate()
        .toList();
    expect(indicators.length, 2);
    final first = indicators.first.renderObject! as RenderBox;
    final second = indicators.last.renderObject! as RenderBox;
    // Non-last bar extends through the tile gap so the rail reads continuous.
    expect(
      first.size.height,
      kWorkspaceSidebarRowPaintHeight + kWorkspaceSidebarRowGap,
    );
    expect(second.size.height, kWorkspaceSidebarRowPaintHeight);
    final firstBottom = first.localToGlobal(Offset(0, first.size.height)).dy;
    final secondTop = second.localToGlobal(Offset.zero).dy;
    expect(firstBottom, secondTop);
  });
  testWidgets('session menus lock their owning split groups', (tester) async {
    workbenchCubit
      ..openSession('ws-1', 'a')
      ..openSession('ws-1', 'b')
      ..splitTab(
        'ws-1',
        WorkbenchTabId.session('b'),
        axis: Axis.horizontal,
        before: false,
      );
    for (final id in const ['a', 'b']) {
      chatCubit.tabStore.registerSession(
        ChatTab(
          info: ChatTabInfo(id: id, title: id, subtitle: ''),
          cliTeamName: id,
        ),
      );
    }
    await pumpSidebar(tester);

    final first = workbenchCubit.centerLayout('ws-1').leafGroupIds.first;
    workbenchCubit.toggleGroupLock('ws-1', first);
    expect(workbenchCubit.centerLayout('ws-1').lockedGroupIds, {first});
    await pumpSidebar(tester);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(SidebarSessionTile).first),
    );

    await tester.tap(
      find.byType(SidebarSessionTile).first,
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(l10n.workbenchUnlockGroup), findsOneWidget);
    await tester.tap(find.text(l10n.workbenchUnlockGroup));
    await tester.pump();

    expect(workbenchCubit.centerLayout('ws-1').lockedGroupIds, isEmpty);
  });

  testWidgets('second split session menu locks only its owning group', (
    tester,
  ) async {
    workbenchCubit
      ..openSession('ws-1', 'a')
      ..openSession('ws-1', 'b')
      ..splitTab(
        'ws-1',
        WorkbenchTabId.session('b'),
        axis: Axis.horizontal,
        before: false,
      );
    for (final id in const ['a', 'b']) {
      chatCubit.tabStore.registerSession(
        ChatTab(
          info: ChatTabInfo(id: id, title: id, subtitle: ''),
          cliTeamName: id,
        ),
      );
    }
    final layout = workbenchCubit.centerLayout('ws-1');
    final first = layout.leafGroupIds.first;
    final second = layout.leafGroupIds.last;
    workbenchCubit.toggleGroupLock('ws-1', first);
    await pumpSidebar(tester);

    final l10n = AppLocalizations.of(
      tester.element(find.byKey(const ValueKey('workspace-running-session-b'))),
    );
    await tester.tap(
      find.byKey(const ValueKey('workspace-running-session-b')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(l10n.workbenchLockGroup), findsOneWidget);
    await tester.tap(find.text(l10n.workbenchLockGroup));
    await tester.pump();

    expect(workbenchCubit.centerLayout('ws-1').lockedGroupIds, {first, second});
  });

  testWidgets('flat session menu uses the focused workbench group', (
    tester,
  ) async {
    workbenchCubit.openSession('ws-1', 'a');
    chatCubit.tabStore.registerSession(
      ChatTab(
        info: ChatTabInfo(id: 'a', title: 'a', subtitle: ''),
        cliTeamName: 'a',
      ),
    );
    await pumpSidebar(tester, ids: const ['a']);

    final groupId = workbenchCubit.centerLayout('ws-1').focusedGroupId;
    final l10n = AppLocalizations.of(
      tester.element(find.byType(SidebarSessionTile).first),
    );
    await tester.tap(
      find.byKey(const ValueKey('workspace-running-session-a')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.text(l10n.workbenchLockGroup));
    await tester.pump();

    expect(workbenchCubit.centerLayout('ws-1').lockedGroupIds, {groupId});
  });
}
