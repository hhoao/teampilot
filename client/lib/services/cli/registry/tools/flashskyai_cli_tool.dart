import '../../../../models/team_config.dart';
import '../../cli_tool_adapter.dart';
import '../cli_capability.dart';
import '../cli_tool_definition.dart';
import '../capabilities/built_in_tool_capabilities.dart';
import '../capabilities/config_profile_capability.dart';
import '../capabilities/executable_resolver_capability.dart';
import '../capabilities/installer_capability.dart';
import '../capabilities/unsupported_installer_capability.dart';
import '../capabilities/headless_run_capability.dart';
import '../capabilities/launch_args_capability.dart';
import '../capabilities/presence_capability.dart';
import '../capabilities/provider_model_capability.dart';
import '../capabilities/transcript_probe_capability.dart';
import '../capabilities/headless_provision_capability.dart';
import '../config_profile/flashskyai_config_profile_capability.dart';
import '../headless/flashskyai_headless_run_capability.dart';
import '../headless/flashskyai_headless_provision_capability.dart';
import '../../../provider/flashskyai/flashskyai_provider_form_capability.dart';
import '../capabilities/provider_form_capability.dart';
import '../capabilities/resource_capability.dart';
import '../resources/default_resource_capability.dart';

final class FlashskyaiCliTool implements CliToolDefinition {
  const FlashskyaiCliTool({
    this.launchArgs = const FlashskyaiCliToolAdapter(),
    this.configProfile = const FlashskyaiConfigProfileCapability(),
    this.transcriptProbe = const FlashskyaiTranscriptProbe(),
    this.executableResolver = const FlashskyaiExecutableResolver(),
    this.installer = const UnsupportedInstallerCapability(),
    this.presence = const FlashskyaiPresence(),
    this.display = const FlashskyaiDisplay(),
    this.terminalBehavior = const FlashskyaiTerminalBehavior(),
    this.pluginManifest = const FlashskyaiPluginManifest(),
    this.providerCatalog = const FlashskyaiProviderCatalog(),
    this.providerModel = const ProviderRecordModelCapability(),
    this.headlessRun = const FlashskyaiHeadlessRunCapability(),
    this.headlessProvision = const FlashskyaiHeadlessProvisionCapability(),
    this.providerForm = const FlashskyaiProviderFormCapability(),
    this.resource = const DefaultResourceCapability(),
  });

  final LaunchArgsCapability launchArgs;
  final ConfigProfileCapability configProfile;
  final TranscriptProbeCapability transcriptProbe;
  final ExecutableResolverCapability executableResolver;
  final InstallerCapability installer;
  final PresenceCapability presence;
  final FlashskyaiDisplay display;
  final FlashskyaiTerminalBehavior terminalBehavior;
  final FlashskyaiPluginManifest pluginManifest;
  final FlashskyaiProviderCatalog providerCatalog;
  final ProviderModelCapability providerModel;
  final HeadlessRunCapability headlessRun;
  final HeadlessProvisionCapability headlessProvision;
  final ProviderFormCapability providerForm;
  final ResourceCapability resource;

  @override
  CliTool get id => CliTool.flashskyai;

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
    providerForm,
    headlessRun,
    headlessProvision,
    resource,
  ];
}
