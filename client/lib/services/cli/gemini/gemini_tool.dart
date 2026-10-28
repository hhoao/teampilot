import '../../../models/team_config.dart';
import '../registry/cli_capability.dart';
import '../registry/cli_tool_definition.dart';
import '../registry/capabilities/acp_capability.dart';
import '../registry/capabilities/cli_transport_capability.dart';
import '../registry/capabilities/ai_history_capability.dart';
import '../registry/capabilities/cli_executable_capability.dart';
import '../registry/capabilities/cli_launch_security_capability.dart';
import '../registry/capabilities/cli_session_capability.dart';
import '../registry/capabilities/chat_interaction_capability.dart';
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
import '../registry/launch/user_extra_args_provider.dart';
import '../registry/resources/default_resource_capability.dart';
import 'capabilities/acp.dart';
import 'capabilities/defaults.dart';
import 'capabilities/executable.dart';
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/hook_writer.dart';
import 'capabilities/mcp.dart';
import 'capabilities/native_commands.dart';
import 'capabilities/prompt.dart';
import 'capabilities/provider.dart';
import 'capabilities/session.dart';
import 'capabilities/usage/session_usage.dart';
import 'capabilities/workspace_base_info.dart';

/// Gemini CLI (`@google/gemini-cli`) tool definition.
///
/// Phase 1 (this file): registry-complete default capabilities — npm
/// executable/installer, noop session lifecycle, minimal provider catalog,
/// and "not supported" team/chat/plugin defaults. ACP transport arrives in a
/// later task as a [CliCapability] on this definition.
final class GeminiCliTool implements CliToolDefinition {
  const GeminiCliTool({
    this.teamBehavior = const GeminiTeamBehavior(),
    this.executable = const GeminiExecutableCapability(),
    this.session = const GeminiCliSessionCapability(),
    this.provider = const GeminiProviderCapability(),
    this.terminalBehavior = const GeminiTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.plugin = const GeminiPluginCapability(),
    this.chatInteraction = const GeminiChatInteraction(),
    this.runtimeEvents = const GeminiChatInteraction(),
    this.skill = const DefaultSkillCapability(),
    this.nativeCommands = const GeminiNativeCommands(),
    this.aiHistory = const GeminiAiHistoryCapability(),
    this.sessionUsage = const GeminiSessionUsageCapability(),
    this.userExtraArgs = const UserExtraArgsProvider(),
    this.prompt = const GeminiPromptCapability(),
    this.mcp = const GeminiMcpCapability(),
    this.hookWriter = const GeminiHookWriter(),
    this.workspaceBaseInfo = const GeminiWorkspaceBaseInfo(),
    this.launchSecurity = const AcpAskFullAccessCliLaunchSecurityCapability(),
    this.acp = const GeminiAcpCapability(),
    this.transport = const CliTransportCapability(
      supported: {CliTransport.acp},
    ),
  });

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
  final GeminiSessionUsageCapability sessionUsage;
  final UserExtraArgsProvider userExtraArgs;
  final PromptCapability prompt;
  final McpCapability mcp;
  final HookCapability hookWriter;
  final WorkspaceBaseInfoCapability workspaceBaseInfo;
  final CliLaunchSecurityCapability launchSecurity;
  final AcpCapability acp;
  final CliTransportCapability transport;

  @override
  CliTool get id => CliTool.gemini;

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
    acp,
    transport,
  ];
}
