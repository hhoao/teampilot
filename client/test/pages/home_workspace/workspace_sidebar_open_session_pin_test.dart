import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/member_presence_cubit.dart';
import 'package:teampilot/cubits/session_groups_cubit.dart';
import 'package:teampilot/cubits/shortcut_cubit.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_sidebar.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/repositories/keybinding_repository.dart';

import '../../support/post_frame_test_harness.dart';
import 'package:teampilot/services/storage/home_storage.dart';

/// The open-session strip is a rebuild-isolated surface (see
/// `workspace_sidebar_working_rebuild_test.dart`): its host does not react to
/// ChatCubit churn, so the pin mark has to come from a live per-tile read of
/// the session, never from the `AppSession` snapshot captured at build time.
final _workspace = Workspace(
  workspaceId: 'ws-1',
  folders: const [WorkspaceFolder(path: '/tmp/ws-1')],
  createdAt: 1,
);

AppSession _session({
  required String id,
  String display = '',
  int createdAt = 1,
  int updatedAt = 1,
  bool pinned = false,
}) {
  return AppSession(
    sessionId: id,
    workspaceId: _workspace.workspaceId,
    folders: const [WorkspaceFolder(path: '/tmp/ws-1')],
    display: display,
    createdAt: createdAt,
    updatedAt: updatedAt,
    pinned: pinned,
  );
}

void main() {
  late ChatCubit chatCubit;
  late WorkbenchCubit workbenchCubit;
  late ShortcutCubit shortcutCubit;
  late AutomationCubit automationCubit;
  late WorktreeCubit worktreeCubit;
  late AgentAttentionCubit attentionCubit;
  late SessionRepository sessionRepository;

  setUp(() {
    setUpTestAppStorage();
    sessionRepository = SessionRepository(storage: testHomeStorage);
    chatCubit = testChatCubit(
      executableResolver: () => 'claude',
      sessionRepository: sessionRepository,
    );
    workbenchCubit = WorkbenchCubit();
    shortcutCubit = ShortcutCubit(
      storage: testHomeStorage,
      repository: KeybindingRepository(storage: testHomeStorage),
    );
    automationCubit = testAutomationCubit();
    worktreeCubit = WorktreeCubit(storage: testHomeStorage);
    attentionCubit = AgentAttentionCubit(pruneInterval: null);
  });

  tearDown(() async {
    if (!chatCubit.isClosed) await chatCubit.close();
    if (!workbenchCubit.isClosed) await workbenchCubit.close();
    if (!shortcutCubit.isClosed) await shortcutCubit.close();
    if (!automationCubit.isClosed) await automationCubit.close();
    if (!worktreeCubit.isClosed) await worktreeCubit.close();
    if (!attentionCubit.isClosed) await attentionCubit.close();
    tearDownTestAppStorage();
  });

  Future<void> pumpSidebar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
                BlocProvider<ChatCubit>(lazy: false, create: (_) => chatCubit),
                BlocProvider(
                  create: (_) => MemberPresenceCubit(storage: testHomeStorage),
                ),
                BlocProvider<WorkbenchCubit>.value(value: workbenchCubit),
                BlocProvider<ShortcutCubit>.value(value: shortcutCubit),
                BlocProvider<AutomationCubit>.value(value: automationCubit),
                BlocProvider<WorktreeCubit>.value(value: worktreeCubit),
                BlocProvider<AgentAttentionCubit>.value(value: attentionCubit),
                BlocProvider<SessionGroupsCubit>(
                  create: (_) => SessionGroupsCubit(storage: testHomeStorage),
                ),
              ],
              child: SizedBox(
                width: 320,
                height: 1000,
                child: WorkspaceSidebar(
                  workspace: _workspace,
                  tabScopeId: 'ws-1',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  Finder pinMarkIn(Key tileKey) => find.descendant(
    of: find.byKey(tileKey),
    matching: find.byIcon(Icons.push_pin),
  );

  const runningTileKey = ValueKey('workspace-running-session-a');
  const conversationTileKey = ValueKey('workspace-sidebar-session-a');

  Future<void> emitPinned(WidgetTester tester, {required bool pinned}) async {
    chatCubit.emit(
      chatCubit.state.copyWith(
        sessions: [_session(id: 'a', display: 'Alpha', pinned: pinned)],
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('pinning an open session paints its running tile pin mark', (
    tester,
  ) async {
    await emitPinned(tester, pinned: false);
    workbenchCubit.openSession(_workspace.workspaceId, 'a');
    await pumpSidebar(tester);

    expect(find.byKey(runningTileKey), findsOneWidget);
    expect(pinMarkIn(runningTileKey), findsNothing);
    expect(pinMarkIn(conversationTileKey), findsNothing);

    await emitPinned(tester, pinned: true);

    expect(
      pinMarkIn(conversationTileKey),
      findsOneWidget,
      reason: 'conversation-list tile mirrors the live pin state',
    );
    expect(
      pinMarkIn(runningTileKey),
      findsOneWidget,
      reason: 'running tile must mirror the live pin state',
    );
  });

  testWidgets('unpinning an open session clears its running tile pin mark', (
    tester,
  ) async {
    await emitPinned(tester, pinned: true);
    workbenchCubit.openSession(_workspace.workspaceId, 'a');
    await pumpSidebar(tester);

    expect(pinMarkIn(runningTileKey), findsOneWidget);

    await emitPinned(tester, pinned: false);

    expect(
      pinMarkIn(runningTileKey),
      findsNothing,
      reason: 'running tile must drop the pin mark when the session unpins',
    );
  });
}
