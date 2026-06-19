import '../../../../models/team_config.dart';
import '../../cli_tool_adapter.dart';
import '../cli_capability.dart';
import '../cli_tool_definition.dart';
import '../capabilities/built_in_tool_capabilities.dart';
import '../capabilities/config_profile_capability.dart';
import '../capabilities/executable_resolver_capability.dart';
import '../capabilities/installer_capability.dart';
import '../capabilities/launch_args_capability.dart';
import '../capabilities/presence_capability.dart';
import '../../../provider/opencode/opencode_provider_credential_capability.dart';
import '../../../provider/opencode/opencode_provider_catalog_capability.dart';
import '../capabilities/cli_effort_capability.dart';
import '../capabilities/headless_run_capability.dart';
import '../capabilities/provider_catalog_capability.dart';
import '../capabilities/provider_credential_capability.dart';
import '../capabilities/provider_model_capability.dart';
import '../capabilities/session_resume_capability.dart';
import '../capabilities/resume/opencode_resume_strategy.dart';
import '../capabilities/headless_provision_capability.dart';
import '../config_profile/opencode_config_profile_capability.dart';
import '../headless/opencode_headless_run_capability.dart';
import '../headless/opencode_headless_provision_capability.dart';
import '../installer/opencode_installer_capability.dart';
import '../../../provider/opencode/opencode_effort_capability.dart';
import '../../../provider/opencode/opencode_provider_form_capability.dart';
import '../capabilities/member_config_inspection_capability.dart';
import '../capabilities/provider_form_capability.dart';
import '../capabilities/resource_capability.dart';
import '../mcp_writers/opencode_mcp_config_writer.dart';
import '../mcp_writers/opencode_mcp_config_writer.dart';
import '../plugin_provisioners/opencode_plugin_provisioner.dart';
import '../resources/opencode_resource_capability.dart';

final class OpencodeCliTool implements CliToolDefinition {
  OpencodeCliTool({
    this.launchArgs = const OpencodeCliToolAdapter(),
    this.configProfile = const OpencodeConfigProfileCapability(),
    this.sessionResume = const OpencodeResumeStrategy(),
    this.executableResolver = const OpencodeExecutableResolver(),
    this.installer = const OpencodeInstallerCapability(),
    this.presence = const OpencodePresence(),
    this.display = const OpencodeDisplay(),
    this.terminalBehavior = const OpencodeTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.pluginProvisioner = const OpencodePluginProvisioner(),
    this.providerCatalog = const OpencodeProviderCatalogCapability(),
    this.providerModel = const OpencodeProviderModelCapability(),
    this.effort = const OpencodeEffortCapability(),
    this.headlessRun = const OpencodeHeadlessRunCapability(),
    this.headlessProvision = const OpencodeHeadlessProvisionCapability(),
    this.providerForm = const OpencodeProviderFormCapability(),
    this.resource = const OpencodeResourceCapability(),
    this.mcpConfigWriter = const OpencodeMcpConfigWriter(),
    ProviderCredentialCapability? providerCredential,
  }) : providerCredential =
           providerCredential ?? OpencodeProviderCredentialCapability();

  final ProviderCredentialCapability providerCredential;
  final ProviderFormCapability providerForm;

  final LaunchArgsCapability launchArgs;
  final ConfigProfileCapability configProfile;
  final SessionResumeCapability sessionResume;
  final ExecutableResolverCapability executableResolver;
  final InstallerCapability installer;
  final PresenceCapability presence;
  final OpencodeDisplay display;
  final OpencodeTerminalBehavior terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final OpencodePluginProvisioner pluginProvisioner;
  final ProviderCatalogCapability providerCatalog;
  final ProviderModelCapability providerModel;
  final CliEffortCapability effort;
  final HeadlessRunCapability headlessRun;
  final HeadlessProvisionCapability headlessProvision;
  final ResourceCapability resource;
  final OpencodeMcpConfigWriter mcpConfigWriter;

  @override
  CliTool get id => CliTool.opencode;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => [
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
