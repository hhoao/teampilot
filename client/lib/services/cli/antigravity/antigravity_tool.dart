import '../../../models/team_config.dart';
import '../registry/capabilities/acp_capability.dart';
import '../registry/capabilities/acp_settings_capability.dart';
import '../registry/capabilities/chat_interaction_capability.dart';
import '../registry/capabilities/cli_executable_capability.dart';
import '../registry/capabilities/cli_launch_security_capability.dart';
import '../registry/capabilities/cli_session_capability.dart';
import '../registry/capabilities/cli_transport_capability.dart';
import '../registry/capabilities/member_config_inspection_capability.dart';
import '../registry/capabilities/plugin_capability.dart';
import '../registry/capabilities/provider_capability.dart';
import '../registry/capabilities/runtime_event_capability.dart';
import '../registry/capabilities/skill_capability.dart';
import '../registry/capabilities/team_behavior_capability.dart';
import '../registry/capabilities/terminal_behavior_capability.dart';
import '../registry/capabilities/workspace_base_info_capability.dart';
import '../registry/cli_capability.dart';
import '../registry/cli_tool_definition.dart';
import '../registry/launch/user_extra_args_provider.dart';
import '../registry/resources/default_resource_capability.dart';
import 'capabilities/acp.dart';
import 'capabilities/acp_settings.dart';
import 'capabilities/defaults.dart';
import 'capabilities/executable.dart';
import 'capabilities/plugin.dart';
import 'capabilities/provider.dart';
import 'capabilities/session.dart';

/// Antigravity CLI (`agy`) tool definition.
///
/// ACP-only: TeamPilot launches the separate Antigravity ACP adapter and never
/// launches this CLI as a PTY. Later tasks add the remaining resource surfaces.
final class AntigravityCliTool implements CliToolDefinition {
  const AntigravityCliTool({
    this.teamBehavior = const AntigravityTeamBehavior(),
    this.executable = const AntigravityExecutableCapability(),
    this.session = const AntigravityCliSessionCapability(),
    this.provider = const AntigravityProviderCapability(),
    this.terminalBehavior = const AntigravityTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.plugin = const AntigravityPluginCapability(),
    this.chatInteraction = const AntigravityChatInteraction(),
    this.runtimeEvents = const AntigravityChatInteraction(),
    this.skill = const DefaultSkillCapability(),
    this.userExtraArgs = const UserExtraArgsProvider(),
    this.workspaceBaseInfo = const AntigravityWorkspaceBaseInfo(),
    this.launchSecurity = const AcpAskFullAccessCliLaunchSecurityCapability(),
    this.acp = const AntigravityAcpCapability(),
    this.acpSettings = const AntigravityAcpSettings(),
    this.transport = const CliTransportCapability(supported: {CliTransport.acp}),
  });

  final ProviderCapability provider;
  final CliSessionCapability session;
  final CliExecutableCapability executable;
  final TeamBehaviorCapability teamBehavior;
  final TerminalBehaviorCapability terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final PluginCapability plugin;
  final ChatInteractionCapability chatInteraction;
  final RuntimeEventCapability runtimeEvents;
  final SkillCapability skill;
  final UserExtraArgsProvider userExtraArgs;
  final WorkspaceBaseInfoCapability workspaceBaseInfo;
  final CliLaunchSecurityCapability launchSecurity;
  final AcpCapability acp;
  final AcpSettingsCapability acpSettings;
  final CliTransportCapability transport;

  @override
  CliTool get id => CliTool.antigravity;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => [
    executable,
    session,
    provider,
    teamBehavior,
    terminalBehavior,
    memberConfigInspection,
    plugin,
    chatInteraction,
    runtimeEvents,
    skill,
    userExtraArgs,
    workspaceBaseInfo,
    launchSecurity,
    acp,
    acpSettings,
    transport,
  ];
}
