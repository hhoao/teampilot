import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/simple_launch_identity.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';
import 'package:teampilot/services/team_generation/models/team_generation_job.dart';
import 'package:teampilot/services/team_generation/models/team_generation_launch.dart';
import 'package:teampilot/services/team_generation/team_generation_job_store.dart';
import 'package:teampilot/services/team_generation/team_generation_recovery_service.dart';
import 'package:teampilot/services/team_generation/team_generation_session_port.dart';

import '../../support/in_memory_filesystem.dart';

class _RecordingPort implements TeamGenerationSessionPort {
  final events = <String>[];

  @override
  Future<SessionPortOpenResult> createBuilder({
    required Workspace workspace,
    required SimpleLaunchIdentity identity,
    required String projectFolderPath,
    required String workingDirectoryPath,
    required String workflowId,
    required String fixedSessionId,
    required String expertKey,
    String emptyDisplayTitleFallback = 'Team Builder',
    bool preserveWorkbenchView = true,
  }) async => const SessionPortOpenResult(status: 'opened');

  @override
  Future<SessionPortOpenResult> createDestination({
    required Workspace workspace,
    required TeamProfile team,
    required String projectFolderPath,
    required String workingDirectoryPath,
    required String fixedSessionId,
  }) async => const SessionPortOpenResult(status: 'opened');

  @override
  Future<SessionPortOpenResult> open(String sessionId) async {
    events.add('open:$sessionId');
    return SessionPortOpenResult(status: 'opened', sessionId: sessionId);
  }

  @override
  Future<void> select(String sessionId) async {}

  @override
  Future<AppSession?> sessionById(String sessionId) async =>
      AppSession(sessionId: sessionId, workspaceId: 'ws', createdAt: 1);

  @override
  Future<void> waitForInputReady(
    String sessionId,
    String memberId, {
    required bool directToPty,
  }) async {
    events.add('ready:$sessionId:$memberId');
  }

  @override
  Future<void> persistHistoryPending(
    String sessionId,
    String memberId,
    String text, {
    required String deliveryId,
  }) async {
    events.add('history:$sessionId:$memberId:$deliveryId:$text');
  }

  @override
  Future<PortDeliveryOutcome> deliverTracked(
    String sessionId,
    String memberId,
    String text, {
    required bool directToPty,
    required String deliveryId,
  }) async {
    events.add('deliver:$sessionId:$memberId:$deliveryId:$text');
    return const PortDeliveryOutcome(result: 'submitted');
  }

  @override
  Future<bool> deleteBuilder(String sessionId, String workflowId) async => true;

  @override
  Stream<PortActivity> activityStream(String sessionId) => const Stream.empty();
}

class _RecordingForwarder implements TeamGenerationRecoveryForwarder {
  final events = <String>[];

  @override
  Future<void> commitForward(
    TeamGenerationJob job, {
    required bool retainBuilder,
  }) async {
    events.add('commit:${job.workflowId}:retain=$retainBuilder');
  }

  @override
  Future<void> launchForward(TeamGenerationJob job) async {
    events.add('launch:${job.workflowId}');
  }

  @override
  Future<void> cleanupForward(TeamGenerationJob job) async {
    events.add('cleanup:${job.workflowId}');
  }
}

Future<TeamGenerationJobStore> _seedRecoveryJob({
  required InMemoryFilesystem fs,
  required String workflowId,
  required TeamGenerationPhase phase,
  required Map<String, TeamGenerationReceipt> receipts,
}) async {
  final store = TeamGenerationJobStore(
    fs: fs,
    layout: WorkspaceLayout(teampilotRoot: '/tp', fs: fs),
  );
  final settings = resolveTeamGenerationSettingsSnapshot(
    settings: TeamGenerationSettings(teamMode: TeamMode.mixed),
    presets: const <CliPreset>[],
    registry: CliToolRegistry.builtIn(),
    capturedAt: 1,
  );
  await store.create(
    workspaceId: 'ws',
    workflowId: workflowId,
    builderSessionId: 'builder-$workflowId',
    originalPrompt: 'Plan the release',
    generator: TeamGenerationJobGenerator.fromSettings(settings),
    settings: settings,
    launch: const TeamGenerationLaunchSnapshot(
      projectFolderPath: '/proj',
      workingDirectoryPath: '/proj',
      launchSecurityPolicyValue: 'cliDefault',
      folderIds: <String>[],
      targetIds: <String>['local'],
      workspaceRevision: '',
      capturedAt: 1,
    ),
  );
  await store.mutate('ws', workflowId, (job) {
    return job.copyWith(
      phase: phase,
      destinationSessionId:
          receipts['destination']?.state == TeamGenerationReceiptState.succeeded
          ? 'destination-$workflowId'
          : '',
      receipts: receipts,
    );
  });
  return store;
}

void main() {
  test(
    'recovery replays a crash after builder history seed before delivery',
    () async {
      final fs = InMemoryFilesystem();
      final store = TeamGenerationJobStore(
        fs: fs,
        layout: WorkspaceLayout(teampilotRoot: '/tp', fs: fs),
      );
      const workflowId = 'workflow-12345678';
      const builderSessionId = 'teamgen-builder-955fd54dbf2634e37179';
      final settings = resolveTeamGenerationSettingsSnapshot(
        settings: TeamGenerationSettings(teamMode: TeamMode.mixed),
        presets: const <CliPreset>[],
        registry: CliToolRegistry.builtIn(),
        capturedAt: 1,
      );
      await store.create(
        workspaceId: 'ws',
        workflowId: workflowId,
        builderSessionId: builderSessionId,
        originalPrompt: 'Plan the release',
        generator: TeamGenerationJobGenerator.fromSettings(settings),
        settings: settings,
        launch: const TeamGenerationLaunchSnapshot(
          projectFolderPath: '/proj',
          workingDirectoryPath: '/proj',
          launchSecurityPolicyValue: 'cliDefault',
          folderIds: <String>[],
          targetIds: <String>['local'],
          workspaceRevision: '',
          capturedAt: 1,
        ),
      );
      final port = _RecordingPort();
      final recovery = TeamGenerationRecoveryService(
        jobStore: store,
        sessionPort: port,
        forwarder: _RecordingForwarder(),
      );

      await recovery.recoverWorkspace('ws');

      final kickoff = buildTeamGenerationKickoff('Plan the release');
      final kickoffId = teamGenerationStableId('teamgen-kickoff-', workflowId);
      expect(port.events, [
        'open:$builderSessionId',
        'ready:$builderSessionId:$builderSessionId',
        'history:$builderSessionId:$builderSessionId:$kickoffId:$kickoff',
        'deliver:$builderSessionId:$builderSessionId:$kickoffId:$kickoff',
      ]);
      final recovered = await store.read('ws', workflowId);
      expect(recovered!.phase, TeamGenerationPhase.planning);
      expect(recovered.receipts['builderKickoff']!.value, kickoffId);

      await recovery.recoverWorkspace('ws');
      expect(
        port.events.where((event) => event.startsWith('history:')),
        hasLength(1),
      );
      expect(
        port.events.where((event) => event.startsWith('deliver:')),
        hasLength(1),
      );
    },
  );

  test(
    'recovery executes durable commit launch and cleanup forwards',
    () async {
      final fs = InMemoryFilesystem();
      const succeeded = TeamGenerationReceipt(
        state: TeamGenerationReceiptState.succeeded,
      );
      final cases =
          <
            ({
              String workflowId,
              TeamGenerationPhase phase,
              Map<String, TeamGenerationReceipt> receipts,
            })
          >[
            (
              workflowId: 'workflow-retain-12345678',
              phase: TeamGenerationPhase.committing,
              receipts: const {'finalizeAccepted': succeeded},
            ),
            (
              workflowId: 'workflow-commit-12345678',
              phase: TeamGenerationPhase.committing,
              receipts: const {
                'finalizeAccepted': succeeded,
                'finalizeResponseFlushed': succeeded,
              },
            ),
            (
              workflowId: 'workflow-launch-12345678',
              phase: TeamGenerationPhase.committing,
              receipts: const {'profile': succeeded},
            ),
            (
              workflowId: 'workflow-cleanup-12345678',
              phase: TeamGenerationPhase.delivered,
              receipts: const {
                'profile': succeeded,
                'destination': succeeded,
                'finalizeResponseFlushed': succeeded,
                'promptDeliveryDelivered': succeeded,
              },
            ),
          ];
      TeamGenerationJobStore? store;
      for (final recoveryCase in cases) {
        store = await _seedRecoveryJob(
          fs: fs,
          workflowId: recoveryCase.workflowId,
          phase: recoveryCase.phase,
          receipts: recoveryCase.receipts,
        );
      }
      final forwarder = _RecordingForwarder();
      final recovery = TeamGenerationRecoveryService(
        jobStore: store!,
        sessionPort: _RecordingPort(),
        forwarder: forwarder,
      );

      await recovery.recoverWorkspace('ws');

      expect(
        forwarder.events,
        unorderedEquals(const [
          'commit:workflow-retain-12345678:retain=true',
          'commit:workflow-commit-12345678:retain=false',
          'launch:workflow-launch-12345678',
          'cleanup:workflow-cleanup-12345678',
        ]),
      );
    },
  );
}
