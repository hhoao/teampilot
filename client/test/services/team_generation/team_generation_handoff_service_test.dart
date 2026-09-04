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
  String destinationStatus = 'opened';
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
    if (destinationStatus == 'opened') {
      knownSessions.add(fixedSessionId);
    }
    return SessionPortOpenResult(status: destinationStatus);
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

class _ResultCommands implements PromptDeliveryCommands {
  _ResultCommands(this.result);

  PromptSubmissionResult result;
  int submits = 0;

  @override
  Future<void> stage(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  }) async {}

  @override
  Future<PromptSubmissionResult> submit(
    PromptDelivery delivery, {
    required bool Function() canExecute,
    bool Function()? isAcked,
  }) async {
    submits++;
    return result;
  }
}

void main() {
  late InMemoryFilesystem fs;
  late TeamGenerationJobStore store;
  late _FakePort port;
  late MemoryPromptDeliveryStore promptStore;
  late TeamGenerationHandoffService service;

  TeamGenerationHandoffService serviceWith(PromptDeliveryCommands commands) =>
      TeamGenerationHandoffService(
        jobStore: store,
        sessionPort: port,
        promptCoordinator: PromptDeliveryCoordinator(
          store: promptStore,
          commands: commands,
        ),
        promptStore: promptStore,
      );

  Future<String> reserveDelivery(PromptDeliveryState state) async {
    final destinationId = teamGenerationStableId('teamgen-', 'wf');
    port.knownSessions.add(destinationId);
    final deliveryId = teamGenerationStableId('teamgen-prompt-0-', 'wf');
    await promptStore.save(
      PromptDelivery(
        id: deliveryId,
        seat: RuntimeSeatKey(sessionId: destinationId, memberId: 'team-lead'),
        cli: CliTool.claude,
        text: 'exact\nrequest',
        normalizedText: 'exact request',
        promptEpoch: 1,
        state: state,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        failureReason: state == PromptDeliveryState.failed ? 'failed' : null,
      ),
    );
    await store.mutate('ws', 'wf', (job) {
      return job.copyWith(
        receipts: {
          ...job.receipts,
          'promptDelivery': TeamGenerationReceipt(
            state: TeamGenerationReceiptState.reserved,
            value: deliveryId,
          ),
        },
      );
    });
    return deliveryId;
  }

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
    'failed delivery reserves a genuinely new id for the next attempt',
    () async {
      final failedId = await reserveDelivery(PromptDeliveryState.failed);
      final commands = _ResultCommands(PromptSubmissionResult.submitted);
      final retryingService = serviceWith(commands);

      await expectLater(
        retryingService.handoff(
          workspace: workspace(),
          team: team(),
          workflowId: 'wf',
        ),
        throwsStateError,
      );
      final afterFailure = (await store.read('ws', 'wf'))!;
      final nextId = afterFailure.receipts['promptDelivery']!.value;
      expect(afterFailure.attempt, 1);
      expect(nextId, isNot(failedId));

      final retried = await retryingService.handoff(
        workspace: workspace(),
        team: team(),
        workflowId: 'wf',
      );
      expect(retried.deliveryId, nextId);
      expect(commands.submits, 1);
    },
  );

  test('submit failure lets the next call use the replacement id', () async {
    final commands = _ResultCommands(PromptSubmissionResult.failed);
    final retryingService = serviceWith(commands);

    await expectLater(
      retryingService.handoff(
        workspace: workspace(),
        team: team(),
        workflowId: 'wf',
      ),
      throwsStateError,
    );
    final afterFailure = (await store.read('ws', 'wf'))!;
    final failedId = teamGenerationStableId('teamgen-prompt-0-', 'wf');
    final replacementId = afterFailure.receipts['promptDelivery']!.value;
    expect(afterFailure.attempt, 1);
    expect(replacementId, isNot(failedId));

    commands.result = PromptSubmissionResult.submitted;
    final retried = await retryingService.handoff(
      workspace: workspace(),
      team: team(),
      workflowId: 'wf',
    );

    expect(retried.deliveryId, replacementId);
    expect(commands.submits, 2);
  });

  for (final ambiguousState in const [
    PromptDeliveryState.submitIssued,
    PromptDeliveryState.submittedUnknown,
  ]) {
    test(
      '$ambiguousState is never replayed without a succeeded receipt',
      () async {
        final deliveryId = await reserveDelivery(ambiguousState);
        final commands = _ResultCommands(PromptSubmissionResult.submitted);

        await expectLater(
          serviceWith(
            commands,
          ).handoff(workspace: workspace(), team: team(), workflowId: 'wf'),
          throwsA(
            isA<PromptDeliveryUnknownException>().having(
              (error) => error.deliveryId,
              'deliveryId',
              deliveryId,
            ),
          ),
        );

        expect(commands.submits, 0);
        expect(port.historySeedCalls, isEmpty);
        final job = await store.read('ws', 'wf');
        expect(job!.receipts['promptDeliveryDelivered'], isNull);
      },
    );
  }

  test('a dropped submit stays unknown and never records delivered', () async {
    final commands = _ResultCommands(PromptSubmissionResult.dropped);

    await expectLater(
      serviceWith(
        commands,
      ).handoff(workspace: workspace(), team: team(), workflowId: 'wf'),
      throwsA(isA<PromptDeliveryUnknownException>()),
    );

    final job = await store.read('ws', 'wf');
    expect(job!.receipts['promptDeliveryDelivered'], isNull);
    final deliveryId = job.receipts['promptDelivery']!.value;
    expect(
      (await promptStore.read(deliveryId))!.state,
      PromptDeliveryState.submittedUnknown,
    );
  });

  test(
    'handoff retains leading and trailing original prompt whitespace',
    () async {
      const originalPrompt = '  exact\nrequest  ';
      final originalJob = (await store.read('ws', 'wf'))!;
      await store.create(
        workspaceId: 'ws',
        workflowId: 'wf-whitespace',
        builderSessionId: originalJob.builderSessionId,
        originalPrompt: originalPrompt,
        generator: originalJob.generator,
        settings: originalJob.settings,
        launch: originalJob.launch,
      );
      await store.mutate(
        'ws',
        'wf-whitespace',
        (job) => job.copyWith(
          validatedRevision: 'valid-rev',
          validatedDestinationJson: const {
            'folderId': '/proj',
            'projectFolderPath': '/proj',
            'workingDirectoryPath': '/proj',
            'leadTargetId': 'local',
          },
        ),
      );

      final result = await service.handoff(
        workspace: workspace(),
        team: team(),
        workflowId: 'wf-whitespace',
      );

      expect(port.historyByDeliveryId, {result.deliveryId: originalPrompt});
      expect((await promptStore.read(result.deliveryId))!.text, originalPrompt);
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

  test(
    'missingTeamMember destination keeps the workflow recoverable with builder evidence',
    () async {
      await store.mutate('ws', 'wf', (job) {
        return job.copyWith(
          receipts: {
            ...job.receipts,
            'builderKickoff': const TeamGenerationReceipt(
              state: TeamGenerationReceiptState.succeeded,
              value: 'builder-kickoff',
            ),
          },
        );
      });
      port.destinationStatus = 'missingTeamMember';

      await expectLater(
        service.handoff(workspace: workspace(), team: team(), workflowId: 'wf'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('missingTeamMember'),
          ),
        ),
      );

      final job = (await store.read('ws', 'wf'))!;
      expect(job.isActive, isTrue);
      expect(job.phase, TeamGenerationPhase.launching);
      expect(job.builderSessionId, 'builder');
      expect(
        job.receipts['builderKickoff']!.state,
        TeamGenerationReceiptState.succeeded,
      );
      expect(job.receipts['destination'], isNull);
      expect(port.historySeedCalls, isEmpty);
      expect(port.deliveryCalls, isEmpty);
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
    bool Function()? isAcked,
  }) async => PromptSubmissionResult.submitted;
}
