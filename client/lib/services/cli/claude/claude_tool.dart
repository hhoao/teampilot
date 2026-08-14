import '../../../models/team_config.dart';
import 'capabilities/launch_args.dart';
import 'capabilities/wait_before_stop.dart';
import 'capabilities/provider_display.dart';
import 'capabilities/config_ui.dart';
import 'capabilities/title_attention.dart';
import 'capabilities/marketplace_consumer.dart';
import '../registry/capabilities/claude_family_agent_status_normalizer.dart';
import 'capabilities/history_context_env.dart';
import 'capabilities/remote_app_data.dart';
import 'capabilities/credential_export.dart';
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
import '../registry/capabilities/launch_args_capability.dart';
import '../registry/capabilities/presence_capability.dart';
import '../registry/capabilities/cli_effort_capability.dart';
import '../registry/capabilities/headless_run_capability.dart';
import '../registry/capabilities/headless_provision_capability.dart';
import '../registry/capabilities/provider_credential_capability.dart';
import '../registry/capabilities/provider_model_capability.dart';
import '../registry/capabilities/session_resume_capability.dart';
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/resume_strategy.dart';
import 'capabilities/config_profile.dart';
import 'capabilities/headless_run.dart';
import 'capabilities/headless_provision.dart';
import 'capabilities/installer.dart';
import 'provider/claude_effort_capability.dart';
import 'provider/claude_provider_credential_capability.dart';
import 'provider/claude_provider_form_capability.dart';
import 'provider/claude_provider_model_capability.dart';
import '../registry/capabilities/member_config_inspection_capability.dart';
import '../registry/capabilities/provider_form_capability.dart';
import '../registry/capabilities/resource_capability.dart';
import '../registry/capabilities/ask_user_question_capability.dart';
import '../registry/capabilities/pty_ask_user_question_capability.dart';
import '../registry/capabilities/exit_plan_mode_capability.dart';
import '../registry/capabilities/turn_completion_capability.dart';
import '../registry/capabilities/wait_before_stop_capability.dart';
import '../registry/capabilities/provider_display_capability.dart';
import '../registry/capabilities/credential_binding_capability.dart';
import '../registry/capabilities/cli_config_ui_capability.dart';
import '../registry/capabilities/title_attention_capability.dart';
import '../registry/capabilities/marketplace_consumer_capability.dart';
import '../registry/capabilities/agent_status_normalizer_capability.dart';
import '../registry/capabilities/history_context_env_capability.dart';
import '../registry/capabilities/remote_app_data_capability.dart';
import '../registry/capabilities/credential_export_capability.dart';
import '../registry/capabilities/turn_interrupt_capability.dart';
import 'capabilities/tool_call_resolvers.dart';
import 'capabilities/mcp_config_writer.dart';
import 'capabilities/plugin_provisioner.dart';
import 'capabilities/credential_binding.dart';
import 'capabilities/prompt_provision.dart';
import '../registry/capabilities/prompt_provision_capability.dart';
import '../registry/resources/default_resource_capability.dart';
import '../registry/config_profile/claude_family_hook_writer.dart';
import '../registry/capabilities/hook_writer_capability.dart';

final class ClaudeCliTool implements CliToolDefinition {
  ClaudeCliTool({
    this.busTransport = const BusTransportCapability(
      longBlockingWaitForMessage: true,
      supportsLocalStdioBridge: true,
    ),
    this.remoteCliLocator = const DefaultRemoteCliLocator('claude'),
    this.launchArgs = const ClaudeCodeCliToolAdapter(),
    this.configProfile = const ClaudeConfigProfileCapability(),
    this.sessionResume = const ClaudeResumeStrategy(),
    this.executableResolver = const ClaudeExecutableResolver(),
    this.installer = const ClaudeInstallerCapability(),
    this.presence = const ClaudePresence(),
    this.display = const ClaudeDisplay(),
    this.terminalBehavior = const ClaudeTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.pluginProvisioner = const ClaudePluginProvisioner(),
    this.providerCatalog = const ClaudeProviderCatalogCapability(),
    this.providerModel = const ClaudeProviderModelCapability(),
    this.effort = const ClaudeEffortCapability(),
    this.headlessRun = const ClaudeHeadlessRunCapability(),
    this.headlessProvision = const ClaudeHeadlessProvisionCapability(),
    this.providerForm = const ClaudeProviderFormCapability(),
    this.resource = const DefaultResourceCapability(),
    this.mcpConfigWriter = const ClaudeMcpConfigWriter(),
    this.turnInterrupt = const CtrlCTurnInterrupt(),
    this.askUserQuestion = const PtyAskUserQuestionCapability(),
    this.exitPlanMode = const HookExitPlanModeCapability(),
    this.aiHistory = const ClaudeAiHistoryCapability(),
    this.skillSyntax = const DefaultSkillInvocationSyntaxCapability(),
    this.turnCompletion = const ClaudeTurnCompletion(),
    this.waitBeforeStop = const DefaultWaitBeforeStop(),
    this.providerDisplay = const ClaudeProviderDisplay(),
    this.configUi = const ClaudeConfigUi(),
    this.titleAttention = const NoTitleAttention(),
    this.marketplaceConsumer = const MarketplaceConsumer(),
    this.agentStatusNormalizer = const ClaudeFamilyAgentStatusNormalizer(),
    this.historyContextEnv = const NoHistoryContextEnv(),
    this.remoteAppData = const NoRemoteAppData(),
    this.credentialExport = const ClaudeCredentialExport(),
    this.toolCallResolvers = const ClaudeToolCallResolvers(),
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
  final SessionResumeCapability sessionResume;
  final ExecutableResolverCapability executableResolver;
  final InstallerCapability installer;
  final PresenceCapability presence;
  final ClaudeDisplay display;
  final ClaudeTerminalBehavior terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final ClaudePluginProvisioner pluginProvisioner;
  final ProviderCatalogCapability providerCatalog;
  final ProviderModelCapability providerModel;
  final CliEffortCapability effort;
  final HeadlessRunCapability headlessRun;
  final HeadlessProvisionCapability headlessProvision;
  final ResourceCapability resource;
  final ClaudeMcpConfigWriter mcpConfigWriter;

  final BusTransportCapability busTransport;
  final RemoteCliLocatorCapability remoteCliLocator;
  final TurnInterruptCapability turnInterrupt;
  final AskUserQuestionCapability askUserQuestion;
  final ExitPlanModeCapability exitPlanMode;
  final ClaudeAiHistoryCapability aiHistory;
  final SkillInvocationSyntaxCapability skillSyntax;
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
  final ClaudeToolCallResolvers toolCallResolvers;
  final CredentialBindingCapability credentialBinding;
  final PromptProvisionCapability promptProvision;

  @override
  CliTool get id => CliTool.claude;

  @override
  bool get isLaunchSupported => true;

  static const _nativeTeam = NativeTeamSupport();
  static const _memberAgentPreset = ClaudeMemberAgentPreset();

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
    providerCredential,
    providerForm,
    effort,
    headlessRun,
    headlessProvision,
    resource,
    mcpConfigWriter,
    turnInterrupt,
    askUserQuestion,
    exitPlanMode,
    aiHistory,
    skillSyntax,
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
    toolCallResolvers,
    credentialBinding,
    promptProvision,
    hookWriter,
  ];
}

final class ClaudeTurnCompletion implements TurnCompletionCapability {
  const ClaudeTurnCompletion();
  @override
  Set<String> get doneEventNames => const {'Stop', 'StopFailure'};
  @override
  bool get requiresPtyFallback => false;
  @override
  bool get usesDoorbellPush => false;
}
