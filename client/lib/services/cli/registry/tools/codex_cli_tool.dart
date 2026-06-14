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
import '../../../provider/codex/codex_provider_credential_capability.dart';
import '../capabilities/cli_effort_capability.dart';
import '../capabilities/headless_run_capability.dart';
import '../capabilities/provider_credential_capability.dart';
import '../capabilities/provider_model_capability.dart';
import '../capabilities/transcript_probe_capability.dart';
import '../capabilities/headless_provision_capability.dart';
import '../config_profile/codex_config_profile_capability.dart';
import '../headless/codex_headless_run_capability.dart';
import '../headless/codex_headless_provision_capability.dart';
import '../installer/codex_installer_capability.dart';
import '../../../provider/codex/codex_effort_capability.dart';
import '../../../provider/codex/codex_provider_form_capability.dart';
import '../capabilities/member_config_inspection_capability.dart';
import '../capabilities/provider_form_capability.dart';

final class CodexCliTool implements CliToolDefinition {
  CodexCliTool({
    this.launchArgs = const CodexCliToolAdapter(),
    this.configProfile = const CodexConfigProfileCapability(),
    this.transcriptProbe = const CodexTranscriptProbe(),
    this.executableResolver = const CodexExecutableResolver(),
    this.installer = const CodexInstallerCapability(),
    this.presence = const CodexPresence(),
    this.display = const CodexDisplay(),
    this.terminalBehavior = const CodexTerminalBehavior(),
    this.memberConfigInspection = const DefaultMemberConfigInspection(),
    this.pluginManifest = const CodexPluginManifest(),
    this.providerCatalog = const CodexProviderCatalog(),
    this.providerModel = const ProviderRecordModelCapability(),
    this.effort = const CodexEffortCapability(),
    this.headlessRun = const CodexHeadlessRunCapability(),
    this.headlessProvision = const CodexHeadlessProvisionCapability(),
    this.providerForm = const CodexProviderFormCapability(),
    ProviderCredentialCapability? providerCredential,
  }) : providerCredential =
           providerCredential ?? CodexProviderCredentialCapability();

  final ProviderCredentialCapability providerCredential;
  final ProviderFormCapability providerForm;

  final LaunchArgsCapability launchArgs;
  final ConfigProfileCapability configProfile;
  final TranscriptProbeCapability transcriptProbe;
  final ExecutableResolverCapability executableResolver;
  final InstallerCapability installer;
  final PresenceCapability presence;
  final CodexDisplay display;
  final CodexTerminalBehavior terminalBehavior;
  final MemberConfigInspectionCapability memberConfigInspection;
  final CodexPluginManifest pluginManifest;
  final CodexProviderCatalog providerCatalog;
  final ProviderModelCapability providerModel;
  final CliEffortCapability effort;
  final HeadlessRunCapability headlessRun;
  final HeadlessProvisionCapability headlessProvision;

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
    memberConfigInspection,
    pluginManifest,
    providerCatalog,
    providerModel,
    providerCredential,
    providerForm,
    effort,
    headlessRun,
    headlessProvision,
  ];
}
