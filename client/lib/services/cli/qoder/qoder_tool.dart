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
import 'capabilities/executable_cn.dart';
import 'capabilities/headless.dart';
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/hook_writer.dart';
import 'capabilities/mcp.dart';
import 'capabilities/plugin.dart';
import 'capabilities/prompt.dart';
import 'capabilities/provider.dart';
import 'capabilities/session.dart';
import 'capabilities/usage/session_usage.dart';
import 'qoder_flavor.dart';

/// Qoder CLI (`qodercli` or `qoderclicn`), ACP-only.
final class QoderCliTool implements CliToolDefinition {
  QoderCliTool({
    QoderFlavor flavor = QoderFlavor.global,
    QoderTeamBehavior teamBehavior = const QoderTeamBehavior(),
    CliExecutableCapability? executable,
    CliSessionCapability session = const QoderCliSessionCapability(),
    QoderProviderCapability? provider,
    QoderTerminalBehavior terminalBehavior = const QoderTerminalBehavior(),
    MemberConfigInspectionCapability memberConfigInspection =
        const DefaultMemberConfigInspection(),
    QoderPluginCapability plugin = const QoderPluginCapability(),
    QoderChatInteraction chatInteraction = const QoderChatInteraction(),
    QoderChatInteraction runtimeEvents = const QoderChatInteraction(),
    SkillCapability skill = const DefaultSkillCapability(),
    QoderNativeCommands nativeCommands = const QoderNativeCommands(),
    QoderAiHistoryCapability? aiHistory,
    QoderSessionUsageCapability? sessionUsage,
    UserExtraArgsProvider userExtraArgs = const UserExtraArgsProvider(),
    QoderPromptCapability? prompt,
    QoderMcpCapability mcp = const QoderMcpCapability(),
    QoderHookWriter? hookWriter,
    QoderWorkspaceBaseInfo workspaceBaseInfo = const QoderWorkspaceBaseInfo(),
    CliLaunchSecurityCapability launchSecurity =
        const AcpAskFullAccessCliLaunchSecurityCapability(),
    QoderHeadlessCapability? headless,
    QoderAcpCapability? acp,
    AcpSettingsCapability acpSettings = const DefaultAcpSettingsCapability(
      usesSeparateAdapter: false,
    ),
    CliTransportCapability transport = const CliTransportCapability(
      supported: {CliTransport.acp},
    ),
  }) : _flavor = flavor,
       teamBehavior = teamBehavior,
       executable = executable ?? qoderExecutableForFlavor(flavor),
       session = session,
       provider = provider ?? QoderProviderCapability(flavor: flavor),
       terminalBehavior = terminalBehavior,
       memberConfigInspection = memberConfigInspection,
       plugin = plugin,
       chatInteraction = chatInteraction,
       runtimeEvents = runtimeEvents,
       skill = skill,
       nativeCommands = nativeCommands,
       aiHistory = aiHistory ?? QoderAiHistoryCapability(flavor: flavor),
       sessionUsage =
           sessionUsage ?? QoderSessionUsageCapability(flavor: flavor),
       userExtraArgs = userExtraArgs,
       prompt = prompt ?? QoderPromptCapability(flavor: flavor),
       mcp = mcp,
       hookWriter = hookWriter ?? QoderHookWriter(flavor: flavor),
       workspaceBaseInfo = workspaceBaseInfo,
       launchSecurity = launchSecurity,
       headless = headless ?? QoderHeadlessCapability(flavor: flavor),
       acp =
           acp ??
           QoderAcpCapability(transcriptFallbackPrefix: flavor.cli.value),
       acpSettings = acpSettings,
       transport = transport;

  final QoderFlavor _flavor;
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
  final QoderSessionUsageCapability sessionUsage;
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
  CliTool get id => _flavor.cli;

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

CliExecutableCapability qoderExecutableForFlavor(QoderFlavor flavor) =>
    flavor.isCn
        ? const QoderCnExecutableCapability()
        : const QoderExecutableCapability();
