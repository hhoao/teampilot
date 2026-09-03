import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/agent_attention_cubit.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/session_groups_cubit.dart';
import 'package:teampilot/cubits/shortcut_cubit.dart';
import 'package:teampilot/cubits/workbench/workbench_cubit.dart';
import 'package:teampilot/cubits/worktree_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_sidebar.dart';
import 'package:teampilot/repositories/keybinding_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/commands/key_chord.dart';
import 'package:teampilot/services/commands/key_chord_formatter.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../../support/post_frame_test_harness.dart';

final _workspace = Workspace(
  workspaceId: 'ws-1',
  folders: const [WorkspaceFolder(path: '/tmp/ws-1')],
  createdAt: 1,
);

void main() {
  late ChatCubit chatCubit;
  late AutomationCubit automationCubit;
  late WorktreeCubit worktreeCubit;
  late AgentAttentionCubit attentionCubit;
  late SessionRepository sessionRepository;
  late ShortcutCubit shortcutCubit;

  setUp(() {
    setUpTestAppStorage();
    sessionRepository = SessionRepository();
    chatCubit = testChatCubit(
      executableResolver: () => 'claude',
      sessionRepository: sessionRepository,
    );
    automationCubit = testAutomationCubit();
    worktreeCubit = WorktreeCubit();
    attentionCubit = AgentAttentionCubit(pruneInterval: null);
    shortcutCubit = ShortcutCubit(repository: KeybindingRepository());
  });

  tearDown(() async {
    if (!chatCubit.isClosed) await chatCubit.close();
    if (!automationCubit.isClosed) await automationCubit.close();
    if (!worktreeCubit.isClosed) await worktreeCubit.close();
    if (!attentionCubit.isClosed) await attentionCubit.close();
    if (!shortcutCubit.isClosed) await shortcutCubit.close();
    tearDownTestAppStorage();
  });

  Future<void> pumpSidebar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.runAsync(() => shortcutCubit.load());

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
                BlocProvider<ChatCubit>(lazy: false, create: (_) => chatCubit),
                BlocProvider<WorkbenchCubit>(create: (_) => WorkbenchCubit()),
                BlocProvider<AutomationCubit>.value(value: automationCubit),
                BlocProvider<WorktreeCubit>.value(value: worktreeCubit),
                BlocProvider<AgentAttentionCubit>.value(value: attentionCubit),
                BlocProvider<SessionGroupsCubit>(
                  create: (_) => SessionGroupsCubit(),
                ),
                BlocProvider<ShortcutCubit>.value(value: shortcutCubit),
              ],
              child: SizedBox(
                width: 320,
                height: 1000,
                child: WorkspaceSidebar(
                  workspace: _workspace,
                  tabScopeId: 'ws-1',
                  embedFooter: true,
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

  testWidgets('search sidebar tile shows shortcut in tooltip', (tester) async {
    await pumpSidebar(tester);

    final expectedChord = formatKeyChord(
      KeyChord.doubleTapShift(),
      isMacOS: defaultIsMacOS(),
    );
    final l10n = AppLocalizations.of(
      tester.element(find.byKey(AppKeys.searchSidebarTile)),
    )!;
    final tooltip = tester.widget<Tooltip>(
      find.descendant(
        of: find.byKey(AppKeys.searchSidebarTile),
        matching: find.byType(Tooltip),
      ),
    );
    expect(tooltip.message, '${l10n.workspaceSearchTitle} ($expectedChord)');
  });
}
