import '../../models/app_session.dart';
import '../../models/cli_preset.dart';
import '../../models/personal_profile.dart';
import '../../models/runtime_target.dart';
import '../../models/session_member_binding.dart';
import '../../models/team_config.dart';
import '../../models/workspace.dart';
import '../../utils/team_member_naming.dart';
import '../team_bus/member_bus_idle_endpoint.dart';
import '../provider/config_profile_service.dart';
import '../../services/cli/preset_resolver.dart';
import '../session/session_lifecycle_service.dart';
import '../storage/runtime_context.dart';
import 'manifest_executor.dart';
import 'workspace_provision_coordinator.dart';

typedef ConfigProfileServiceFactory =
    Future<ConfigProfileService> Function(RuntimeContext context);

/// Phase A + B orchestration for personal and team session connect.
class SessionConnectOrchestrator {
  SessionConnectOrchestrator({
    required this.lifecycle,
    required this.workspaceProvision,
    required this.configProfileFor,
    required this.homeContext,
    required this.manifestExecutor,
  });

  final SessionLifecycleService lifecycle;
  final WorkspaceProvisionCoordinator workspaceProvision;
  final ConfigProfileServiceFactory configProfileFor;
  final RuntimeContext Function() homeContext;
  final ManifestExecutor manifestExecutor;

  Future<({
    ShellLaunchSpec shellLaunch,
    List<String> warnings,
    String remoteCliPath,
  })> preparePersonalConnect({
    required AppSession session,
    required Workspace workspace,
    required PersonalProfile personal,
    required CliPreset? preset,
    required RuntimeTarget launchTarget,
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
  }) async {
    final cli = session.cli ?? preset?.cli ?? CliTool.claude;
    final trustedDirectories = [
      for (final folder in workspace.folders) folder.path,
    ];

    final offHome = workspaceProvision.isOffHome(launchTarget);
    late final RuntimeContext workContext;
    late final String remoteCliPath;

    if (offHome) {
      final provision = await workspaceProvision.ensureReady(
        target: launchTarget,
        workspaceId: workspace.workspaceId,
        cli: cli,
        personal: personal,
        trustedDirectories: trustedDirectories,
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
    final staged = await catalogProfile.stageSessionLaunch(
      readDelegate: offHome ? homeContext().fs : workContext.fs,
      workTeampilotRoot: workContext.appDataRoot,
      workspaceId: workspace.workspaceId,
      sessionId: session.sessionId,
      profileId: personal.id,
      personal: personal,
      workingDirectory: session.firstFolderPath,
      additionalDirectories: session.extraFolderPaths,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
      preset: preset,
    );

    await manifestExecutor.flush(
      manifest: staged.manifest,
      targetFs: workContext.fs,
      sourceFs: offHome ? homeContext().fs : workContext.fs,
      sshProfileId: offHome ? launchTarget.sshProfileId : null,
    );

    final shellLaunch = await lifecycle.prepareShellLaunchFromEnvironment(
      session: session,
      workspace: workspace,
      personal: personal,
      preset: preset,
      environment: staged.outcome.environment,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
    );

    return (
      shellLaunch: shellLaunch,
      warnings: [
        ...staged.outcome.warnings,
        ...shellLaunch.plan.warnings,
      ],
      remoteCliPath: remoteCliPath,
    );
  }

  Future<({
    ShellLaunchSpec shellLaunch,
    List<String> warnings,
    String remoteCliPath,
  })> prepareTeamConnect({
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
    final cli = memberLaunchCli(
      team: team,
      member: member,
      globalPresets: lifecycle.globalPresets,
    );
    final offHome = workspaceProvision.isOffHome(launchTarget);
    late final RuntimeContext workContext;
    late final String remoteCliPath;

    if (offHome) {
      final provision = await workspaceProvision.ensureReady(
        target: launchTarget,
        workspaceId: session.workspaceId,
        cli: cli,
        personal: null,
      );
      workContext = provision.workContext;
      remoteCliPath = provision.remoteCliPath;
    } else {
      workContext = await lifecycle.resolveWorkContextForTargetId(
        launchTarget.id,
      );
      remoteCliPath = await workspaceProvision.provisioner.localCliPath(cli);
    }

    final teamId = team.id.trim();
    final cliTeamName = session.cliTeamName.trim();
    final runtimeTeamId = cliTeamName.isNotEmpty ? cliTeamName : session.sessionId;
    final leadTaskId = memberBinding?.taskId.trim() ?? '';
    final leadSessionId =
        TeamMemberNaming.isTeamLead(member) && leadTaskId.isNotEmpty
        ? leadTaskId
        : null;

    final catalogProfile = await configProfileFor(
      offHome ? homeContext() : workContext,
    );
    final staged = await catalogProfile.stageTeamLaunch(
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
      leadSessionId: leadSessionId,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
    );

    await manifestExecutor.flush(
      manifest: staged.manifest,
      targetFs: workContext.fs,
      sourceFs: offHome ? homeContext().fs : workContext.fs,
      sshProfileId: offHome ? launchTarget.sshProfileId : null,
    );

    final shellLaunch = await lifecycle.prepareTeamShellLaunchFromEnvironment(
      session: session,
      team: team,
      member: member,
      memberBinding: memberBinding,
      workspace: workspace,
      environment: staged.outcome.environment,
    );

    return (
      shellLaunch: shellLaunch,
      warnings: [
        ...staged.outcome.warnings,
        ...shellLaunch.plan.warnings,
      ],
      remoteCliPath: remoteCliPath,
    );
  }

  void scheduleWorkspaceProvision({
    required RuntimeTarget launchTarget,
    required Workspace workspace,
    required PersonalProfile personal,
    required CliTool cli,
  }) {
    workspaceProvision.schedule(
      target: launchTarget,
      workspaceId: workspace.workspaceId,
      cli: cli,
      personal: personal,
      trustedDirectories: [
        for (final folder in workspace.folders) folder.path,
      ],
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
      personal: null,
      trustedDirectories: [
        for (final folder in workspace.folders) folder.path,
      ],
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
}
