import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/install_job/install_cancel_policy.dart';
import 'package:teampilot/models/install_job/install_job_cancelled_exception.dart';
import 'package:teampilot/models/install_job/install_job_context.dart';
import 'package:teampilot/models/install_job/install_job_key.dart';
import 'package:teampilot/models/install_job/install_job_spec.dart';
import 'package:teampilot/services/install/install_job_keys.dart';
import 'package:teampilot/services/install/runners/hub_clone_install_job_runner.dart';
import 'package:teampilot/services/team/team_clone_service.dart';

InstallJobSpec<CloneResult> _spec(InstallJobKey key) => InstallJobSpec(
  key: key,
  title: 'Clone hub',
  cancelPolicy: InstallCancelPolicy.cooperative,
  run: (ctx) => throw UnimplementedError(),
);

void main() {
  group('parseHubCloneTarget', () {
    test('parses team and expert prefixes', () {
      expect(parseHubCloneTarget('team:alpha').kind, HubCloneTargetKind.team);
      expect(parseHubCloneTarget('team:alpha').hubKey, 'alpha');
      expect(
        parseHubCloneTarget('expert:beta').kind,
        HubCloneTargetKind.expert,
      );
    });

    test('throws for unknown prefix', () {
      expect(
        () => parseHubCloneTarget('unknown:foo'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('HubCloneInstallJobRunner', () {
    test('supports hub clone keys with known prefixes', () {
      final runner = HubCloneInstallJobRunner();

      expect(runner.supports(InstallJobKeys.hubTeam('alpha')), isTrue);
      expect(runner.supports(InstallJobKeys.hubExpert('beta')), isTrue);
      expect(
        runner.supports(
          const InstallJobKey(kind: InstallJobKind.hubClone, target: 'bad:key'),
        ),
        isFalse,
      );
    });

    test('run reports CloneProgress and returns result', () async {
      final reported = <String>[];
      bool Function()? capturedCancelled;

      final runner = HubCloneInstallJobRunner(
        cloneTeam: (hubKey, onProgress, isCancelled) async {
          capturedCancelled = isCancelled;
          expect(hubKey, 'alpha');
          onProgress(const CloneProgress('skill-a', 1, 2));
          onProgress(const CloneProgress('skill-b', 2, 2));
          return const CloneResult(
            teamId: 'team-1',
            installed: CloneDepInstallSummary(skillIds: ['skill-a']),
            failedDeps: [],
          );
        },
      );

      final result = await runner.run(
        _spec(InstallJobKeys.hubTeam('alpha')),
        InstallJobContext(
          reportPhase: (label, {detail, fraction}) => reported.add(label),
          reportItems: ({required completed, required total}) {
            reported.add('items:$completed/$total');
          },
        ),
      );

      expect(result.teamId, 'team-1');
      expect(reported, [
        'skill-a',
        'items:1/2',
        'skill-b',
        'items:2/2',
      ]);
      expect(capturedCancelled, isNotNull);
      expect(capturedCancelled!(), isFalse);
    });

    test('run routes expert targets to expert invoker', () async {
      final runner = HubCloneInstallJobRunner(
        cloneExpert: (hubKey, onProgress, isCancelled) async {
          expect(hubKey, 'beta');
          return const CloneResult(
            teamId: 'team-2',
            installed: CloneDepInstallSummary(),
            failedDeps: [],
          );
        },
      );

      final result = await runner.run(
        _spec(InstallJobKeys.hubExpert('beta')),
        InstallJobContext(),
      );
      expect(result.teamId, 'team-2');
    });

    test('run throws when cancelled cooperatively', () async {
      final runner = HubCloneInstallJobRunner(
        cloneTeam: (hubKey, onProgress, isCancelled) async {
          return const CloneResult(
            teamId: 'team-1',
            installed: CloneDepInstallSummary(),
            failedDeps: [],
          );
        },
      );
      final ctx = InstallJobContext();
      final key = InstallJobKeys.hubTeam('alpha');
      final future = runner.run(_spec(key), ctx);
      ctx.requestCancel();

      await expectLater(future, throwsA(isA<InstallJobCancelledException>()));
    });

    test('invoker observes cancellation between clone steps', () async {
      var checks = 0;
      final runner = HubCloneInstallJobRunner(
        runOverride: (hubKey, onProgress, isCancelled) async {
          onProgress(const CloneProgress('step-1', 1, 2));
          expect(isCancelled(), isFalse);
          checks++;
          return const CloneResult(
            teamId: 'team-1',
            installed: CloneDepInstallSummary(),
            failedDeps: [],
          );
        },
      );
      final ctx = InstallJobContext();
      await runner.run(_spec(InstallJobKeys.hubTeam('alpha')), ctx);
      expect(checks, 1);
    });
  });
}
