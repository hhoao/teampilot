import 'capabilities/provider.dart';
import '../registry/capabilities/provider_capability.dart';
import '../../../models/team_config.dart';
import '../registry/cli_capability.dart';
import '../registry/cli_tool_definition.dart';
import 'capabilities/team_behavior.dart';
import 'capabilities/native_commands.dart';
import 'capabilities/session_selection_launch.dart';
import 'capabilities/workspace_access_launch.dart';
import 'capabilities/model_launch.dart';
import 'capabilities/permission_launch.dart';
import 'capabilities/chat_interaction.dart';
import 'capabilities/terminal_behavior.dart';
import 'capabilities/prompt.dart';
import '../registry/capabilities/prompt_capability.dart';
import '../registry/capabilities/cli_session_capability.dart';
import '../registry/capabilities/team_behavior_capability.dart';
import '../registry/capabilities/headless_capability.dart';
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/session_lifecycle.dart';
import 'capabilities/headless.dart';
import '../registry/capabilities/member_config_inspection_capability.dart';
import '../registry/capabilities/skill_capability.dart';
import '../registry/capabilities/native_command_capability.dart';
import '../registry/capabilities/chat_interaction_capability.dart';
import '../registry/capabilities/runtime_event_capability.dart';
import '../registry/capabilities/cli_executable_capability.dart';
import 'capabilities/mcp.dart';
import 'capabilities/plugin.dart';
import '../registry/capabilities/plugin_capability.dart';
import 'capabilities/skill.dart';
import 'capabilities/executable.dart';
import '../registry/capabilities/hook_capability.dart';
import 'provider/cursor_hook_writer.dart';
import '../registry/launch/user_extra_args_provider.dart';

/// Cursor CLI (`cursor-agent`). Standalone and mixed-mode (HOME isolation +
/// provider auth) embedded terminal.
final class CursorCliTool implements CliToolDefinition {
  CursorCliTool({
    this.teamBehavior = const CursorTeamBehavior(),
    this.sessionSelection = const CursorSessionSelectionLaunch(),
    this.workspaceAccess = const CursorWorkspaceAccessLaunch(),
    this.modelLaunch = const CursorModelLaunch(),
    this.permissionLaunch = const CursorPermissionLaunch(),
    this.userExtraArgs = const UserExtraArgsProvider(),
    this.session = const CursorSessionLifecycleCapability(),
    this.executable = const CursorExecutableCapability(),
    this.terminalBehavior = const CursorTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.plugin = const CursorPluginCapability(),
    this.headless = const CursorHeadlessCapability(),
    this.mcp = const CursorMcpCapability(),
    this.chatInteraction = const CursorChatInteraction(),
    this.runtimeEvents = const CursorChatInteraction(),
    this.aiHistory = const CursorAiHistoryCapability(),
    this.skill = const CursorSkillCapability(),
    this.nativeCommands = const CursorNativeCommands(),
    this.hookWriter = const CursorHookWriter(),
    this.prompt = const CursorPromptCapability(),
    CursorProviderCapability? provider,
  }) : provider = provider ?? CursorProviderCapability();

  final ProviderCapability provider;

  final CliSessionCapability session;
  final CliExecutableCapability executable;
  final CursorTerminalBehavior terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final PluginCapability plugin;
  final HeadlessCapability headless;
  final CursorMcpCapability mcp;

  final TeamBehaviorCapability teamBehavior;
  final CursorSessionSelectionLaunch sessionSelection;
  final CursorWorkspaceAccessLaunch workspaceAccess;
  final CursorModelLaunch modelLaunch;
  final CursorPermissionLaunch permissionLaunch;
  final UserExtraArgsProvider userExtraArgs;
  final HookCapability hookWriter;
  final ChatInteractionCapability chatInteraction;
  final RuntimeEventCapability runtimeEvents;
  final CursorAiHistoryCapability aiHistory;
  final SkillCapability skill;
  final NativeCommandCapability nativeCommands;
  final PromptCapability prompt;

  @override
  CliTool get id => CliTool.cursor;

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
