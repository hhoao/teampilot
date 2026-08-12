import '../../../models/team_config.dart';
import 'capabilities/launch_args.dart';
import '../registry/cli_capability.dart';
import '../registry/cli_tool_definition.dart';
import '../registry/capabilities/bus_transport_capability.dart';
import '../registry/capabilities/remote_cli_locator_capability.dart';
import '../registry/capabilities/skill_invocation_syntax_capability.dart';
import 'provider/cursor_cli_config_layout.dart';
import 'provider/cursor_provider_catalog_capability.dart';
import '../registry/capabilities/cli_config_layout_capability.dart';
import 'capabilities/executable_resolver.dart';
import 'capabilities/presence.dart';
import 'capabilities/display.dart';
import 'capabilities/terminal_behavior.dart';
import '../registry/capabilities/provider_catalog_capability.dart';
import '../registry/capabilities/config_profile_capability.dart';
import '../registry/capabilities/executable_resolver_capability.dart';
import '../registry/capabilities/installer_capability.dart';
import '../registry/capabilities/launch_args_capability.dart';
import '../registry/capabilities/presence_capability.dart';
import 'provider/cursor_provider_credential_capability.dart';
import 'provider/cursor_provider_model_capability.dart';
import '../registry/capabilities/headless_run_capability.dart';
import '../registry/capabilities/provider_credential_capability.dart';
import '../registry/capabilities/session_resume_capability.dart';
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/history/side_resolver.dart';
import 'capabilities/resume_strategy.dart';
import 'capabilities/installer.dart';
import 'capabilities/config_profile.dart';
import 'capabilities/session_lifecycle.dart';
import '../registry/capabilities/cli_session_lifecycle_capability.dart';
import '../registry/capabilities/post_manifest_flush_capability.dart';
import 'capabilities/headless_run.dart';
import 'provider/cursor_provider_form_capability.dart';
import '../registry/capabilities/member_config_inspection_capability.dart';
import '../registry/capabilities/provider_form_capability.dart';
import '../registry/capabilities/resource_capability.dart';
import '../registry/capabilities/ask_user_question_capability.dart';
import 'capabilities/ask_user_question.dart';
import '../registry/capabilities/exit_plan_mode_capability.dart';
import '../registry/capabilities/turn_completion_capability.dart';
import 'capabilities/provider_display.dart';
import '../registry/capabilities/provider_display_capability.dart';
import 'capabilities/config_ui.dart';
import '../registry/capabilities/cli_config_ui_capability.dart';
import 'capabilities/title_attention.dart';
import 'capabilities/marketplace_consumer.dart';
import 'capabilities/agent_status_normalizer.dart';
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
import 'capabilities/post_manifest_flush.dart';
import 'capabilities/resource.dart';

/// Cursor CLI (`cursor-agent`). Standalone and mixed-mode (HOME isolation +
/// provider auth) embedded terminal.
final class CursorCliTool implements CliToolDefinition {
  CursorCliTool({
    this.busTransport = const BusTransportCapability(
      longBlockingWaitForMessage: false,
    ),
    this.remoteCliLocator = const DefaultRemoteCliLocator('cursor-agent'),
    this.launchArgs = const CursorCliToolAdapter(),
    this.configProfile = const CursorConfigProfileCapability(),
    this.sessionLifecycle = const CursorSessionLifecycleCapability(),
    this.sessionResume = const CursorResumeStrategy(),
    this.executableResolver = const CursorExecutableResolver(),
    this.installer = const CursorInstallerCapability(),
    this.presence = const CursorPresence(),
    this.display = const CursorDisplay(),
    this.terminalBehavior = const CursorTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.pluginProvisioner = const CursorPluginProvisioner(),
    this.providerCatalog = const CursorProviderCatalogCapability(),
    CursorProviderModelCapability? providerModel,
    this.headlessRun = const CursorHeadlessRunCapability(),
    this.providerForm = const CursorProviderFormCapability(),
    this.resource = const CursorResourceCapability(),
    this.configLayout = const CursorCliConfigLayout(),
    this.mcpConfigWriter = const CursorMcpConfigWriter(),
    this.turnInterrupt = const CtrlCTurnInterrupt(),
    this.askUserQuestion = const NoAskUserQuestionCapability(),
    this.exitPlanMode = const NoExitPlanModeCapability(),
    CursorAiHistoryCapability? aiHistory,
    this.skillSyntax = const DefaultSkillInvocationSyntaxCapability(),
    this.postManifestFlush = const CursorPostManifestFlushCapability(),
    this.turnCompletion = const CursorTurnCompletion(),
    this.waitBeforeStop = const CursorWaitBeforeStop(),
    this.providerDisplay = const CursorProviderDisplay(),
    this.configUi = const CursorConfigUi(),
    this.titleAttention = const CursorTitleAttention(),
    this.marketplaceConsumer = const MarketplaceConsumer(),
    this.agentStatusNormalizer = const CursorAgentStatusNormalizer(),
    this.historyContextEnv = const CursorHistoryContextEnv(),
    this.remoteAppData = const NoRemoteAppData(),
    this.credentialExport = const CursorCredentialExport(),
    this.toolCallResolvers = const CursorToolCallResolvers(),
    ProviderCredentialCapability? providerCredential,
  }) : aiHistory = aiHistory ??
           CursorAiHistoryCapability(
             shellResolver: toolCallResolvers.shellResolver,
             subagentSideResolver: const CursorSideResolver(),
           ),
       providerModel = providerModel ?? CursorProviderModelCapability(),
       providerCredential =
           providerCredential ?? CursorProviderCredentialCapability();

  final ProviderCredentialCapability providerCredential;
  final ProviderFormCapability providerForm;

  final LaunchArgsCapability launchArgs;
  final ConfigProfileCapability configProfile;
  final CliSessionLifecycleCapability sessionLifecycle;
  final SessionResumeCapability sessionResume;
  final ExecutableResolverCapability executableResolver;
  final InstallerCapability installer;
  final PresenceCapability presence;
  final CursorDisplay display;
  final CursorTerminalBehavior terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final CursorPluginProvisioner pluginProvisioner;
  final ProviderCatalogCapability providerCatalog;
  final CursorProviderModelCapability providerModel;
  final HeadlessRunCapability headlessRun;
  final ResourceCapability resource;
  final CliConfigLayoutCapability configLayout;
  final CursorMcpConfigWriter mcpConfigWriter;

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
  final CursorToolCallResolvers toolCallResolvers;
  final AskUserQuestionCapability askUserQuestion;
  final ExitPlanModeCapability exitPlanMode;
  final CursorAiHistoryCapability aiHistory;
  final SkillInvocationSyntaxCapability skillSyntax;
  final PostManifestFlushCapability postManifestFlush;

  @override
  CliTool get id => CliTool.cursor;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => [
    busTransport,
    remoteCliLocator,
    launchArgs,
    configProfile,
    sessionLifecycle,
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
    headlessRun,
    resource,
    configLayout,
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
    postManifestFlush,
    toolCallResolvers,
  ];
}

final class CursorTurnCompletion implements TurnCompletionCapability {
  const CursorTurnCompletion();
  @override
  Set<String> get doneEventNames => const {'stop'};
  @override
  bool get requiresPtyFallback => true;
  @override
  bool get usesDoorbellPush => true;
}
