import '../../../models/team_config.dart';
import '../registry/capabilities/acp_capability.dart';
import '../registry/capabilities/acp_settings_capability.dart';
import '../registry/capabilities/ai_history_capability.dart';
import '../registry/capabilities/chat_interaction_capability.dart';
import '../registry/capabilities/cli_executable_capability.dart';
import '../registry/capabilities/cli_launch_security_capability.dart';
import '../registry/capabilities/cli_session_capability.dart';
import '../registry/capabilities/cli_transport_capability.dart';
import '../registry/capabilities/headless_capability.dart';
import '../registry/capabilities/hook_capability.dart';
import '../registry/capabilities/mcp_capability.dart';
import '../registry/capabilities/member_config_inspection_capability.dart';
import '../registry/capabilities/native_command_capability.dart';
import '../registry/capabilities/plugin_capability.dart';
import '../registry/capabilities/prompt_capability.dart';
import '../registry/capabilities/provider_capability.dart';
import '../registry/capabilities/runtime_event_capability.dart';
import '../registry/capabilities/session_credential_capability.dart';
import '../registry/capabilities/skill_capability.dart';
import '../registry/capabilities/team_behavior_capability.dart';
import '../registry/capabilities/terminal_behavior_capability.dart';
import '../registry/capabilities/workspace_base_info_capability.dart';
import '../registry/cli_capability.dart';
import '../registry/cli_tool_definition.dart';
import '../registry/launch/user_extra_args_provider.dart';
import '../registry/resources/default_resource_capability.dart';
import 'capabilities/acp.dart';
import 'capabilities/defaults.dart';
import 'capabilities/executable.dart';
import 'capabilities/headless.dart';
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/hook_writer.dart';
import 'capabilities/mcp.dart';
import 'capabilities/native_commands.dart';
import 'capabilities/plugin.dart';
import 'capabilities/prompt.dart';
import 'capabilities/provider.dart';
import 'capabilities/session.dart';
import 'capabilities/usage/session_usage.dart';
import 'capabilities/workspace_base_info.dart';

/// Official Grok Build CLI (`grok`), ACP-only.
///
/// PTY launching is intentionally absent: Grok always runs as an ACP agent
/// (`grok agent stdio`) with an isolated `GROK_HOME` per seat.
final class GrokCliTool implements CliToolDefinition {
  GrokCliTool({
    this.teamBehavior = const GrokTeamBehavior(),
    this.executable = const GrokExecutableCapability(),
    this.session = const GrokCliSessionCapability(),
    this.provider = const GrokProviderCapability(),
    this.terminalBehavior = const GrokTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.plugin = const GrokPluginCapability(),
    this.chatInteraction = const GrokChatInteraction(),
    this.runtimeEvents = const GrokChatInteraction(),
    this.skill = const DefaultSkillCapability(),
    this.nativeCommands = const GrokNativeCommands(),
    this.aiHistory = const GrokAiHistoryCapability(),
    this.sessionUsage = const GrokSessionUsageCapability(),
    this.userExtraArgs = const UserExtraArgsProvider(),
    this.prompt = const GrokPromptCapability(),
    this.mcp = const GrokMcpCapability(),
    this.hookWriter = const GrokHookWriter(),
    this.workspaceBaseInfo = const GrokWorkspaceBaseInfo(),
    this.launchSecurity = const AcpAskFullAccessCliLaunchSecurityCapability(),
    this.sessionCredential,
    GrokHeadlessCapability? headless,
    GrokAcpCapability? acp,
    this.acpSettings = const DefaultAcpSettingsCapability(
      usesSeparateAdapter: false,
    ),
    this.transport = const CliTransportCapability(
      supported: {CliTransport.acp},
    ),
  }) : headless = headless ?? const GrokHeadlessCapability(),
       acp = acp ?? const GrokAcpCapability();

  final TeamBehaviorCapability teamBehavior;
  final CliExecutableCapability executable;
  final CliSessionCapability session;
  final ProviderCapability provider;
  final TerminalBehaviorCapability terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final PluginCapability plugin;
  final ChatInteractionCapability chatInteraction;
  final RuntimeEventCapability runtimeEvents;
  final SkillCapability skill;
  final NativeCommandCapability nativeCommands;
  final AiHistoryCapability aiHistory;
  final GrokSessionUsageCapability sessionUsage;
  final UserExtraArgsProvider userExtraArgs;
  final PromptCapability prompt;
  final McpCapability mcp;
  final HookCapability hookWriter;
  final WorkspaceBaseInfoCapability workspaceBaseInfo;
  final CliLaunchSecurityCapability launchSecurity;
  final SessionCredentialCapability? sessionCredential;
  final HeadlessCapability headless;
  final AcpCapability acp;
  final AcpSettingsCapability acpSettings;
  final CliTransportCapability transport;

  @override
  CliTool get id => CliTool.grok;

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
    nativeCommands,
    aiHistory,
    sessionUsage,
    userExtraArgs,
    prompt,
    mcp,
    hookWriter,
    workspaceBaseInfo,
    launchSecurity,
    headless,
    acp,
    acpSettings,
    const GrokAcpNoPtyFallback(),
    const GrokAcpUsageLog(),
    transport,
    // Real runtime assembly injects the control-plane adapter; the
    // pre-configure registry (launch-arg assembly only) has none.
    if (sessionCredential != null) sessionCredential!,
  ];
}
