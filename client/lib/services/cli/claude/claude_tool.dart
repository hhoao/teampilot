import '../../../models/team_config.dart';
import 'capabilities/launch_args.dart';
import 'capabilities/provider_display.dart';
import 'capabilities/marketplace_consumer.dart';
import 'capabilities/remote_app_data.dart';
import 'capabilities/credential_export.dart';
import '../registry/cli_capability.dart';
import '../registry/cli_tool_definition.dart';
import 'capabilities/team_behavior.dart';
import 'capabilities/terminal_behavior.dart';
import 'capabilities/chat_interaction.dart';
import 'capabilities/provider_catalog.dart';
import '../registry/capabilities/provider_catalog_capability.dart';
import '../registry/capabilities/team_behavior_capability.dart';
import '../registry/capabilities/config_profile_capability.dart';
import '../registry/capabilities/launch_args_capability.dart';
import '../registry/capabilities/cli_effort_capability.dart';
import '../registry/capabilities/headless_capability.dart';
import '../registry/capabilities/provider_credential_capability.dart';
import '../registry/capabilities/provider_model_capability.dart';
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/config_profile.dart';
import 'capabilities/headless.dart';
import 'provider/claude_effort_capability.dart';
import 'provider/claude_provider_credential_capability.dart';
import 'provider/claude_provider_form_capability.dart';
import 'provider/claude_provider_model_capability.dart';
import '../registry/capabilities/member_config_inspection_capability.dart';
import '../registry/capabilities/provider_form_capability.dart';
import '../registry/capabilities/skill_capability.dart';
import '../registry/capabilities/chat_interaction_capability.dart';
import '../registry/capabilities/provider_display_capability.dart';
import '../registry/capabilities/credential_binding_capability.dart';
import '../registry/capabilities/cli_executable_capability.dart';
import '../registry/capabilities/marketplace_consumer_capability.dart';
import '../registry/capabilities/remote_app_data_capability.dart';
import '../registry/capabilities/credential_export_capability.dart';
import 'capabilities/mcp_config_writer.dart';
import 'capabilities/plugin_provisioner.dart';
import 'capabilities/credential_binding.dart';
import 'capabilities/prompt_provision.dart';
import 'capabilities/executable.dart';
import '../registry/capabilities/prompt_provision_capability.dart';
import '../registry/resources/default_resource_capability.dart';
import '../registry/config_profile/claude_family_hook_writer.dart';
import '../registry/capabilities/hook_writer_capability.dart';

final class ClaudeCliTool implements CliToolDefinition {
  ClaudeCliTool({
    this.teamBehavior = const ClaudeTeamBehavior(),
    this.launchArgs = const ClaudeCodeCliToolAdapter(),
    this.configProfile = const ClaudeConfigProfileCapability(),
    this.executable = const ClaudeExecutableCapability(),
    this.terminalBehavior = const ClaudeTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.pluginProvisioner = const ClaudePluginProvisioner(),
    this.providerCatalog = const ClaudeProviderCatalogCapability(),
    this.providerModel = const ClaudeProviderModelCapability(),
    this.effort = const ClaudeEffortCapability(),
    this.headless = const ClaudeHeadlessCapability(),
    this.providerForm = const ClaudeProviderFormCapability(),
    this.mcpConfigWriter = const ClaudeMcpConfigWriter(),
    this.chatInteraction = const ClaudeChatInteraction(),
    this.aiHistory = const ClaudeAiHistoryCapability(),
    this.skill = const DefaultSkillCapability(),
    this.providerDisplay = const ClaudeProviderDisplay(),
    this.marketplaceConsumer = const MarketplaceConsumer(),
    this.remoteAppData = const NoRemoteAppData(),
    this.credentialExport = const ClaudeCredentialExport(),
    this.credentialBinding = const ClaudeCredentialBindingCapability(),
    this.promptProvision = const ClaudePromptProvisionCapability(),
    ProviderCredentialCapability? providerCredential,
    HookWriterCapability? hookWriter,
  }) : providerCredential =
           providerCredential ?? ClaudeProviderCredentialCapability(),
       hookWriter = hookWriter ?? const ClaudeFamilyHookWriter();

  final ProviderCredentialCapability providerCredential;
  final HookWriterCapability hookWriter;
  final ProviderFormCapability providerForm;

  final LaunchArgsCapability launchArgs;
  final ConfigProfileCapability configProfile;
  final CliExecutableCapability executable;
  final ClaudeTerminalBehavior terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final ClaudePluginProvisioner pluginProvisioner;
  final ProviderCatalogCapability providerCatalog;
  final ProviderModelCapability providerModel;
  final CliEffortCapability effort;
  final HeadlessCapability headless;
  final ClaudeMcpConfigWriter mcpConfigWriter;

  final TeamBehaviorCapability teamBehavior;
  final ChatInteractionCapability chatInteraction;
  final ClaudeAiHistoryCapability aiHistory;
  final SkillCapability skill;
  final ProviderDisplayCapability providerDisplay;
  final MarketplaceConsumerCapability marketplaceConsumer;
  final RemoteAppDataCapability remoteAppData;
  final CredentialExportCapability credentialExport;
  final CredentialBindingCapability credentialBinding;
  final PromptProvisionCapability promptProvision;

  @override
  CliTool get id => CliTool.claude;

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
    pluginProvisioner,
    providerCatalog,
    providerModel,
    providerCredential,
    providerForm,
    effort,
    headless,
    mcpConfigWriter,
    chatInteraction,
    aiHistory,
    skill,
    providerDisplay,
    marketplaceConsumer,
    remoteAppData,
    credentialExport,
    credentialBinding,
    promptProvision,
    hookWriter,
  ];
}
