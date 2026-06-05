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
import '../capabilities/transcript_probe_capability.dart';
import '../config_profile/claude_config_profile_capability.dart';
import '../installer/claude_installer_capability.dart';

final class ClaudeCliTool implements CliToolDefinition {
  const ClaudeCliTool({
    this.launchArgs = const ClaudeCodeCliToolAdapter(),
    this.configProfile = const ClaudeConfigProfileCapability(),
    this.transcriptProbe = const ClaudeTranscriptProbe(),
    this.executableResolver = const ClaudeExecutableResolver(),
    this.installer = const ClaudeInstallerCapability(),
    this.presence = const ClaudePresence(),
    this.display = const ClaudeDisplay(),
    this.terminalBehavior = const ClaudeTerminalBehavior(),
    this.pluginManifest = const ClaudePluginManifest(),
    this.providerCatalog = const ClaudeProviderCatalog(),
  });

  final LaunchArgsCapability launchArgs;
  final ConfigProfileCapability configProfile;
  final TranscriptProbeCapability transcriptProbe;
  final ExecutableResolverCapability executableResolver;
  final InstallerCapability installer;
  final PresenceCapability presence;
  final ClaudeDisplay display;
  final ClaudeTerminalBehavior terminalBehavior;
  final ClaudePluginManifest pluginManifest;
  final ClaudeProviderCatalog providerCatalog;

  @override
  CliTool get id => CliTool.claude;

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
  ];
}
