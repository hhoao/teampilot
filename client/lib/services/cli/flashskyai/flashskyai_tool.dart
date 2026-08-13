import '../../../models/team_config.dart';
import 'capabilities/launch_args.dart';
import '../registry/cli_capability.dart';
import '../registry/cli_tool_definition.dart';
import '../registry/capabilities/bus_transport_capability.dart';
import '../registry/capabilities/remote_cli_locator_capability.dart';
import '../registry/capabilities/skill_invocation_syntax_capability.dart';
import 'capabilities/executable_resolver.dart';
import 'capabilities/presence.dart';
import 'capabilities/display.dart';
import 'capabilities/terminal_behavior.dart';
import 'capabilities/provider_catalog.dart';
import '../registry/capabilities/provider_catalog_capability.dart';
import 'capabilities/member_agent_preset.dart';
import '../registry/capabilities/native_team_capability.dart';
import '../registry/capabilities/config_profile_capability.dart';
import '../registry/capabilities/executable_resolver_capability.dart';
import '../registry/capabilities/installer_capability.dart';
import '../registry/capabilities/unsupported_installer_capability.dart';
import '../registry/capabilities/cli_effort_capability.dart';
import '../registry/capabilities/headless_run_capability.dart';
import '../registry/capabilities/launch_args_capability.dart';
import '../registry/capabilities/presence_capability.dart';
import '../registry/capabilities/provider_model_capability.dart';
import '../registry/capabilities/session_resume_capability.dart';
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/resume_strategy.dart';
import '../registry/capabilities/headless_provision_capability.dart';
import 'capabilities/config_profile.dart';
import 'capabilities/prompt_provision.dart';
import '../registry/capabilities/prompt_provision_capability.dart';
import 'capabilities/headless_run.dart';
import 'capabilities/headless_provision.dart';
import 'provider/flashskyai_effort_capability.dart';
import 'provider/flashskyai_provider_form_capability.dart';
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
import '../claude/capabilities/mcp_config_writer.dart';
import 'capabilities/plugin_provisioner.dart';
import '../registry/resources/default_resource_capability.dart';
import '../../team_bus/bus_idle_hooks_capability.dart';

final class FlashskyaiCliTool implements CliToolDefinition {
  const FlashskyaiCliTool({
    this.busTransport = const BusTransportCapability(
      longBlockingWaitForMessage: true,
    ),
    this.remoteCliLocator = const DefaultRemoteCliLocator('flashskyai'),
    this.launchArgs = const FlashskyaiCliToolAdapter(),
    this.configProfile = const FlashskyaiConfigProfileCapability(),
    this.sessionResume = const FlashskyaiResumeStrategy(),
    this.executableResolver = const FlashskyaiExecutableResolver(),
    this.installer = const UnsupportedInstallerCapability(),
    this.presence = const FlashskyaiPresence(),
    this.display = const FlashskyaiDisplay(),
    this.terminalBehavior = const FlashskyaiTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.pluginProvisioner = const FlashskyaiPluginProvisioner(),
    this.providerCatalog = const FlashskyaiProviderCatalogCapability(),
    this.providerModel = const ProviderRecordModelCapability(),
    this.effort = const FlashskyaiEffortCapability(),
    this.headlessRun = const FlashskyaiHeadlessRunCapability(),
    this.headlessProvision = const FlashskyaiHeadlessProvisionCapability(),
    this.providerForm = const FlashskyaiProviderFormCapability(),
    this.resource = const DefaultResourceCapability(),
    this.mcpConfigWriter = const FlashskyaiMcpConfigWriter(),
    this.turnInterrupt = const CtrlCTurnInterrupt(),
    this.askUserQuestion = const PtyAskUserQuestionCapability(),
    this.exitPlanMode = const HookExitPlanModeCapability(),
    this.aiHistory = const FlashskyaiAiHistoryCapability(),
    this.skillSyntax = const DefaultSkillInvocationSyntaxCapability(),
    this.turnCompletion = const FlashskyaiTurnCompletion(),
    this.waitBeforeStop = const DefaultWaitBeforeStop(),
    this.providerDisplay = const FlashskyaiProviderDisplay(),
    this.configUi = const FlashskyaiConfigUi(),
    this.titleAttention = const NoTitleAttention(),
    this.marketplaceConsumer = const MarketplaceConsumer(),
    this.agentStatusNormalizer = const ClaudeFamilyAgentStatusNormalizer(),
    this.historyContextEnv = const NoHistoryContextEnv(),
    this.remoteAppData = const NoRemoteAppData(),
    this.credentialExport = const NoCredentialExport(),
    this.toolCallResolvers = const FlashskyaiToolCallResolvers(),
    this.promptProvision = const FlashskyaiPromptProvisionCapability(),
    this.busIdleHooks = const BusIdleHooksCapability(),
  });

  final LaunchArgsCapability launchArgs;
  final ConfigProfileCapability configProfile;
  final SessionResumeCapability sessionResume;
  final ExecutableResolverCapability executableResolver;
  final InstallerCapability installer;
  final PresenceCapability presence;
  final FlashskyaiDisplay display;
  final FlashskyaiTerminalBehavior terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final FlashskyaiPluginProvisioner pluginProvisioner;
  final ProviderCatalogCapability providerCatalog;
  final ProviderModelCapability providerModel;
  final CliEffortCapability effort;
  final HeadlessRunCapability headlessRun;
  final HeadlessProvisionCapability headlessProvision;
  final ProviderFormCapability providerForm;
  final ResourceCapability resource;
  final FlashskyaiMcpConfigWriter mcpConfigWriter;

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
  final FlashskyaiToolCallResolvers toolCallResolvers;
  final PromptProvisionCapability promptProvision;
  final BusIdleHooksCapability busIdleHooks;
  final AskUserQuestionCapability askUserQuestion;
  final ExitPlanModeCapability exitPlanMode;
  final FlashskyaiAiHistoryCapability aiHistory;
  final SkillInvocationSyntaxCapability skillSyntax;

  @override
  CliTool get id => CliTool.flashskyai;

  @override
  bool get isLaunchSupported => true;

  static const _nativeTeam = NativeTeamSupport();
  static const _memberAgentPreset = FlashskyaiMemberAgentPreset();

  @override
  Iterable<CliCapability> get capabilities => [
    busTransport,
    remoteCliLocator,
    _nativeTeam,
    _memberAgentPreset,
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
    promptProvision,
    busIdleHooks,
  ];
}

final class FlashskyaiTurnCompletion implements TurnCompletionCapability {
  const FlashskyaiTurnCompletion();
  @override
  Set<String> get doneEventNames => const {'Stop', 'StopFailure'};
  @override
  bool get requiresPtyFallback => false;
  @override
  bool get usesDoorbellPush => false;
}
