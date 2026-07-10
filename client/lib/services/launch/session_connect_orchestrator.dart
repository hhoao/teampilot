import '../../models/app_session.dart';
import '../../models/runtime_target.dart';
import '../../models/session_member_binding.dart';
import '../../models/team_config.dart';
import '../../models/team_roster_slot.dart';
import '../../models/workspace.dart';
import '../../utils/team_member_naming.dart';
import '../cli/registry/mcp_writers/claude_project_mcp_cleanup.dart';
import '../cli/preset_resolver.dart';
import '../provider/config_profile_service.dart';
import '../session/session_lifecycle_service.dart';
import '../storage/runtime_context.dart';
import '../team_bus/member_bus_idle_endpoint.dart';
import 'launch_manifest.dart';
import 'launch_manifest_paths.dart';
import 'manifest_executor.dart';
import 'session_runtime_plan.dart';
import 'session_runtime_plan_builder.dart';
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
  });

  final SessionLifecycleService lifecycle;
  final WorkspaceProvisionCoordinator workspaceProvision;
  final ConfigProfileServiceFactory configProfileFor;
  final RuntimeContext Function() homeContext;
  final ManifestExecutor manifestExecutor;
  final SessionRuntimePlanBuilder runtimePlanBuilder;

  Future<
    ({ShellLaunchSpec shellLaunch, List<String> warnings, String remoteCliPath})
  >
  prepareSimpleConnect({
    required AppSession session,
    required Workspace workspace,
    required RuntimeTarget launchTarget,
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
  }) async {
    final identity = session.simpleIdentity;
    final plan = await runtimePlanBuilder.buildSimple(
      workspaceId: workspace.workspaceId,
      sessionId: session.sessionId,
      memberId: session.sessionId,
      identity: identity,
    );
    return _prepareConnectFromPlan(
      session: session,
      workspace: workspace,
      plan: plan,
      launchTarget: launchTarget,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
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
  }) async {
    final resolvedWorkspace =
        workspace ??
        Workspace(
          workspaceId: session.workspaceId,
          folders: session.folders,
          createdAt: session.createdAt,
        );
    final slot = _slotForMember(team, member);
    final plan = await runtimePlanBuilder.buildTeamSeat(
      workspaceId: resolvedWorkspace.workspaceId,
      sessionId: session.sessionId,
      team: team,
      slot: slot,
      presetId: member.activePresetId,
      member: member,
    );
    return _prepareConnectFromPlan(
      session: session,
      workspace: resolvedWorkspace,
      plan: plan,
      team: team,
      memberBinding: memberBinding,
      launchTarget: launchTarget,
      workingDirectory: workingDirectory,
      additionalDirectories: additionalDirectories,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
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
  }) async {
    final isSimple = plan.mode == SessionRuntimeMode.simple;
    final member = plan.member;
    final cli = isSimple
        ? (session.cli ?? member.cli ?? CliTool.claude)
        : memberLaunchCli(
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
      );
      workContext = provision.workContext;
      remoteCliPath = provision.remoteCliPath;
    } else {
      workContext = await lifecycle.resolveWorkContextForTargetId(
        launchTarget.id,
      );
      remoteCliPath = await workspaceProvision.provisioner.localCliPath(cli);
    }

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
        members: team.members,
        member: member,
        workingDirectory: workingDirectory,
        additionalDirectories: additionalDirectories,
        team: team,
        runtimeBundle: plan.runtimeBundle,
        leadSessionId: leadSessionId,
        extraMcpServers: extraMcpServers,
        busIdle: busIdle,
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

    await manifestExecutor.flush(
      manifest: staged.manifest,
      targetFs: workContext.fs,
      sourceFs: offHome ? homeContext().fs : workContext.fs,
      sshProfileId: offHome ? launchTarget.sshProfileId : null,
    );

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
