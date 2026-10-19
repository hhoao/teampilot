import '../../models/team_config.dart';
import '../../utils/logging/logger.dart';
import 'acp_adapter_locator.dart';
import 'registry/capabilities/acp_settings_capability.dart';
import 'registry/cli_tool_registry.dart';
import 'remote_cli_locator.dart';

class AcpAdapterDiscovery {
  AcpAdapterDiscovery({required CliToolRegistry registry}) : _registry = registry;

  final CliToolRegistry _registry;

  Future<Map<CliTool, String>> locateLocal({
    Map<String, String>? environment,
    bool Function(String path)? fileExists,
    bool? isWindows,
  }) async {
    final located = <CliTool, String>{};
    for (final def in _registry.launchable) {
      final settings = _registry.capability<AcpSettingsCapability>(def.id);
      if (settings == null ||
          !settings.usesSeparateAdapter ||
          settings.adapterExecutableName == null ||
          settings.adapterExecutableName!.isEmpty) {
        continue;
      }
      final path = locateAcpAdapter(
        name: settings.adapterExecutableName!,
        environment: environment,
        fileExists: fileExists,
        isWindows: isWindows,
      );
      if (path.contains('/') || path.contains(r'\')) {
        located[def.id] = path;
      }
    }
    return located;
  }

  /// Locates separate ACP adapters (Claude / Codex) on a remote host over
  /// [run]. Entries are omitted when the probe cannot resolve an absolute path.
  Future<Map<CliTool, String>> locateRemote({
    required SshCommandRunner run,
  }) async {
    final located = <CliTool, String>{};
    for (final def in _registry.launchable) {
      final settings = _registry.capability<AcpSettingsCapability>(def.id);
      final name = settings?.adapterExecutableName?.trim() ?? '';
      if (settings == null || !settings.usesSeparateAdapter || name.isEmpty) {
        continue;
      }
      try {
        final path =
            (await DefaultRemoteCliLocator(name).locate(run))?.trim() ?? '';
        if (path.isNotEmpty) located[def.id] = path;
      } on Object catch (error, stackTrace) {
        appLogger.w(
          '[acp-adapter] remote locate failed cli=${def.id.value} name=$name',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return located;
  }
}
