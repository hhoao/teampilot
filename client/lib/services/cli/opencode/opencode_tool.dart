import '../../../models/team_config.dart';
import 'capabilities/launch_args.dart';
import '../registry/cli_capability.dart';
import '../registry/cli_tool_definition.dart';
import 'capabilities/team_behavior.dart';
import 'capabilities/chat_interaction.dart';
import 'capabilities/terminal_behavior.dart';
import '../registry/capabilities/config_profile_capability.dart';
import '../registry/capabilities/launch_args_capability.dart';
import '../registry/capabilities/team_behavior_capability.dart';
import 'provider/opencode_provider_credential_capability.dart';
import 'provider/opencode_provider_catalog_capability.dart';
import '../registry/capabilities/cli_effort_capability.dart';
import '../registry/capabilities/headless_capability.dart';
import '../registry/capabilities/provider_catalog_capability.dart';
import '../registry/capabilities/provider_credential_capability.dart';
import '../registry/capabilities/provider_model_capability.dart';
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/config_profile.dart';
import 'capabilities/headless.dart';
import 'provider/opencode_effort_capability.dart';
import 'provider/opencode_provider_form_capability.dart';
import 'provider/opencode_provider_model_capability.dart';
import '../registry/capabilities/member_config_inspection_capability.dart';
import '../registry/capabilities/provider_form_capability.dart';
import '../registry/capabilities/skill_capability.dart';
import '../registry/capabilities/chat_interaction_capability.dart';
import 'capabilities/provider_display.dart';
import '../registry/capabilities/provider_display_capability.dart';
import '../registry/capabilities/cli_executable_capability.dart';
import 'capabilities/marketplace_consumer.dart';
import 'capabilities/remote_app_data.dart';
import 'capabilities/credential_export.dart';
import '../registry/capabilities/marketplace_consumer_capability.dart';
import '../registry/capabilities/remote_app_data_capability.dart';
import '../registry/capabilities/credential_export_capability.dart';
import '../registry/capabilities/hook_writer_capability.dart';
import 'capabilities/mcp_config_writer.dart';
import 'capabilities/plugin_provisioner.dart';
import 'capabilities/prompt_provision.dart';
import 'capabilities/skill.dart';
import 'capabilities/opencode_hook_writer.dart';
import 'capabilities/executable.dart';
import '../registry/capabilities/prompt_provision_capability.dart';

final class OpencodeCliTool implements CliToolDefinition {
  OpencodeCliTool({
    this.teamBehavior = const OpencodeTeamBehavior(),
    this.launchArgs = const OpencodeCliToolAdapter(),
    this.configProfile = const OpencodeConfigProfileCapability(),
    this.executable = const OpencodeExecutableCapability(),
    this.terminalBehavior = const OpencodeTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.pluginProvisioner = const OpencodePluginProvisioner(),
    this.providerCatalog = const OpencodeProviderCatalogCapability(),
    OpencodeProviderModelCapability? providerModel,
    this.effort = const OpencodeEffortCapability(),
    this.headless = const OpencodeHeadlessCapability(),
    this.providerForm = const OpencodeProviderFormCapability(),
    this.mcpConfigWriter = const OpencodeMcpConfigWriter(),
    this.chatInteraction = const OpencodeChatInteraction(),
    this.aiHistory = const OpencodeAiHistoryCapability(),
    this.skill = const OpencodeSkillCapability(),
    this.promptProvision = const OpencodePromptProvisionCapability(),
    this.providerDisplay = const OpencodeProviderDisplay(),
    this.marketplaceConsumer = const NoMarketplaceConsumer(),
    this.remoteAppData = const OpencodeRemoteAppData(),
    this.credentialExport = const OpencodeCredentialExport(),
    this.hookWriter = const OpencodeHookWriter(),
    ProviderCredentialCapability? providerCredential,
  }) : providerModel = providerModel ?? OpencodeProviderModelCapability(),
       providerCredential =
           providerCredential ?? OpencodeProviderCredentialCapability();

  final ProviderCredentialCapability providerCredential;
  final ProviderFormCapability providerForm;

  final LaunchArgsCapability launchArgs;
  final ConfigProfileCapability configProfile;
  final CliExecutableCapability executable;
  final OpencodeTerminalBehavior terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final OpencodePluginProvisioner pluginProvisioner;
  final ProviderCatalogCapability providerCatalog;
  final ProviderModelCapability providerModel;
  final CliEffortCapability effort;
  final HeadlessCapability headless;
  final OpencodeMcpConfigWriter mcpConfigWriter;

  final TeamBehaviorCapability teamBehavior;
  final ProviderDisplayCapability providerDisplay;
  final MarketplaceConsumerCapability marketplaceConsumer;
  final RemoteAppDataCapability remoteAppData;
  final CredentialExportCapability credentialExport;
  final HookWriterCapability hookWriter;
  final ChatInteractionCapability chatInteraction;
  final OpencodeAiHistoryCapability aiHistory;
  final SkillCapability skill;
  final PromptProvisionCapability promptProvision;

  @override
  CliTool get id => CliTool.opencode;

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
    providerDisplay,
    marketplaceConsumer,
    remoteAppData,
    credentialExport,
    chatInteraction,
    aiHistory,
    skill,
    promptProvision,
    hookWriter,
  ];
}
