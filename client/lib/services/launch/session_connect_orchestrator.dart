import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/runtime_target.dart';
import '../../models/session_member_binding.dart';
import '../../models/team_config.dart';
import '../../models/team_roster_slot.dart';
import '../../models/workspace.dart';
import '../../utils/team/team_member_naming.dart';
import '../../utils/workspace/landing_draft_resolver.dart';
import '../cli/installer_types.dart';
import '../cli/registry/capabilities/cli_session_capability.dart';
import '../cli/registry/cli_tool_registry.dart';
import '../cli/claude/team_roster_service.dart';
import '../cli/claude/capabilities/mcp_project_cleanup.dart';
import '../cli/preset_resolver.dart';
import '../provider/config_profile_service.dart';
import '../session/session_continue_overrides_apply.dart';
import '../session/session_launch_config_snapshot.dart';
import '../session/session_lifecycle_service.dart';
import '../storage/runtime_context.dart';
import '../team_bus/member_bus_idle_endpoint.dart';
import '../agent_status/member_agent_status_endpoint.dart';
import '../../utils/logging/logger.dart';
import 'launch_manifest.dart';
import 'launch_manifest_paths.dart';
import 'manifest_executor.dart';
import 'session_runtime_plan.dart';
import 'session_runtime_plan_builder.dart';
import 'work_plane_script_runner.dart';
import 'session_bootstrap_coordinator.dart';
import 'workspace_provision_coordinator.dart';

export '../provider/config_profile_service.dart' show TeamLaunchOutcome;

typedef ConfigProfileServiceFactory =
    Future<ConfigProfileService> Function(RuntimeContext context);

/// Phase A + B orchestration for simple and team session connect.
///
/// Both modes build a [SessionRuntimePlan] first, then stage/provision from it.
class SessionConnectOrchestrator {
  SessionConnectOrchestrator({
    required this.lifecycle,
    required this.workspaceProvision,
    required this.configProfileFor,
    required this.homeContext,
    required this.manifestExecutor,
    required this.runtimePlanBuilder,
    SessionBootstrapCoordinator? sessionBootstrap,
    CliToolRegistry? registry,
  }) : sessionBootstrap = sessionBootstrap ?? SessionBootstrapCoordinator(),
       registry = registry ?? CliToolRegistry.builtIn();

  final SessionLifecycleService lifecycle;
  final WorkspaceProvisionCoordinator workspaceProvision;
  final ConfigProfileServiceFactory configProfileFor;
  final RuntimeContext Function() homeContext;
  final ManifestExecutor manifestExecutor;
  final SessionRuntimePlanBuilder runtimePlanBuilder;
  final SessionBootstrapCoordinator sessionBootstrap;
  final CliToolRegistry registry;

  Future<
    ({ShellLaunchSpec shellLaunch, List<String> warnings, String remoteCliPath})
  >
  prepareSimpleConnect({
    required AppSession session,
    required Workspace workspace,
    required RuntimeTarget launchTarget,
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
    MemberAgentStatusEndpoint? agentStatus,
    void Function(CliInstallProgress progress)? onProvisionProgress,
  }) async {
    final planSw = Stopwatch()..start();
    // Back-fill the official default provider for legacy rows persisted before
    // provider resolution existed.
    final identity = enrichSimpleLaunchIdentityFromPreset(
      identity: session.simpleIdentity.withOfficialDefaultProvider(
        CliToolRegistry.builtIn().defaultOfficialProviderId,
      ),
      presets: lifecycle.globalPresets,
    );
    final plan = await runtimePlanBuilder.buildSimple(
      workspaceId: workspace.workspaceId,
      sessionId: session.sessionId,
      memberId: session.sessionId,
      identity: identity,
    );
    appLogger.d(
      '[session-launch] build-runtime-plan '
      'session=${session.sessionId} '
      'plugins=${plan.runtimeBundle.pluginIds.length} '
      'skills=${plan.runtimeBundle.skillIds.length} '
      'ms=${planSw.elapsedMilliseconds}',
    );
    final finalizedMember = finalizeSessionLaunchMember(
      session: session,
      baseMember: plan.member,
      memberId: session.sessionId,
      isSimple: true,
    );
    return _prepareConnectFromPlan(
      session: session,
      workspace: workspace,
      plan: plan.copyWith(member: finalizedMember),
      launchTarget: launchTarget,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
      agentStatus: agentStatus,
      onProvisionProgress: onProvisionProgress,
    );
  }

  Future<
    ({ShellLaunchSpec shellLaunch, List<String> warnings, String remoteCliPath})
  >
  prepareTeamConnect({
    required AppSession session,
    required TeamProfile team,
    required TeamMemberConfig member,
    SessionMemberBinding? memberBinding,
    Workspace? workspace,
    required RuntimeTarget launchTarget,
    required String workingDirectory,
    List<String> additionalDirectories = const [],
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
    MemberAgentStatusEndpoint? agentStatus,
    void Function(CliInstallProgress progress)? onProvisionProgress,
  }) async {
    final resolvedWorkspace =
        workspace ??
        Workspace(
          workspaceId: session.workspaceId,
          folders: session.folders,
          createdAt: session.createdAt,
        );
    final connectMember = memberForSessionConnect(
      session: session,
      team: team,
      member: member,
      memberBinding: memberBinding,
      globalPresets: lifecycle.globalPresets,
    );
    final slot = _slotForMember(team, connectMember);
    final preset = presetForSessionConnect(
      session: session,
      team: team,
      member: member,
      memberBinding: memberBinding,
      globalPresets: lifecycle.globalPresets,
    );
    final plan = await runtimePlanBuilder.buildTeamSeat(
      workspaceId: resolvedWorkspace.workspaceId,
      sessionId: session.sessionId,
      team: team,
      slot: slot,
      presetId: preset?.id,
      member: connectMember,
    );
    final memberId = memberBinding?.rosterMemberId ?? member.id;
    final finalizedMember = finalizeSessionLaunchMember(
      session: session,
      baseMember: plan.member,
      memberId: memberId,
      isSimple: false,
      preset: preset,
      withPreset: _memberWithPreset,
    );
    return _prepareConnectFromPlan(
      session: session,
      workspace: resolvedWorkspace,
      plan: plan.copyWith(member: finalizedMember),
      team: team,
      memberBinding: memberBinding,
      launchTarget: launchTarget,
      workingDirectory: workingDirectory,
      additionalDirectories: additionalDirectories,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
      agentStatus: agentStatus,
      onProvisionProgress: onProvisionProgress,
    );
  }

  Future<
    ({ShellLaunchSpec shellLaunch, List<String> warnings, String remoteCliPath})
  >
  _prepareConnectFromPlan({
    required AppSession session,
    required Workspace workspace,
    required SessionRuntimePlan plan,
    TeamProfile? team,
    SessionMemberBinding? memberBinding,
    required RuntimeTarget launchTarget,
    String workingDirectory = '',
    List<String> additionalDirectories = const [],
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
    MemberAgentStatusEndpoint? agentStatus,
    void Function(CliInstallProgress progress)? onProvisionProgress,
  }) async {
    final isSimple = plan.mode == SessionRuntimeMode.simple;
    final member = plan.member;
    final cli = isSimple
        ? (session.cli ?? member.cli ?? CliTool.claude)
        : sessionMemberLaunchCli(
            session: session,
            team: team!,
            member: member,
            globalPresets: lifecycle.globalPresets,
          );

    final offHome = workspaceProvision.isOffHome(launchTarget);
    late final RuntimeContext workContext;
    late final String remoteCliPath;

    if (offHome) {
      final provision = await workspaceProvision.ensureReady(
        target: launchTarget,
        workspaceId: workspace.workspaceId,
        cli: cli,
        trustedDirectories: [
          for (final folder in workspace.folders) folder.path,
        ],
        onProgress: onProvisionProgress,
      );
      workContext = provision.workContext;
      remoteCliPath = provision.remoteCliPath;
    } else {
      workContext = await lifecycle.resolveWorkContextForTargetId(
        launchTarget.id,
      );
      remoteCliPath = await workspaceProvision.provisioner.localCliPath(cli);
    }

    void report(CliInstallPhase phase, {String? detail}) {
      onProvisionProgress?.call(
        CliInstallProgress(phase: phase, detail: detail),
      );
    }

    report(CliInstallPhase.syncingRemoteWorkspace, detail: 'stage-session');
    appLogger.d(
      '[session-launch] stage-session begin '
      'session=${session.sessionId} cli=${cli.value} offHome=$offHome',
    );

    // Ensure session-level shared resources (credential symlinks, workspace
    // trust) are provisioned exactly once.  With readSymlinkTarget-based
    // detection the underlying operations are idempotent; the bootstrap
    // coordinator provides a shared-future barrier so concurrent member
    // connects don't duplicate the work.
    sessionBootstrap.ensureBootstrapped(
      session.sessionId,
      () async => const SessionBootstrapResult(),
    );

    final catalogProfile = await configProfileFor(
      offHome ? homeContext() : workContext,
    );

    late final ({TeamLaunchOutcome outcome, LaunchManifest manifest}) staged;
    if (isSimple) {
      staged = await catalogProfile.stageSimpleSessionLaunch(
        readDelegate: offHome ? homeContext().fs : workContext.fs,
        workTeampilotRoot: workContext.appDataRoot,
        workspaceId: workspace.workspaceId,
        sessionId: session.sessionId,
        runtimeBundle: plan.runtimeBundle,
        member: member,
        workingDirectory: workingDirectory.isNotEmpty
            ? workingDirectory
            : session.firstFolderPath,
        additionalDirectories: additionalDirectories.isNotEmpty
            ? additionalDirectories
            : session.extraFolderPaths,
        extraMcpServers: extraMcpServers,
        busIdle: busIdle,
        agentStatus: agentStatus,
      );
    } else {
      final teamId = team!.id.trim();
      final cliTeamName = session.cliTeamName.trim();
      final runtimeTeamId = cliTeamName.isNotEmpty
          ? cliTeamName
          : session.sessionId;
      final leadTaskId = memberBinding?.taskId.trim() ?? '';
      final leadSessionId =
          TeamMemberNaming.isTeamLead(member) && leadTaskId.isNotEmpty
          ? leadTaskId
          : null;
      staged = await catalogProfile.stageTeamLaunch(
        readDelegate: offHome ? homeContext().fs : workContext.fs,
        workTeampilotRoot: workContext.appDataRoot,
        workspaceId: effectiveLaunchWorkspaceId(
          workspaceId: session.workspaceId,
          teamId: teamId,
        ),
        sessionId: session.sessionId,
        teamId: teamId,
        cliTeamName: runtimeTeamId,
        cli: cli,
        members: cliTeamRosterMembers(session, team),
        member: member,
        workingDirectory: workingDirectory,
        additionalDirectories: additionalDirectories,
        team: team,
        runtimeBundle: plan.runtimeBundle,
        leadSessionId: leadSessionId,
        extraMcpServers: extraMcpServers,
        busIdle: busIdle,
        agentStatus: agentStatus,
      );

      await maybeRemoveStaleProjectTeammateBus(
        fs: workContext.fs,
        extraServers: extraMcpServers,
        projectRoots: projectMcpRootsFromLaunch(
          workingDirectory: workingDirectory,
          additionalDirectories: additionalDirectories,
        ),
      );
    }

    appLogger.d(
      '[session-launch] stage-session done '
      'session=${session.sessionId} ops=${staged.manifest.entries.length}',
    );

    report(CliInstallPhase.syncingRemoteWorkspace, detail: 'manifest-flush');
    final flushStarted = Stopwatch()..start();
    // SSH/Termux work plane (including Android home-on-SSH): batch via one
    // remote script. Local/WSL keep per-op apply. Off-home still expands
    // control-plane copies first inside ManifestExecutor.
    final workSshProfileId = launchTarget.sshProfileId?.trim();
    await manifestExecutor.flush(
      manifest: staged.manifest,
      targetFs: workContext.fs,
      sourceFs: offHome ? homeContext().fs : workContext.fs,
      sshProfileId: (workSshProfileId != null && workSshProfileId.isNotEmpty)
          ? workSshProfileId
          : null,
    );
    appLogger.d(
      '[session-launch] manifest-flush done '
      'session=${session.sessionId} ops=${staged.manifest.entries.length} '
      'sshBatch=${workSshProfileId != null && workSshProfileId.isNotEmpty} '
      'ms=${flushStarted.elapsedMilliseconds}',
    );

    // The normal connect path stages through ManifestFilesystem and flushes
    // here, rather than calling ConfigProfileService.prepare*. Native CLI
    // plugin installation must happen after that flush so Codex can see the
    // marketplace source on the target machine.
    final postFlushProfile = await configProfileFor(workContext);
    final nativeMemberId = !isSimple && team?.teamMode == TeamMode.mixed
        ? ClaudeTeamRosterService.safeClaudePathSegment(member.id)
        : null;
    final nativePluginStarted = Stopwatch()..start();
    await postFlushProfile.provisionNativePlugins(
      workspaceId: isSimple
          ? workspace.workspaceId
          : effectiveLaunchWorkspaceId(
              workspaceId: workspace.workspaceId,
              teamId: team?.id ?? '',
            ),
      sessionId: session.sessionId,
      runtimeBundle: plan.runtimeBundle,
      cli: cli,
      memberId: nativeMemberId,
      team: team,
      executable: remoteCliPath,
    );
    appLogger.d(
      '[session-launch] native-plugin-install done '
      'session=${session.sessionId} cli=${cli.value} '
      'ms=${nativePluginStarted.elapsedMilliseconds}',
    );

    final postFlush = registry.capability<CliSessionCapability>(cli);
    if (postFlush != null) {
      await postFlush.afterManifestFlush(
        PostManifestFlushContext(
          workFs: workContext.fs,
          workHome: workContext.home,
          environment: staged.outcome.environment,
          remoteRunner: SshWorkPlaneScriptRunner.tryCreate(
            sshProfileId: workSshProfileId,
            sshClientFactory: manifestExecutor.sshClientFactory,
            profileById: manifestExecutor.profileById,
          ),
          reportDetail: (detail) {
            report(CliInstallPhase.syncingRemoteWorkspace, detail: detail);
          },
        ),
      );
    }

    final environment = offHome
        ? normalizeWorkEnvironment(workContext.fs, staged.outcome.environment)
        : staged.outcome.environment;

    final shellLaunch = await lifecycle.prepareShellLaunchFromEnvironmentPlan(
      session: session,
      workspace: workspace,
      plan: plan,
      team: team,
      memberBinding: memberBinding,
      environment: environment,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
      agentStatus: agentStatus,
    );

    return (
      shellLaunch: shellLaunch,
      warnings: [...staged.outcome.warnings, ...shellLaunch.plan.warnings],
      remoteCliPath: remoteCliPath,
    );
  }

  void scheduleWorkspaceProvision({
    required RuntimeTarget launchTarget,
    required Workspace workspace,
    required CliTool cli,
  }) {
    workspaceProvision.schedule(
      target: launchTarget,
      workspaceId: workspace.workspaceId,
      cli: cli,
      trustedDirectories: [for (final folder in workspace.folders) folder.path],
    );
  }

  void scheduleTeamWorkspaceProvision({
    required RuntimeTarget launchTarget,
    required Workspace workspace,
    required TeamProfile team,
    required CliTool cli,
  }) {
    workspaceProvision.schedule(
      target: launchTarget,
      workspaceId: workspace.workspaceId,
      cli: cli,
      trustedDirectories: [for (final folder in workspace.folders) folder.path],
    );
  }

  void invalidateWorkspaceProvision(Workspace workspace) {
    final seen = <String>{};
    for (final folder in workspace.folders) {
      final targetId = folder.targetId.trim();
      if (targetId.isEmpty || !seen.add(targetId)) continue;
      workspaceProvision.invalidate(
        targetId: targetId,
        workspaceId: workspace.workspaceId,
      );
    }
  }

  TeamRosterSlot _slotForMember(TeamProfile team, TeamMemberConfig member) =>
      teamRosterSlotForMember(team, member);
}

/// Same preset merge as [SessionLifecycleService] shell launch (team only).
TeamMemberConfig _memberWithPreset(TeamMemberConfig member, CliPreset? preset) {
  if (preset == null) return member;
  return member.copyWith(
    provider: preset.provider.trim().isNotEmpty
        ? preset.provider.trim()
        : member.provider,
    model: preset.model.trim().isNotEmpty ? preset.model.trim() : member.model,
    effort: preset.effort.trim().isNotEmpty
        ? preset.effort.trim()
        : member.effort,
    cli: preset.cli,
    updateCli: true,
  );
}
