import '../../../../models/team_config.dart';
import '../../cli_tool_adapter.dart';
import '../cli_capability.dart';
import '../cli_tool_definition.dart';
import '../capabilities/bus_transport_capability.dart';
import '../capabilities/remote_cli_locator_capability.dart';
import '../capabilities/built_in_tool_capabilities.dart';
import '../capabilities/flashskyai_provider_catalog_capability.dart';
import '../capabilities/provider_catalog_capability.dart';
import '../capabilities/member_agent_preset_capability.dart';
import '../capabilities/native_team_capability.dart';
import '../capabilities/config_profile_capability.dart';
import '../capabilities/executable_resolver_capability.dart';
import '../capabilities/installer_capability.dart';
import '../capabilities/unsupported_installer_capability.dart';
import '../capabilities/cli_effort_capability.dart';
import '../capabilities/headless_run_capability.dart';
import '../capabilities/launch_args_capability.dart';
import '../capabilities/presence_capability.dart';
import '../capabilities/provider_model_capability.dart';
import '../capabilities/session_resume_capability.dart';
import '../capabilities/resume/transcript_resume_strategy.dart';
import '../capabilities/headless_provision_capability.dart';
import '../config_profile/flashskyai_config_profile_capability.dart';
import '../headless/flashskyai_headless_run_capability.dart';
import '../headless/flashskyai_headless_provision_capability.dart';
import '../../../provider/flashskyai/flashskyai_effort_capability.dart';
import '../../../provider/flashskyai/flashskyai_provider_form_capability.dart';
import '../capabilities/member_config_inspection_capability.dart';
import '../capabilities/provider_form_capability.dart';
import '../capabilities/resource_capability.dart';
import '../mcp_writers/claude_mcp_config_writer.dart';
import '../plugin_provisioners/flashskyai_plugin_provisioner.dart';
import '../resources/default_resource_capability.dart';

final class FlashskyaiCliTool implements CliToolDefinition {
  const FlashskyaiCliTool({
    this.busTransport = const BusTransportCapability(longBlockingWaitForMessage: true),
    this.remoteCliLocator = const DefaultRemoteCliLocator('flashskyai'),
    this.launchArgs = const FlashskyaiCliToolAdapter(),
    this.configProfile = const FlashskyaiConfigProfileCapability(),
    this.sessionResume = const TranscriptResumeStrategy(),
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
  ];
}
