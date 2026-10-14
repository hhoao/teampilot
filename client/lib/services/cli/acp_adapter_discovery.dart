import '../../models/team_config.dart';
import 'acp_adapter_locator.dart';
import 'registry/capabilities/acp_settings_capability.dart';
import 'registry/cli_tool_registry.dart';

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
}
