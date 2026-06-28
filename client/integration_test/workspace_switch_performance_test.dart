@Tags(['performance', 'integration'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:teampilot/cubits/chat_cubit.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/router/app_router.dart';
import 'package:teampilot/services/storage/launch_profile_provisioner.dart';
import 'package:teampilot/utils/app_keys.dart';

import '../test/support/performance_scenario_app.dart';
import '../test/support/post_frame_test_harness.dart';
import '../tool/performance_snapshot/vm_performance_capture.dart';

/// Startup + workspace tab switch scenario for automated performance capture.
///
/// Run:
///   cd client
///   dart run tool/run_workspace_switch_performance.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const outputPath = String.fromEnvironment(
    'PERF_OUTPUT',
    defaultValue: 'build/perf_workspace_switch.json',
  );

  late PerformanceScenarioApp scenario;

  setUp(() async {
    setUpTestAppStorage();
    scenario = await PerformanceScenarioApp.create();
    await scenario.warmCaches();
    resetPerformanceRouterHome();
  });

  tearDown(() {
    tearDownTestAppStorage();
    resetPerformanceRouterHome();
  });

  testWidgets('capture startup and workspace tab switches', (tester) async {
    final teamCubit = await createPerformanceTeamCubit(tester);
    final sessionPreferencesCubit =
        await createPerformanceSessionPreferences(tester);

    final chatCubit = ChatCubit(
      executableResolver: () => performanceTestExecutable,
      terminalSessionFactory:
          ({required String executable, int scrollbackLines = 10000}) =>
              PerformanceFakeTerminalSession(
                executable: executable,
                scrollbackLines: scrollbackLines,
              ),
      sessionRepository: scenario.sessionRepository,
    );

    late final Workspace workspaceA;
    late final Workspace workspaceB;
    await tester.runAsync(() async {
      workspaceA = await scenario.sessionRepository.createWorkspace(
        [WorkspaceFolder(path: '/perf/work-alpha')],
        display: 'Alpha',
      );
      workspaceB = await scenario.sessionRepository.createWorkspace(
        [WorkspaceFolder(path: '/perf/work-beta')],
        display: 'Beta',
      );
      chatCubit.ingestWorkspaceSessionSnapshot(
        workspaces: [workspaceA, workspaceB],
        sessions: const [],
      );
    });

    await pumpPerformanceDesktopApp(
      tester,
      scenario,
      teamCubit: teamCubit,
      sessionPreferencesCubit: sessionPreferencesCubit,
      chatCubit: chatCubit,
    );

    final personalAs = LaunchProfileProvisioner.defaultPersonalId;
    final capture = VmPerformanceCapture();
    await capture.start();

    // Startup: land on home, open first workspace.
    appRouter.go('/home-v2');
    await pumpPerformanceFrames(tester);
    appRouter.go('/home-v2/workspace/${workspaceA.workspaceId}?as=$personalAs');
    await pumpPerformanceFrames(tester);
    expect(find.byKey(AppKeys.chatWorkspace), findsOneWidget);

    // Open second workspace tab, then switch back and forth.
    appRouter.go('/home-v2/workspace/${workspaceB.workspaceId}?as=$personalAs');
    await pumpPerformanceFrames(tester);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);

    await tester.tap(find.text('Alpha'));
    await pumpPerformanceFrames(tester);
    expect(find.byKey(AppKeys.chatWorkspace), findsOneWidget);

    await tester.tap(find.text('Beta'));
    await pumpPerformanceFrames(tester);

    await tester.tap(find.text('Alpha'));
    await pumpPerformanceFrames(tester);

    await tester.tap(find.text('Beta'));
    await pumpPerformanceFrames(tester);

    await capture.stopAndWrite(outputPath);
    expect(File(outputPath).existsSync(), isTrue);

    // ignore: avoid_print
    print('PERF_SNAPSHOT=$outputPath');
  });
}
