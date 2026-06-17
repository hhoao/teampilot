import '../../../../models/team_config.dart';
import '../../cli_tool_adapter.dart';
import '../cli_capability.dart';
import '../cli_tool_definition.dart';
import '../../../provider/cursor/cursor_provider_catalog_capability.dart';
import '../capabilities/built_in_tool_capabilities.dart';
import '../capabilities/provider_catalog_capability.dart';
import '../capabilities/config_profile_capability.dart';
import '../capabilities/executable_resolver_capability.dart';
import '../capabilities/installer_capability.dart';
import '../capabilities/launch_args_capability.dart';
import '../capabilities/presence_capability.dart';
import '../../../provider/cursor/cursor_provider_credential_capability.dart';
import '../../../provider/cursor/cursor_provider_model_capability.dart';
import '../capabilities/headless_run_capability.dart';
import '../capabilities/provider_credential_capability.dart';
import '../capabilities/session_resume_capability.dart';
import '../capabilities/resume/cursor_resume_strategy.dart';
import '../capabilities/unsupported_installer_capability.dart';
import '../config_profile/cursor_config_profile_capability.dart';
import '../headless/cursor_headless_run_capability.dart';
import '../../../provider/cursor/cursor_provider_form_capability.dart';
import '../capabilities/member_config_inspection_capability.dart';
import '../capabilities/provider_form_capability.dart';
import '../capabilities/resource_capability.dart';
import '../resources/default_resource_capability.dart';

/// Cursor CLI (`cursor-agent`). Standalone and mixed-mode (HOME isolation +
/// provider auth) embedded terminal.
final class CursorCliTool implements CliToolDefinition {
  CursorCliTool({
    this.launchArgs = const CursorCliToolAdapter(),
    this.configProfile = const CursorConfigProfileCapability(),
    this.sessionResume = const CursorResumeStrategy(),
    this.executableResolver = const CursorExecutableResolver(),
    this.installer = const UnsupportedInstallerCapability(),
    this.presence = const CursorPresence(),
    this.display = const CursorDisplay(),
    this.terminalBehavior = const CursorTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.pluginManifest = const CursorPluginManifest(),
    this.providerCatalog = const CursorProviderCatalogCapability(),
    CursorProviderModelCapability? providerModel,
    this.headlessRun = const CursorHeadlessRunCapability(),
    this.providerForm = const CursorProviderFormCapability(),
    this.resource = const DefaultResourceCapability(),
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
  final CursorPluginManifest pluginManifest;
  final ProviderCatalogCapability providerCatalog;
  final CursorProviderModelCapability providerModel;
  final HeadlessRunCapability headlessRun;
  final ResourceCapability resource;

  @override
  CliTool get id => CliTool.cursor;

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
    pluginManifest,
    providerCatalog,
    providerModel,
    providerCredential,
    providerForm,
    headlessRun,
    resource,
  ];
}
