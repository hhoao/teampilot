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
import '../config_profile/flashskyai_config_profile_capability.dart';

final class FlashskyaiCliTool implements CliToolDefinition {
  const FlashskyaiCliTool({
    this.launchArgs = const FlashskyaiCliToolAdapter(),
    this.configProfile = const FlashskyaiConfigProfileCapability(),
    this.transcriptProbe = const FlashskyaiTranscriptProbe(),
    this.executableResolver = const FlashskyaiExecutableResolver(),
    this.installer = const FlashskyaiInstaller(),
    this.presence = const FlashskyaiPresence(),
  });

  final LaunchArgsCapability launchArgs;
  final ConfigProfileCapability configProfile;
  final TranscriptProbeCapability transcriptProbe;
  final ExecutableResolverCapability executableResolver;
  final InstallerCapability installer;
  final PresenceCapability presence;

  @override
  String get id => 'flashskyai';

  @override
  bool get isLaunchSupported => true;

  @override
  AppProviderCli? get providerCatalogCli => AppProviderCli.flashskyai;

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
