import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/cubits/chat/model/session_connect_request.dart';
import 'package:teampilot/router/app_router.dart';
import 'package:teampilot/services/workspace/workspace_pane_policy.dart';
import 'package:teampilot/theme/app_theme.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../support/desktop_app_harness.dart';
import '../support/fake_terminal_session.dart';
import '../support/post_frame_test_harness.dart';
import 'package:shared_ui/shared_ui.dart';

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  setUpAll(setUpDesktopAppHarness);
  tearDownAll(tearDownDesktopAppHarness);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    setUpTestAppStorage();
    resetAppRouterLocationForWidgetTests();
  });

  tearDown(() {
    tearDownTestAppStorage();
    resetAppRouterLocationForWidgetTests();
  });

  testWidgets('renders chat workbench shell on workspace route', (
    tester,
  ) async {
    final teamCubit = await createTeamCubitInTest(tester);
    final postFrame = PostFrameTestHarness();
    final chatCubit = ChatCubit(
      executableResolver: desktopHarnessExecutable,
      automationRepository: testAutomationRepository(),
      terminalSessionFactory:
          ({required String executable, int scrollbackLines = 10000}) =>
              FakeTerminalSession(
                executable: executable,
                scrollbackLines: scrollbackLines,
              ),
      postFrameScheduler: postFrame.scheduler,
      sessionRepository: desktopHarnessSessionRepo,
    );
    late final Workspace workspace;
    late final Directory workspaceDir;
    final layoutCubit = LayoutCubit();
    addTearDown(layoutCubit.close);
    await tester.runAsync(() async {
      workspaceDir = await Directory.systemTemp.createTemp('widget_ws_');
      workspace = await desktopHarnessSessionRepo.createWorkspace([
        WorkspaceFolder(path: workspaceDir.path),
      ]);
      chatCubit.ingestWorkspaceSessionSnapshot(
        workspaces: [workspace],
        sessions: const [],
      );
    });
    addTearDown(() {
      try {
        if (workspaceDir.existsSync()) {
          workspaceDir.deleteSync(recursive: true);
        }
      } on Object catch (_) {}
    });
    await pumpDesktopApp(
      tester,
      teamCubit,
      chatCubit: chatCubit,
      layoutCubit: layoutCubit,
    );
    appRouter.go('/home-v2/workspace/${workspace.workspaceId}');
    await tester.pump();
    await pumpPhaseTransitions(tester);

    expect(find.byKey(AppKeys.chatWorkspace), findsOneWidget);
    expect(find.byKey(AppKeys.membersPanel), findsNothing);
    final selectedTeam = teamCubit.state.selectedTeam;
    expect(selectedTeam, isNotNull);
    expect(chatCubit.state.tabs.length, 0);
    final workbenchCtx = tester.element(find.byKey(AppKeys.chatWorkspace));
    final l10n = AppLocalizations.of(workbenchCtx);
    expect(find.text(l10n.workspaceChatLandingInputHint), findsOneWidget);
    // Compose landing default-hides right tools (prefs stay visible).
    expect(layoutCubit.state.preferences.rightToolsVisible, isTrue);
    expect(
      WorkspacePanePolicy.effective(
        preferences: layoutCubit.state.preferences,
        viewportWidth: 1400,
        composeLanding: true,
        landingRightToolsOverride: layoutCubit.state.landingRightToolsOverride,
      ).dockRight,
      isFalse,
    );
    expect(
      find.byKey(AppKeys.rightToolsPanel).hitTestable(),
      findsNothing,
    );

    chatCubit.setActiveWorkspace(workspace.workspaceId);
    // Real repository I/O must run inside runAsync in widget tests.
    await tester.runAsync(() async {
      await chatCubit.connectWorkspaceSession(
        TeamSessionConnect(selectedTeam!),
      );
    });
    await tester.pump();
    await tester.runAsync(() async {
      await drainPendingAsyncWork();
      await postFrame.flush();
    });
    await tester.pump();
    expect(chatCubit.state.tabs.length, 1);
    expect(chatCubit.state.tabs.single.id.startsWith('local-'), isFalse);
    expect(chatCubit.isMemberRunning('team-lead'), isTrue);
    await pumpPhaseTransitions(tester);
    // Session exits compose: prefs dock restored. Prefer key mount over
    // hitTestable — pane size sync can lag TpDeferredMountShell in smoke.
    expect(chatCubit.state.composeActive, isFalse);
    expect(
      WorkspacePanePolicy.effective(
        preferences: layoutCubit.state.preferences,
        viewportWidth: 1400,
        composeLanding: false,
        landingRightToolsOverride: layoutCubit.state.landingRightToolsOverride,
      ).dockRight,
      isTrue,
    );
    expect(find.byKey(AppKeys.rightToolsPanel), findsOneWidget);
  });

  testWidgets('renders settings shell with title bar and icon navigation', (
    tester,
  ) async {
    final teamCubit = await createTeamCubitInTest(tester);
    await pumpDesktopApp(tester, teamCubit);

    appRouter.go('/config');
    await pumpPhaseTransitions(tester);

    expect(
      find.text('Manage FlashskyAI team and model settings.'),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.dashboard_customize_outlined), findsWidgets);
    expect(find.byIcon(Icons.memory_outlined), findsNothing);
  });

  testWidgets('settings pages use the global component theme', (tester) async {
    final teamCubit = await createTeamCubitInTest(tester);
    await pumpDesktopApp(tester, teamCubit);

    appRouter.go('/providers/claude');
    await pumpPhaseTransitions(tester);

    final providerCtx = tester.element(find.byKey(AppKeys.llmConfigWorkspace));
    final providerTheme = Theme.of(providerCtx);
    final cs = providerTheme.colorScheme;
    expect(cs.primary, themePresetSwatchPrimary(kDefaultThemeColorPreset));

    final providerList = tester.widget<Material>(
      find.byKey(AppKeys.llmProviderList),
    );
    expect(providerList.color, cs.surfaceContainer);
  });

  testWidgets('desktop add provider opens form in detail area', (tester) async {
    final teamCubit = await createTeamCubitInTest(tester);
    await pumpDesktopApp(tester, teamCubit);

    appRouter.go('/providers/claude');
    await pumpPhaseTransitions(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(AppKeys.llmProviderList),
        matching: find.byIcon(Icons.add),
      ),
    );
    await pumpPhaseTransitions(tester);
    await tester.tap(find.text('Add Provider').last);
    await pumpPhaseTransitions(tester);

    expect(find.byKey(AppKeys.llmProviderList), findsOneWidget);
    expect(find.text('Add Provider'), findsWidgets);
    expect(find.text('Provider name'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(DraggableScrollableSheet), findsNothing);
  });

  testWidgets('cli settings configure Claude Code CLI path', (tester) async {
    final teamCubit = await createTeamCubitInTest(tester);
    final sessionCubit = await tester.runAsync(testSessionPreferencesCubit);
    expect(sessionCubit, isNotNull);
    await sessionCubit!.load();

    await pumpDesktopApp(
      tester,
      teamCubit,
      sessionPreferencesCubit: sessionCubit,
    );

    appRouter.go('/config');
    await pumpPhaseTransitions(tester);
    await tester.tap(find.byKey(AppKeys.configCliSectionButton));
    await pumpPhaseTransitions(tester);

    expect(find.text('Claude Code CLI path'), findsOneWidget);
    final claudeField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.key == AppKeys.claudeCliExecutablePathField,
    );
    await tester.ensureVisible(claudeField);
    await tester.enterText(claudeField, '/opt/bin/claude');
    await tester.pump(const Duration(milliseconds: 500));

    expect(sessionCubit.state.preferences.cliExecutablePaths, {
      'claude': '/opt/bin/claude',
    });
  });

}
