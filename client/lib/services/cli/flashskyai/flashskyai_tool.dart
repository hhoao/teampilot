import 'capabilities/provider.dart';
import '../registry/capabilities/provider_capability.dart';
import '../../../models/team_config.dart';
import 'capabilities/session.dart';
import '../registry/cli_capability.dart';
import '../registry/cli_tool_definition.dart';
import 'capabilities/team_behavior.dart';
import 'capabilities/session_selection_launch.dart';
import 'capabilities/workspace_access_launch.dart';
import 'capabilities/model_launch.dart';
import 'capabilities/permission_launch.dart';
import 'capabilities/prompt_launch.dart';
import 'capabilities/chat_interaction.dart';
import 'capabilities/terminal_behavior.dart';
import '../registry/capabilities/team_behavior_capability.dart';
import '../registry/capabilities/cli_session_capability.dart';
import '../registry/capabilities/headless_capability.dart';
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/prompt.dart';
import '../registry/capabilities/prompt_capability.dart';
import 'capabilities/headless.dart';
import '../registry/capabilities/member_config_inspection_capability.dart';
import '../registry/capabilities/skill_capability.dart';
import '../registry/capabilities/chat_interaction_capability.dart';
import '../registry/capabilities/cli_executable_capability.dart';
import '../claude/capabilities/mcp.dart';
import 'capabilities/plugin.dart';
import '../registry/capabilities/plugin_capability.dart';
import 'capabilities/executable.dart';
import '../registry/resources/default_resource_capability.dart';
import '../registry/capabilities/hook_capability.dart';
import '../registry/launch/user_extra_args_provider.dart';
import 'capabilities/hook_writer.dart';

final class FlashskyaiCliTool implements CliToolDefinition {
  const FlashskyaiCliTool({
    this.teamBehavior = const FlashskyaiTeamBehavior(),
    this.sessionSelection = const FlashskyaiSessionSelectionLaunch(),
    this.workspaceAccess = const FlashskyaiWorkspaceAccessLaunch(),
    this.modelLaunch = const FlashskyaiModelLaunch(),
    this.permissionLaunch = const FlashskyaiPermissionLaunch(),
    this.userExtraArgs = const UserExtraArgsProvider(),
    this.promptLaunch = const FlashskyaiPromptLaunch(),
    this.session = const FlashskyaiCliSessionCapability(),
    this.executable = const FlashskyaiExecutableCapability(),
    this.terminalBehavior = const FlashskyaiTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.plugin = const FlashskyaiPluginCapability(),
    this.provider = const FlashskyaiProviderCapability(),
    this.headless = const FlashskyaiHeadlessCapability(),
    this.mcp = const FlashskyaiMcpCapability(),
    this.chatInteraction = const FlashskyaiChatInteraction(),
    this.aiHistory = const FlashskyaiAiHistoryCapability(),
    this.skill = const DefaultSkillCapability(),
    this.hookWriter = const FlashskyaiHookWriter(),
    this.prompt = const FlashskyaiPromptCapability(),
  });

  final ProviderCapability provider;

  final CliSessionCapability session;
  final CliExecutableCapability executable;
  final FlashskyaiTerminalBehavior terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final PluginCapability plugin;
  final HeadlessCapability headless;
  final FlashskyaiMcpCapability mcp;

  final TeamBehaviorCapability teamBehavior;
  final FlashskyaiSessionSelectionLaunch sessionSelection;
  final FlashskyaiWorkspaceAccessLaunch workspaceAccess;
  final FlashskyaiModelLaunch modelLaunch;
  final FlashskyaiPermissionLaunch permissionLaunch;
  final FlashskyaiPromptLaunch promptLaunch;
  final UserExtraArgsProvider userExtraArgs;
  final HookCapability hookWriter;
  final PromptCapability prompt;
  final ChatInteractionCapability chatInteraction;
  final FlashskyaiAiHistoryCapability aiHistory;
  final SkillCapability skill;

  @override
  CliTool get id => CliTool.flashskyai;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => [
    teamBehavior,
    sessionSelection,
    workspaceAccess,
    modelLaunch,
    permissionLaunch,
    userExtraArgs,
    promptLaunch,
    executable,
    session,
    terminalBehavior,
    memberConfigInspection,
    plugin,
    provider,
    headless,
    mcp,
    chatInteraction,
    aiHistory,
    skill,
    hookWriter,
    prompt,
  ];
}
