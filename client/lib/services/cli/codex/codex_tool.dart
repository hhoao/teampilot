import 'capabilities/provider.dart';
import '../registry/capabilities/provider_capability.dart';
import '../../../models/team_config.dart';
import 'capabilities/session.dart';
import '../registry/cli_capability.dart';
import '../registry/cli_tool_definition.dart';
import 'capabilities/skill.dart';
import 'capabilities/team_behavior.dart';
import 'capabilities/chat_interaction.dart';
import 'capabilities/terminal_behavior.dart';
import '../registry/capabilities/config_profile_capability.dart';
import '../registry/capabilities/cli_session_capability.dart';
import '../registry/capabilities/team_behavior_capability.dart';
import '../registry/capabilities/headless_capability.dart';
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/config_profile.dart';
import 'capabilities/headless.dart';
import '../registry/capabilities/member_config_inspection_capability.dart';
import '../registry/capabilities/skill_capability.dart';
import '../registry/capabilities/chat_interaction_capability.dart';
import '../registry/capabilities/cli_executable_capability.dart';
import 'capabilities/mcp.dart';
import 'capabilities/plugin.dart';
import '../registry/capabilities/plugin_capability.dart';
import 'provider/codex_hook_writer.dart';
import '../registry/capabilities/hook_capability.dart';
import 'capabilities/prompt.dart';
import 'capabilities/executable.dart';
import '../registry/capabilities/prompt_capability.dart';

final class CodexCliTool implements CliToolDefinition {
  CodexCliTool({
    this.teamBehavior = const CodexTeamBehavior(),
    this.session = const CodexCliSessionCapability(),
    this.configProfile = const CodexConfigProfileCapability(),
    this.executable = const CodexExecutableCapability(),
    this.terminalBehavior = const CodexTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.plugin = const CodexPluginCapability(),
    this.headless = const CodexHeadlessCapability(),
    this.mcp = const CodexMcpCapability(),
    this.chatInteraction = const CodexChatInteraction(),
    this.aiHistory = const CodexAiHistoryCapability(),
    this.skill = const CodexSkillCapability(),
    this.prompt = const CodexPromptCapability(),
    this.hookWriter = const CodexHookWriter(),
    CodexProviderCapability? provider,
  }) : provider = provider ?? CodexProviderCapability();

  final ProviderCapability provider;

  final CliSessionCapability session;
  final ConfigProfileCapability configProfile;
  final CliExecutableCapability executable;
  final CodexTerminalBehavior terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final PluginCapability plugin;
  final HeadlessCapability headless;
  final CodexMcpCapability mcp;

  final TeamBehaviorCapability teamBehavior;
  final ChatInteractionCapability chatInteraction;
  final CodexAiHistoryCapability aiHistory;
  final SkillCapability skill;
  final HookCapability hookWriter;
  final PromptCapability prompt;

  @override
  CliTool get id => CliTool.codex;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => [
    teamBehavior,
    executable,
    session,
    configProfile,
    terminalBehavior,
    memberConfigInspection,
    plugin,
    provider,
    headless,
    mcp,
    chatInteraction,
    aiHistory,
    skill,
    prompt,
    hookWriter,
  ];
}
