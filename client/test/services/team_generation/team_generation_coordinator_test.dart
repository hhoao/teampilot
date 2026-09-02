import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/simple_launch_identity.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_topology.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/expert_hub/local_expert_store.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_coordinator.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_store.dart';
import 'package:teampilot/services/team_generation/generated_team_commit_service.dart';
import 'package:teampilot/services/team_generation/generated_team_plan_validator.dart';
import 'package:teampilot/services/team_generation/models/team_generation_job.dart';
import 'package:teampilot/services/team_generation/team_generation_builder_idle_waiter.dart';
import 'package:teampilot/services/team_generation/team_generation_cleanup_service.dart';
import 'package:teampilot/services/team_generation/team_generation_compatibility.dart';
import 'package:teampilot/services/team_generation/team_generation_coordinator.dart';
import 'package:teampilot/services/team_generation/team_generation_handoff_service.dart';
import 'package:teampilot/services/team_generation/team_generation_job_store.dart';
import 'package:teampilot/services/team_generation/team_generation_session_port.dart';
import 'package:teampilot/services/team_generation/team_generation_settings_store.dart';
import 'package:teampilot/services/team_generation/team_target_probe_service.dart';
import 'package:teampilot/services/team_generation/models/team_target_probe.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';

import '../../support/in_memory_filesystem.dart';
import '../../support/post_frame_test_harness.dart';

class _RecordingSessionPort implements TeamGenerationSessionPort {
  final events = <String>[];
  final sessions = <String, AppSession>{};

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
  }) async {
    events.add('builderCreated');
    sessions[fixedSessionId] = AppSession(
      sessionId: fixedSessionId,
      workspaceId: workspace.workspaceId,
      createdAt: 1,
      purpose: SessionPurpose.teamGeneration,
      workflowId: workflowId,
      expertKey: expertKey,
      cli: identity.cli,
    );
    return SessionPortOpenResult(status: 'opened', sessionId: fixedSessionId);
  }

  @override
  Future<SessionPortOpenResult> createDestination({
    required Workspace workspace,
    required TeamProfile team,
    required String projectFolderPath,
    required String workingDirectoryPath,
    required String fixedSessionId,
  }) async {
    events.add('destinationCreated');
    sessions[fixedSessionId] = AppSession(
      sessionId: fixedSessionId,
      workspaceId: workspace.workspaceId,
      createdAt: 1,
      purpose: SessionPurpose.normal,
      sessionTeam: team.id,
    );
    return SessionPortOpenResult(status: 'opened', sessionId: fixedSessionId);
  }

  @override
  Future<SessionPortOpenResult> open(String sessionId) async =>
      SessionPortOpenResult(status: 'opened', sessionId: sessionId);

  @override
  Future<void> select(String sessionId) async {}

  @override
  Future<AppSession?> sessionById(String sessionId) async =>
      sessions[sessionId];

  @override
  Future<void> waitForInputReady(
    String sessionId,
    String memberId, {
    required bool directToPty,
  }) async {}

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
    if (sessionId.startsWith('teamgen-builder-')) {
      events.add('deliverTracked:$sessionId:$memberId:$deliveryId:$text');
    }
    return const PortDeliveryOutcome(result: 'submitted');
  }

  @override
  Future<bool> deleteBuilder(String sessionId, String workflowId) async {
    events.add('builderDeleted');
    sessions.remove(sessionId);
    return true;
  }

  @override
  Stream<PortActivity> activityStream(String sessionId) =>
      Stream.value(PortActivity(sessionId: sessionId, readyToChat: true));
}

class _RecordingPromptCommands implements PromptDeliveryCommands {
  _RecordingPromptCommands(this.events);

  final List<String> events;

  @override
  Future<void> stage(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  }) async {}

  @override
  Future<PromptSubmissionResult> submit(
    PromptDelivery delivery, {
    required bool Function() canExecute,
  }) async {
    events.add('prompt:${delivery.seat.memberId}:${delivery.text}');
    return PromptSubmissionResult.submitted;
  }
}

class _RecordingPublisher implements GeneratedTeamStatePublisher {
  _RecordingPublisher(this.events);

  final List<String> events;

  @override
  Future<void> publish({
    required TeamProfile team,
    required Workspace workspace,
  }) async {
    events.add('profilePersisted:${team.id}');
  }
}

class _RecordingProvisioner implements TeamProfileResourceProvisioner {
  @override
  Future<void> provision(TeamProfile team) async {}
}

class _FakeSessionRepository extends Fake implements SessionRepository {
  @override
  Future<Workspace?> updateWorkspaceMemberPlacement(
    String workspaceId,
    String teamId, {
    required MemberTargetAssignments targets,
  }) async => null;
}

void main() {
  setUp(setUpTestAppStorage);
  tearDown(tearDownTestAppStorage);

  test(
    'runs Builder kickoff, commit, destination handoff, and cleanup in order',
    () async {
      final fs = InMemoryFilesystem();
      final layout = WorkspaceLayout(teampilotRoot: '/tp', fs: fs);
      final jobStore = TeamGenerationJobStore(fs: fs, layout: layout);
      final settingsStore = TeamGenerationSettingsStore(
        fs: fs,
        pathOverride: '/tp/settings.json',
      );
      final port = _RecordingSessionPort();
      final events = port.events;
      final promptStore = MemoryPromptDeliveryStore();
      final promptCoordinator = PromptDeliveryCoordinator(
        store: promptStore,
        commands: _RecordingPromptCommands(events),
      );
      final workspace = Workspace(
        workspaceId: 'ws',
        folders: const [WorkspaceFolder(path: '/proj', targetId: 'local')],
        createdAt: 1,
        updatedAt: 1,
      );
      final preset = CliPreset(
        id: 'generator',
        name: 'Generator',
        cli: CliTool.claude,
        provider: 'official',
        model: 'strong',
        createdAt: 1,
        updatedAt: 1,
      );
      await settingsStore.save(
        TeamGenerationSettings(
          teamMode: TeamMode.mixed,
          modelPool: [GenerateModelPoolEntry(presetId: preset.id)],
        ),
      );
      final compatibility = TeamGenerationCompatibility(
        registry: CliToolRegistry.builtIn(),
      );
      final probeService = TeamTargetProbeService(runner: _EmptyProbeRunner());
      final handoff = TeamGenerationHandoffService(
        jobStore: jobStore,
        sessionPort: port,
        promptCoordinator: promptCoordinator,
        promptStore: promptStore,
      );
      final cleanup = TeamGenerationCleanupService(
        jobStore: jobStore,
        sessionPort: port,
        idleWaiter: TeamGenerationBuilderIdleWaiter(sessionPort: port),
        revokeToken: (_) {},
        quietWindow: Duration.zero,
        idleTimeout: const Duration(seconds: 1),
      );
      final profileRepository = testLaunchProfileRepository(
        await Directory.systemTemp.createTemp('team_generation_profiles_'),
      );
      final publisher = _RecordingPublisher(events);
      final commit = GeneratedTeamCommitService(
        jobStore: jobStore,
        expertStore: LocalExpertStore(fs: fs, dirOverride: '/tp/experts'),
        profileRepository: profileRepository,
        sessionRepository: _FakeSessionRepository(),
        resourceProvisioner: _RecordingProvisioner(),
        publisher: publisher,
      );
      final coordinator = TeamGenerationCoordinator(
        jobStore: jobStore,
        settingsStore: settingsStore,
        sessionPort: port,
        compatibility: compatibility,
        probeService: probeService,
        planValidator: GeneratedTeamPlanValidator(),
        handoffService: handoff,
        cleanupService: cleanup,
        commitService: commit,
        uuidFactory: () => 'workflow-12345678',
        presets: () => [preset],
        workspaceResolver: (_) async => workspace,
      );

      final missingGenerator = await coordinator.preflight(
        workspace: workspace,
        originalPrompt: 'Build the release plan',
        generatorPresetId: '',
      );
      expect(
        missingGenerator.issues.map((issue) => issue.code),
        contains('generator_not_configured'),
      );
      final supportedGenerator = await coordinator.preflight(
        workspace: workspace,
        originalPrompt: 'Build the release plan',
        generatorPresetId: preset.id,
      );
      expect(supportedGenerator.ok, isTrue);
      final unsupportedCoordinator = TeamGenerationCoordinator(
        jobStore: jobStore,
        settingsStore: settingsStore,
        sessionPort: port,
        compatibility: TeamGenerationCompatibility(registry: CliToolRegistry()),
        probeService: probeService,
        planValidator: GeneratedTeamPlanValidator(),
        handoffService: handoff,
        cleanupService: cleanup,
        commitService: commit,
        uuidFactory: () => 'workflow-unsupported',
        presets: () => [preset],
        workspaceResolver: (_) async => workspace,
      );
      final unsupportedGenerator = await unsupportedCoordinator.preflight(
        workspace: workspace,
        originalPrompt: 'Build the release plan',
        generatorPresetId: preset.id,
      );
      expect(
        unsupportedGenerator.issues.map((issue) => issue.code),
        contains('generator_launch_unsupported'),
      );

      const originalRequest = 'Build the release plan';
      const expectedKickoff =
          'Build and launch the optimal TeamPilot team for the task below.\n'
          'Follow the managed Team Builder skill and use Team Composer until '
          'finalize_team_generation succeeds.\n\n'
          'Build the release plan';
      final started = await coordinator.start(
        workspace: workspace,
        originalPrompt: originalRequest,
        generatorPresetId: preset.id,
        projectFolderPath: '/proj',
        workingDirectoryPath: '/proj',
        folderIds: const ['/proj'],
        targetIds: const ['local'],
      );
      expect(events[0], 'builderCreated');
      final kickoffId = teamGenerationStableId(
        'teamgen-kickoff-',
        started.workflowId,
      );
      expect(
        events[1],
        'history:${started.builderSessionId}:${started.builderSessionId}:'
        '$kickoffId:$expectedKickoff',
      );
      expect(
        events[2],
        'deliverTracked:${started.builderSessionId}:${started.builderSessionId}:'
        '$kickoffId:$expectedKickoff',
      );

      await jobStore.mutate('ws', started.workflowId, (job) {
        return job.copyWith(
          normalizedPlanJson: const {
            'team': {'name': 'Release Team', 'mode': 'mixed'},
            'members': [
              {
                'name': 'team-lead',
                'role': 'Lead',
                'responsibilities': 'Coordinate release',
                'workingMethod': 'Delegate',
                'presetId': 'generator',
                'replicas': 1,
                'placement': {'local': 1},
              },
              {
                'name': 'builder',
                'role': 'Builder',
                'responsibilities': 'Implement changes',
                'workingMethod': 'Test first',
                'presetId': 'generator',
                'replicas': 1,
                'placement': {'local': 1},
              },
            ],
            'resources': {
              'skillIds': <String>[],
              'pluginIds': <String>[],
              'mcpServerIds': <String>[],
            },
          },
          planRevision: 'plan-rev',
          validatedRevision: 'plan-rev',
          validatedDestinationJson: const {
            'folderId': '/proj',
            'projectFolderPath': '/proj',
            'workingDirectoryPath': '/proj',
            'leadTargetId': 'local',
          },
        );
      });
      final accepted = await jobStore.read('ws', started.workflowId);
      await coordinator.completeAccepted(accepted!, 'finalize-key');

      expect(events[3], startsWith('profilePersisted:'));
      expect(events[4], 'destinationCreated');
      final destinationId = teamGenerationStableId(
        'teamgen-',
        started.workflowId,
      );
      final handoffDeliveryId = teamGenerationStableId(
        'teamgen-prompt-0-',
        started.workflowId,
      );
      expect(
        events[5],
        'history:$destinationId:team-lead:$handoffDeliveryId:$originalRequest',
      );
      expect(events[6], 'prompt:team-lead:$originalRequest');
      expect(events[7], 'builderDeleted');
      expect(events, hasLength(8));
      expect((await profileRepository.loadTeamProfiles()), hasLength(1));
      expect(
        (await jobStore.read('ws', started.workflowId))!.phase,
        TeamGenerationPhase.complete,
      );
    },
  );
}

class _EmptyProbeRunner implements TeamTargetProbeRunner {
  @override
  Future<TeamTargetProbe> probe({
    required Workspace workspace,
    required String targetId,
    required Set<String> cliValues,
  }) async => TeamTargetProbe(
    targetId: targetId,
    status: TeamTargetProbeStatus.available,
    folderIds: const [],
    cliProbes: const [],
  );
}
