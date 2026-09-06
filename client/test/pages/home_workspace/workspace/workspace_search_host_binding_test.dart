import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/home_workspace/home_workspace_tab_scope.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_search_dialog.dart';
import 'package:teampilot/router/app_router.dart';
import 'package:teampilot/services/commands/workspace_search_command_registrar.dart';
import 'package:teampilot/main.dart';

import '../../../support/desktop_app_harness.dart';
import '../../../support/fake_terminal_session.dart';
import '../../../support/post_frame_test_harness.dart';
import '../../../support/rust_lib_test_init.dart';

/// Reproduces the double-shift workspace-search scoping bug: the shared
/// [WorkspaceSearchHost] must follow the active title-bar workspace tab.
///
/// One long app session mirrors real usage: many tab switches, each followed
/// by a double-shift search that must hit the *active* workspace.
///
/// Distinguishes workspaces by a marker file in each workspace folder: the
/// dialog's 文件 section searches the active workspace's first folder.
void main() {
  setUpAll(initRustLibForTests);
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

  testWidgets(
    'double-shift search follows the active workspace across a session',
    (tester) async {
      final teamCubit = await createTeamCubitInTest(tester);
      final chatCubit = ChatCubit(
        executableResolver: desktopHarnessExecutable,
        automationRepository: testAutomationRepository(),
        terminalSessionFactory:
            ({required String executable, int scrollbackLines = 10000}) =>
                FakeTerminalSession(
                  executable: executable,
                  scrollbackLines: scrollbackLines,
                ),
        sessionRepository: desktopHarnessSessionRepo,
      );
      final layoutCubit = LayoutCubit();
      addTearDown(layoutCubit.close);
      addTearDown(chatCubit.close);

      late final Workspace workspaceA;
      late final Workspace workspaceB;
      final tempDirs = <Directory>[];
      await tester.runAsync(() async {
        final dirA = await Directory.systemTemp.createTemp('ws_host_a_');
        final dirB = await Directory.systemTemp.createTemp('ws_host_b_');
        tempDirs..add(dirA)..add(dirB);
        File('${dirA.path}/alpha_marker_file.dart').writeAsStringSync('// a');
        File('${dirB.path}/beta_marker_file.dart').writeAsStringSync('// b');
        workspaceA = await desktopHarnessSessionRepo.createWorkspace([
          WorkspaceFolder(path: dirA.path),
        ]);
        workspaceB = await desktopHarnessSessionRepo.createWorkspace([
          WorkspaceFolder(path: dirB.path),
        ]);
        chatCubit.ingestWorkspaceSessionSnapshot(
          workspaces: [workspaceA, workspaceB],
          sessions: const [],
        );
      });
      addTearDown(() {
        for (final dir in tempDirs) {
          try {
            if (dir.existsSync()) dir.deleteSync(recursive: true);
          } on Object catch (_) {}
        }
      });

      await pumpDesktopApp(
        tester,
        teamCubit,
        chatCubit: chatCubit,
        layoutCubit: layoutCubit,
      );

      /// Opens the search via the shared host (double-shift equivalent),
      /// asserts the 文件 section comes from the expected workspace's folder,
      /// then closes the dialog so the next step starts clean.
      Future<void> expectHostSearches(
        String step, {
        required bool expectAlpha,
      }) async {
        final host = tester
            .element(find.byType(TeamPilotApp))
            .read<WorkspaceSearchHost>();
        host.open();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.byType(WorkspaceSearchDialog),
          findsOneWidget,
          reason: '$step: dialog must open',
        );

        final dialogField = find.descendant(
          of: find.byType(WorkspaceSearchDialog),
          matching: find.byType(TextField),
        );
        await tester.enterText(dialogField, 'marker_file');
        await tester.pump(const Duration(milliseconds: 400));
        await pumpPhaseTransitions(tester);

        const wanted = 'beta_marker_file.dart';
        const other = 'alpha_marker_file.dart';
        final expectWanted = !expectAlpha;
        expect(
          find.text(expectWanted ? wanted : other),
          findsWidgets,
          reason: '$step: results must come from the active workspace',
        );
        expect(
          find.text(expectWanted ? other : wanted),
          findsNothing,
          reason: '$step: results must not leak the other workspace',
        );

        // Dismiss so the top-level open-guard does not swallow the next open.
        Navigator.of(
          tester.element(find.byType(WorkspaceSearchDialog)),
        ).pop();
        await tester.pump();
        await pumpPhaseTransitions(tester);
        expect(find.byType(WorkspaceSearchDialog), findsNothing,
            reason: '$step: dialog must be closed');
      }

      // Step 1: open tab A — its deferred pane mounts and binds the host.
      appRouter.go('/home-v2/workspace/${workspaceA.workspaceId}');
      await tester.pump();
      await pumpPhaseTransitions(tester);
      await expectHostSearches('after opening A', expectAlpha: true);

      // Step 2: switch to tab B.
      appRouter.go('/home-v2/workspace/${workspaceB.workspaceId}');
      await tester.pump();
      await pumpPhaseTransitions(tester);
      await expectHostSearches('after switching to B', expectAlpha: false);

      // Step 3: back to tab A.
      appRouter.go('/home-v2/workspace/${workspaceA.workspaceId}');
      await tester.pump();
      await pumpPhaseTransitions(tester);
      await expectHostSearches('after switching back to A', expectAlpha: true);

      // Step 4: home round-trip then back to B.
      appRouter.go('/home-v2');
      await tester.pump();
      await pumpPhaseTransitions(tester);
      appRouter.go('/home-v2/workspace/${workspaceB.workspaceId}');
      await tester.pump();
      await pumpPhaseTransitions(tester);
      await expectHostSearches('after home round-trip to B', expectAlpha: false);

      // Step 5: browser-like background open of A, then activate it.
      final scopeCtx = tester.element(find.byType(HomeTabScope));
      HomeTabScope.openInTab(scopeCtx, workspaceA.workspaceId, activate: false);
      await tester.pump();
      await pumpPhaseTransitions(tester);
      HomeTabScope.openInTab(scopeCtx, workspaceA.workspaceId, activate: true);
      await tester.pump();
      await pumpPhaseTransitions(tester);
      await expectHostSearches('after background open + activate A',
          expectAlpha: true);
    },
  );
}
