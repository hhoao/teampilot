import 'capabilities/provider.dart';
import '../registry/capabilities/provider_capability.dart';
import '../../../models/team_config.dart';
import 'capabilities/launch_args.dart';
import '../registry/cli_capability.dart';
import '../registry/cli_tool_definition.dart';
import 'provider/cursor_cli_config_layout.dart';
import '../registry/capabilities/cli_config_layout_capability.dart';
import 'capabilities/team_behavior.dart';
import 'capabilities/chat_interaction.dart';
import 'capabilities/terminal_behavior.dart';
import 'capabilities/prompt.dart';
import '../registry/capabilities/prompt_capability.dart';
import '../registry/capabilities/config_profile_capability.dart';
import '../registry/capabilities/launch_args_capability.dart';
import '../registry/capabilities/team_behavior_capability.dart';
import '../registry/capabilities/headless_capability.dart';
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/config_profile.dart';
import 'capabilities/session_lifecycle.dart';
import '../registry/capabilities/cli_session_lifecycle_capability.dart';
import '../registry/capabilities/post_manifest_flush_capability.dart';
import 'capabilities/headless.dart';
import '../registry/capabilities/member_config_inspection_capability.dart';
import '../registry/capabilities/skill_capability.dart';
import '../registry/capabilities/chat_interaction_capability.dart';
import '../registry/capabilities/cli_executable_capability.dart';
import 'capabilities/mcp.dart';
import 'capabilities/plugin.dart';
import '../registry/capabilities/plugin_capability.dart';
import 'capabilities/post_manifest_flush.dart';
import 'capabilities/skill.dart';
import 'capabilities/executable.dart';
import '../registry/capabilities/hook_capability.dart';
import 'provider/cursor_hook_writer.dart';

/// Cursor CLI (`cursor-agent`). Standalone and mixed-mode (HOME isolation +
/// provider auth) embedded terminal.
final class CursorCliTool implements CliToolDefinition {
  CursorCliTool({
    this.teamBehavior = const CursorTeamBehavior(),
    this.launchArgs = const CursorCliToolAdapter(),
    this.configProfile = const CursorConfigProfileCapability(),
    this.sessionLifecycle = const CursorSessionLifecycleCapability(),
    this.executable = const CursorExecutableCapability(),
    this.terminalBehavior = const CursorTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.plugin = const CursorPluginCapability(),
    this.headless = const CursorHeadlessCapability(),
    this.configLayout = const CursorCliConfigLayout(),
    this.mcp = const CursorMcpCapability(),
    this.chatInteraction = const CursorChatInteraction(),
    this.aiHistory = const CursorAiHistoryCapability(),
    this.skill = const CursorSkillCapability(),
    this.postManifestFlush = const CursorPostManifestFlushCapability(),
    this.hookWriter = const CursorHookWriter(),
    this.prompt = const CursorPromptCapability(),
    CursorProviderCapability? provider,
  }) : provider = provider ?? CursorProviderCapability();

  final ProviderCapability provider;

  final LaunchArgsCapability launchArgs;
  final ConfigProfileCapability configProfile;
  final CliSessionLifecycleCapability sessionLifecycle;
  final CliExecutableCapability executable;
  final CursorTerminalBehavior terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final PluginCapability plugin;
  final HeadlessCapability headless;
  final CliConfigLayoutCapability configLayout;
  final CursorMcpCapability mcp;

  final TeamBehaviorCapability teamBehavior;
  final HookCapability hookWriter;
  final ChatInteractionCapability chatInteraction;
  final CursorAiHistoryCapability aiHistory;
  final SkillCapability skill;
  final PostManifestFlushCapability postManifestFlush;
  final PromptCapability prompt;

  @override
  CliTool get id => CliTool.cursor;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => [
    teamBehavior,
    executable,
    launchArgs,
    configProfile,
    sessionLifecycle,
    terminalBehavior,
    memberConfigInspection,
    plugin,
    provider,
    headless,
    configLayout,
    mcp,
    chatInteraction,
    aiHistory,
    skill,
    postManifestFlush,
    prompt,
    hookWriter,
  ];
}
