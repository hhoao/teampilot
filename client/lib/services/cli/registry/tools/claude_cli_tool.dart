import '../../../../models/team_config.dart';
import '../../cli_tool_adapter.dart';
import '../cli_capability.dart';
import '../cli_tool_definition.dart';
import '../capabilities/bus_transport_capability.dart';
import '../capabilities/built_in_tool_capabilities.dart';
import '../capabilities/claude_provider_catalog_capability.dart';
import '../capabilities/provider_catalog_capability.dart';
import '../capabilities/member_agent_preset_capability.dart';
import '../capabilities/native_team_capability.dart';
import '../capabilities/config_profile_capability.dart';
import '../capabilities/executable_resolver_capability.dart';
import '../capabilities/installer_capability.dart';
import '../capabilities/launch_args_capability.dart';
import '../capabilities/presence_capability.dart';
import '../capabilities/cli_effort_capability.dart';
import '../capabilities/headless_run_capability.dart';
import '../capabilities/headless_provision_capability.dart';
import '../capabilities/provider_credential_capability.dart';
import '../capabilities/provider_model_capability.dart';
import '../capabilities/session_resume_capability.dart';
import '../capabilities/resume/claude_resume_strategy.dart';
import '../config_profile/claude_config_profile_capability.dart';
import '../headless/claude_headless_run_capability.dart';
import '../headless/claude_headless_provision_capability.dart';
import '../installer/claude_installer_capability.dart';
import '../../../provider/claude/claude_effort_capability.dart';
import '../../../provider/claude/claude_provider_credential_capability.dart';
import '../../../provider/claude/claude_provider_form_capability.dart';
import '../../../provider/claude/claude_provider_model_capability.dart';
import '../capabilities/member_config_inspection_capability.dart';
import '../capabilities/provider_form_capability.dart';
import '../capabilities/resource_capability.dart';
import '../mcp_writers/claude_mcp_config_writer.dart';
import '../plugin_provisioners/claude_plugin_provisioner.dart';
import '../resources/default_resource_capability.dart';

final class ClaudeCliTool implements CliToolDefinition {
  ClaudeCliTool({
    this.busTransport = const BusTransportCapability(longBlockingWaitForMessage: true),
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
    ProviderCredentialCapability? providerCredential,
  }) : providerCredential =
           providerCredential ?? ClaudeProviderCredentialCapability();

  final ProviderCredentialCapability providerCredential;
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

  @override
  CliTool get id => CliTool.claude;

  @override
  bool get isLaunchSupported => true;

  static const _nativeTeam = NativeTeamSupport();
  static const _memberAgentPreset = ClaudeMemberAgentPreset();

  @override
  Iterable<CliCapability> get capabilities => [
    busTransport,
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
  ];
}
