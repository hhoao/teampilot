import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/workspace/config/workspace_skills_section.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_info_section.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_page.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_split_pane.dart';
import 'package:teampilot/router/app_router.dart';
import 'package:teampilot/utils/ui/app_keys.dart';
import 'package:teampilot/widgets/settings/workspace_hub_shell.dart';

import '../../support/desktop_app_harness.dart';
import '../../support/fake_terminal_session.dart';
import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';
import '../../support/rust_lib_test_init.dart';

/// Rebuild-isolation regression: a kept-alive workspace tab in the background
/// must not rebuild its [WorkspacePage] when another tab becomes active.
void main() {
  setUpAll(initRustLibForTests);
  setUpAll(setUpDesktopAppHarness);
  tearDownAll(tearDownDesktopAppHarness);
  GoogleFonts.config.allowRuntimeFetching = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    setUpTestAppStorage();
    resetAppRouterLocationForWidgetTests();
    WorkspacePage.debugBuildCounts.clear();
    WorkspaceSplitPane.debugBuildCounts.clear();
  });

  tearDown(() {
    tearDownTestAppStorage();
    resetAppRouterLocationForWidgetTests();
    WorkspacePage.debugBuildCounts.clear();
    WorkspaceSplitPane.debugBuildCounts.clear();
  });

  Future<Workspace> pumpSingleWorkspace(WidgetTester tester) async {
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
                fs: InMemoryFilesystem(),
              ),
      postFrameScheduler: postFrame.scheduler,
      sessionRepository: desktopHarnessSessionRepo,
      storage: testHomeStorage,
    );

    late final Workspace workspace;
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('ws_manage'),
    ))!;
    addTearDown(() {
      try {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } on Object catch (_) {}
    });
    await tester.runAsync(() async {
      workspace = await desktopHarnessSessionRepo.createWorkspace(
        [WorkspaceFolder(path: dir.path)],
        display: 'manage',
      );
      chatCubit.ingestWorkspaceSessionSnapshot(
        workspaces: [workspace],
        sessions: const [],
      );
    });

    await pumpDesktopApp(tester, teamCubit, chatCubit: chatCubit);
    return workspace;
  }

  testWidgets('active tab applies a query-only manage navigation', (
    tester,
  ) async {
    final workspace = await pumpSingleWorkspace(tester);

    appRouter.go('/home-v2/workspace/${workspace.workspaceId}');
    await tester.pump();
    await pumpPhaseTransitions(tester);
    expect(find.byKey(AppKeys.workspaceConfigWorkspace), findsNothing);

    appRouter.go('/home-v2/workspace/${workspace.workspaceId}?view=manage');
    await tester.pump();
    await pumpPhaseTransitions(tester);
    expect(
      find.byKey(AppKeys.workspaceConfigWorkspace),
      findsWidgets,
      reason:
          'workspace management must open for a same-tab view=manage change',
    );
  });

  testWidgets('manage section nav repaints the body for a query-only change', (
    tester,
  ) async {
    final workspace = await pumpSingleWorkspace(tester);

    appRouter.go(
      '/home-v2/workspace/${workspace.workspaceId}?view=manage',
    );
    await tester.pump();
    await pumpPhaseTransitions(tester);
    expect(find.byType(WorkspaceInfoSection), findsWidgets);

    final skillsNav = find.descendant(
      of: find.byType(WorkspaceHubNavList),
      matching: find.byIcon(Icons.extension_outlined),
    );
    await tester.tap(skillsNav.first);
    await tester.pump();
    await pumpPhaseTransitions(tester);

    expect(
      appRouter.routerDelegate.currentConfiguration.uri.queryParameters['section'],
      'skills',
    );
    expect(
      find.byType(WorkspaceSkillsSection),
      findsWidgets,
      reason: 'the manage body must follow a same-tab section navigation',
    );
  });

  testWidgets('same-tab session deep link resyncs the workspace route', (
    tester,
  ) async {
    final workspace = await pumpSingleWorkspace(tester);

    appRouter.go('/home-v2/workspace/${workspace.workspaceId}');
    await tester.pump();
    await pumpPhaseTransitions(tester);
    expect(
      appRouter.routerDelegate.currentConfiguration.uri.queryParameters,
      isNot(contains('session')),
    );

    // A missing session id is enough to prove the route resync ran: the page
    // clears the query only after `_applySessionFromRoute` resolves it.
    appRouter.go(
      '/home-v2/workspace/${workspace.workspaceId}?session=missing-session',
    );
    await tester.pump();
    await pumpPhaseTransitions(tester);
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      appRouter.routerDelegate.currentConfiguration.uri.queryParameters,
      isNot(contains('session')),
      reason:
          'a same-tab ?session= change (notification tap) must bump the '
          'route revision so the workspace page applies the deep link',
    );
  });

  testWidgets(
    'background workspace does not rebuild when another tab activates',
    (tester) async {
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
                  fs: InMemoryFilesystem(),
                ),
        postFrameScheduler: postFrame.scheduler,
        sessionRepository: desktopHarnessSessionRepo,
        storage: testHomeStorage,
      );

      late final Workspace alpha;
      late final Workspace beta;
      final dirs = <Directory>[];
      await tester.runAsync(() async {
        for (final name in ['alpha', 'beta']) {
          final dir = await Directory.systemTemp.createTemp('ws_$name');
          dirs.add(dir);
          final workspace = await desktopHarnessSessionRepo.createWorkspace(
            [WorkspaceFolder(path: dir.path)],
            display: name,
          );
          if (name == 'alpha') {
            alpha = workspace;
          } else {
            beta = workspace;
          }
        }
        chatCubit.ingestWorkspaceSessionSnapshot(
          workspaces: [alpha, beta],
          sessions: const [],
        );
      });
      addTearDown(() {
        for (final dir in dirs) {
          try {
            if (dir.existsSync()) dir.deleteSync(recursive: true);
          } on Object catch (_) {}
        }
      });

      await pumpDesktopApp(tester, teamCubit, chatCubit: chatCubit);

      appRouter.go('/home-v2/workspace/${alpha.workspaceId}');
      await tester.pump();
      await pumpPhaseTransitions(tester);
      expect(find.byKey(AppKeys.chatWorkspace), findsWidgets);

      final alphaMounted =
          WorkspacePage.debugBuildCounts[alpha.workspaceId] ?? 0;
      final alphaPaneBuilds =
          WorkspaceSplitPane.debugBuildCounts[alpha.workspaceId] ?? 0;
      expect(alphaMounted, greaterThan(0), reason: 'alpha must mount first');
      expect(
        alphaPaneBuilds,
        greaterThan(0),
        reason: 'alpha split pane must mount, or the isolation check is vacuous',
      );

      // Activate Beta; Alpha becomes a background kept-alive tab.
      appRouter.go('/home-v2/workspace/${beta.workspaceId}');
      await tester.pump();
      await pumpPhaseTransitions(tester);

      expect(
        WorkspacePage.debugBuildCounts[alpha.workspaceId] ?? 0,
        alphaMounted,
        reason:
            'background workspace alpha must not rebuild when beta activates',
      );
      expect(
        WorkspaceSplitPane.debugBuildCounts[alpha.workspaceId] ?? 0,
        alphaPaneBuilds,
        reason:
            'background workspace alpha split pane must not rebuild when beta '
            'activates',
      );

      final betaMounted =
          WorkspacePage.debugBuildCounts[beta.workspaceId] ?? 0;
      final betaPaneBuilds =
          WorkspaceSplitPane.debugBuildCounts[beta.workspaceId] ?? 0;
      expect(betaMounted, greaterThan(0), reason: 'beta must mount');

      // Switch back to Alpha; Beta becomes the background tab.
      appRouter.go('/home-v2/workspace/${alpha.workspaceId}');
      await tester.pump();
      await pumpPhaseTransitions(tester);

      expect(
        WorkspacePage.debugBuildCounts[beta.workspaceId] ?? 0,
        betaMounted,
        reason:
            'background workspace beta must not rebuild when alpha activates',
      );
      expect(
        WorkspaceSplitPane.debugBuildCounts[beta.workspaceId] ?? 0,
        betaPaneBuilds,
        reason:
            'background workspace beta split pane must not rebuild when alpha '
            'activates',
      );
    },
  );
}
