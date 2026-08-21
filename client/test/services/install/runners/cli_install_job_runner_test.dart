import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/install_job/install_cancel_policy.dart';
import 'package:teampilot/models/install_job/install_job_context.dart';
import 'package:teampilot/models/install_job/install_job_key.dart';
import 'package:teampilot/models/install_job/install_job_scope.dart';
import 'package:teampilot/models/install_job/install_job_spec.dart';
import 'package:teampilot/models/ssh_profile.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_installer_service.dart';
import 'package:teampilot/services/cli/installer_types.dart';
import 'package:teampilot/services/install/install_job_keys.dart';
import 'package:teampilot/services/install/runners/cli_install_job_runner.dart';

class _FakeCliInstallerService extends CliInstallerService {
  _FakeCliInstallerService(this._handler) : super(isWindowsOverride: false);

  final Future<CliInstallResult> Function({
    required CliTool cli,
    required CliInstallMode mode,
    SshProfile? sshProfile,
    CliInstallProgressCallback? onProgress,
    bool Function()? isCancelled,
    void Function(Process process)? onProcessStarted,
  })
  _handler;

  @override
  Future<CliInstallResult> install({
    required CliTool cli,
    required CliInstallMode mode,
    SshProfile? sshProfile,
    CliInstallProgressCallback? onProgress,
    bool Function()? isCancelled,
    void Function(Process process)? onProcessStarted,
  }) {
    return _handler(
      cli: cli,
      mode: mode,
      sshProfile: sshProfile,
      onProgress: onProgress,
      isCancelled: isCancelled,
      onProcessStarted: onProcessStarted,
    );
  }
}

InstallJobSpec<CliInstallResult> _spec(InstallJobKey key) => InstallJobSpec(
  key: key,
  title: 'Install CLI',
  cancelPolicy: InstallCancelPolicy.cooperative,
  run: (ctx) => throw UnimplementedError(),
);

void main() {
  group('CliInstallJobRunner', () {
    test('supports cliExecutable keys with known CliTool targets', () {
      final runner = CliInstallJobRunner(installerFactory: () => _FakeCliInstallerService(({
        required cli,
        required mode,
        sshProfile,
        onProgress,
        isCancelled,
        onProcessStarted,
      }) async {
        return const CliInstallResult(success: true, message: 'ok');
      }));

      expect(
        runner.supports(
          InstallJobKeys.cli('claude', scope: const InstallJobScopeLocal()),
        ),
        isTrue,
      );
      expect(
        runner.supports(
          InstallJobKeys.toolchain('git', scope: const InstallJobScopeLocal()),
        ),
        isFalse,
      );
      expect(
        runner.supports(
          InstallJobKey(
            kind: InstallJobKind.cliExecutable,
            target: 'unknown-cli',
          ),
        ),
        isFalse,
      );
    });

    test('run installs locally and returns CliInstallResult', () async {
      CliTool? capturedCli;
      CliInstallMode? capturedMode;
      final runner = CliInstallJobRunner(
        installerFactory: () => _FakeCliInstallerService(({
          required cli,
          required mode,
          sshProfile,
          onProgress,
          isCancelled,
          onProcessStarted,
        }) async {
          capturedCli = cli;
          capturedMode = mode;
          return const CliInstallResult(
            success: true,
            message: 'Installed',
            executablePath: '/usr/local/bin/claude',
          );
        }),
      );

      final key = InstallJobKeys.cli('claude', scope: const InstallJobScopeLocal());
      final result = await runner.run(
        _spec(key),
        InstallJobContext(),
      );

      expect(capturedCli, CliTool.claude);
      expect(capturedMode, CliInstallMode.local);
      expect(result.success, isTrue);
      expect(result.executablePath, '/usr/local/bin/claude');
    });

    test('run uses ssh mode when scope is ssh', () async {
      const profile = SshProfile(
        id: 'profile-1',
        name: 'Remote',
        host: 'example.com',
        username: 'dev',
      );
      CliInstallMode? capturedMode;
      SshProfile? capturedProfile;

      final runner = CliInstallJobRunner(
        installerFactory: () => _FakeCliInstallerService(({
          required cli,
          required mode,
          sshProfile,
          onProgress,
          isCancelled,
          onProcessStarted,
        }) async {
          capturedMode = mode;
          capturedProfile = sshProfile;
          return const CliInstallResult(success: true, message: 'ok');
        }),
        sshProfileById: (id) => id == 'profile-1' ? profile : null,
      );

      final key = InstallJobKeys.cli(
        'claude',
        scope: const InstallJobScopeSsh('profile-1'),
      );
      await runner.run(_spec(key), InstallJobContext());

      expect(capturedMode, CliInstallMode.ssh);
      expect(capturedProfile, profile);
    });

    test('run wires cancellation and process registration', () async {
      bool Function()? capturedCancelled;
      void Function(Process process)? capturedOnProcessStarted;

      final runner = CliInstallJobRunner(
        installerFactory: () => _FakeCliInstallerService(({
          required cli,
          required mode,
          sshProfile,
          onProgress,
          isCancelled,
          onProcessStarted,
        }) async {
          capturedCancelled = isCancelled;
          capturedOnProcessStarted = onProcessStarted;
          return const CliInstallResult(success: true, message: 'ok');
        }),
      );

      final ctx = InstallJobContext();
      final key = InstallJobKeys.cli('claude', scope: const InstallJobScopeLocal());
      await runner.run(_spec(key), ctx);

      expect(capturedCancelled, isNotNull);
      expect(capturedCancelled!(), isFalse);
      ctx.requestCancel();
      expect(capturedCancelled!(), isTrue);

      final process = await Process.start('true', []);
      capturedOnProcessStarted!(process);
      await process.exitCode;
    });

    test('run maps CliInstallProgress to reportPhase labels', () async {
      final reported = <String>[];
      final runner = CliInstallJobRunner(
        installerFactory: () => _FakeCliInstallerService(({
          required cli,
          required mode,
          sshProfile,
          onProgress,
          isCancelled,
          onProcessStarted,
        }) async {
          onProgress?.call(
            const CliInstallProgress(phase: CliInstallPhase.checkingNpm),
          );
          onProgress?.call(
            const CliInstallProgress(
              phase: CliInstallPhase.installingCli,
              detail: 'connecting',
            ),
          );
          onProgress?.call(
            const CliInstallProgress(
              phase: CliInstallPhase.installingCli,
              detail: 'added 42 packages',
            ),
          );
          return const CliInstallResult(success: true, message: 'ok');
        }),
      );

      final key = InstallJobKeys.cli('claude', scope: const InstallJobScopeLocal());
      await runner.run(
        _spec(key),
        InstallJobContext(
          reportPhase: (label, {detail, fraction}) {
            reported.add(detail == null ? label : '$label|$detail');
          },
        ),
      );

      expect(reported, [
        'Checking npm',
        'Installing CLI',
        'Installing CLI|added 42 packages',
      ]);
    });

    test('run throws StateError when install fails', () async {
      final runner = CliInstallJobRunner(
        installerFactory: () => _FakeCliInstallerService(({
          required cli,
          required mode,
          sshProfile,
          onProgress,
          isCancelled,
          onProcessStarted,
        }) async {
          return const CliInstallResult(
            success: false,
            message: 'npm install failed',
          );
        }),
      );

      final key = InstallJobKeys.cli('claude', scope: const InstallJobScopeLocal());
      expect(
        () => runner.run(_spec(key), InstallJobContext()),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'npm install failed',
          ),
        ),
      );
    });
  });
}
