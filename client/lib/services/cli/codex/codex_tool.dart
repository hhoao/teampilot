import '../../../models/team_config.dart';
import 'capabilities/launch_args.dart';
import '../registry/cli_capability.dart';
import '../registry/cli_tool_definition.dart';
import '../registry/capabilities/bus_transport_capability.dart';
import '../registry/capabilities/remote_cli_locator_capability.dart';
import 'capabilities/skill_invocation_syntax.dart';
import '../registry/capabilities/skill_invocation_syntax_capability.dart';
import 'capabilities/executable_resolver.dart';
import 'capabilities/presence.dart';
import 'capabilities/display.dart';
import 'capabilities/terminal_behavior.dart';
import 'capabilities/provider_catalog.dart';
import '../registry/capabilities/provider_catalog_capability.dart';
import '../registry/capabilities/config_profile_capability.dart';
import '../registry/capabilities/executable_resolver_capability.dart';
import '../registry/capabilities/installer_capability.dart';
import '../registry/capabilities/launch_args_capability.dart';
import '../registry/capabilities/presence_capability.dart';
import 'provider/codex_provider_credential_capability.dart';
import '../registry/capabilities/cli_effort_capability.dart';
import '../registry/capabilities/headless_run_capability.dart';
import '../registry/capabilities/provider_credential_capability.dart';
import '../registry/capabilities/provider_model_capability.dart';
import '../registry/capabilities/session_resume_capability.dart';
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/resume_strategy.dart';
import '../registry/capabilities/headless_provision_capability.dart';
import 'capabilities/config_profile.dart';
import 'capabilities/headless_run.dart';
import 'capabilities/headless_provision.dart';
import 'capabilities/installer.dart';
import 'provider/codex_effort_capability.dart';
import 'provider/codex_provider_form_capability.dart';
import '../registry/capabilities/member_config_inspection_capability.dart';
import '../registry/capabilities/provider_form_capability.dart';
import '../registry/capabilities/resource_capability.dart';
import '../registry/capabilities/ask_user_question_capability.dart';
import '../registry/capabilities/pty_ask_user_question_capability.dart';
import '../registry/capabilities/exit_plan_mode_capability.dart';
import '../registry/capabilities/turn_completion_capability.dart';
import 'capabilities/provider_display.dart';
import '../registry/capabilities/provider_display_capability.dart';
import 'capabilities/config_ui.dart';
import '../registry/capabilities/cli_config_ui_capability.dart';
import 'capabilities/title_attention.dart';
import 'capabilities/marketplace_consumer.dart';
import '../registry/capabilities/claude_family_agent_status_normalizer.dart';
import 'capabilities/history_context_env.dart';
import 'capabilities/remote_app_data.dart';
import 'capabilities/credential_export.dart';
import '../registry/capabilities/title_attention_capability.dart';
import '../registry/capabilities/marketplace_consumer_capability.dart';
import '../registry/capabilities/remote_app_data_capability.dart';
import '../registry/capabilities/credential_export_capability.dart';
import '../registry/capabilities/history_context_env_capability.dart';
import '../registry/capabilities/agent_status_normalizer_capability.dart';
import 'capabilities/wait_before_stop.dart';
import '../registry/capabilities/wait_before_stop_capability.dart';
import '../registry/capabilities/turn_interrupt_capability.dart';
import 'capabilities/tool_call_resolvers.dart';
import 'capabilities/mcp_config_writer.dart';
import 'capabilities/plugin_provisioner.dart';
import '../registry/resources/default_resource_capability.dart';

final class CodexCliTool implements CliToolDefinition {
  CodexCliTool({
    this.busTransport = const BusTransportCapability(
      longBlockingWaitForMessage: true,
    ),
    this.remoteCliLocator = const DefaultRemoteCliLocator('codex'),
    this.launchArgs = const CodexCliToolAdapter(),
    this.configProfile = const CodexConfigProfileCapability(),
    this.sessionResume = const CodexResumeStrategy(),
    this.executableResolver = const CodexExecutableResolver(),
    this.installer = const CodexInstallerCapability(),
    this.presence = const CodexPresence(),
    this.display = const CodexDisplay(),
    this.terminalBehavior = const CodexTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.pluginProvisioner = const CodexPluginProvisioner(),
    this.providerCatalog = const CodexProviderCatalogCapability(),
    this.providerModel = const ProviderRecordModelCapability(),
    this.effort = const CodexEffortCapability(),
    this.headlessRun = const CodexHeadlessRunCapability(),
    this.headlessProvision = const CodexHeadlessProvisionCapability(),
    this.providerForm = const CodexProviderFormCapability(),
    this.resource = const DefaultResourceCapability(),
    this.mcpConfigWriter = const CodexMcpConfigWriter(),
    this.turnInterrupt = const CtrlCTurnInterrupt(),
    this.askUserQuestion = const PtyAskUserQuestionCapability(),
    this.exitPlanMode = const NoExitPlanModeCapability(),
    this.aiHistory = const CodexAiHistoryCapability(),
    this.skillSyntax = const CodexSkillInvocationSyntaxCapability(),
    this.turnCompletion = const CodexTurnCompletion(),
    this.waitBeforeStop = const DefaultWaitBeforeStop(),
    this.providerDisplay = const CodexProviderDisplay(),
    this.configUi = const CodexConfigUi(),
    this.titleAttention = const NoTitleAttention(),
    this.marketplaceConsumer = const NoMarketplaceConsumer(),
    this.agentStatusNormalizer = const ClaudeFamilyAgentStatusNormalizer(),
    this.historyContextEnv = const CodexHistoryContextEnv(),
    this.remoteAppData = const NoRemoteAppData(),
    this.credentialExport = const CodexCredentialExport(),
    this.toolCallResolvers = const CodexToolCallResolvers(),
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
  final PresenceCapability presence;
  final CodexDisplay display;
  final CodexTerminalBehavior terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final CodexPluginProvisioner pluginProvisioner;
  final ProviderCatalogCapability providerCatalog;
  final ProviderModelCapability providerModel;
  final CliEffortCapability effort;
  final HeadlessRunCapability headlessRun;
  final HeadlessProvisionCapability headlessProvision;
  final ResourceCapability resource;
  final CodexMcpConfigWriter mcpConfigWriter;

  final BusTransportCapability busTransport;
  final RemoteCliLocatorCapability remoteCliLocator;
  final TurnInterruptCapability turnInterrupt;
  final TurnCompletionCapability turnCompletion;
  final WaitBeforeStopCapability waitBeforeStop;
  final ProviderDisplayCapability providerDisplay;
  final CliConfigUiCapability configUi;
  final TitleAttentionCapability titleAttention;
  final MarketplaceConsumerCapability marketplaceConsumer;
  final AgentStatusNormalizerCapability agentStatusNormalizer;
  final HistoryContextEnvCapability historyContextEnv;
  final RemoteAppDataCapability remoteAppData;
  final CredentialExportCapability credentialExport;
  final CodexToolCallResolvers toolCallResolvers;
  final AskUserQuestionCapability askUserQuestion;
  final ExitPlanModeCapability exitPlanMode;
  final CodexAiHistoryCapability aiHistory;
  final SkillInvocationSyntaxCapability skillSyntax;

  @override
  CliTool get id => CliTool.codex;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => [
    busTransport,
    remoteCliLocator,
    launchArgs,
    configProfile,
    sessionResume,
    executableResolver,
    installer,
    presence,
    display,
    terminalBehavior,
    memberConfigInspection,
    pluginProvisioner,
    providerCatalog,
    providerModel,
    providerCredential,
    providerForm,
    effort,
    headlessRun,
    headlessProvision,
    resource,
    mcpConfigWriter,
    turnInterrupt,
    turnCompletion,
    waitBeforeStop,
    providerDisplay,
    configUi,
    titleAttention,
    marketplaceConsumer,
    agentStatusNormalizer,
    historyContextEnv,
    remoteAppData,
    credentialExport,
    askUserQuestion,
    exitPlanMode,
    aiHistory,
    skillSyntax,
    toolCallResolvers,
  ];
}

final class CodexTurnCompletion implements TurnCompletionCapability {
  const CodexTurnCompletion();
  @override
  Set<String> get doneEventNames => const {'Stop', 'StopFailure'};
  @override
  bool get requiresPtyFallback => false;
  @override
  bool get usesDoorbellPush => false;
}
