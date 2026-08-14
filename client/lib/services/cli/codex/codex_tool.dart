import '../../../models/team_config.dart';
import 'capabilities/launch_args.dart';
import '../registry/cli_capability.dart';
import '../registry/cli_tool_definition.dart';
import 'capabilities/skill.dart';
import 'capabilities/team_behavior.dart';
import 'capabilities/chat_interaction.dart';
import 'capabilities/terminal_behavior.dart';
import 'capabilities/provider_catalog.dart';
import '../registry/capabilities/provider_catalog_capability.dart';
import '../registry/capabilities/config_profile_capability.dart';
import '../registry/capabilities/launch_args_capability.dart';
import '../registry/capabilities/team_behavior_capability.dart';
import 'provider/codex_provider_credential_capability.dart';
import '../registry/capabilities/cli_effort_capability.dart';
import '../registry/capabilities/headless_capability.dart';
import '../registry/capabilities/provider_credential_capability.dart';
import '../registry/capabilities/provider_model_capability.dart';
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/config_profile.dart';
import 'capabilities/headless.dart';
import 'provider/codex_effort_capability.dart';
import 'provider/codex_provider_form_capability.dart';
import '../registry/capabilities/member_config_inspection_capability.dart';
import '../registry/capabilities/provider_form_capability.dart';
import '../registry/capabilities/skill_capability.dart';
import '../registry/capabilities/chat_interaction_capability.dart';
import 'capabilities/provider_display.dart';
import '../registry/capabilities/provider_display_capability.dart';
import '../registry/capabilities/cli_executable_capability.dart';
import 'capabilities/credential_export.dart';
import '../registry/capabilities/credential_export_capability.dart';
import 'capabilities/mcp.dart';
import 'capabilities/plugin.dart';
import '../registry/capabilities/plugin_capability.dart';
import 'provider/codex_hook_writer.dart';
import '../registry/capabilities/hook_writer_capability.dart';
import 'capabilities/prompt_provision.dart';
import 'capabilities/executable.dart';
import '../registry/capabilities/prompt_provision_capability.dart';

final class CodexCliTool implements CliToolDefinition {
  CodexCliTool({
    this.teamBehavior = const CodexTeamBehavior(),
    this.launchArgs = const CodexCliToolAdapter(),
    this.configProfile = const CodexConfigProfileCapability(),
    this.executable = const CodexExecutableCapability(),
    this.terminalBehavior = const CodexTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.plugin = const CodexPluginCapability(),
    this.providerCatalog = const CodexProviderCatalogCapability(),
    this.providerModel = const ProviderRecordModelCapability(),
    this.effort = const CodexEffortCapability(),
    this.headless = const CodexHeadlessCapability(),
    this.providerForm = const CodexProviderFormCapability(),
    this.mcp = const CodexMcpCapability(),
    this.chatInteraction = const CodexChatInteraction(),
    this.aiHistory = const CodexAiHistoryCapability(),
    this.skill = const CodexSkillCapability(),
    this.promptProvision = const CodexPromptProvisionCapability(),
    this.providerDisplay = const CodexProviderDisplay(),
    this.credentialExport = const CodexCredentialExport(),
    this.hookWriter = const CodexHookWriter(),
    ProviderCredentialCapability? providerCredential,
  }) : providerCredential =
           providerCredential ?? CodexProviderCredentialCapability();

  final ProviderCredentialCapability providerCredential;
  final ProviderFormCapability providerForm;

  final LaunchArgsCapability launchArgs;
  final ConfigProfileCapability configProfile;
  final CliExecutableCapability executable;
  final CodexTerminalBehavior terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final PluginCapability plugin;
  final ProviderCatalogCapability providerCatalog;
  final ProviderModelCapability providerModel;
  final CliEffortCapability effort;
  final HeadlessCapability headless;
  final CodexMcpCapability mcp;

  final TeamBehaviorCapability teamBehavior;
  final ProviderDisplayCapability providerDisplay;
  final CredentialExportCapability credentialExport;
  final ChatInteractionCapability chatInteraction;
  final CodexAiHistoryCapability aiHistory;
  final SkillCapability skill;
  final HookWriterCapability hookWriter;
  final PromptProvisionCapability promptProvision;

  @override
  CliTool get id => CliTool.codex;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => [
    teamBehavior,
    executable,
    launchArgs,
    configProfile,
    terminalBehavior,
    memberConfigInspection,
    plugin,
    providerCatalog,
    providerModel,
    providerCredential,
    providerForm,
    effort,
    headless,
    mcp,
    providerDisplay,
    credentialExport,
    chatInteraction,
    aiHistory,
    skill,
    promptProvision,
    hookWriter,
  ];
}
