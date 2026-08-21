import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/install_job/install_job_context.dart';
import 'package:teampilot/models/install_job/install_job_key.dart';
import 'package:teampilot/models/install_job/install_job_scope.dart';
import 'package:teampilot/models/install_job/install_job_spec.dart';
import 'package:teampilot/services/install/install_job_keys.dart';
import 'package:teampilot/services/install/install_job_runner.dart';
import 'package:teampilot/services/install/install_job_runner_registry.dart';

class _FakeRunner implements InstallJobRunner {
  _FakeRunner(this._kind);

  final InstallJobKind _kind;

  @override
  InstallJobKind get kind => _kind;

  @override
  bool supports(InstallJobKey key) => key.kind == _kind;

  @override
  Future<T> run<T>(InstallJobSpec<T> spec, InstallJobContext ctx) async {
    throw UnimplementedError();
  }
}

void main() {
  group('InstallJobRunnerRegistry', () {
    test('resolve returns runner matching kind', () {
      final cliRunner = _FakeRunner(InstallJobKind.cliExecutable);
      final toolchainRunner = _FakeRunner(InstallJobKind.toolchain);
      final registry = InstallJobRunnerRegistry(
        runners: [cliRunner, toolchainRunner],
      );

      final cliKey = InstallJobKeys.cli(
        'claude',
        scope: const InstallJobScopeLocal(),
      );
      final toolchainKey = InstallJobKeys.toolchain(
        'node',
        scope: const InstallJobScopeLocal(),
      );

      expect(registry.resolve(cliKey), same(cliRunner));
      expect(registry.resolve(toolchainKey), same(toolchainRunner));
      expect(
        registry.resolve(
          InstallJobKeys.skill('missing-runner'),
        ),
        isNull,
      );
    });
  });

  group('InstallJobKeys', () {
    test('produce expected activityId strings', () {
      expect(
        InstallJobKeys.cli('claude', scope: const InstallJobScopeLocal())
            .activityId,
        'install-cliExecutable-claude-local',
      );
      expect(
        InstallJobKeys.cli(
          'claude',
          scope: const InstallJobScopeSsh('profile-42'),
        ).activityId,
        'install-cliExecutable-claude-ssh-profile-42',
      );
      expect(
        InstallJobKeys.toolchain('node', scope: const InstallJobScopeLocal())
            .activityId,
        'install-toolchain-node-local',
      );
      expect(
        InstallJobKeys.skill('my-skill').activityId,
        'install-packAcquire-skill:my-skill-local',
      );
      expect(
        InstallJobKeys.plugin('my-plugin').activityId,
        'install-packAcquire-plugin:my-plugin-local',
      );
      expect(
        InstallJobKeys.extension('ext-id').activityId,
        'install-packAcquire-extension:ext-id-local',
      );
      expect(
        InstallJobKeys.hubTeam('team-key').activityId,
        'install-hubClone-team:team-key-local',
      );
      expect(
        InstallJobKeys.hubExpert('expert-key').activityId,
        'install-hubClone-expert:expert-key-local',
      );
      expect(
        InstallJobKeys.fileImport('ws-1', 'hash123').activityId,
        'install-fileTreeImport-ws-1:hash123-local',
      );
      expect(
        InstallJobKeys.appUpdate('1.2.3').activityId,
        'install-appUpdate-1.2.3-local',
      );
    });
  });
}
