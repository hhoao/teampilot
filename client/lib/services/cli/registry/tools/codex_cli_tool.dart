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
import '../capabilities/provider_model_capability.dart';
import '../capabilities/transcript_probe_capability.dart';
import '../config_profile/codex_config_profile_capability.dart';
import '../installer/codex_installer_capability.dart';

final class CodexCliTool implements CliToolDefinition {
  const CodexCliTool({
    this.launchArgs = const CodexCliToolAdapter(),
    this.configProfile = const CodexConfigProfileCapability(),
    this.transcriptProbe = const CodexTranscriptProbe(),
    this.executableResolver = const CodexExecutableResolver(),
    this.installer = const CodexInstallerCapability(),
    this.presence = const CodexPresence(),
    this.display = const CodexDisplay(),
    this.terminalBehavior = const CodexTerminalBehavior(),
    this.pluginManifest = const CodexPluginManifest(),
    this.providerCatalog = const CodexProviderCatalog(),
    this.providerModel = const ProviderRecordModelCapability(),
  });

  final LaunchArgsCapability launchArgs;
  final ConfigProfileCapability configProfile;
  final TranscriptProbeCapability transcriptProbe;
  final ExecutableResolverCapability executableResolver;
  final InstallerCapability installer;
  final PresenceCapability presence;
  final CodexDisplay display;
  final CodexTerminalBehavior terminalBehavior;
  final CodexPluginManifest pluginManifest;
  final CodexProviderCatalog providerCatalog;
  final ProviderModelCapability providerModel;

  @override
  CliTool get id => CliTool.codex;

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
  ];
}
