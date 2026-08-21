import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/session_preferences.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/config/cli_config_section.dart';
import 'package:teampilot/pages/config/cli_executable_path_settings_row.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';
import 'package:teampilot/services/cli/cli_installer_service.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/install/install_job_registry.dart';
import 'package:teampilot/services/install/install_job_runner_registry.dart';
import 'package:teampilot/services/install/runners/cli_install_job_runner.dart';
import 'package:teampilot/services/notification/notification_recorder.dart';
import 'package:teampilot/utils/ui/app_keys.dart';
import 'package:teampilot/widgets/app_toast/app_toast.dart';

import '../../support/post_frame_test_harness.dart';

class _FakeRecorder implements NotificationRecorder {
  @override
  void record({
    required String message,
    required TpToastVariant variant,
    String title = '',
    String payload = '',
  }) {}
}

class _DelayedCliInstallerService extends CliInstallerService {
  _DelayedCliInstallerService() : super(isWindowsOverride: false);

  @override
  Future<CliInstallResult> install({
    required CliTool cli,
    required CliInstallMode mode,
    sshProfile,
    onProgress,
    isCancelled,
    onProcessStarted,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return CliInstallResult(
      success: true,
      message: 'Installed',
      executablePath: '/installed/${cli.value}',
    );
  }
}

Future<SessionPreferencesCubit> _makeCubit({
  Map<CliTool, String> locatedExecutables = const {},
  Map<String, String> locatedToolchains = const {},
}) async {
  final prefs = await SharedPreferences.getInstance();
  final cubit = SessionPreferencesCubit(
    repository: SessionPreferencesRepository(prefs),
    locatedExecutables: locatedExecutables,
    locatedToolchains: locatedToolchains,
  );
  await cubit.load();
  return cubit;
}

Widget _wrap(SessionPreferencesCubit cubit) {
  final progressCubit = ProgressActivityCubit(historyRecorder: _FakeRecorder());
  final registry = InstallJobRegistry(
    progressCubit: progressCubit,
    runnerRegistry: InstallJobRunnerRegistry(
      runners: [
        CliInstallJobRunner(
          installerFactory: () => _DelayedCliInstallerService(),
        ),
      ],
    ),
  );

  return MultiRepositoryProvider(
    providers: [
      RepositoryProvider<ConnectionModeService>(
        create: (_) => ConnectionModeService(
          defaultTargetResolver: RuntimeTarget.local,
          hasSshProfiles: () => false,
        ),
      ),
      RepositoryProvider<InstallJobRegistry>.value(value: registry),
    ],
    child: BlocProvider.value(
      value: cubit,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: CliConfigWorkspace(showHeading: false),
        ),
      ),
    ),
  );
}

Widget _wrapRow(
  SessionPreferencesCubit cubit, {
  Future<String?> Function()? locateOverride,
  InstallJobRegistry? installJobRegistry,
}) {
  final progressCubit = ProgressActivityCubit(historyRecorder: _FakeRecorder());
  final registry =
      installJobRegistry ??
      InstallJobRegistry(
        progressCubit: progressCubit,
        runnerRegistry: InstallJobRunnerRegistry(
          runners: [
            CliInstallJobRunner(
              installerFactory: () => _DelayedCliInstallerService(),
            ),
          ],
        ),
      );

  return MultiRepositoryProvider(
    providers: [
      RepositoryProvider<ConnectionModeService>(
        create: (_) => ConnectionModeService(
          defaultTargetResolver: RuntimeTarget.local,
          hasSshProfiles: () => false,
        ),
      ),
      RepositoryProvider<InstallJobRegistry>.value(value: registry),
    ],
    child: BlocProvider.value(
      value: cubit,
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CliExecutablePathSettingsRow(
            cubit: cubit,
            cli: CliTool.claude,
            title: 'Claude Code',
            subtitle: 'Path to the Claude Code CLI',
            fieldKey: AppKeys.claudeCliExecutablePathField,
            browseKey: AppKeys.claudeCliExecutablePathBrowseButton,
            resetKey: AppKeys.claudeCliExecutablePathResetButton,
            debouncerTag: 'claude_cli_executable_path_test',
            installKey: AppKeys.claudeCliInstallButton,
            showDividerBelow: false,
            locateOverride: locateOverride,
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    setUpTestAppStorage();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(tearDownTestAppStorage);

  testWidgets('shows install button when CLI path is unknown', (tester) async {
    final cubit = await _makeCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pump();

    expect(find.byKey(AppKeys.cursorCliInstallButton), findsOneWidget);
    expect(find.byKey(AppKeys.claudeCliInstallButton), findsOneWidget);
    expect(find.byKey(AppKeys.codexCliInstallButton), findsOneWidget);
    expect(find.byKey(AppKeys.opencodeCliInstallButton), findsOneWidget);
  });

  testWidgets('hides install button when CLI path is already known', (
    tester,
  ) async {
    final cubit = await _makeCubit(
      locatedExecutables: const {
        CliTool.claude: '/usr/local/bin/claude',
        CliTool.codex: '/usr/local/bin/codex',
        CliTool.opencode: '/usr/local/bin/opencode',
        CliTool.cursor: '/usr/local/bin/cursor-agent',
      },
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pump();

    expect(find.byKey(AppKeys.cursorCliInstallButton), findsNothing);
    expect(find.byKey(AppKeys.claudeCliInstallButton), findsNothing);
    expect(find.byKey(AppKeys.codexCliInstallButton), findsNothing);
    expect(find.byKey(AppKeys.opencodeCliInstallButton), findsNothing);
  });

  testWidgets('hides toolchain install buttons when paths are known', (
    tester,
  ) async {
    final cubit = await _makeCubit(
      locatedToolchains: const {
        SessionPreferences.toolchainGit: '/usr/bin/git',
        SessionPreferences.toolchainNode: '/usr/bin/node',
      },
    );
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pump();

    expect(find.byKey(AppKeys.gitToolchainInstallButton), findsNothing);
    expect(find.byKey(AppKeys.nodeToolchainInstallButton), findsNothing);
  });

  testWidgets('shows Locate when CLI path is empty', (tester) async {
    final cubit = await _makeCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(_wrap(cubit));
    await tester.pump();

    final button = find.byKey(AppKeys.cursorCliExecutablePathResetButton);
    expect(button, findsOneWidget);
    expect(
      find.descendant(of: button, matching: find.text('Locate')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: button, matching: find.text('Reset')),
      findsNothing,
    );
  });

  testWidgets('shows Reset when CLI path is configured', (tester) async {
    final cubit = await _makeCubit();
    addTearDown(cubit.close);
    await cubit.setCliExecutablePathFor(CliTool.cursor, '/custom/cursor-agent');
    await tester.pumpWidget(_wrap(cubit));
    await tester.pump();

    final button = find.byKey(AppKeys.cursorCliExecutablePathResetButton);
    expect(
      find.descendant(of: button, matching: find.text('Reset')),
      findsOneWidget,
    );
  });

  testWidgets('Locate success writes and persists path', (tester) async {
    final cubit = await _makeCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      _wrapRow(cubit, locateOverride: () async => '/found/claude'),
    );
    await tester.pump();
    await tester.tap(find.byKey(AppKeys.claudeCliExecutablePathResetButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(cubit.configuredExecutablePath(CliTool.claude), '/found/claude');
    expect(find.text('Reset'), findsOneWidget);
    AppToast.dismiss();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('Locate failure leaves path empty and keeps Install', (
    tester,
  ) async {
    final cubit = await _makeCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      _wrapRow(cubit, locateOverride: () async => null),
    );
    await tester.pump();
    await tester.tap(find.byKey(AppKeys.claudeCliExecutablePathResetButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(cubit.configuredExecutablePath(CliTool.claude), isEmpty);
    expect(find.text('Locate'), findsOneWidget);
    expect(find.byKey(AppKeys.claudeCliInstallButton), findsOneWidget);
    AppToast.dismiss();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('install button uses registry and persists after unmount', (
    tester,
  ) async {
    final cubit = await _makeCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrapRow(cubit));
    await tester.pump();
    await tester.tap(find.byKey(AppKeys.claudeCliInstallButton));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(cubit.configuredExecutablePath(CliTool.claude), '/installed/claude');
  });
}
