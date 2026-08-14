import '../../../models/team_config.dart';
import 'capabilities/launch_args.dart';
import '../registry/cli_capability.dart';
import '../registry/cli_tool_definition.dart';
import 'capabilities/team_behavior.dart';
import 'capabilities/chat_interaction.dart';
import 'capabilities/terminal_behavior.dart';
import 'capabilities/provider_catalog.dart';
import '../registry/capabilities/provider_catalog_capability.dart';
import '../registry/capabilities/team_behavior_capability.dart';
import '../registry/capabilities/config_profile_capability.dart';
import '../registry/capabilities/cli_effort_capability.dart';
import '../registry/capabilities/headless_capability.dart';
import '../registry/capabilities/launch_args_capability.dart';
import '../registry/capabilities/provider_model_capability.dart';
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/config_profile.dart';
import 'capabilities/prompt_provision.dart';
import '../registry/capabilities/prompt_provision_capability.dart';
import 'capabilities/headless.dart';
import 'provider/flashskyai_effort_capability.dart';
import 'provider/flashskyai_provider_form_capability.dart';
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
import '../claude/capabilities/mcp_config_writer.dart';
import 'capabilities/plugin_provisioner.dart';
import 'capabilities/executable.dart';
import '../registry/resources/default_resource_capability.dart';
import '../registry/config_profile/claude_family_hook_writer.dart';
import '../registry/capabilities/hook_writer_capability.dart';

final class FlashskyaiCliTool implements CliToolDefinition {
  const FlashskyaiCliTool({
    this.teamBehavior = const FlashskyaiTeamBehavior(),
    this.launchArgs = const FlashskyaiCliToolAdapter(),
    this.configProfile = const FlashskyaiConfigProfileCapability(),
    this.executable = const FlashskyaiExecutableCapability(),
    this.terminalBehavior = const FlashskyaiTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.pluginProvisioner = const FlashskyaiPluginProvisioner(),
    this.providerCatalog = const FlashskyaiProviderCatalogCapability(),
    this.providerModel = const ProviderRecordModelCapability(),
    this.effort = const FlashskyaiEffortCapability(),
    this.headless = const FlashskyaiHeadlessCapability(),
    this.providerForm = const FlashskyaiProviderFormCapability(),
    this.mcpConfigWriter = const FlashskyaiMcpConfigWriter(),
    this.chatInteraction = const FlashskyaiChatInteraction(),
    this.aiHistory = const FlashskyaiAiHistoryCapability(),
    this.skill = const DefaultSkillCapability(),
    this.providerDisplay = const FlashskyaiProviderDisplay(),
    this.marketplaceConsumer = const MarketplaceConsumer(),
    this.remoteAppData = const NoRemoteAppData(),
    this.credentialExport = const NoCredentialExport(),
    this.hookWriter = const ClaudeFamilyHookWriter(),
    this.promptProvision = const FlashskyaiPromptProvisionCapability(),
  });

  final LaunchArgsCapability launchArgs;
  final ConfigProfileCapability configProfile;
  final CliExecutableCapability executable;
  final FlashskyaiTerminalBehavior terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final FlashskyaiPluginProvisioner pluginProvisioner;
  final ProviderCatalogCapability providerCatalog;
  final ProviderModelCapability providerModel;
  final CliEffortCapability effort;
  final HeadlessCapability headless;
  final ProviderFormCapability providerForm;
  final FlashskyaiMcpConfigWriter mcpConfigWriter;

  final TeamBehaviorCapability teamBehavior;
  final ProviderDisplayCapability providerDisplay;
  final MarketplaceConsumerCapability marketplaceConsumer;
  final RemoteAppDataCapability remoteAppData;
  final CredentialExportCapability credentialExport;
  final HookWriterCapability hookWriter;
  final PromptProvisionCapability promptProvision;
  final ChatInteractionCapability chatInteraction;
  final FlashskyaiAiHistoryCapability aiHistory;
  final SkillCapability skill;

  @override
  CliTool get id => CliTool.flashskyai;

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
    hookWriter,
    promptProvision,
  ];
}
