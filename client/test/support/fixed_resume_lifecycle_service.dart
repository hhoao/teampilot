import 'dart:io';

import 'package:teampilot/models/app_session.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/session_member_binding.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/workspace.dart';
import 'package:teampilot/services/launch/session_runtime_plan.dart';
import 'package:teampilot/services/session/session_lifecycle_service.dart';
import 'package:teampilot/services/session/shell_launch_spec.dart'
    show LaunchPlan, ShellLaunchSpec;
import 'package:teampilot/services/agent_status/member_agent_status_endpoint.dart';
import 'package:teampilot/services/team_bus/member_bus_idle_endpoint.dart';

/// Forces [LaunchPlan.resume] so open-session tests can assert session-id vs resume.
class FixedResumeLifecycleService extends SessionLifecycleService {
  FixedResumeLifecycleService({required this.resume})
    : super(appDataBasePath: Directory.systemTemp.path);

  final bool resume;

  @override
  Future<ShellLaunchSpec> prepareShellLaunch({
    required AppSession session,
    required TeamProfile team,
    TeamMemberConfig? member,
    SessionMemberBinding? memberBinding,
    Workspace? workspace,
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
    MemberAgentStatusEndpoint? agentStatus,
  }) async {
    final spec = await super.prepareShellLaunch(
      session: session,
      team: team,
      member: member,
      memberBinding: memberBinding,
      workspace: workspace,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
      agentStatus: agentStatus,
    );
    return _withFixedResume(spec);
  }

  @override
  Future<ShellLaunchSpec> prepareShellLaunchFromEnvironmentPlan({
    required AppSession session,
    required Workspace workspace,
    required SessionRuntimePlan plan,
    TeamProfile? team,
    SessionMemberBinding? memberBinding,
    CliPreset? preset,
    required Map<String, String> environment,
    Map<String, Map<String, Object?>>? extraMcpServers,
    MemberBusIdleEndpoint? busIdle,
    MemberAgentStatusEndpoint? agentStatus,
  }) async {
    final spec = await super.prepareShellLaunchFromEnvironmentPlan(
      session: session,
      workspace: workspace,
      plan: plan,
      team: team,
      memberBinding: memberBinding,
      preset: preset,
      environment: environment,
      extraMcpServers: extraMcpServers,
      busIdle: busIdle,
      agentStatus: agentStatus,
    );
    return _withFixedResume(spec);
  }

  @override
  Future<ShellLaunchSpec> prepareTeamShellLaunchFromEnvironment({
    required AppSession session,
    required TeamProfile team,
    required TeamMemberConfig member,
    SessionMemberBinding? memberBinding,
    Workspace? workspace,
    required Map<String, String> environment,
    List<String> launchWarnings = const [],
  }) async {
    final spec = await super.prepareTeamShellLaunchFromEnvironment(
      session: session,
      team: team,
      member: member,
      memberBinding: memberBinding,
      workspace: workspace,
      environment: environment,
      launchWarnings: launchWarnings,
    );
    return _withFixedResume(spec);
  }

  ShellLaunchSpec _withFixedResume(ShellLaunchSpec spec) {
    final plan = spec.plan;
    return ShellLaunchSpec(
      plan: LaunchPlan(
        env: plan.env,
        resume: resume,
        taskId: plan.taskId,
        createSessionId: resume ? null : plan.taskId,
        resumeSessionId: resume ? plan.taskId : null,
        cliTeamName: plan.cliTeamName,
        memberConfigDir: plan.memberConfigDir,
        resolvedRoots: plan.resolvedRoots,
        warnings: plan.warnings,
      ),
      launchContext: spec.launchContext,
    );
  }
}
