import '../registry/capabilities/provider_capability.dart';
import 'capabilities/provider.dart';
import '../../../models/team_config.dart';
import 'capabilities/session.dart';
import '../registry/cli_capability.dart';
import '../registry/cli_tool_definition.dart';
import 'capabilities/team_behavior.dart';
import 'capabilities/native_commands.dart';
import 'capabilities/session_selection_launch.dart';
import 'capabilities/model_launch.dart';
import 'capabilities/permission_launch.dart';
import 'capabilities/agent_launch.dart';
import 'capabilities/user_extra_args_launch.dart';
import 'capabilities/chat_interaction.dart';
import 'capabilities/terminal_behavior.dart';
import '../registry/capabilities/cli_session_capability.dart';
import '../registry/capabilities/team_behavior_capability.dart';
import '../registry/capabilities/headless_capability.dart';
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/headless.dart';
import '../registry/capabilities/member_config_inspection_capability.dart';
import '../registry/capabilities/skill_capability.dart';
import '../registry/capabilities/native_command_capability.dart';
import '../registry/capabilities/chat_interaction_capability.dart';
import '../registry/capabilities/cli_executable_capability.dart';
import '../registry/capabilities/hook_capability.dart';
import 'capabilities/mcp.dart';
import 'capabilities/plugin.dart';
import '../registry/capabilities/plugin_capability.dart';
import 'capabilities/prompt.dart';
import 'capabilities/skill.dart';
import 'capabilities/opencode_hook_writer.dart';
import 'capabilities/executable.dart';
import '../registry/capabilities/prompt_capability.dart';

final class OpencodeCliTool implements CliToolDefinition {
  OpencodeCliTool({
    this.teamBehavior = const OpencodeTeamBehavior(),
    this.sessionSelection = const OpencodeSessionSelectionLaunch(),
    this.modelLaunch = const OpencodeModelLaunch(),
    this.permissionLaunch = const OpencodePermissionLaunch(),
    this.agentLaunch = const OpencodeAgentLaunch(),
    this.userExtraArgs = const OpencodeUserExtraArgsLaunch(),
    this.session = const OpencodeCliSessionCapability(),
    this.executable = const OpencodeExecutableCapability(),
    this.terminalBehavior = const OpencodeTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.plugin = const OpencodePluginCapability(),
    OpencodeProviderCapability? provider,
    this.headless = const OpencodeHeadlessCapability(),
    this.mcp = const OpencodeMcpCapability(),
    this.chatInteraction = const OpencodeChatInteraction(),
    this.aiHistory = const OpencodeAiHistoryCapability(),
    this.skill = const OpencodeSkillCapability(),
    this.nativeCommands = const OpencodeNativeCommands(),
    this.prompt = const OpencodePromptCapability(),
    this.hookWriter = const OpencodeHookWriter(),
  }) : provider = provider ?? OpencodeProviderCapability();

  final ProviderCapability provider;

  final CliSessionCapability session;
  final CliExecutableCapability executable;
  final OpencodeTerminalBehavior terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final PluginCapability plugin;
  final HeadlessCapability headless;
  final OpencodeMcpCapability mcp;

  final TeamBehaviorCapability teamBehavior;
  final OpencodeSessionSelectionLaunch sessionSelection;
  final OpencodeModelLaunch modelLaunch;
  final OpencodePermissionLaunch permissionLaunch;
  final OpencodeAgentLaunch agentLaunch;
  final OpencodeUserExtraArgsLaunch userExtraArgs;
  final HookCapability hookWriter;
  final ChatInteractionCapability chatInteraction;
  final OpencodeAiHistoryCapability aiHistory;
  final SkillCapability skill;
  final NativeCommandCapability nativeCommands;
  final PromptCapability prompt;

  @override
  CliTool get id => CliTool.opencode;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => [
    teamBehavior,
    sessionSelection,
    modelLaunch,
    permissionLaunch,
    agentLaunch,
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
    aiHistory,
    skill,
    nativeCommands,
    prompt,
    hookWriter,
  ];
}
