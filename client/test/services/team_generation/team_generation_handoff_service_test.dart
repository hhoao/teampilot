import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/services/agent_runtime/runtime_event.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_coordinator.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_store.dart';
import 'package:teampilot/models/simple_launch_identity.dart';
import 'package:teampilot/services/team_generation/models/team_generation_job.dart';
import 'package:teampilot/services/team_generation/models/team_generation_launch.dart';
import 'package:teampilot/services/team_generation/team_generation_handoff_service.dart';
import 'package:teampilot/services/team_generation/team_generation_job_store.dart';
import 'package:teampilot/services/team_generation/team_generation_session_port.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../../support/in_memory_filesystem.dart';

class _FakePort implements TeamGenerationSessionPort {
  final createRequests = <String>[];
  final openRequests = <String>[];
  final selected = <String>[];
  final readyCalls = <String>[];
  final deliveryCalls = <String>[];
  final historySeedCalls = <String>[];
  final historyByDeliveryId = <String, String>{};
  final knownSessions = <String>{};

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
  }) async {
    createRequests.add(fixedSessionId);
    knownSessions.add(fixedSessionId);
    return const SessionPortOpenResult(status: 'opened');
  }

  @override
  Future<SessionPortOpenResult> open(String sessionId) async {
    openRequests.add(sessionId);
    return const SessionPortOpenResult(status: 'opened');
  }

  @override
  Future<void> select(String sessionId) async {
    selected.add(sessionId);
  }

  @override
  Future<AppSession?> sessionById(String sessionId) async =>
      knownSessions.contains(sessionId)
      ? AppSession(sessionId: sessionId, workspaceId: 'ws', createdAt: 1)
      : null;

  @override
  Future<void> waitForInputReady(
    String sessionId,
    String memberId, {
    required bool directToPty,
  }) async {
    readyCalls.add('$sessionId/$memberId/$directToPty');
  }

  @override
  Future<void> persistHistoryPending(
    String sessionId,
    String memberId,
    String text, {
    required String deliveryId,
  }) async {
    historySeedCalls.add('$sessionId/$memberId/$deliveryId/$text');
    historyByDeliveryId.putIfAbsent(deliveryId, () => text);
  }

  @override
  Future<PortDeliveryOutcome> deliverTracked(
    String sessionId,
    String memberId,
    String text, {
    required bool directToPty,
    required String deliveryId,
  }) async {
    deliveryCalls.add('$sessionId/$memberId/$deliveryId');
    return const PortDeliveryOutcome(result: 'submitted');
  }

  @override
  Future<bool> deleteBuilder(String sessionId, String workflowId) async => true;

  @override
  Stream<PortActivity> activityStream(String sessionId) => const Stream.empty();
}

void main() {
  late InMemoryFilesystem fs;
  late TeamGenerationJobStore store;
  late _FakePort port;
  late MemoryPromptDeliveryStore promptStore;
  late TeamGenerationHandoffService service;

  Workspace workspace() => Workspace(
    workspaceId: 'ws',
    folders: const [WorkspaceFolder(path: '/proj', targetId: 'local')],
    createdAt: 1,
    updatedAt: 1,
  );

  TeamProfile team() => TeamProfile(
    id: 'generated-team',
    name: 'Generated Team',
    cli: CliTool.claude,
    teamMode: TeamMode.mixed,
    createdAt: 1,
  );

  setUp(() async {
    fs = InMemoryFilesystem();
    store = TeamGenerationJobStore(
      fs: fs,
      layout: WorkspaceLayout(teampilotRoot: '/tp', fs: fs),
    );
    final settings = resolveTeamGenerationSettingsSnapshot(
      settings: TeamGenerationSettings(teamMode: TeamMode.mixed),
      presets: const [],
      registry: CliToolRegistry.builtIn(),
      capturedAt: 42,
    );
    await store.create(
      workspaceId: 'ws',
      workflowId: 'wf',
      builderSessionId: 'builder',
      originalPrompt: 'exact\nrequest',
      generator: TeamGenerationJobGenerator.fromSettings(settings),
      settings: settings,
      launch: const TeamGenerationLaunchSnapshot(
        projectFolderPath: '/proj',
        workingDirectoryPath: '/proj',
        launchSecurityPolicyValue: 'fullAccess',
        folderIds: [],
        targetIds: ['local'],
        workspaceRevision: 'rev-1',
        capturedAt: 1000,
      ),
    );
    await store.mutate('ws', 'wf', (job) {
      return job.copyWith(
        validatedRevision: 'valid-rev',
        validatedDestinationJson: const {
          'folderId': '/proj',
          'projectFolderPath': '/proj',
          'workingDirectoryPath': '/proj',
          'leadTargetId': 'local',
        },
      );
    });
    port = _FakePort();
    promptStore = MemoryPromptDeliveryStore();
    service = TeamGenerationHandoffService(
      jobStore: store,
      sessionPort: port,
      promptCoordinator: PromptDeliveryCoordinator(
        store: promptStore,
        commands: _NoopCommands(),
      ),
      promptStore: promptStore,
    );
  });

  test(
    'seeds the raw original prompt with the reserved delivery id before handoff submit',
    () async {
      final first = await service.handoff(
        workspace: workspace(),
        team: team(),
        workflowId: 'wf',
      );

      expect(port.historySeedCalls, [
        '${first.destinationSessionId}/team-lead/${first.deliveryId}/'
            'exact\nrequest',
      ]);
      expect(port.historyByDeliveryId, {first.deliveryId: 'exact\nrequest'});
      final delivery = await promptStore.read(first.deliveryId);
      expect(delivery!.text, 'exact\nrequest');
      expect(delivery.id, first.deliveryId);

      final resumed = await service.handoff(
        workspace: workspace(),
        team: team(),
        workflowId: 'wf',
      );

      expect(resumed.deliveryId, first.deliveryId);
      expect(port.historyByDeliveryId, {first.deliveryId: 'exact\nrequest'});
      expect(port.historySeedCalls, hasLength(2));
    },
  );

  test(
    'creates one team session, selects it, and delivers exactly once',
    () async {
      final result = await service.handoff(
        workspace: workspace(),
        team: team(),
        workflowId: 'wf',
      );

      expect(port.createRequests, hasLength(1));
      expect(port.createRequests.single, result.destinationSessionId);
      expect(port.selected, [result.destinationSessionId]);
      expect(port.readyCalls.single, endsWith('team-lead/true'));

      final job = await store.read('ws', 'wf');
      expect(job!.phase, TeamGenerationPhase.delivered);
      expect(
        job.receipts['promptDeliveryDelivered']!.state,
        TeamGenerationReceiptState.succeeded,
      );
      expect(job.originalPrompt, 'exact\nrequest');
    },
  );

  test(
    'recovery reuses destination id and does not duplicate sessions',
    () async {
      final first = await service.handoff(
        workspace: workspace(),
        team: team(),
        workflowId: 'wf',
      );
      final createCount = port.createRequests.length;

      final second = await service.handoff(
        workspace: workspace(),
        team: team(),
        workflowId: 'wf',
      );

      expect(second.destinationSessionId, first.destinationSessionId);
      expect(port.createRequests.length, createCount);
    },
  );
}

class _NoopCommands implements PromptDeliveryCommands {
  @override
  Future<void> stage(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  }) async {}

  @override
  Future<PromptSubmissionResult> submit(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  }) async => PromptSubmissionResult.submitted;
}
