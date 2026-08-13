import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_search_dialog.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/io/local_filesystem.dart';
import 'package:teampilot/services/search/workspace_search_indexes.dart';
import 'package:teampilot/theme/app_typography_scale.dart';

import '../support/post_frame_test_harness.dart';

AppSession _session(
  String id,
  String display, {
  int createdAt = 1000,
  int updatedAt = 0,
}) {
  return AppSession(
    sessionId: id,
    workspaceId: 'ws-1',
    display: display,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}

/// Test host for the dialog: localizations + TpTheme + the cubits
/// [SidebarSessionTile] reads (ChatCubit, AgentAttentionCubit, AutomationCubit,
/// SessionRepository).
Widget _host({
  required Workspace workspace,
  required List<AppSession> sessions,
  required ChatCubit chatCubit,
  required AgentAttentionCubit attentionCubit,
  required AutomationCubit automationCubit,
  required SessionRepository sessionRepo,
}) {
  final theme = ThemeData(useMaterial3: true);
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    theme: theme,
    home: TpTheme(
      data: TpThemeData.fromColorScheme(
        theme.colorScheme,
        scale: 1.0,
        controlScale: AppTypographyScale.standard.multiplier,
      ),
      child: MultiRepositoryProvider(
        providers: [
          RepositoryProvider<SessionRepository>.value(value: sessionRepo),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: chatCubit),
            BlocProvider.value(value: attentionCubit),
            BlocProvider.value(value: automationCubit),
          ],
          child: Scaffold(
            // The real app mounts the dialog inside showTpDialog, whose Dialog /
            // fullscreen Material provides the Material ancestor TextField and
            // TpHover's ink splashes require. Scaffold stands in for it here.
            body: WorkspaceSearchDialog(
              workspace: workspace,
              sessions: sessions,
              indexes: WorkspaceSearchIndexes(),
              fs: LocalFilesystem(),
              emptyTitleFallback: 'New Chat',
              onOpenSession: (_) {},
              onOpenFile: (_) {},
            ),
          ),
        ),
      ),
    ),
  );
}

/// Pumps [widget] inside a real-async zone so the dialog's background index
/// warm (real filesystem probes against test app data) completes, then settles
/// back into fake-async pumps for the test body.
Future<void> _pumpDialog(WidgetTester tester, Widget widget) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(widget);
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await tester.pump();
  });
  await tester.pump();
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  testWidgets('renders search field, filter chips, and recent sessions', (
    tester,
  ) async {
    final workspace = Workspace(workspaceId: 'ws-1', createdAt: 1);
    final sessions = [
      _session('s1', 'Flutter test runner', updatedAt: 2000),
      _session('s2', 'Codex review', updatedAt: 1000),
    ];
    final sessionRepo = SessionRepository();
    final attention = AgentAttentionCubit(pruneInterval: null);
    final automation = testAutomationCubit(sessionRepository: sessionRepo);
    final chatCubit = ChatCubit(
      executableResolver: () => 'claude',
      automationRepository: testAutomationRepository(),
      sessionRepository: sessionRepo,
      agentAttentionCubit: attention,
    );
    chatCubit.ingestWorkspaceSessionSnapshot(
      workspaces: [workspace],
      sessions: sessions,
    );
    addTearDown(chatCubit.close);
    addTearDown(attention.close);
    addTearDown(automation.close);

    await _pumpDialog(
      tester,
      _host(
        workspace: workspace,
        sessions: sessions,
        chatCubit: chatCubit,
        attentionCubit: attention,
        automationCubit: automation,
        sessionRepo: sessionRepo,
      ),
    );

    // Search field pinned to the top plus the three filter chips.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);

    // Empty query → recent sessions (rendered through SidebarSessionTile).
    expect(find.text('Recent sessions'), findsOneWidget);
    expect(find.text('Flutter test runner'), findsOneWidget);
    expect(find.text('Codex review'), findsOneWidget);
  });

  testWidgets('query shows merged conversations; filter chips switch sections', (
    tester,
  ) async {
    final workspace = Workspace(workspaceId: 'ws-1', createdAt: 1);
    final sessions = [_session('s1', 'Flutter test runner', updatedAt: 2000)];
    final sessionRepo = SessionRepository();
    final attention = AgentAttentionCubit(pruneInterval: null);
    final automation = testAutomationCubit(sessionRepository: sessionRepo);
    final chatCubit = ChatCubit(
      executableResolver: () => 'claude',
      automationRepository: testAutomationRepository(),
      sessionRepository: sessionRepo,
      agentAttentionCubit: attention,
    );
    chatCubit.ingestWorkspaceSessionSnapshot(
      workspaces: [workspace],
      sessions: sessions,
    );
    addTearDown(chatCubit.close);
    addTearDown(attention.close);
    addTearDown(automation.close);

    await _pumpDialog(
      tester,
      _host(
        workspace: workspace,
        sessions: sessions,
        chatCubit: chatCubit,
        attentionCubit: attention,
        automationCubit: automation,
        sessionRepo: sessionRepo,
      ),
    );

    // A title match surfaces under the merged 对话 group.
    await tester.enterText(find.byType(TextField), 'flutter');
    await tester.pump(const Duration(milliseconds: 250)); // debounce
    await tester.pump();

    expect(find.text('Conversations'), findsOneWidget);
    expect(find.text('Recent sessions'), findsNothing);
    expect(find.text('Flutter test runner'), findsOneWidget);

    // 文件 filter hides the conversations group; nothing matches → empty state.
    await tester.tap(find.text('Files'));
    await tester.pump();
    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('Conversations'), findsNothing);

    // 全部 restores the conversations group.
    await tester.tap(find.text('All'));
    await tester.pump();
    expect(find.text('Conversations'), findsOneWidget);
  });

  testWidgets('show more expands the recent section and disappears', (
    tester,
  ) async {
    final workspace = Workspace(workspaceId: 'ws-1', createdAt: 1);
    final sessions = [
      for (var i = 0; i < 10; i++)
        _session('s$i', 'Session $i', createdAt: 1000 + i),
    ];
    final sessionRepo = SessionRepository();
    final attention = AgentAttentionCubit(pruneInterval: null);
    final automation = testAutomationCubit(sessionRepository: sessionRepo);
    final chatCubit = ChatCubit(
      executableResolver: () => 'claude',
      automationRepository: testAutomationRepository(),
      sessionRepository: sessionRepo,
      agentAttentionCubit: attention,
    );
    chatCubit.ingestWorkspaceSessionSnapshot(
      workspaces: [workspace],
      sessions: sessions,
    );
    addTearDown(chatCubit.close);
    addTearDown(attention.close);
    addTearDown(automation.close);

    await _pumpDialog(
      tester,
      _host(
        workspace: workspace,
        sessions: sessions,
        chatCubit: chatCubit,
        attentionCubit: attention,
        automationCubit: automation,
        sessionRepo: sessionRepo,
      ),
    );

    // Recent sessions capped at 8 of 10 → the show-more link is visible and the
    // two least-recent sessions are hidden.
    expect(find.text('Show more results'), findsOneWidget);
    expect(find.text('Session 1'), findsNothing);

    // Expanding reveals everything and removes the link.
    await tester.tap(find.text('Show more results'));
    await tester.pump();
    expect(find.text('Show more results'), findsNothing);
    expect(find.text('Session 1'), findsOneWidget);
    expect(find.text('Session 0'), findsOneWidget);
  });
}
