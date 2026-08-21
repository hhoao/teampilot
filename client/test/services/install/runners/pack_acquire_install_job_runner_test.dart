import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/install_job/install_cancel_policy.dart';
import 'package:teampilot/models/install_job/install_job_cancelled_exception.dart';
import 'package:teampilot/models/install_job/install_job_context.dart';
import 'package:teampilot/models/install_job/install_job_key.dart';
import 'package:teampilot/models/install_job/install_job_scope.dart';
import 'package:teampilot/models/install_job/install_job_spec.dart';
import 'package:teampilot/services/install/install_job_keys.dart';
import 'package:teampilot/services/install/runners/pack_acquire_install_job_runner.dart';

InstallJobSpec<String> _spec(InstallJobKey key) => InstallJobSpec(
  key: key,
  title: 'Install pack',
  cancelPolicy: InstallCancelPolicy.cooperative,
  run: (ctx) => throw UnimplementedError(),
);

void main() {
  group('parsePackAcquireTarget', () {
    test('parses skill, plugin, and extension prefixes', () {
      expect(
        parsePackAcquireTarget('skill:lint').kind,
        PackAcquireTargetKind.skill,
      );
      expect(parsePackAcquireTarget('skill:lint').id, 'lint');
      expect(
        parsePackAcquireTarget('plugin:git').kind,
        PackAcquireTargetKind.plugin,
      );
      expect(
        parsePackAcquireTarget('extension:rtk').kind,
        PackAcquireTargetKind.extension,
      );
    });

    test('throws for unknown prefix', () {
      expect(
        () => parsePackAcquireTarget('unknown:foo'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('PackAcquireInstallJobRunner', () {
    test('supports pack acquire keys with known prefixes', () {
      final runner = PackAcquireInstallJobRunner();

      expect(runner.supports(InstallJobKeys.skill('lint')), isTrue);
      expect(runner.supports(InstallJobKeys.plugin('git')), isTrue);
      expect(runner.supports(InstallJobKeys.extension('rtk')), isTrue);
      expect(
        runner.supports(
          const InstallJobKey(
            kind: InstallJobKind.packAcquire,
            target: 'unknown:foo',
          ),
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

    test('run delegates to skill invoker and reports steps', () async {
      String? capturedId;
      final steps = <String>[];
      bool Function()? capturedCancelled;

      final runner = PackAcquireInstallJobRunner(
        installSkill: (id, onStep, isCancelled) async {
          capturedId = id;
          capturedCancelled = isCancelled;
          onStep(subtitle: 'Downloading', completedSteps: 1, totalSteps: 3);
          onStep(subtitle: 'Registering', completedSteps: 3, totalSteps: 3);
          return 'skill-id';
        },
      );

      final key = InstallJobKeys.skill('lint');
      final result = await runner.run(
        _spec(key),
        InstallJobContext(
          reportPhase: (label, {detail, fraction}) {
            steps.add(detail == null ? label : '$label|$detail');
          },
          reportItems: ({required completed, required total}) {
            steps.add('items:$completed/$total');
          },
        ),
      );

      expect(capturedId, 'lint');
      expect(result, 'skill-id');
      expect(steps, [
        'Downloading',
        'items:1/3',
        'Registering',
        'items:3/3',
      ]);
      expect(capturedCancelled, isNotNull);
      expect(capturedCancelled!(), isFalse);
    });

    test('run routes plugin and extension targets to matching invokers', () async {
      final runner = PackAcquireInstallJobRunner(
        installPlugin: (id, onStep, isCancelled) async => 'plugin:$id',
        installExtension: (id, onStep, isCancelled) async => 'extension:$id',
      );

      expect(
        await runner.run(_spec(InstallJobKeys.plugin('git')), InstallJobContext()),
        'plugin:git',
      );
      expect(
        await runner.run(
          _spec(InstallJobKeys.extension('rtk')),
          InstallJobContext(),
        ),
        'extension:rtk',
      );
    });

    test('run throws when cancelled before start', () async {
      final runner = PackAcquireInstallJobRunner(
        installSkill: (id, onStep, isCancelled) async => id,
      );
      final ctx = InstallJobContext();
      ctx.requestCancel();

      expect(
        () => runner.run(_spec(InstallJobKeys.skill('lint')), ctx),
        throwsA(isA<InstallJobCancelledException>()),
      );
    });

    test('run throws when cancelled after invoker completes', () async {
      final runner = PackAcquireInstallJobRunner(
        installSkill: (id, onStep, isCancelled) async {
          onStep(completedSteps: 1, totalSteps: 1);
          return id;
        },
      );
      final ctx = InstallJobContext();
      final key = InstallJobKeys.skill('lint');
      final future = runner.run(_spec(key), ctx);
      ctx.requestCancel();

      await expectLater(future, throwsA(isA<InstallJobCancelledException>()));
    });

    test('run falls back to spec.run when invoker is not configured', () async {
      final runner = PackAcquireInstallJobRunner();
      final key = InstallJobKeys.skill('lint');
      final spec = InstallJobSpec<String>(
        key: key,
        title: 'Install pack',
        cancelPolicy: InstallCancelPolicy.cooperative,
        run: (ctx) async => 'from-spec',
      );

      expect(await runner.run(spec, InstallJobContext()), 'from-spec');
    });
  });
}
