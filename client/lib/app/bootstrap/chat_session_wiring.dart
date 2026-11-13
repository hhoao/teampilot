import '../../cubits/agent_attention_cubit.dart';
import '../../cubits/chat_cubit.dart';
import '../../cubits/layout_cubit.dart';
import '../../cubits/seat_lease_cubit.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../cubits/ssh_profile_cubit.dart';
import '../../cubits/termux_cubit.dart';
import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import '../../repositories/automation_repository.dart';
import '../../repositories/launch_profile_repository.dart';
import '../../repositories/session_repository.dart';
import '../../services/agent_status/agent_status_seat_lookup.dart';
import '../../services/agent_status/ask_user_answer_pending_store.dart';
import '../../services/agent_status/general_permission_request_gate.dart';
import '../../services/chat/conversation/approvals/ask_user_question_answer_service.dart';
import '../../services/chat/conversation/approvals/exit_plan_mode_approval_service.dart';
import '../../services/chat/conversation/prompt_delivery/prompt_delivery_coordinator.dart';
import '../../services/chat/launch/launch_factory.dart';
import '../../services/chat/launch/staging/session_runtime_plan_builder.dart';
import '../../services/chat/session/session_lifecycle_service.dart';
import '../../services/chat/team_bus/mcp/teammate_bus_mcp_gateway.dart';
import '../../services/chat/team_bus/remote/remote_bus_binding_resolver.dart';
import '../../services/chat/team_bus/remote/remote_member_bus_setup.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/install/install_job_registry.dart';
import '../../services/remote/local_credential_exporter.dart';
import '../../services/remote/remote_cli_readiness.dart';
import '../../services/ssh/ssh_client_factory.dart';
import '../../services/storage/home_storage.dart';
import '../../services/storage/runtime_context_registry.dart';
import '../../services/storage/targets_repository.dart';
import '../../services/terminal/terminal_transport_factory.dart';
import '../../services/termux/termux_work_ops_message.dart';

/// Builds the app's [ChatCubit] on top of the agent event plane, the session
/// repositories and the session-connect composition the shell already wired.
///
/// [sessions], [lifecycle], [identities] and [sshProfiles] are getters because
/// the shell owns the session repository, lifecycle service, launch-profile
/// repository and SSH cubit as `late final` dependencies. [promptDeliveries]
/// and [termuxGate] stay lazy because the shell assigns the prompt-delivery
/// coordinator after the cubit exists and the termux gate after bootstrap.
ChatCubit wireChatSession({
  required HomeStorage storage,
  required SessionRepository Function() sessions,
  required SessionLifecycleService Function() lifecycle,
  required RuntimeContextRegistry runtimeContexts,
  required CliToolRegistry cliToolRegistry,
  required SessionPreferencesCubit sessionPreferences,
  required LaunchProfileRepository Function() identities,
  required SshProfileCubit Function() sshProfiles,
  required PromptDeliveryCoordinator? Function() promptDeliveries,
  required TeammateBusMcpGateway teammateBusMcpGateway,
  required AgentStatusSeatLookup agentStatusSeatLookup,
  required AgentAttentionCubit agentAttentionCubit,
  required SeatLeaseCubit seatLeaseCubit,
  required AskUserAnswerPendingStore askUserAnswerPendingStore,
  required AskUserQuestionAnswerService askUserQuestionAnswerService,
  required GeneralPermissionRequestGate generalPermissionRequestGate,
  required ExitPlanModeApprovalService exitPlanModeApprovalService,
  required AutomationRepository automationRepository,
  required LayoutCubit layoutCubit,
  required TargetsRepository targets,
  required TerminalTransportFactory transportFactory,
  required SshProfile? Function(String id) sshProfileById,
  required RuntimeTarget Function() defaultTargetResolver,
  required SshClientFactory sshClientFactory,
  required SessionRuntimePlanBuilder runtimePlanBuilder,
  required RemoteCliReadinessService remoteCliReadiness,
  required InstallJobRegistry installJobRegistry,
  required TermuxCubit? Function() termuxGate,
}) {
  // Shell-local names so the construction below stays identical to the call it
  // was moved out of.
  final homeStorage = storage;
  final sessionRepo = sessions();
  final sessionLifecycleService = lifecycle();
  final sessionPreferencesCubit = sessionPreferences;
  final identityRepository = identities();
  final automationRepo = automationRepository;
  final targetsRepo = targets;
  final sessionRuntimePlanBuilder = runtimePlanBuilder;
  final runtimeContextRegistry = runtimeContexts;

  final chatCubit = ChatCubit(
    storage: homeStorage,
    promptDeliveries: promptDeliveries,
    teammateBusMcpGateway: teammateBusMcpGateway,
    agentStatusSeatLookup: agentStatusSeatLookup,
    agentAttentionCubit: agentAttentionCubit,
    seatLeaseCubit: seatLeaseCubit,
    askUserAnswerPendingStore: askUserAnswerPendingStore,
    askUserQuestionAnswerService: askUserQuestionAnswerService,
    generalPermissionGate: generalPermissionRequestGate,
    exitPlanApprovalService: exitPlanModeApprovalService,
    sessionRepository: sessionRepo,
    lifecycleService: sessionLifecycleService,
    automationRepository: automationRepo,
    layoutCubit: layoutCubit,
    autoLaunchAllMembersOnConnect: () => sessionPreferencesCubit
        .state
        .preferences
        .autoLaunchAllMembersOnConnect,
    discoveredAcpAdapterPath: sessionPreferencesCubit.resolveAcpAdapterPath,
    acpAdapterPathOverride: targetsRepo.acpAdapterPathOverride,
    reclaimIdleTerminalsEnabled: () =>
        sessionPreferencesCubit.state.preferences.reclaimIdleTerminals,
    reclaimIdleTerminalAfterSeconds: () => sessionPreferencesCubit
        .state
        .preferences
        .reclaimIdleTerminalAfterSeconds,
    executableResolver: () => sessionPreferencesCubit.resolveExecutable(),
    cliExecutableResolver: sessionPreferencesCubit.resolveExecutable,
    transportFactory: transportFactory,
    sshProfileResolver: () => sshProfiles().state.selectedProfile,
    sshProfileById: sshProfileById,
    teamById: (teamId) async {
      for (final team in await identityRepository.loadTeamProfiles()) {
        if (team.id == teamId) return team;
      }
      return null;
    },
    sshDefaultWorkingDirectoryResolver: () =>
        sessionPreferencesCubit.state.preferences.defaultSshWorkingDirectory,
    sshUseLoginShellResolver: () =>
        sessionPreferencesCubit.state.preferences.sshUseLoginShell,
    defaultTargetResolver: defaultTargetResolver,
    terminalScrollbackLinesResolver: () =>
        sessionPreferencesCubit.state.preferences.terminalScrollbackLines,
    // P3b (#1): connect remote (ssh) mixed-team members back to the in-process
    // bus over a reverse tunnel. Local members resolve to null (unchanged).
    remoteBusSetup: RemoteMemberBusSetup(
      resolver: RemoteBusBindingResolver(registry: cliToolRegistry),
    ),
    sessionConnect: buildSessionConnectOrchestrator(
      lifecycle: sessionLifecycleService,
      registry: cliToolRegistry,
      sshClientFactory: sshClientFactory,
      profileById: sshProfileById,
      contextForTarget: runtimeContextRegistry.forTarget,
      homeContext: runtimeContextRegistry.home,
      homeTarget: defaultTargetResolver,
      isCredentialOptIn: targetsRepo.isCredentialOptIn,
      cliPathOverride: targetsRepo.cliPathOverride,
      setCliPathOverride: targetsRepo.setCliPathOverride,
      loadLocalCredentials: (cli) =>
          LocalCredentialExporter(storage: homeStorage).export(cli),
      localCliPath: (cli) async =>
          sessionPreferencesCubit.resolveExecutable(cli),
      runtimePlanBuilder: sessionRuntimePlanBuilder,
    ),
    remoteCliReadiness: remoteCliReadiness,
    installJobRegistry: installJobRegistry,
    termuxConnectedResolver: () => termuxGate()?.state.connected ?? true,
    termuxDisconnectedWorkOpsMessageResolver:
        TermuxWorkOpsMessage.disconnectedBlocked,
    termuxGateHomeResolver: defaultTargetResolver,
  );

  return chatCubit;
}
