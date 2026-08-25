import 'capabilities/provider.dart';
import '../registry/capabilities/provider_capability.dart';
import '../../../models/team_config.dart';
import 'capabilities/session.dart';
import '../registry/cli_capability.dart';
import '../registry/cli_tool_definition.dart';
import 'capabilities/team_behavior.dart';
import 'capabilities/native_commands.dart';
import 'capabilities/session_selection_launch.dart';
import 'capabilities/workspace_access_launch.dart';
import 'capabilities/model_launch.dart';
import 'capabilities/permission_launch.dart';
import 'capabilities/prompt_launch.dart';
import 'capabilities/terminal_behavior.dart';
import 'capabilities/chat_interaction.dart';
import '../registry/capabilities/team_behavior_capability.dart';
import '../registry/capabilities/cli_session_capability.dart';
import '../registry/capabilities/headless_capability.dart';
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/headless.dart';
import '../registry/capabilities/member_config_inspection_capability.dart';
import '../registry/capabilities/skill_capability.dart';
import '../registry/capabilities/native_command_capability.dart';
import '../registry/capabilities/chat_interaction_capability.dart';
import '../registry/capabilities/runtime_event_capability.dart';
import '../registry/capabilities/cli_executable_capability.dart';
import 'capabilities/mcp.dart';
import 'capabilities/plugin.dart';
import 'capabilities/prompt.dart';
import 'capabilities/executable.dart';
import '../registry/capabilities/prompt_capability.dart';
import '../registry/capabilities/plugin_capability.dart';
import '../registry/resources/default_resource_capability.dart';
import '../registry/config_profile/claude_family_hook_writer.dart';
import '../registry/capabilities/hook_capability.dart';
import '../registry/launch/user_extra_args_provider.dart';

final class ClaudeCliTool implements CliToolDefinition {
  ClaudeCliTool({
    this.teamBehavior = const ClaudeTeamBehavior(),
    this.sessionSelection = const ClaudeSessionSelectionLaunch(),
    this.workspaceAccess = const ClaudeWorkspaceAccessLaunch(),
    this.modelLaunch = const ClaudeModelLaunch(),
    this.permissionLaunch = const ClaudePermissionLaunch(),
    this.promptLaunch = const ClaudePromptLaunch(),
    this.userExtraArgs = const UserExtraArgsProvider(),
    this.session = const ClaudeCliSessionCapability(),
    this.executable = const ClaudeExecutableCapability(),
    this.terminalBehavior = const ClaudeTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.plugin = const ClaudePluginCapability(),
    this.provider = const ClaudeProviderCapability(),

    this.headless = const ClaudeHeadlessCapability(),

    this.mcp = const ClaudeMcpCapability(),
    this.chatInteraction = const ClaudeChatInteraction(),
    this.runtimeEvents = const ClaudeChatInteraction(),
    this.aiHistory = const ClaudeAiHistoryCapability(),
    this.skill = const DefaultSkillCapability(),
    this.nativeCommands = const ClaudeNativeCommands(),

    this.prompt = const ClaudePromptCapability(),

    HookCapability? hookWriter,
  }) : hookWriter = hookWriter ?? const ClaudeFamilyHookWriter();

  final ProviderCapability provider;
  final HookCapability hookWriter;

  final CliSessionCapability session;
  final CliExecutableCapability executable;
  final ClaudeTerminalBehavior terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final PluginCapability plugin;
  final HeadlessCapability headless;
  final ClaudeMcpCapability mcp;

  final TeamBehaviorCapability teamBehavior;
  final ClaudeSessionSelectionLaunch sessionSelection;
  final ClaudeWorkspaceAccessLaunch workspaceAccess;
  final ClaudeModelLaunch modelLaunch;
  final ClaudePermissionLaunch permissionLaunch;
  final ClaudePromptLaunch promptLaunch;
  final UserExtraArgsProvider userExtraArgs;
  final ChatInteractionCapability chatInteraction;
  final RuntimeEventCapability runtimeEvents;
  final ClaudeAiHistoryCapability aiHistory;
  final SkillCapability skill;
  final NativeCommandCapability nativeCommands;
  final PromptCapability prompt;

  @override
  CliTool get id => CliTool.claude;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => [
    teamBehavior,
    sessionSelection,
    workspaceAccess,
    modelLaunch,
    permissionLaunch,
    promptLaunch,
    userExtraArgs,
    executable,
    session,
    terminalBehavior,
    memberConfigInspection,
    plugin,
    provider,
    headless,
    mcp,
    chatInteraction,
    runtimeEvents,
    aiHistory,
    skill,
    nativeCommands,
    prompt,
    hookWriter,
  ];
}
