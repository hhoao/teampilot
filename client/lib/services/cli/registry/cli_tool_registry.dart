import '../../../models/team_config.dart';
import 'built_in_cli_tools.dart';
import 'cli_capability.dart';
import 'cli_tool_definition.dart';

class CliToolRegistry {
  CliToolRegistry._();

  static CliToolRegistry? _builtIn;

  /// Single built-in registry for all default (non-injected) call sites.
  factory CliToolRegistry.builtIn() {
    return _builtIn ??= () {
      final registry = CliToolRegistry._();
      registerBuiltInCliTools(registry);
      return registry;
    }();
  }

  factory CliToolRegistry() => CliToolRegistry._();

  final _definitions = <CliTool, CliToolDefinition>{};

  void register(CliToolDefinition definition) {
    _definitions[definition.id] = definition;
  }

  CliToolDefinition? tryGet(CliTool id) => _definitions[id];

  T? capability<T extends CliCapability>(CliTool id) {
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

  Iterable<CliToolDefinition> withCapability<T extends CliCapability>() =>
      _definitions.values.where(
        (d) => d.capabilities.any((c) => c is T),
      );
}
