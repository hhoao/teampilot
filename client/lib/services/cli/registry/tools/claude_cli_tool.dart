import '../../../../models/app_provider_config.dart';
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

final class ClaudeCliTool implements CliToolDefinition {
  const ClaudeCliTool({
    this.launchArgs = const ClaudeCodeCliToolAdapter(),
    this.configProfile = const ClaudeConfigProfileCapability(),
    this.transcriptProbe = const ClaudeTranscriptProbe(),
    this.executableResolver = const ClaudeExecutableResolver(),
    this.installer = const ClaudeInstaller(),
    this.presence = const ClaudePresence(),
  });

  final LaunchArgsCapability launchArgs;
  final ConfigProfileCapability configProfile;
  final TranscriptProbeCapability transcriptProbe;
  final ExecutableResolverCapability executableResolver;
  final InstallerCapability installer;
  final PresenceCapability presence;

  @override
  String get id => 'claude';

  @override
  bool get isLaunchSupported => true;

  @override
  AppProviderCli? get providerCatalogCli => AppProviderCli.claude;

  @override
  Iterable<CliCapability> get capabilities => [
    launchArgs,
    configProfile,
    transcriptProbe,
    executableResolver,
    installer,
    presence,
  ];
}
