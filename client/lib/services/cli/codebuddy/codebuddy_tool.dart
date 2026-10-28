import '../../../models/team_config.dart';
import '../registry/capabilities/cli_transport_capability.dart';
import '../registry/capabilities/acp_capability.dart';
import '../registry/capabilities/acp_settings_capability.dart';
import '../registry/capabilities/ai_history_capability.dart';
import '../registry/capabilities/chat_interaction_capability.dart';
import '../registry/capabilities/cli_executable_capability.dart';
import '../registry/capabilities/cli_launch_security_capability.dart';
import '../registry/capabilities/cli_session_capability.dart';
import '../registry/capabilities/headless_capability.dart';
import '../registry/capabilities/hook_capability.dart';
import '../registry/capabilities/mcp_capability.dart';
import '../registry/capabilities/member_config_inspection_capability.dart';
import '../registry/capabilities/native_command_capability.dart';
import '../registry/capabilities/plugin_capability.dart';
import '../registry/capabilities/prompt_capability.dart';
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
import 'capabilities/defaults.dart';
import 'capabilities/executable.dart';
import 'capabilities/headless.dart';
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/hook_writer.dart';
import 'capabilities/mcp.dart';
import 'capabilities/plugin.dart';
import 'capabilities/prompt.dart';
import 'capabilities/provider.dart';
import 'capabilities/session.dart';
import 'capabilities/usage/session_usage.dart';

/// CodeBuddy CLI (`codebuddy`, alias `cbc`).
///
/// ACP-only: the CLI is launched as `codebuddy --acp` and never as a PTY.
/// Everything else (provider/models, skills, MCP, hooks, plugins, prompt,
/// native commands, headless) uses the CLI's Claude-compatible config
/// surfaces under `CODEBUDDY_CONFIG_DIR`.
final class CodebuddyCliTool implements CliToolDefinition {
  const CodebuddyCliTool({
    this.teamBehavior = const CodebuddyTeamBehavior(),
    this.executable = const CodebuddyExecutableCapability(),
    this.session = const CodebuddyCliSessionCapability(),
    this.provider = const CodebuddyProviderCapability(),
    this.terminalBehavior = const CodebuddyTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.plugin = const CodebuddyPluginCapability(),
    this.chatInteraction = const CodebuddyChatInteraction(),
    this.runtimeEvents = const CodebuddyChatInteraction(),
    this.skill = const DefaultSkillCapability(),
    this.nativeCommands = const CodebuddyNativeCommands(),
    this.aiHistory = const CodebuddyAiHistoryCapability(),
    this.sessionUsage = const CodebuddySessionUsageCapability(),
    this.userExtraArgs = const UserExtraArgsProvider(),
    this.prompt = const CodebuddyPromptCapability(),
    this.mcp = const CodebuddyMcpCapability(),
    this.hookWriter = const CodebuddyHookWriter(),
    this.workspaceBaseInfo = const CodebuddyWorkspaceBaseInfo(),
    this.launchSecurity = const AcpAskFullAccessCliLaunchSecurityCapability(),
    this.headless = const CodebuddyHeadlessCapability(),
    this.acp = const CodebuddyAcpCapability(),
    this.acpSettings = const DefaultAcpSettingsCapability(
      usesSeparateAdapter: false,
      showsPersonalAcpSwitch: false,
    ),
    this.transport = const CliTransportCapability(
      supported: {CliTransport.acp},
    ),
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
  final NativeCommandCapability nativeCommands;
  final AiHistoryCapability aiHistory;
  final CodebuddySessionUsageCapability sessionUsage;
  final UserExtraArgsProvider userExtraArgs;
  final PromptCapability prompt;
  final McpCapability mcp;
  final HookCapability hookWriter;
  final WorkspaceBaseInfoCapability workspaceBaseInfo;
  final CliLaunchSecurityCapability launchSecurity;
  final HeadlessCapability headless;
  final AcpCapability acp;
  final AcpSettingsCapability acpSettings;
  final CliTransportCapability transport;

  @override
  CliTool get id => CliTool.codebuddy;

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
    transport,
  ];
}
