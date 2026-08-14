import '../../../models/team_config.dart';
import 'capabilities/launch_args.dart';
import '../registry/cli_capability.dart';
import '../registry/cli_tool_definition.dart';
import '../registry/capabilities/remote_cli_locator_capability.dart';
import 'capabilities/skill_invocation_syntax.dart';
import '../registry/capabilities/skill_invocation_syntax_capability.dart';
import 'capabilities/executable_resolver.dart';
import 'capabilities/team_behavior.dart';
import 'capabilities/chat_interaction.dart';
import 'capabilities/display.dart';
import 'capabilities/terminal_behavior.dart';
import '../registry/capabilities/config_profile_capability.dart';
import '../registry/capabilities/executable_resolver_capability.dart';
import '../registry/capabilities/installer_capability.dart';
import '../registry/capabilities/launch_args_capability.dart';
import '../registry/capabilities/team_behavior_capability.dart';
import 'provider/opencode_provider_credential_capability.dart';
import 'provider/opencode_provider_catalog_capability.dart';
import '../registry/capabilities/cli_effort_capability.dart';
import '../registry/capabilities/headless_capability.dart';
import '../registry/capabilities/provider_catalog_capability.dart';
import '../registry/capabilities/provider_credential_capability.dart';
import '../registry/capabilities/provider_model_capability.dart';
import '../registry/capabilities/session_resume_capability.dart';
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/resume_strategy.dart';
import 'capabilities/config_profile.dart';
import 'capabilities/headless.dart';
import 'capabilities/installer.dart';
import 'provider/opencode_effort_capability.dart';
import 'provider/opencode_provider_form_capability.dart';
import 'provider/opencode_provider_model_capability.dart';
import '../registry/capabilities/member_config_inspection_capability.dart';
import '../registry/capabilities/provider_form_capability.dart';
import '../registry/capabilities/resource_capability.dart';
import '../registry/capabilities/chat_interaction_capability.dart';
import 'capabilities/provider_display.dart';
import '../registry/capabilities/provider_display_capability.dart';
import 'capabilities/config_ui.dart';
import '../registry/capabilities/cli_config_ui_capability.dart';
import 'capabilities/marketplace_consumer.dart';
import 'capabilities/history_context_env.dart';
import 'capabilities/remote_app_data.dart';
import 'capabilities/credential_export.dart';
import '../registry/capabilities/marketplace_consumer_capability.dart';
import '../registry/capabilities/remote_app_data_capability.dart';
import '../registry/capabilities/credential_export_capability.dart';
import '../registry/capabilities/history_context_env_capability.dart';
import '../registry/capabilities/hook_writer_capability.dart';
import 'capabilities/tool_call_resolvers.dart';
import 'capabilities/mcp_config_writer.dart';
import 'capabilities/plugin_provisioner.dart';
import 'capabilities/prompt_provision.dart';
import 'capabilities/resource.dart';
import 'capabilities/opencode_hook_writer.dart';
import '../registry/capabilities/prompt_provision_capability.dart';

final class OpencodeCliTool implements CliToolDefinition {
  OpencodeCliTool({
    this.teamBehavior = const OpencodeTeamBehavior(),
    this.remoteCliLocator = const DefaultRemoteCliLocator('opencode'),
    this.launchArgs = const OpencodeCliToolAdapter(),
    this.configProfile = const OpencodeConfigProfileCapability(),
    this.sessionResume = const OpencodeResumeStrategy(),
    this.executableResolver = const OpencodeExecutableResolver(),
    this.installer = const OpencodeInstallerCapability(),
    this.display = const OpencodeDisplay(),
    this.terminalBehavior = const OpencodeTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.pluginProvisioner = const OpencodePluginProvisioner(),
    this.providerCatalog = const OpencodeProviderCatalogCapability(),
    OpencodeProviderModelCapability? providerModel,
    this.effort = const OpencodeEffortCapability(),
    this.headless = const OpencodeHeadlessCapability(),
    this.providerForm = const OpencodeProviderFormCapability(),
    this.resource = const OpencodeResourceCapability(),
    this.mcpConfigWriter = const OpencodeMcpConfigWriter(),
    this.chatInteraction = const OpencodeChatInteraction(),
    this.aiHistory = const OpencodeAiHistoryCapability(),
    this.skillSyntax = const OpencodeSkillInvocationSyntaxCapability(),
    this.promptProvision = const OpencodePromptProvisionCapability(),
    this.providerDisplay = const OpencodeProviderDisplay(),
    this.configUi = const OpencodeConfigUi(),
    this.marketplaceConsumer = const NoMarketplaceConsumer(),
    this.historyContextEnv = const OpencodeHistoryContextEnv(),
    this.remoteAppData = const OpencodeRemoteAppData(),
    this.credentialExport = const OpencodeCredentialExport(),
    this.toolCallResolvers = const OpencodeToolCallResolvers(),
    this.hookWriter = const OpencodeHookWriter(),
    ProviderCredentialCapability? providerCredential,
  }) : providerModel = providerModel ?? OpencodeProviderModelCapability(),
       providerCredential =
           providerCredential ?? OpencodeProviderCredentialCapability();

  final ProviderCredentialCapability providerCredential;
  final ProviderFormCapability providerForm;

  final LaunchArgsCapability launchArgs;
  final ConfigProfileCapability configProfile;
  final SessionResumeCapability sessionResume;
  final ExecutableResolverCapability executableResolver;
  final InstallerCapability installer;
  final OpencodeDisplay display;
  final OpencodeTerminalBehavior terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final OpencodePluginProvisioner pluginProvisioner;
  final ProviderCatalogCapability providerCatalog;
  final ProviderModelCapability providerModel;
  final CliEffortCapability effort;
  final HeadlessCapability headless;
  final ResourceCapability resource;
  final OpencodeMcpConfigWriter mcpConfigWriter;

  final TeamBehaviorCapability teamBehavior;
  final RemoteCliLocatorCapability remoteCliLocator;
  final ProviderDisplayCapability providerDisplay;
  final CliConfigUiCapability configUi;
  final MarketplaceConsumerCapability marketplaceConsumer;
  final HistoryContextEnvCapability historyContextEnv;
  final RemoteAppDataCapability remoteAppData;
  final CredentialExportCapability credentialExport;
  final OpencodeToolCallResolvers toolCallResolvers;
  final HookWriterCapability hookWriter;
  final ChatInteractionCapability chatInteraction;
  final OpencodeAiHistoryCapability aiHistory;
  final SkillInvocationSyntaxCapability skillSyntax;
  final PromptProvisionCapability promptProvision;

  @override
  CliTool get id => CliTool.opencode;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => [
    teamBehavior,
    remoteCliLocator,
    launchArgs,
    configProfile,
    sessionResume,
    executableResolver,
    installer,
    display,
    terminalBehavior,
    memberConfigInspection,
    pluginProvisioner,
    providerCatalog,
    providerModel,
    providerCredential,
    providerForm,
    effort,
    headless,
    resource,
    mcpConfigWriter,
    providerDisplay,
    configUi,
    marketplaceConsumer,
    historyContextEnv,
    remoteAppData,
    credentialExport,
    chatInteraction,
    aiHistory,
    skillSyntax,
    promptProvision,
    toolCallResolvers,
    hookWriter,
  ];
}
