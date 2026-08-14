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
import 'capabilities/provider_catalog.dart';
import '../registry/capabilities/provider_catalog_capability.dart';
import '../registry/capabilities/config_profile_capability.dart';
import '../registry/capabilities/executable_resolver_capability.dart';
import '../registry/capabilities/installer_capability.dart';
import '../registry/capabilities/launch_args_capability.dart';
import '../registry/capabilities/team_behavior_capability.dart';
import 'provider/codex_provider_credential_capability.dart';
import '../registry/capabilities/cli_effort_capability.dart';
import '../registry/capabilities/headless_capability.dart';
import '../registry/capabilities/provider_credential_capability.dart';
import '../registry/capabilities/provider_model_capability.dart';
import '../registry/capabilities/session_resume_capability.dart';
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/resume_strategy.dart';
import 'capabilities/config_profile.dart';
import 'capabilities/headless.dart';
import 'capabilities/installer.dart';
import 'provider/codex_effort_capability.dart';
import 'provider/codex_provider_form_capability.dart';
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
import 'capabilities/tool_call_resolvers.dart';
import 'capabilities/mcp_config_writer.dart';
import 'capabilities/plugin_provisioner.dart';
import 'provider/codex_hook_writer.dart';
import '../registry/capabilities/hook_writer_capability.dart';
import 'capabilities/prompt_provision.dart';
import '../registry/resources/default_resource_capability.dart';
import '../registry/capabilities/prompt_provision_capability.dart';

final class CodexCliTool implements CliToolDefinition {
  CodexCliTool({
    this.teamBehavior = const CodexTeamBehavior(),
    this.remoteCliLocator = const DefaultRemoteCliLocator('codex'),
    this.launchArgs = const CodexCliToolAdapter(),
    this.configProfile = const CodexConfigProfileCapability(),
    this.sessionResume = const CodexResumeStrategy(),
    this.executableResolver = const CodexExecutableResolver(),
    this.installer = const CodexInstallerCapability(),
    this.display = const CodexDisplay(),
    this.terminalBehavior = const CodexTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.pluginProvisioner = const CodexPluginProvisioner(),
    this.providerCatalog = const CodexProviderCatalogCapability(),
    this.providerModel = const ProviderRecordModelCapability(),
    this.effort = const CodexEffortCapability(),
    this.headless = const CodexHeadlessCapability(),
    this.providerForm = const CodexProviderFormCapability(),
    this.resource = const DefaultResourceCapability(),
    this.mcpConfigWriter = const CodexMcpConfigWriter(),
    this.chatInteraction = const CodexChatInteraction(),
    this.aiHistory = const CodexAiHistoryCapability(),
    this.skillSyntax = const CodexSkillInvocationSyntaxCapability(),
    this.promptProvision = const CodexPromptProvisionCapability(),
    this.providerDisplay = const CodexProviderDisplay(),
    this.configUi = const CodexConfigUi(),
    this.marketplaceConsumer = const NoMarketplaceConsumer(),
    this.historyContextEnv = const CodexHistoryContextEnv(),
    this.remoteAppData = const NoRemoteAppData(),
    this.credentialExport = const CodexCredentialExport(),
    this.toolCallResolvers = const CodexToolCallResolvers(),
    this.hookWriter = const CodexHookWriter(),
    ProviderCredentialCapability? providerCredential,
  }) : providerCredential =
           providerCredential ?? CodexProviderCredentialCapability();

  final ProviderCredentialCapability providerCredential;
  final ProviderFormCapability providerForm;

  final LaunchArgsCapability launchArgs;
  final ConfigProfileCapability configProfile;
  final SessionResumeCapability sessionResume;
  final ExecutableResolverCapability executableResolver;
  final InstallerCapability installer;
  final CodexDisplay display;
  final CodexTerminalBehavior terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final CodexPluginProvisioner pluginProvisioner;
  final ProviderCatalogCapability providerCatalog;
  final ProviderModelCapability providerModel;
  final CliEffortCapability effort;
  final HeadlessCapability headless;
  final ResourceCapability resource;
  final CodexMcpConfigWriter mcpConfigWriter;

  final TeamBehaviorCapability teamBehavior;
  final RemoteCliLocatorCapability remoteCliLocator;
  final ProviderDisplayCapability providerDisplay;
  final CliConfigUiCapability configUi;
  final MarketplaceConsumerCapability marketplaceConsumer;
  final HistoryContextEnvCapability historyContextEnv;
  final RemoteAppDataCapability remoteAppData;
  final CredentialExportCapability credentialExport;
  final CodexToolCallResolvers toolCallResolvers;
  final ChatInteractionCapability chatInteraction;
  final CodexAiHistoryCapability aiHistory;
  final SkillInvocationSyntaxCapability skillSyntax;
  final HookWriterCapability hookWriter;
  final PromptProvisionCapability promptProvision;

  @override
  CliTool get id => CliTool.codex;

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
