import '../../../../models/team_config.dart';
import '../../cli_tool_adapter.dart';
import '../cli_capability.dart';
import '../cli_tool_definition.dart';
import '../capabilities/bus_transport_capability.dart';
import '../capabilities/remote_cli_locator_capability.dart';
import '../../../provider/cursor/cursor_cli_config_layout.dart';
import '../../../provider/cursor/cursor_provider_catalog_capability.dart';
import '../capabilities/cli_config_layout_capability.dart';
import '../capabilities/built_in_tool_capabilities.dart';
import '../capabilities/provider_catalog_capability.dart';
import '../capabilities/config_profile_capability.dart';
import '../capabilities/executable_resolver_capability.dart';
import '../capabilities/installer_capability.dart';
import '../capabilities/launch_args_capability.dart';
import '../capabilities/presence_capability.dart';
import '../../../provider/cursor/cursor_provider_credential_capability.dart';
import '../../../provider/cursor/cursor_provider_model_capability.dart';
import '../capabilities/cli_effort_capability.dart';
import '../capabilities/headless_run_capability.dart';
import '../capabilities/provider_credential_capability.dart';
import '../capabilities/session_resume_capability.dart';
import '../capabilities/resume/cursor_resume_strategy.dart';
import '../capabilities/unsupported_installer_capability.dart';
import '../config_profile/cursor_config_profile_capability.dart';
import '../headless/cursor_headless_run_capability.dart';
import '../../../provider/cursor/cursor_effort_capability.dart';
import '../../../provider/cursor/cursor_provider_form_capability.dart';
import '../capabilities/member_config_inspection_capability.dart';
import '../capabilities/provider_form_capability.dart';
import '../capabilities/resource_capability.dart';
import '../mcp_writers/cursor_mcp_config_writer.dart';
import '../plugin_provisioners/cursor_plugin_provisioner.dart';
import '../resources/cursor_resource_capability.dart';

/// Cursor CLI (`cursor-agent`). Standalone and mixed-mode (HOME isolation +
/// provider auth) embedded terminal.
final class CursorCliTool implements CliToolDefinition {
  CursorCliTool({
    this.busTransport = const BusTransportCapability(longBlockingWaitForMessage: false),
    this.remoteCliLocator = const DefaultRemoteCliLocator('cursor-agent'),
    this.launchArgs = const CursorCliToolAdapter(),
    this.configProfile = const CursorConfigProfileCapability(),
    this.sessionResume = const CursorResumeStrategy(),
    this.executableResolver = const CursorExecutableResolver(),
    this.installer = const UnsupportedInstallerCapability(),
    this.presence = const CursorPresence(),
    this.display = const CursorDisplay(),
    this.terminalBehavior = const CursorTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.pluginProvisioner = const CursorPluginProvisioner(),
    this.providerCatalog = const CursorProviderCatalogCapability(),
    CursorProviderModelCapability? providerModel,
    this.effort = const CursorEffortCapability(),
    this.headlessRun = const CursorHeadlessRunCapability(),
    this.providerForm = const CursorProviderFormCapability(),
    this.resource = const CursorResourceCapability(),
    this.configLayout = const CursorCliConfigLayout(),
    this.mcpConfigWriter = const CursorMcpConfigWriter(),
    ProviderCredentialCapability? providerCredential,
  }) : providerModel = providerModel ?? CursorProviderModelCapability(),
       providerCredential = providerCredential ?? CursorProviderCredentialCapability();

  final ProviderCredentialCapability providerCredential;
  final ProviderFormCapability providerForm;

  final LaunchArgsCapability launchArgs;
  final ConfigProfileCapability configProfile;
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
  final CliEffortCapability effort;
  final HeadlessRunCapability headlessRun;
  final ResourceCapability resource;
  final CliConfigLayoutCapability configLayout;
  final CursorMcpConfigWriter mcpConfigWriter;

  final BusTransportCapability busTransport;
  final RemoteCliLocatorCapability remoteCliLocator;

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
    resource,
    configLayout,
    mcpConfigWriter,
  ];
}
