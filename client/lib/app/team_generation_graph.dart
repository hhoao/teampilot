import '../../models/workspace.dart';
import '../../repositories/session_repository.dart';
import '../../services/expert_hub/local_expert_store.dart';
import '../../services/team_generation/generated_team_commit_service.dart';
import '../../services/team_generation/generated_team_plan_validator.dart';
import '../../services/team_generation/team_generation_authorizer.dart';
import '../../services/team_generation/team_generation_builder_idle_waiter.dart';
import '../../services/team_generation/team_generation_cleanup_service.dart';
import '../../services/team_generation/team_generation_coordinator.dart';
import '../../services/team_generation/team_generation_compatibility.dart';
import '../../services/team_generation/team_generation_handoff_service.dart';
import '../../services/team_generation/team_generation_job_store.dart';
import '../../services/team_generation/team_generation_settings_store.dart';
import '../../services/team_generation/mcp/team_composer_mcp_handler.dart';
import '../../services/team_generation/team_generation_workflow_executor.dart';
import '../../services/team_generation/catalog/catalog_generation_stager.dart';
import '../../services/catalog/catalog_kind_registry.dart';
import '../../services/team_generation/team_target_probe_service.dart';
import '../../services/team_generation/runtime_team_target_probe_runner.dart';
import '../../services/remote/remote_cli_readiness.dart';
import '../../services/resource/resource_provider_set.dart';
import '../../services/session/session_lifecycle_service.dart';
import '../../services/storage/runtime_target_registry.dart';
import '../../services/team_generation/providers/managed_team_builder_skill_provider.dart';
import '../../repositories/launch_profile_repository.dart';
import '../../services/prompt_delivery/prompt_delivery_coordinator.dart';
import '../../services/prompt_delivery/prompt_delivery_store.dart';
import '../../models/app_session.dart';
import 'package:uuid/uuid.dart';
import '../cubits/workbench/workbench_cubit.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/storage/app_storage.dart';
import '../../models/team_config.dart';

import '../../services/team_generation/team_generation_context_payload.dart';
import '../../services/team_generation/models/team_target_probe.dart';

import '../cubits/chat/tab_member_pty_delivery.dart';
import '../cubits/launch_profile_cubit.dart';
import '../cubits/team/cubit_team_generation_session_port.dart';
import '../cubits/chat_cubit.dart';

/// Control-plane holder for the team-generation workflow graph. Built once in
/// [buildAppShell]; services receive interfaces, the coordinator and settings
/// store are exposed for the landing UI.

final class TeamGenerationGraph {
  TeamGenerationGraph({
    required this.coordinator,
    required this.settingsStore,
    required this.authorizer,
    required this.jobStore,
    required this.composerHandler,
    required this.catalogStager,
  });

  final TeamGenerationCoordinator coordinator;
  final TeamGenerationSettingsStore settingsStore;
  final TeamGenerationAuthorizer authorizer;
  final TeamGenerationJobStore jobStore;
  final TeamComposerMcpHandler composerHandler;
  final CatalogGenerationStager catalogStager;

  /// Builder-only resource injection owned by the generation composition
  /// graph. Normal Simple and Team sessions retain their ordinary resources.
  static ResourceProviderSet resourceProvidersForSession(
    AppSession session,
    ResourceProviderSet defaults,
  ) {
    if (session.purpose != SessionPurpose.teamGeneration) return defaults;
    if (defaults.skills.any(
      (provider) =>
          provider.providerId == ManagedTeamBuilderSkillProvider.skillId,
    )) {
      return defaults;
    }
    return ResourceProviderSet(
      prompts: defaults.prompts,
      skills: [...defaults.skills, ManagedTeamBuilderSkillProvider()],
      mcp: defaults.mcp,
      hooks: defaults.hooks,
    );
  }

  /// Issues a fresh workflow token for a builder session connect.
  String? tokenForSession(AppSession session) {
    if (session.purpose != SessionPurpose.teamGeneration ||
        session.workflowId.isEmpty) {
      return null;
    }
    return authorizer.issueForSession(
      TeamGenerationPrincipal(
        sessionId: session.sessionId,
        workspaceId: session.workspaceId,
        workflowId: session.workflowId,
      ),
    );
  }
}

/// App-owned attachment points for the generation graph. Keeping these as
/// callbacks makes the production bootstrap wiring observable without
/// constructing the full [AppShell].
final class TeamGenerationGraphBootstrapPort {
  const TeamGenerationGraphBootstrapPort({
    required this.setTokenIssuer,
    required this.attachResourceProviderResolver,
    required this.attachComposerHandler,
    required this.setComposerPrincipalResolver,
    required this.attachCatalogGenerationStager,
  });

  final void Function(String? Function(AppSession session) issuer)
  setTokenIssuer;
  final void Function(SessionResourceProviderResolver resolver)
  attachResourceProviderResolver;
  final void Function({
    required TeamComposerMcpHandler handler,
    required TeamGenerationAuthorizer authorizer,
  })
  attachComposerHandler;
  final void Function(TeamComposerPrincipalFactory resolver)
  setComposerPrincipalResolver;
  final void Function(CatalogGenerationStager stager)
  attachCatalogGenerationStager;
}

/// Attaches one graph-owned generation workflow to app-scoped consumers.
/// Repeated calls are ignored so no handler or resolver is registered twice.
final class TeamGenerationGraphBootstrap {
  TeamGenerationGraphBootstrap({
    required this.graph,
    required this.port,
    required this.principalResolver,
  });

  final TeamGenerationGraph graph;
  final TeamGenerationGraphBootstrapPort port;
  final TeamComposerPrincipalFactory principalResolver;
  bool _attached = false;

  TeamGenerationCoordinator get coordinator => graph.coordinator;

  void attach() {
    if (_attached) return;
    _attached = true;
    port.setTokenIssuer(graph.tokenForSession);
    port.attachResourceProviderResolver(
      TeamGenerationGraph.resourceProvidersForSession,
    );
    port.attachComposerHandler(
      handler: graph.composerHandler,
      authorizer: graph.authorizer,
    );
    port.setComposerPrincipalResolver(principalResolver);
    port.attachCatalogGenerationStager(graph.catalogStager);
  }
}

/// App-layer publisher: patches persisted snapshots into the cubits.
final class CubitGeneratedTeamStatePublisher
    implements GeneratedTeamStatePublisher {
  CubitGeneratedTeamStatePublisher(this._teamCubit);

  final LaunchProfileCubit _teamCubit;

  @override
  Future<void> publish({
    required TeamProfile team,
    required Workspace workspace,
  }) async {
    // The profile is already on disk; refresh the cubit snapshot and select
    // the generated team so the Landing mirrors the same selection.
    await _teamCubit.load(bootSilent: true);
    await _teamCubit.selectTeam(team.id, silent: true);
  }
}

/// Session-lookup adapter over the repository for the authorizer.
final class SessionRepoLookup implements TeamGenerationSessionLookup {
  SessionRepoLookup(this._repo);

  final SessionRepository _repo;

  @override
  Future<AppSession?> findById(String sessionId) => _repo.findById(sessionId);
}

/// Keeps generated resource provisioning behind the commit boundary until the
/// resource synchronizer is exposed as a profile-level service.
final class NoopResourceProvisioner implements TeamProfileResourceProvisioner {
  @override
  Future<void> provision(TeamProfile team) async {}
}

/// Builds the team-generation object graph in dependency order.
TeamGenerationGraph buildTeamGenerationGraph({
  required ChatCubit chatCubit,
  required WorkbenchCubit workbenchCubit,
  required LaunchProfileCubit teamCubit,
  required SessionRepository sessionRepo,
  required LaunchProfileRepository identityRepository,
  required CliToolRegistry cliToolRegistry,
  required RuntimeTargetRegistry targetRegistry,
  required RemoteCliReadinessService remoteCliReadiness,
  CatalogKindRegistry? catalogRegistry,
}) {
  final jobStore = TeamGenerationJobStore();
  final workflowExecutor = TeamGenerationWorkflowExecutor();
  final catalogStager = CatalogGenerationStager(
    jobStore: jobStore,
    executor: workflowExecutor,
    registry: catalogRegistry,
  );
  final settingsStore = TeamGenerationSettingsStore();
  final authorizer = TeamGenerationAuthorizer(
    sessionLookup: SessionRepoLookup(sessionRepo),
    jobStore: jobStore,
  );
  final sessionPort = CubitTeamGenerationSessionPort(
    chatCubit: chatCubit,
    workbenchCubit: workbenchCubit,
    sessionRepository: sessionRepo,
  );
  final compatibility = TeamGenerationCompatibility(registry: cliToolRegistry);
  final probeRunner = RuntimeTeamTargetProbeRunner(
    registry: cliToolRegistry,
    targetResolver: (targetId) => targetRegistry.findById(targetId),
    remoteReadiness: remoteCliReadiness,
  );
  final probeService = TeamTargetProbeService(runner: probeRunner);
  final validator = GeneratedTeamPlanValidator();
  final commitService = GeneratedTeamCommitService(
    jobStore: jobStore,
    expertStore: LocalExpertStore(),
    profileRepository: identityRepository,
    sessionRepository: sessionRepo,
    resourceProvisioner: NoopResourceProvisioner(),
    publisher: CubitGeneratedTeamStatePublisher(teamCubit),
    resourcePromoter: catalogStager,
  );
  final promptDeliveryStore = FilePromptDeliveryStore(
    root: AppStorage.fs.pathContext.join(
      AppStorage.paths.basePath,
      'prompt-deliveries',
    ),
    fs: AppStorage.fs,
  );
  final promptCoordinator = PromptDeliveryCoordinator(
    store: promptDeliveryStore,
    commands: TabPromptDeliveryCommands(chatCubit.tabStore),
  );
  final handoffService = TeamGenerationHandoffService(
    jobStore: jobStore,
    sessionPort: sessionPort,
    promptCoordinator: promptCoordinator,
    promptStore: promptDeliveryStore,
  );
  final cleanupService = TeamGenerationCleanupService(
    jobStore: jobStore,
    sessionPort: sessionPort,
    idleWaiter: TeamGenerationBuilderIdleWaiter(sessionPort: sessionPort),
    revokeToken: authorizer.revoke,
  );
  Future<Workspace?> workspaceResolver(String workspaceId) async {
    for (final workspace in chatCubit.state.workspaces) {
      if (workspace.workspaceId == workspaceId) return workspace;
    }
    return null;
  }

  final coordinator = TeamGenerationCoordinator(
    jobStore: jobStore,
    settingsStore: settingsStore,
    sessionPort: sessionPort,
    compatibility: compatibility,
    probeService: probeService,
    planValidator: validator,
    handoffService: handoffService,
    cleanupService: cleanupService,
    commitService: commitService,
    uuidFactory: () => const Uuid().v4(),
    presets: () => chatCubit.lifecycle.globalPresets,
    workspaceResolver: workspaceResolver,
  );
  final handler = TeamComposerMcpHandler(
    context: TeamComposerToolContext(
      jobStore: jobStore,
      executor: TeamGenerationWorkflowExecutor(),
      contextProvider: (job) async => teamGenerationContextPayload(job),
      probeRunner: (job) async =>
          job.probeSnapshotJson ??
          (await probeService.probe(
            workspace: chatCubit.state.workspaces.firstWhere(
              (workspace) => workspace.workspaceId == job.workspaceId,
            ),
            cliValues: {
              for (final entry in job.settings.modelPool)
                entry.preset.cli.value,
            },
          )).toJson(),
      planValidator: (job, plan) async {
        final parsedProbe = TeamTargetProbeSnapshot.fromJson(
          job.probeSnapshotJson ?? const {},
        );
        final result = await validator.validate(
          input: GeneratedTeamValidationInput(
            settings: job.settings,
            probe: parsedProbe,
            installedResourceIds: const {},
            stagedResourceIds: {
              for (final resource in job.stagedResources) resource.refId,
            },
            existingExpertKeys: const {},
            presetDigests: {
              for (final entry in job.settings.modelPool)
                effectiveTeamGenerationPresetId(entry): [
                  'cli:',
                  entry.preset.cli.value,
                  'provider:',
                  entry.preset.provider,
                  'model:',
                  entry.preset.model,
                  'effort:',
                  entry.preset.effort,
                ].join('|'),
            },
            currentFolders: chatCubit.state.workspaces
                .firstWhere(
                  (workspace) => workspace.workspaceId == job.workspaceId,
                )
                .folders,
          ),
          planJson: plan,
        );
        return PlanValidationOutcome(
          valid: result.isValid && result.destinationLaunch != null,
          issues: [
            for (final issue in result.issues)
              {'code': issue.code, 'detail': issue.detail},
          ],
          normalizedPlan: result.normalizedPlan.toJson(),
          revision: result.revision,
          destination: result.destinationLaunch?.toJson(),
        );
      },
      finalizer: (job, key) => coordinator.completeAccepted(job, key),
    ),
  );
  return TeamGenerationGraph(
    coordinator: coordinator,
    settingsStore: settingsStore,
    authorizer: authorizer,
    jobStore: jobStore,
    composerHandler: handler,
    catalogStager: catalogStager,
  );
}
