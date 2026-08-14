import '../../../models/team_config.dart';
import 'capabilities/launch_args.dart';
import '../registry/cli_capability.dart';
import '../registry/cli_tool_definition.dart';
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
import 'capabilities/history/ai_history_capability.dart';
import 'capabilities/config_profile.dart';
import 'capabilities/session_lifecycle.dart';
import '../registry/capabilities/cli_session_lifecycle_capability.dart';
import '../registry/capabilities/post_manifest_flush_capability.dart';
import 'capabilities/headless.dart';
import 'provider/cursor_provider_form_capability.dart';
import '../registry/capabilities/member_config_inspection_capability.dart';
import '../registry/capabilities/provider_form_capability.dart';
import '../registry/capabilities/skill_capability.dart';
import '../registry/capabilities/chat_interaction_capability.dart';
import 'capabilities/provider_display.dart';
import '../registry/capabilities/provider_display_capability.dart';
import '../registry/capabilities/cli_executable_capability.dart';
import 'capabilities/credential_export.dart';
import '../registry/capabilities/credential_export_capability.dart';
import 'capabilities/mcp.dart';
import 'capabilities/plugin.dart';
import '../registry/capabilities/plugin_capability.dart';
import 'capabilities/post_manifest_flush.dart';
import 'capabilities/skill.dart';
import 'capabilities/executable.dart';
import '../registry/capabilities/hook_capability.dart';
import 'provider/cursor_hook_writer.dart';

/// Cursor CLI (`cursor-agent`). Standalone and mixed-mode (HOME isolation +
/// provider auth) embedded terminal.
final class CursorCliTool implements CliToolDefinition {
  CursorCliTool({
    this.teamBehavior = const CursorTeamBehavior(),
    this.launchArgs = const CursorCliToolAdapter(),
    this.configProfile = const CursorConfigProfileCapability(),
    this.sessionLifecycle = const CursorSessionLifecycleCapability(),
    this.executable = const CursorExecutableCapability(),
    this.terminalBehavior = const CursorTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.plugin = const CursorPluginCapability(),
    this.providerCatalog = const CursorProviderCatalogCapability(),
    CursorProviderModelCapability? providerModel,
    this.headless = const CursorHeadlessCapability(),
    this.providerForm = const CursorProviderFormCapability(),
    this.configLayout = const CursorCliConfigLayout(),
    this.mcp = const CursorMcpCapability(),
    this.chatInteraction = const CursorChatInteraction(),
    this.aiHistory = const CursorAiHistoryCapability(),
    this.skill = const CursorSkillCapability(),
    this.postManifestFlush = const CursorPostManifestFlushCapability(),
    this.providerDisplay = const CursorProviderDisplay(),
    this.credentialExport = const CursorCredentialExport(),
    this.hookWriter = const CursorHookWriter(),
    this.promptProvision = const CursorPromptProvisionCapability(),
    ProviderCredentialCapability? providerCredential,
  }) : providerModel = providerModel ?? CursorProviderModelCapability(),
       providerCredential =
           providerCredential ?? CursorProviderCredentialCapability();

  final ProviderCredentialCapability providerCredential;
  final ProviderFormCapability providerForm;

  final LaunchArgsCapability launchArgs;
  final ConfigProfileCapability configProfile;
  final CliSessionLifecycleCapability sessionLifecycle;
  final CliExecutableCapability executable;
  final CursorTerminalBehavior terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final PluginCapability plugin;
  final ProviderCatalogCapability providerCatalog;
  final CursorProviderModelCapability providerModel;
  final HeadlessCapability headless;
  final CliConfigLayoutCapability configLayout;
  final CursorMcpCapability mcp;

  final TeamBehaviorCapability teamBehavior;
  final ProviderDisplayCapability providerDisplay;
  final CredentialExportCapability credentialExport;
  final HookCapability hookWriter;
  final ChatInteractionCapability chatInteraction;
  final CursorAiHistoryCapability aiHistory;
  final SkillCapability skill;
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
    terminalBehavior,
    memberConfigInspection,
    plugin,
    providerCatalog,
    providerModel,
    providerCredential,
    providerForm,
    headless,
    configLayout,
    mcp,
    providerDisplay,
    credentialExport,
    chatInteraction,
    aiHistory,
    skill,
    postManifestFlush,
    promptProvision,
    hookWriter,
  ];
}
