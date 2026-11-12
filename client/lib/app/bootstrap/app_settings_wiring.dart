import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../cubits/ai_feature_settings_cubit.dart';
import '../../cubits/discovery_settings_cubit.dart';
import '../../cubits/session_preferences_cubit.dart';
import '../../repositories/app_settings_repository.dart';
import '../../repositories/session_preferences_repository.dart';
import '../../services/acp/acp_frame_logger.dart';
import '../../services/cli/acp_adapter_discovery.dart';
import '../../services/cli/cli_executable_discovery.dart';
import '../../services/cli/cli_local_discovery_bootstrap.dart';
import '../../services/cli/cli_version_probe.dart';
import '../../services/cli/registry/cli_tool_registry.dart';
import '../../services/cli/toolchain_executable_discovery.dart';
import '../../services/storage/app_paths.dart';
import '../../utils/logging/logger.dart';

/// The settings side of the boot sequence: the persisted-settings repository,
/// the AI/discovery/session-preference cubits built on it, the CLI registry and
/// executable discovery, and the resolved on-disk workspace directory.
typedef AppSettingsWiring = ({
  SharedPrefsAppSettingsRepository appSettings,
  AiFeatureSettingsCubit aiFeatureSettingsCubit,
  DiscoverySettingsCubit discoverySettingsCubit,
  SessionPreferencesCubit sessionPreferencesCubit,
  String defaultWorkspaceDirectory,
  CliExecutableDiscovery cliExecutableDiscovery,
  CliToolRegistry cliToolRegistry,
});

/// Builds the app-settings cubits and resolves the workspace directory.
///
/// [boot] is the shell's phase logger; each call stays at the point it used to
/// log inline, so background CLI discovery and preference loading report the
/// same phases in the same order.
Future<AppSettingsWiring> wireAppSettings({
  required SharedPreferences preferences,
  required Future<String>? defaultWorkspaceDirectoryFuture,
  required void Function(String phase) boot,
}) async {
  final documentsFuture =
      defaultWorkspaceDirectoryFuture ??
      DefaultWorkspaceDirectory.resolve(preferences: preferences);
  final cliToolRegistry = CliToolRegistry.builtIn();
  final cliExecutableDiscovery = CliExecutableDiscovery(
    registry: cliToolRegistry,
  );

  final appSettings = SharedPrefsAppSettingsRepository(preferences);
  // Apply the persisted ACP frame-log choice before any ACP session starts so
  // the log viewer toggle keeps working across restarts.
  AcpFrameLogger.mirrorEnabled = AcpFrameLogger.resolveEnabled(
    await appSettings.loadAcpFrameLogEnabled(),
  );
  final aiFeatureSettingsCubit = AiFeatureSettingsCubit(
    repository: appSettings,
  );
  final discoverySettingsCubit = DiscoverySettingsCubit(
    repository: appSettings,
  );
  final sessionPreferencesCubit = SessionPreferencesCubit(
    repository: SessionPreferencesRepository(preferences),
    cliToolRegistry: cliToolRegistry,
  );
  if (!Platform.isAndroid) {
    boot('scheduling CLI tool discovery (background)');
    unawaited(() async {
      final counts = await runLocalCliDiscovery(
        cubit: sessionPreferencesCubit,
        locateCli: () => cliExecutableDiscovery.locateLocal(),
        locateAdapters: () =>
            AcpAdapterDiscovery(registry: cliToolRegistry).locateLocal(),
        locateToolchains: () => ToolchainExecutableDiscovery().locateLocal(),
        probeInstalled: CliVersionProbe().installed,
      );
      appLogger.i(
        '[boot] CLI/toolchain discovery complete '
        '(${counts.cliCount} CLI, ${counts.adapterCount} adapter, '
        '${counts.toolchainCount} toolchain, background)',
      );
    }());
  }
  boot('loading session preferences and workspace directory');
  final parallel = await Future.wait<Object?>([
    sessionPreferencesCubit.load(),
    documentsFuture,
  ]);
  // Native cwd must be TeamPilot's own subtree, never the OS documents root —
  // otherwise terminals/agents spill files directly into the user's Documents.
  final defaultWorkspaceDirectory =
      DefaultWorkspaceDirectory.teamPilotDirFromDocuments(
        parallel[1]! as String,
      );
  await Directory(defaultWorkspaceDirectory).create(recursive: true);
  boot('session preferences and workspace directory ready');

  return (
    appSettings: appSettings,
    aiFeatureSettingsCubit: aiFeatureSettingsCubit,
    discoverySettingsCubit: discoverySettingsCubit,
    sessionPreferencesCubit: sessionPreferencesCubit,
    defaultWorkspaceDirectory: defaultWorkspaceDirectory,
    cliExecutableDiscovery: cliExecutableDiscovery,
    cliToolRegistry: cliToolRegistry,
  );
}
