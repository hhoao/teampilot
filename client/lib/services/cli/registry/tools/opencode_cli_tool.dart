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
import '../capabilities/provider_catalog_capability.dart';
import '../capabilities/provider_credential_capability.dart';
import '../capabilities/provider_model_capability.dart';
import '../capabilities/transcript_probe_capability.dart';
import '../config_profile/opencode_config_profile_capability.dart';
import '../installer/opencode_installer_capability.dart';

final class OpencodeCliTool implements CliToolDefinition {
  OpencodeCliTool({
    this.launchArgs = const OpencodeCliToolAdapter(),
    this.configProfile = const OpencodeConfigProfileCapability(),
    this.transcriptProbe = const OpencodeTranscriptProbe(),
    this.executableResolver = const OpencodeExecutableResolver(),
    this.installer = const OpencodeInstallerCapability(),
    this.presence = const OpencodePresence(),
    this.display = const OpencodeDisplay(),
    this.terminalBehavior = const OpencodeTerminalBehavior(),
    this.pluginManifest = const OpencodePluginManifest(),
    this.providerCatalog = const OpencodeProviderCatalog(),
    this.providerModel = const OpencodeProviderModelCapability(),
    ProviderCredentialCapability? providerCredential,
  }) : providerCredential =
           providerCredential ?? OpencodeProviderCredentialCapability();

  final ProviderCredentialCapability providerCredential;

  final LaunchArgsCapability launchArgs;
  final ConfigProfileCapability configProfile;
  final TranscriptProbeCapability transcriptProbe;
  final ExecutableResolverCapability executableResolver;
  final InstallerCapability installer;
  final PresenceCapability presence;
  final OpencodeDisplay display;
  final OpencodeTerminalBehavior terminalBehavior;
  final OpencodePluginManifest pluginManifest;
  final ProviderCatalogCapability providerCatalog;
  final ProviderModelCapability providerModel;

  @override
  CliTool get id => CliTool.opencode;

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
  ];
}
