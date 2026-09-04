import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/simple_launch_identity.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/models/workspace_folder.dart';
import 'package:teampilot/models/workspace_topology.dart';
import 'package:teampilot/repositories/launch_profile_repository.dart';
import 'package:teampilot/repositories/session_repository.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/expert_hub/local_expert_store.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_coordinator.dart';
import 'package:teampilot/services/prompt_delivery/prompt_delivery_store.dart';
import 'package:teampilot/services/storage/workspace_layout.dart';
import 'package:teampilot/services/team_generation/generated_team_commit_service.dart';
import 'package:teampilot/services/team_generation/generated_team_plan_validator.dart';
import 'package:teampilot/services/team_generation/team_generation_builder_idle_waiter.dart';
import 'package:teampilot/services/team_generation/team_generation_cleanup_service.dart';
import 'package:teampilot/services/team_generation/team_generation_compatibility.dart';
import 'package:teampilot/services/team_generation/team_generation_coordinator.dart';
import 'package:teampilot/services/team_generation/team_generation_handoff_service.dart';
import 'package:teampilot/services/team_generation/mcp/team_composer_mcp_constants.dart';
import 'package:teampilot/services/team_generation/mcp/team_composer_mcp_handler.dart';
import 'package:teampilot/services/team_generation/team_generation_job_store.dart';
import 'package:teampilot/services/team_generation/team_generation_session_port.dart';
import 'package:teampilot/services/team_generation/team_generation_settings_store.dart';
import 'package:teampilot/services/team_generation/team_target_probe_service.dart';
import 'package:teampilot/services/team_generation/team_generation_workflow_executor.dart';
import 'package:teampilot/services/team_generation/models/team_target_probe.dart';

import '../../support/in_memory_filesystem.dart';

Map<String, Object?> structured(TeamComposerMcpResult result) =>
    ((result.response['result'] as Map)['structuredContent'] as Map)
        .cast<String, Object?>();

final class _FakeComposerConversation {
  const _FakeComposerConversation({
    required this.handler,
    required this.principal,
  });

  final TeamComposerMcpHandler handler;
  final ComposerPrincipal principal;

  Future<List<TeamComposerMcpResult>> run() async => [
    await _call(TeamComposerToolName.getContext),
    await _call(TeamComposerToolName.probeTargets),
    await _call(TeamComposerToolName.validatePlan, {
      'plan': 'malformed-tool-arguments',
    }),
    await _call(TeamComposerToolName.validatePlan, {
      'plan': {'draft': 'rejected'},
    }),
    await _call(TeamComposerToolName.validatePlan, {
      'plan': {'draft': 'corrected'},
    }),
    await _call(TeamComposerToolName.finalize, {
      'plan': {'draft': 'corrected'},
      'validationRevision': 'good-revision',
      'idempotencyKey': 'builder-finalize-1',
    }),
  ];

  Future<TeamComposerMcpResult> _call(
    String tool, [
    Map<String, Object?> arguments = const {},
  ]) => handler.handleToolCall(
    requestId: tool,
    toolName: tool,
    arguments: arguments,
    principal: principal,
  );
}

class _BuilderSessionPort implements TeamGenerationSessionPort {
  final sessions = <String, AppSession>{};
  final history = <String>[];
  final deliveries = <String>[];

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
    sessions[fixedSessionId] = AppSession(
      sessionId: fixedSessionId,
      workspaceId: workspace.workspaceId,
      createdAt: 1,
      purpose: SessionPurpose.teamGeneration,
      workflowId: workflowId,
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
  }) async => const SessionPortOpenResult(status: 'opened');

  @override
  Future<SessionPortOpenResult> open(String sessionId) async =>
      const SessionPortOpenResult(status: 'opened');

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
    history.add('$sessionId/$memberId/$deliveryId/$text');
  }

  @override
  Future<PortDeliveryOutcome> deliverTracked(
    String sessionId,
    String memberId,
    String text, {
    required bool directToPty,
    required String deliveryId,
  }) async {
    deliveries.add('$sessionId/$memberId/$deliveryId/$text');
    return const PortDeliveryOutcome(result: 'submitted');
  }

  @override
  Future<bool> deleteBuilder(String sessionId, String workflowId) async => true;

  @override
  Stream<PortActivity> activityStream(String sessionId) => const Stream.empty();
}

class _NoopPromptCommands implements PromptDeliveryCommands {
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

class _NoopProvisioner implements TeamProfileResourceProvisioner {
  @override
  Future<void> provision(TeamProfile team) async {}
}

class _NoopPublisher implements GeneratedTeamStatePublisher {
  @override
  Future<void> publish({
    required TeamProfile team,
    required Workspace workspace,
  }) async {}
}

class _FakeSessionRepository extends Fake implements SessionRepository {
  @override
  Future<Workspace?> updateWorkspaceMemberPlacement(
    String workspaceId,
    String teamId, {
    required MemberTargetAssignments targets,
  }) async => null;
}

class _AvailableProbeRunner implements TeamTargetProbeRunner {
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

void main() {
  test(
    'coordinator-started Builder script recovers MCP and validation errors without automatic retries',
    () async {
      final fs = InMemoryFilesystem();
      final store = TeamGenerationJobStore(
        fs: fs,
        layout: WorkspaceLayout(teampilotRoot: '/tp', fs: fs),
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
      final settingsStore = TeamGenerationSettingsStore(
        fs: fs,
        pathOverride: '/tp/settings.json',
      );
      await settingsStore.save(
        TeamGenerationSettings(
          teamMode: TeamMode.mixed,
          modelPool: [
            GenerateModelPoolEntry(
              id: preset.id,
              cli: preset.cli,
              provider: preset.provider,
              model: preset.model,
              effort: preset.effort,
            ),
          ],
        ),
      );
      final workspace = Workspace(
        workspaceId: 'ws',
        folders: const [WorkspaceFolder(path: '/proj', targetId: 'local')],
        createdAt: 1,
        updatedAt: 1,
      );
      final port = _BuilderSessionPort();
      final promptStore = MemoryPromptDeliveryStore();
      final handoff = TeamGenerationHandoffService(
        jobStore: store,
        sessionPort: port,
        promptCoordinator: PromptDeliveryCoordinator(
          store: promptStore,
          commands: _NoopPromptCommands(),
        ),
        promptStore: promptStore,
      );
      final coordinator = TeamGenerationCoordinator(
        jobStore: store,
        settingsStore: settingsStore,
        sessionPort: port,
        compatibility: TeamGenerationCompatibility(
          registry: CliToolRegistry.builtIn(),
        ),
        probeService: TeamTargetProbeService(runner: _AvailableProbeRunner()),
        planValidator: GeneratedTeamPlanValidator(),
        handoffService: handoff,
        cleanupService: TeamGenerationCleanupService(
          jobStore: store,
          sessionPort: port,
          idleWaiter: TeamGenerationBuilderIdleWaiter(sessionPort: port),
          revokeToken: (_) {},
        ),
        commitService: GeneratedTeamCommitService(
          jobStore: store,
          expertStore: LocalExpertStore(fs: fs, dirOverride: '/tp/experts'),
          profileRepository: LaunchProfileRepository(rootDir: '/tp/profiles'),
          sessionRepository: _FakeSessionRepository(),
          resourceProvisioner: _NoopProvisioner(),
          publisher: _NoopPublisher(),
        ),
        uuidFactory: () => 'wf',
        presets: () => [preset],
        workspaceResolver: (_) async => workspace,
      );
      final started = await coordinator.start(
        workspace: workspace,
        originalPrompt: 'Create a release team',
        generatorIdentity: SimpleLaunchIdentity.resolve(
          preset: preset,
          expertKey: 'teampilot/builtin/team-builder',
        ),
        projectFolderPath: '/proj',
        workingDirectoryPath: '/proj',
        folderIds: const ['/proj'],
        targetIds: const ['local'],
      );
      expect(port.history, hasLength(1));
      expect(port.deliveries, hasLength(1));

      final calls = <String>[];
      final finalized = <String>[];
      final handler = TeamComposerMcpHandler(
        context: TeamComposerHandlerContext(
          jobStore: store,
          executor: TeamGenerationWorkflowExecutor(),
          contextProvider: (job) async {
            calls.add(TeamComposerToolName.getContext);
            return {
              'originalPrompt': job.originalPrompt,
              'launch': job.launch.toJson(),
            };
          },
          probeRunner: (job) async {
            calls.add(TeamComposerToolName.probeTargets);
            return {
              'targets': ['local'],
            };
          },
          planValidator: (job, plan) async {
            final draft = plan['draft'] as String;
            calls.add('${TeamComposerToolName.validatePlan}:$draft');
            if (draft == 'rejected') {
              return const PlanValidationOutcome(
                valid: false,
                issues: [
                  {'code': 'missing_team_lead'},
                ],
                normalizedPlan: {'draft': 'rejected'},
                revision: 'bad-revision',
              );
            }
            return const PlanValidationOutcome(
              valid: true,
              issues: [],
              normalizedPlan: {'draft': 'corrected'},
              revision: 'good-revision',
              destination: {
                'folderId': '/proj',
                'projectFolderPath': '/proj',
                'workingDirectoryPath': '/proj',
                'leadTargetId': 'local',
              },
            );
          },
          finalizer: (job, key) async {
            finalized.add('${job.workflowId}:$key');
          },
        ),
      );
      final principal = ComposerPrincipal(
        sessionId: started.builderSessionId,
        workspaceId: 'ws',
        workflowId: started.workflowId,
      );

      expect(started.workflowId, principal.workflowId);
      expect(started.builderSessionId, principal.sessionId);
      expect(calls, isEmpty);

      // The script, not the coordinator, makes every tool call and recovers.
      final transcript = await _FakeComposerConversation(
        handler: handler,
        principal: principal,
      ).run();
      final context = transcript[0];
      expect(structured(context)['originalPrompt'], 'Create a release team');

      final probe = transcript[1];
      expect(structured(probe)['status'], 'probed');

      final toolError = transcript[2];
      expect(structured(toolError), {'code': 'invalid_plan'});

      final rejected = transcript[3];
      expect(structured(rejected), {
        'valid': false,
        'issues': [
          {'code': 'missing_team_lead'},
        ],
        'revision': 'bad-revision',
      });

      final corrected = transcript[4];
      expect(structured(corrected)['valid'], isTrue);
      expect(structured(corrected)['revision'], 'good-revision');
      expect(
        (await store.read('ws', 'wf'))!.validatedRevision,
        'good-revision',
      );

      final accepted = transcript[5];
      expect(structured(accepted)['accepted'], isTrue);
      expect(finalized, isEmpty);
      expect(calls, [
        TeamComposerToolName.getContext,
        TeamComposerToolName.probeTargets,
        '${TeamComposerToolName.validatePlan}:rejected',
        '${TeamComposerToolName.validatePlan}:corrected',
      ]);
      expect(
        calls.where(
          (call) => call.startsWith(TeamComposerToolName.validatePlan),
        ),
        hasLength(2),
      );

      await accepted.afterResponseFlushed!();
      expect(finalized, ['wf:builder-finalize-1']);
    },
  );
}
