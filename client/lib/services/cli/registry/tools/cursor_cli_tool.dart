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
import '../capabilities/unsupported_installer_capability.dart';
import '../config_profile/cursor_config_profile_capability.dart';

/// Cursor CLI (`cursor-agent`). Launchable as a standalone embedded terminal
/// (Phase 1). Mixed-mode team-bus participation is pending Phase 2.
final class CursorCliTool implements CliToolDefinition {
  const CursorCliTool({
    this.launchArgs = const CursorCliToolAdapter(),
    this.configProfile = const CursorConfigProfileCapability(),
    this.transcriptProbe = const CursorTranscriptProbe(),
    this.executableResolver = const CursorExecutableResolver(),
    this.installer = const UnsupportedInstallerCapability(),
    this.presence = const CursorPresence(),
    this.display = const CursorDisplay(),
    this.terminalBehavior = const CursorTerminalBehavior(),
    this.pluginManifest = const CursorPluginManifest(),
  });

  final LaunchArgsCapability launchArgs;
  final ConfigProfileCapability configProfile;
  final TranscriptProbeCapability transcriptProbe;
  final ExecutableResolverCapability executableResolver;
  final InstallerCapability installer;
  final PresenceCapability presence;
  final CursorDisplay display;
  final CursorTerminalBehavior terminalBehavior;
  final CursorPluginManifest pluginManifest;

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
  ];
}
