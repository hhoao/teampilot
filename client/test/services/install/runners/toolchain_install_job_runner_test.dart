import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/install_job/install_cancel_policy.dart';
import 'package:teampilot/models/install_job/install_job_context.dart';
import 'package:teampilot/models/install_job/install_job_key.dart';
import 'package:teampilot/models/install_job/install_job_scope.dart';
import 'package:teampilot/models/install_job/install_job_spec.dart';
import 'package:teampilot/services/cli/git_installer.dart';
import 'package:teampilot/services/install/install_job_keys.dart';
import 'package:teampilot/services/install/runners/toolchain_install_job_runner.dart';

InstallJobSpec<GitInstallResult> _spec(InstallJobKey key) => InstallJobSpec(
  key: key,
  title: 'Install toolchain',
  cancelPolicy: InstallCancelPolicy.cooperative,
  run: (ctx) => throw UnimplementedError(),
);

void main() {
  group('ToolchainInstallJobRunner', () {
    test('supports toolchain git only', () {
      final runner = ToolchainInstallJobRunner(
        installerFactory: () => const GitInstaller(),
      );

      expect(
        runner.supports(
          InstallJobKeys.toolchain('git', scope: const InstallJobScopeLocal()),
        ),
        isTrue,
      );
      expect(
        runner.supports(
          InstallJobKeys.toolchain('node', scope: const InstallJobScopeLocal()),
        ),
        isFalse,
      );
      expect(
        runner.supports(
          InstallJobKeys.cli('claude', scope: const InstallJobScopeLocal()),
        ),
        isFalse,
      );
    });

    test('run installs git and returns GitInstallResult', () async {
      var installCalls = 0;
      bool Function()? capturedCancelled;

      final runner = ToolchainInstallJobRunner(
        installOverride: ({onProgress, isCancelled}) async {
          installCalls++;
          capturedCancelled = isCancelled;
          onProgress?.call(
            const GitInstallProgress(phase: GitInstallPhase.installing),
          );
          return const GitInstallResult.installed('/usr/local/bin/git');
        },
      );

      final key = InstallJobKeys.toolchain('git', scope: const InstallJobScopeLocal());
      final result = await runner.run(_spec(key), InstallJobContext());

      expect(installCalls, 1);
      expect(capturedCancelled, isNotNull);
      expect(result.success, isTrue);
      expect(result.executablePath, '/usr/local/bin/git');
    });

    test('run maps GitInstallProgress to reportPhase labels', () async {
      final reported = <String>[];

      final runner = ToolchainInstallJobRunner(
        installOverride: ({onProgress, isCancelled}) async {
          onProgress?.call(
            const GitInstallProgress(phase: GitInstallPhase.checking),
          );
          onProgress?.call(
            const GitInstallProgress(
              phase: GitInstallPhase.installing,
              detail: 'brew install git',
            ),
          );
          onProgress?.call(
            const GitInstallProgress(phase: GitInstallPhase.locating),
          );
          return const GitInstallResult.installed('/usr/bin/git');
        },
      );

      final key = InstallJobKeys.toolchain('git', scope: const InstallJobScopeLocal());
      await runner.run(
        _spec(key),
        InstallJobContext(
          reportPhase: (label, {detail, fraction}) {
            reported.add(detail == null ? label : '$label|$detail');
          },
        ),
      );

      expect(reported, [
        'Checking git',
        'Installing git|brew install git',
        'Locating git',
      ]);
    });

    test('run throws StateError when install fails', () async {
      final runner = ToolchainInstallJobRunner(
        installOverride: ({onProgress, isCancelled}) async {
          return const GitInstallResult.failed('brew not found');
        },
      );

      final key = InstallJobKeys.toolchain('git', scope: const InstallJobScopeLocal());
      expect(
        () => runner.run(_spec(key), InstallJobContext()),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'brew not found',
          ),
        ),
      );
    });
  });
}
