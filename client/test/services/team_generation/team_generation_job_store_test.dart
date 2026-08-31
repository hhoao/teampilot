import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';
import 'package:teampilot/services/team_generation/models/team_generation_job.dart';
import 'package:teampilot/services/team_generation/models/team_generation_launch.dart';
import 'package:teampilot/services/team_generation/team_generation_authorizer.dart';
import 'package:teampilot/services/team_generation/team_generation_job_store.dart';
import 'package:teampilot/services/team_generation/team_generation_workflow_executor.dart';

import '../../support/in_memory_filesystem.dart';

TeamGenerationJobGenerator generatorSnapshot() {
  final settings = TeamGenerationSettings(teamMode: TeamMode.mixed);
  final snapshot = resolveTeamGenerationSettingsSnapshot(
    settings: settings,
    presets: const [],
    registry: _emptyRegistry(),
    capturedAt: 42,
  );
  return TeamGenerationJobGenerator.fromSettings(snapshot);
}

TeamGenerationSettingsSnapshot settingsSnapshot() {
  return resolveTeamGenerationSettingsSnapshot(
    settings: TeamGenerationSettings(teamMode: TeamMode.mixed),
    presets: const [],
    registry: _emptyRegistry(),
    capturedAt: 42,
  );
}

TeamGenerationLaunchSnapshot launchSnapshot() {
  return TeamGenerationLaunchSnapshot(
    projectFolderPath: '/proj',
    workingDirectoryPath: '/proj',
    launchSecurityPolicyValue: 'fullAccess',
    folderIds: const ['f1'],
    targetIds: const ['local'],
    workspaceRevision: 'ws-rev-1',
    capturedAt: 1000,
  );
}

TeamGenerationJobStore buildJobStore({
  InMemoryFilesystem? fs,
  DateTime Function()? clock,
}) {
  final filesystem = fs ?? InMemoryFilesystem();
  return TeamGenerationJobStore(
    fs: filesystem,
    layout: WorkspaceLayout(teampilotRoot: '/tp', fs: filesystem),
    clock: clock ?? () => DateTime.utc(2026, 8, 31),
  );
}

Future<TeamGenerationJob> seedCreatedJob(
  TeamGenerationJobStore store, {
  String workspaceId = 'ws',
  String workflowId = 'wf',
  String builderSessionId = 'builder-1',
}) {
  return store.create(
    workspaceId: workspaceId,
    workflowId: workflowId,
    originalPrompt: 'exact\nrequest',
    builderSessionId: builderSessionId,
    generator: generatorSnapshot(),
    settings: settingsSnapshot(),
    launch: launchSnapshot(),
  );
}

class _FakeSessionLookup implements TeamGenerationSessionLookup {
  _FakeSessionLookup(this.sessions);

  final Map<String, AppSession> sessions;

  @override
  Future<AppSession?> findById(String sessionId) async => sessions[sessionId];
}

void main() {
  group('job store', () {
    test('job round-trips prompt, snapshot, phase, and receipts', () async {
      final store = buildJobStore(clock: () => DateTime.utc(2026, 8, 31));
      final created = await seedCreatedJob(store);

      expect(created.originalPrompt, 'exact\nrequest');

      await store.mutate('ws', 'wf', (job) {
        return job.copyWith(
          phase: TeamGenerationPhase.committing,
          receipts: {
            ...job.receipts,
            'profile': const TeamGenerationReceipt(
              state: TeamGenerationReceiptState.succeeded,
              value: 'team-1',
            ),
          },
        );
      });

      final loaded = await store.read('ws', 'wf');
      expect(loaded, isNotNull);
      expect(loaded!.settings.revision, created.settings.revision);
      expect(loaded.phase, TeamGenerationPhase.committing);
      expect(loaded.receipts['profile']!.value, 'team-1');
      expect(loaded.generator.settingsRevision, created.generator.settingsRevision);
      expect(loaded.generator.isEmpty, isFalse);
    });

    test('rejects phase regression and receipt value replacement', () async {
      final store = buildJobStore();
      await seedCreatedJob(store);
      await store.mutate('ws', 'wf', (job) {
        return job.copyWith(
          phase: TeamGenerationPhase.launching,
          receipts: {
            'profile': const TeamGenerationReceipt(
              state: TeamGenerationReceiptState.succeeded,
              value: 'team-1',
            ),
          },
        );
      });

      await expectLater(
        store.mutate('ws', 'wf', (job) {
          return job.copyWith(
            phase: TeamGenerationPhase.planning,
            receipts: {
              ...job.receipts,
              'profile': const TeamGenerationReceipt(
                state: TeamGenerationReceiptState.succeeded,
                value: 'team-2',
              ),
            },
          );
        }),
        throwsA(isA<StateError>()),
      );
    });

    test('workflow ids cannot escape the workspace generation directory', () {
      final fs = InMemoryFilesystem();
      final layout = WorkspaceLayout(teampilotRoot: '/tp', fs: fs);
      expect(
        () => layout.teamGenerationJobFile('ws', '../other'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => layout.teamGenerationJobFile('ws', 'a/b'),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        layout.teamGenerationJobFile('ws', 'wf-1'),
        '/tp/workspace/workspaces/ws/team-generation/wf-1/job.json',
      );
    });

    test('recoverable failure resumes only its recorded safe phase', () async {
      final store = buildJobStore();
      await seedCreatedJob(store);
      await store.mutate('ws', 'wf', (job) {
        return job.copyWith(
          phase: TeamGenerationPhase.failed,
          resumePhase: TeamGenerationPhase.validating,
          error: const TeamGenerationJobError(code: 'boom'),
        );
      });

      final resumed = await store.resumeFailed('ws', 'wf');
      expect(resumed.phase, TeamGenerationPhase.validating);
      expect(resumed.error, isNull);
    });

    test('pre-commit cancel blocks new effects and removes directory last',
        () async {
      final store = buildJobStore();
      await seedCreatedJob(store);

      await store.beginCancel('ws', 'wf');

      final cancelled = await store.read('ws', 'wf');
      expect(cancelled!.phase, TeamGenerationPhase.cancelled);
      await expectLater(
        store.resumeFailed('ws', 'wf'),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        store.reserveEffect('ws', 'wf', 'late-effect'),
        throwsA(isA<StateError>()),
      );

      await store.recordReceipt(
        'ws',
        'wf',
        'builderDeleted',
        const TeamGenerationReceipt(
          state: TeamGenerationReceiptState.succeeded,
          value: 'builder-1',
        ),
      );
      await store.recordReceipt(
        'ws',
        'wf',
        'stagingDeleted',
        const TeamGenerationReceipt(
          state: TeamGenerationReceiptState.succeeded,
          value: 'ok',
        ),
      );

      await store.deleteCancelled('ws', 'wf');
      expect(await store.read('ws', 'wf'), isNull);
    });

    test('complete scrubs sensitive data and prunes by age and count',
        () async {
      var now = DateTime.utc(2026, 8, 31);
      final store = buildJobStore(clock: () => now);

      for (var i = 0; i < 102; i++) {
        final id = 'wf-$i';
        await seedCreatedJob(store, workflowId: id);
        // Advance to delivered first, then finish through cleanup so the
        // monotonic transition rule stays honored.
        await store.mutate('ws', id, (job) {
          return job.copyWith(phase: TeamGenerationPhase.delivering);
        });
        await store.mutate('ws', id, (job) {
          return job.copyWith(phase: TeamGenerationPhase.delivered);
        });
        await store.mutate('ws', id, (job) {
          return job.copyWith(phase: TeamGenerationPhase.cleaning);
        });
        await store.mutate('ws', id, (job) {
          return job.copyWith(
            phase: TeamGenerationPhase.complete,
            teamId: 'team-$i',
            destinationSessionId: 'dest-$i',
          );
        });
        now = now.subtract(const Duration(days: 1));
      }

      await store.compactComplete('ws', 'wf-101');

      final jobs = await store.listAll('ws');
      expect(jobs.length, 100);
      expect(
        jobs.every((job) => job.originalPrompt.isEmpty),
        isTrue,
      );
      expect(
        jobs.every(
          (job) => job.normalizedPlanJson == null && job.probeSnapshotJson == null,
        ),
        isTrue,
      );
      expect(jobs.every((job) => job.stagedResources.isEmpty), isTrue);
      expect(jobs.every((job) => job.generator.isEmpty), isTrue);
    });
  });

  group('workflow executor', () {
    test('serializes mutations and preserves order', () async {
      final executor = TeamGenerationWorkflowExecutor();
      final events = <String>[];

      final first = executor.run('ws', 'wf', () async {
        events.add('a-start');
        await Future<void>.delayed(const Duration(milliseconds: 5));
        events.add('a-end');
      });
      final second = executor.run('ws', 'wf', () async {
        events.add('b-start');
      });
      await Future.wait([first, second]);
      expect(events, ['a-start', 'a-end', 'b-start']);

      await executor.run('ws', 'other', () async {
        events.add('c-start');
      });
      expect(events, ['a-start', 'a-end', 'b-start', 'c-start']);
    });

    test('cancel waits for an admitted effect and later effects see cancelled',
        () async {
      final executor = TeamGenerationWorkflowExecutor();
      final store = buildJobStore();
      await seedCreatedJob(store);
      final events = <String>[];
      final release = Completer<void>();

      final first = executor.run('ws', 'wf', () async {
        events.add('effect-start');
        await release.future;
        events.add('effect-end');
      });
      final cancel = executor.run('ws', 'wf', () async {
        await store.beginCancel('ws', 'wf');
        events.add('cancelled');
      });
      final lateEffect = executor.run('ws', 'wf', () async {
        await store.reserveEffect('ws', 'wf', 'late');
        events.add('late-ran');
      });
      release.complete();
      await first;
      await cancel;
      await expectLater(lateEffect, throwsA(isA<StateError>()));
      expect(events, ['effect-start', 'effect-end', 'cancelled']);
    });
  });

  group('authorizer', () {
    test('authorizes only the persisted builder session and one live token',
        () async {
      final fs = InMemoryFilesystem();
      final store = buildJobStore(fs: fs);
      await seedCreatedJob(store, builderSessionId: 'builder');
      final sessions = <String, AppSession>{
        'builder': AppSession(
          sessionId: 'builder',
          workspaceId: 'ws',
          purpose: SessionPurpose.teamGeneration,
          workflowId: 'wf',
          createdAt: 1,
        ),
        'normal': AppSession(
          sessionId: 'normal',
          workspaceId: 'ws',
          createdAt: 1,
        ),
      };
      final auth = TeamGenerationAuthorizer(
        sessionLookup: _FakeSessionLookup(sessions),
        jobStore: store,
        tokenFactory: () => 'token-1',
      );
      const principal = TeamGenerationPrincipal(
        sessionId: 'builder',
        workspaceId: 'ws',
        workflowId: 'wf',
      );

      final token = await auth.issue(principal);
      expect(token, 'token-1');

      expect(
        await auth.authorize(principal: principal, token: token),
        isTrue,
      );
      expect(
        await auth.authorize(
          principal: const TeamGenerationPrincipal(
            sessionId: 'normal',
            workspaceId: 'ws',
            workflowId: 'wf',
          ),
          token: token,
        ),
        isFalse,
      );
      expect(
        await auth.authorize(principal: principal, token: 'wrong'),
        isFalse,
      );

      // Re-issue with a new token factory value rotates the live token.
      final rotating = TeamGenerationAuthorizer(
        sessionLookup: _FakeSessionLookup(sessions),
        jobStore: store,
        tokenFactory: (() {
          var n = 0;
          return () => 'token-${++n}';
        })(),
      );
      const wfPrincipal = TeamGenerationPrincipal(
        sessionId: 'builder',
        workspaceId: 'ws',
        workflowId: 'wf',
      );
      final first = await rotating.issue(wfPrincipal);
      final second = await rotating.issue(wfPrincipal);
      expect(first, isNot(second));
      expect(
        await rotating.authorize(principal: wfPrincipal, token: first),
        isFalse,
      );
      expect(
        await rotating.authorize(principal: wfPrincipal, token: second),
        isTrue,
      );
    });
  });
}

// Minimal stand-in: the real registry is exercised by settings tests.
CliToolRegistry _emptyRegistry() => CliToolRegistry.builtIn();
