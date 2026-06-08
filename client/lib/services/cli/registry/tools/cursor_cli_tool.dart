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
import '../../../provider/cursor/cursor_provider_credential_capability.dart';
import '../../../provider/cursor/cursor_provider_model_capability.dart';
import '../capabilities/headless_run_capability.dart';
import '../capabilities/provider_credential_capability.dart';
import '../capabilities/transcript_probe_capability.dart';
import '../capabilities/unsupported_installer_capability.dart';
import '../config_profile/cursor_config_profile_capability.dart';
import '../headless/cursor_headless_run_capability.dart';

/// Cursor CLI (`cursor-agent`). Standalone and mixed-mode (HOME isolation +
/// provider auth) embedded terminal.
final class CursorCliTool implements CliToolDefinition {
  CursorCliTool({
    this.launchArgs = const CursorCliToolAdapter(),
    this.configProfile = const CursorConfigProfileCapability(),
    this.transcriptProbe = const CursorTranscriptProbe(),
    this.executableResolver = const CursorExecutableResolver(),
    this.installer = const UnsupportedInstallerCapability(),
    this.presence = const CursorPresence(),
    this.display = const CursorDisplay(),
    this.terminalBehavior = const CursorTerminalBehavior(),
    this.pluginManifest = const CursorPluginManifest(),
    this.providerCatalog = const CursorProviderCatalog(),
    CursorProviderModelCapability? providerModel,
    this.headlessRun = const CursorHeadlessRunCapability(),
    ProviderCredentialCapability? providerCredential,
  }) : providerModel = providerModel ?? CursorProviderModelCapability(),
       providerCredential = providerCredential ?? CursorProviderCredentialCapability();

  final ProviderCredentialCapability providerCredential;

  final LaunchArgsCapability launchArgs;
  final ConfigProfileCapability configProfile;
  final TranscriptProbeCapability transcriptProbe;
  final ExecutableResolverCapability executableResolver;
  final InstallerCapability installer;
  final PresenceCapability presence;
  final CursorDisplay display;
  final CursorTerminalBehavior terminalBehavior;
  final CursorPluginManifest pluginManifest;
  final CursorProviderCatalog providerCatalog;
  final CursorProviderModelCapability providerModel;
  final HeadlessRunCapability headlessRun;

  @override
  CliTool get id => CliTool.cursor;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => [
    launchArgs,
    configProfile,
    transcriptProbe,
    executableResolver,
    installer,
    presence,
    display,
    terminalBehavior,
    pluginManifest,
    providerCatalog,
    providerModel,
    providerCredential,
    headlessRun,
  ];
}
