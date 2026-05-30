import 'cli_capability.dart';
import 'cli_tool_definition.dart';
import 'cli_tool_id.dart';

class CliToolRegistry {
  final _definitions = <CliToolId, CliToolDefinition>{};

  void register(CliToolDefinition definition) {
    _definitions[definition.id] = definition;
  }

  CliToolDefinition? tryGet(CliToolId id) => _definitions[id];

  T? capability<T extends CliCapability>(CliToolId id) {
    final def = _definitions[id];
    if (def == null) return null;
    for (final cap in def.capabilities) {
      if (cap is T) return cap;
    }
    return null;
  }

  Iterable<CliToolDefinition> get launchable =>
      _definitions.values.where((d) => d.isLaunchSupported);

  Iterable<CliToolDefinition> get all => _definitions.values;
}
