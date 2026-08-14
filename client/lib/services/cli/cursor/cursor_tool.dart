import '../../../models/team_config.dart';
import 'capabilities/launch_args.dart';
import '../registry/cli_capability.dart';
import '../registry/cli_tool_definition.dart';
import '../registry/capabilities/skill_invocation_syntax_capability.dart';
import 'provider/cursor_cli_config_layout.dart';
import 'provider/cursor_provider_catalog_capability.dart';
import '../registry/capabilities/cli_config_layout_capability.dart';
import 'capabilities/team_behavior.dart';
import 'capabilities/chat_interaction.dart';
import 'capabilities/terminal_behavior.dart';
import 'capabilities/prompt_provision.dart';
import '../registry/capabilities/prompt_provision_capability.dart';
import '../registry/capabilities/provider_catalog_capability.dart';
import '../registry/capabilities/config_profile_capability.dart';
import '../registry/capabilities/launch_args_capability.dart';
import '../registry/capabilities/team_behavior_capability.dart';
import 'provider/cursor_provider_credential_capability.dart';
import 'provider/cursor_provider_model_capability.dart';
import '../registry/capabilities/headless_capability.dart';
import '../registry/capabilities/provider_credential_capability.dart';
import '../registry/capabilities/session_resume_capability.dart';
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/history/side_resolver.dart';
import 'capabilities/resume_strategy.dart';
import 'capabilities/config_profile.dart';
import 'capabilities/session_lifecycle.dart';
import '../registry/capabilities/cli_session_lifecycle_capability.dart';
import '../registry/capabilities/post_manifest_flush_capability.dart';
import 'capabilities/headless.dart';
import 'provider/cursor_provider_form_capability.dart';
import '../registry/capabilities/member_config_inspection_capability.dart';
import '../registry/capabilities/provider_form_capability.dart';
import '../registry/capabilities/resource_capability.dart';
import '../registry/capabilities/chat_interaction_capability.dart';
import 'capabilities/provider_display.dart';
import '../registry/capabilities/provider_display_capability.dart';
import '../registry/capabilities/cli_executable_capability.dart';
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
import 'capabilities/post_manifest_flush.dart';
import 'capabilities/resource.dart';
import 'capabilities/executable.dart';
import '../registry/capabilities/hook_writer_capability.dart';
import 'provider/cursor_hook_writer.dart';

/// Cursor CLI (`cursor-agent`). Standalone and mixed-mode (HOME isolation +
/// provider auth) embedded terminal.
final class CursorCliTool implements CliToolDefinition {
  CursorCliTool({
    this.teamBehavior = const CursorTeamBehavior(),
    this.launchArgs = const CursorCliToolAdapter(),
    this.configProfile = const CursorConfigProfileCapability(),
    this.sessionLifecycle = const CursorSessionLifecycleCapability(),
    this.sessionResume = const CursorResumeStrategy(),
    this.executable = const CursorExecutableCapability(),
    this.terminalBehavior = const CursorTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.pluginProvisioner = const CursorPluginProvisioner(),
    this.providerCatalog = const CursorProviderCatalogCapability(),
    CursorProviderModelCapability? providerModel,
    this.headless = const CursorHeadlessCapability(),
    this.providerForm = const CursorProviderFormCapability(),
    this.resource = const CursorResourceCapability(),
    this.configLayout = const CursorCliConfigLayout(),
    this.mcpConfigWriter = const CursorMcpConfigWriter(),
    this.chatInteraction = const CursorChatInteraction(),
    CursorAiHistoryCapability? aiHistory,
    this.skillSyntax = const DefaultSkillInvocationSyntaxCapability(),
    this.postManifestFlush = const CursorPostManifestFlushCapability(),
    this.providerDisplay = const CursorProviderDisplay(),
    this.marketplaceConsumer = const MarketplaceConsumer(),
    this.historyContextEnv = const CursorHistoryContextEnv(),
    this.remoteAppData = const NoRemoteAppData(),
    this.credentialExport = const CursorCredentialExport(),
    this.toolCallResolvers = const CursorToolCallResolvers(),
    this.hookWriter = const CursorHookWriter(),
    this.promptProvision = const CursorPromptProvisionCapability(),
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
  final CliExecutableCapability executable;
  final CursorTerminalBehavior terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final CursorPluginProvisioner pluginProvisioner;
  final ProviderCatalogCapability providerCatalog;
  final CursorProviderModelCapability providerModel;
  final HeadlessCapability headless;
  final ResourceCapability resource;
  final CliConfigLayoutCapability configLayout;
  final CursorMcpConfigWriter mcpConfigWriter;

  final TeamBehaviorCapability teamBehavior;
  final ProviderDisplayCapability providerDisplay;
  final MarketplaceConsumerCapability marketplaceConsumer;
  final HistoryContextEnvCapability historyContextEnv;
  final RemoteAppDataCapability remoteAppData;
  final CredentialExportCapability credentialExport;
  final CursorToolCallResolvers toolCallResolvers;
  final HookWriterCapability hookWriter;
  final ChatInteractionCapability chatInteraction;
  final CursorAiHistoryCapability aiHistory;
  final SkillInvocationSyntaxCapability skillSyntax;
  final PostManifestFlushCapability postManifestFlush;
  final PromptProvisionCapability promptProvision;

  @override
  CliTool get id => CliTool.cursor;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => [
    teamBehavior,
    executable,
    launchArgs,
    configProfile,
    sessionLifecycle,
    sessionResume,
    terminalBehavior,
    memberConfigInspection,
    pluginProvisioner,
    providerCatalog,
    providerModel,
    providerCredential,
    providerForm,
    headless,
    resource,
    configLayout,
    mcpConfigWriter,
    providerDisplay,
    marketplaceConsumer,
    historyContextEnv,
    remoteAppData,
    credentialExport,
    chatInteraction,
    aiHistory,
    skillSyntax,
    postManifestFlush,
    promptProvision,
    toolCallResolvers,
    hookWriter,
  ];
}
