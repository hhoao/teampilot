import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/cubits/automation_cubit.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/cubits/layout_cubit.dart';
import 'package:teampilot/models/automation.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/pages/automations/automation_editor_dialog.dart';
import 'package:teampilot/router/app_router.dart';
import 'package:teampilot/utils/ui/app_keys.dart';

import '../../support/desktop_app_harness.dart';
import '../../support/fake_terminal_session.dart';
import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';
import '../../support/rust_lib_test_init.dart';

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
    'status-bar popover row opens the editor for a foreign-workspace task',
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
        // Seeded into a DIFFERENT workspace than the active route.
        await testAutomationRepository().upsert(
          Automation(
            id: 'foreign-task',
            name: 'Foreign task',
            action: AutomationAction.launchPrompt,
            workspaceId: 'foreign-ws',
            isPersonal: true,
            presetId: 'preset-1',
            message: 'ping',
            preset: AutomationSchedulePreset.daily,
            hourMinute: '09:00',
            timezone: 'UTC',
            dtstartMs: 1,
            enabled: true,
            nextRunAtMs: DateTime.now()
                .add(const Duration(days: 2))
                .millisecondsSinceEpoch,
            createdAtMs: 1,
            updatedAtMs: 1,
          ),
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

      // The host kicks loadGlobal off unawaited on first build; under fake
      // async that disk read never completes, so force a deterministic
      // snapshot here.
      final cubit = BlocProvider.of<AutomationCubit>(
        tester.element(find.byKey(AppKeys.chatWorkspace)),
      );
      await tester.runAsync(() => cubit.loadGlobal());
      await tester.pump();
      expect(
        cubit.state.globalAutomations.map((a) => a.id),
        contains('foreign-task'),
      );

      await tester.tap(find.byKey(const Key('scheduled-tasks-pill')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Foreign task'), findsOneWidget);

      await tester.tap(find.text('Foreign task'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(AutomationEditorDialog), findsOneWidget);
      final dialog = tester.widget<AutomationEditorDialog>(
        find.byType(AutomationEditorDialog),
      );
      expect(dialog.initial?.id, 'foreign-task');
      expect(dialog.initial?.workspaceId, 'foreign-ws');

      Navigator.of(
        tester.element(find.byType(AutomationEditorDialog)),
      ).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(AutomationEditorDialog), findsNothing);
    },
  );
}
