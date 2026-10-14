import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:teampilot/cubits/progress_activity_cubit.dart';
import 'package:teampilot/cubits/session_preferences_cubit.dart';
import 'package:teampilot/l10n/app_localizations.dart';
import 'package:teampilot/models/cli_binary_kind.dart';
import 'package:teampilot/models/runtime_target.dart';
import 'package:teampilot/models/session_preferences.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/config/cli_config_section.dart';
import 'package:teampilot/pages/config/cli_readiness_card.dart';
import 'package:teampilot/repositories/session_preferences_repository.dart';
import 'package:teampilot/services/app/connection_mode_service.dart';
import 'package:teampilot/services/cli/cli_installer_service.dart';
import 'package:teampilot/services/cli/cli_version_probe.dart';
import 'package:teampilot/services/cli/registry/installer/npm_installer_capability.dart';
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

class _AdapterInstallerService extends CliInstallerService {
  _AdapterInstallerService(this.installs) : super(isWindowsOverride: false);

  final List<String> installs;

  @override
  Future<CliInstallResult> installAdapter({
    required NpmInstallerCapability installer,
    required CliInstallMode mode,
    sshProfile,
    onProgress,
    isCancelled,
    onProcessStarted,
  }) async {
    installs.add(installer.npmPackage);
    return const CliInstallResult(
      success: true,
      message: 'Adapter installed',
      executablePath: '/bin/claude-agent-acp',
    );
  }
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

/// Avoids real `npm view` when settings cards become visible.
CliVersionProbe _silentProbe() => CliVersionProbe(
  runner: (executable, arguments, {environment, stdoutEncoding, stderrEncoding}) async {
    throw StateError('tests must not spawn $executable $arguments');
  },
);

Future<SessionPreferencesCubit> _makeCubit({
  Map<CliTool, String> locatedExecutables = const {},
  Map<CliTool, String> locatedAcpAdapters = const {},
  Map<String, String> locatedToolchains = const {},
}) async {
  final prefs = await SharedPreferences.getInstance();
  final cubit = SessionPreferencesCubit(
    repository: SessionPreferencesRepository(prefs),
    locatedExecutables: locatedExecutables,
    locatedAcpAdapters: locatedAcpAdapters,
    locatedToolchains: locatedToolchains,
  );
  await cubit.load();
  return cubit;
}

Widget _wrap(
  SessionPreferencesCubit cubit, {
  bool? isAndroidOverride,
  List<String>? adapterInstalls,
}) {
  final progressCubit = ProgressActivityCubit(historyRecorder: _FakeRecorder());
  final registry = InstallJobRegistry(
    progressCubit: progressCubit,
    runnerRegistry: InstallJobRunnerRegistry(
      runners: [
        CliInstallJobRunner(
          installerFactory: () => adapterInstalls != null
              ? _AdapterInstallerService(adapterInstalls)
              : _DelayedCliInstallerService(),
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
          body: CliConfigWorkspace(
            showHeading: false,
            isAndroidOverride: isAndroidOverride,
            versionProbe: _silentProbe(),
          ),
        ),
      ),
    ),
  );
}

Widget _wrapCard(
  SessionPreferencesCubit cubit, {
  CliTool cli = CliTool.claude,
  Future<String?> Function()? locateOverride,
}) {
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
        home: Scaffold(
          body: CliReadinessCard(
            cli: cli,
            cubit: cubit,
            versionProbe: _silentProbe(),
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

  test('readinessChip is Ready when binaries are known with no updates', () {
    expect(
      readinessChip(
        cliKnown: true,
        needsAdapter: true,
        adapterKnown: true,
        cliUpdate: false,
        adapterUpdate: false,
      ),
      CliReadinessChipKind.ready,
    );
  });

  test('readinessChip needs setup when adapter is missing', () {
    expect(
      readinessChip(
        cliKnown: true,
        needsAdapter: true,
        adapterKnown: false,
        cliUpdate: false,
        adapterUpdate: false,
      ),
      CliReadinessChipKind.needsSetup,
    );
  });

  test('isNpmUpdate is string inequality, not semver', () {
    expect(isNpmUpdate(installed: '0.42.0', latest: '0.44.1'), isTrue);
    expect(isNpmUpdate(installed: '0.44.1', latest: '0.44.1'), isFalse);
    expect(isNpmUpdate(installed: null, latest: '0.44.1'), isFalse);
  });

  testWidgets(
    'Ready chip when CLI and adapter paths and versions are known',
    (tester) async {
      final cubit = await _makeCubit(
        locatedExecutables: const {CliTool.claude: '/usr/local/bin/claude'},
        locatedAcpAdapters: const {
          CliTool.claude: '/usr/local/bin/claude-agent-acp',
        },
      );
      addTearDown(cubit.close);
      cubit.mergeBinaryVersion(
        cli: CliTool.claude,
        kind: CliBinaryKind.cli,
        installed: '2.0.0',
        latest: '2.0.0',
      );
      cubit.mergeBinaryVersion(
        cli: CliTool.claude,
        kind: CliBinaryKind.adapter,
        installed: '1.0.0',
        latest: '1.0.0',
      );

      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      expect(find.text('Ready'), findsAtLeastNWidgets(1));
      expect(find.byKey(AppKeys.claudeCliInstallButton), findsNothing);
      expect(find.byKey(AppKeys.claudeCliUpgradeButton), findsNothing);
      expect(find.byKey(AppKeys.claudeAcpAdapterInstallButton), findsNothing);
      expect(find.byKey(AppKeys.claudeAcpAdapterUpgradeButton), findsNothing);
    },
  );

  testWidgets(
    'Needs setup shows adapter Install and Locate and keeps the switch',
    (tester) async {
      final cubit = await _makeCubit(
        locatedExecutables: const {CliTool.claude: '/usr/local/bin/claude'},
      );
      addTearDown(cubit.close);

      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      expect(find.byKey(AppKeys.claudeAcpAdapterInstallButton), findsOneWidget);
      expect(find.byKey(AppKeys.claudeAcpAdapterLocateButton), findsOneWidget);
      expect(find.byKey(AppKeys.claudePersonalAcpSwitch), findsOneWidget);
      expect(find.text('Needs setup'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets(
    'Update available shows Codex CLI Upgrade when npm versions differ',
    (tester) async {
      final cubit = await _makeCubit(
        locatedExecutables: const {CliTool.codex: '/usr/local/bin/codex'},
        locatedAcpAdapters: const {CliTool.codex: '/usr/local/bin/codex-acp'},
      );
      addTearDown(cubit.close);
      cubit.mergeBinaryVersion(
        cli: CliTool.codex,
        kind: CliBinaryKind.cli,
        installed: '0.42.0',
        latest: '0.44.1',
      );

      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      expect(find.byKey(AppKeys.codexCliUpgradeButton), findsOneWidget);
      expect(find.text('Update available'), findsAtLeastNWidgets(1));
    },
  );

  testWidgets(
    'Cursor and OpenCode ACP rows use CLI copy with no adapter install key',
    (tester) async {
      final cubit = await _makeCubit(
        locatedExecutables: const {
          CliTool.cursor: '/usr/local/bin/cursor-agent',
          CliTool.opencode: '/usr/local/bin/opencode',
        },
      );
      addTearDown(cubit.close);

      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(find.textContaining(l10n.cliReadinessUsesCli), findsAtLeastNWidgets(2));
      expect(find.byKey(AppKeys.cursorCliInstallButton), findsNothing);
      expect(find.byKey(AppKeys.opencodeCliInstallButton), findsNothing);
    },
  );

  testWidgets('Gemini has no personal ACP switch', (tester) async {
    final cubit = await _makeCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pump();

    expect(find.byKey(AppKeys.personalAcpSwitchFor(CliTool.gemini)), findsNothing);
    expect(find.byKey(AppKeys.claudePersonalAcpSwitch), findsOneWidget);
  });

  testWidgets('Cursor found has no Upgrade key', (tester) async {
    final cubit = await _makeCubit(
      locatedExecutables: const {CliTool.cursor: '/usr/local/bin/cursor-agent'},
    );
    addTearDown(cubit.close);
    cubit.mergeBinaryVersion(
      cli: CliTool.cursor,
      kind: CliBinaryKind.cli,
      installed: '1.0.0',
      latest: '9.9.9',
    );

    await tester.pumpWidget(_wrap(cubit));
    await tester.pump();

    expect(find.byKey(AppKeys.cursorCliUpgradeButton), findsNothing);
    expect(find.byKey(AppKeys.cursorCliInstallButton), findsNothing);
  });

  testWidgets(
    'Android override disables the switch and hides adapter actions',
    (tester) async {
      final cubit = await _makeCubit(
        locatedExecutables: const {CliTool.claude: '/usr/local/bin/claude'},
      );
      addTearDown(cubit.close);

      await tester.pumpWidget(_wrap(cubit, isAndroidOverride: true));
      await tester.pump();

      final tile = tester.widget<SwitchListTile>(
        find.byKey(AppKeys.claudePersonalAcpSwitch),
      );
      expect(tile.onChanged, isNull);
      expect(
        find.text(
          'ACP chat is desktop-only until remote SSH exec is available.',
        ),
        findsAtLeastNWidgets(1),
      );
      expect(find.byKey(AppKeys.claudeAcpAdapterInstallButton), findsNothing);
      expect(find.byKey(AppKeys.claudeAcpAdapterLocateButton), findsNothing);
    },
  );

  testWidgets(
    'Codex adapter install uses the Codex l10n string and key',
    (tester) async {
      final cubit = await _makeCubit(
        locatedExecutables: const {CliTool.codex: '/usr/local/bin/codex'},
      );
      addTearDown(cubit.close);
      final l10n = lookupAppLocalizations(const Locale('en'));

      await tester.pumpWidget(_wrap(cubit));
      await tester.pump();

      final button = find.byKey(AppKeys.codexAcpAdapterInstallButton);
      expect(button, findsOneWidget);
      expect(
        find.descendant(
          of: button,
          matching: find.text(l10n.codexAcpAdapterInstallButton),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('shows install button when CLI path is unknown', (tester) async {
    final cubit = await _makeCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrap(cubit));
    await tester.pump();

    expect(find.byKey(AppKeys.cursorCliInstallButton), findsOneWidget);
    expect(find.byKey(AppKeys.claudeCliInstallButton), findsOneWidget);
    expect(find.byKey(AppKeys.codexCliInstallButton), findsOneWidget);
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
    expect(
      find.byKey(AppKeys.cliExecutablePathFieldFor(CliTool.cursor)),
      findsOneWidget,
    );
    expect(find.text('/custom/cursor-agent'), findsOneWidget);
  });

  testWidgets('Locate success writes and persists path', (tester) async {
    final cubit = await _makeCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      _wrapCard(cubit, locateOverride: () async => '/found/claude'),
    );
    await tester.pump();
    await tester.tap(find.byKey(AppKeys.claudeCliExecutablePathResetButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(cubit.configuredExecutablePath(CliTool.claude), '/found/claude');
    expect(
      find.byKey(AppKeys.claudeCliExecutablePathField),
      findsOneWidget,
    );
    expect(find.text('/found/claude'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
    AppToast.dismiss();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
  });

  testWidgets('install button uses registry and persists after unmount', (
    tester,
  ) async {
    final cubit = await _makeCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(_wrapCard(cubit));
    await tester.pump();
    await tester.tap(find.byKey(AppKeys.claudeCliInstallButton));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(cubit.configuredExecutablePath(CliTool.claude), '/installed/claude');
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
}
