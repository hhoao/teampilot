import '../../../models/team_config.dart';
import 'built_in_cli_tools.dart';
import 'capabilities/member_agent_preset_capability.dart';
import 'capabilities/native_team_capability.dart';
import 'cli_bootstrap.dart';
import 'cli_capability.dart';
import 'cli_tool_definition.dart';

class CliToolRegistry {
  CliToolRegistry._();

  static CliToolRegistry? _builtIn;
  CliBootstrap _bootstrap = const CliBootstrap();

  /// Single built-in registry for all default (non-injected) call sites.
  factory CliToolRegistry.builtIn() {
    return _builtIn ??= () {
      final registry = CliToolRegistry._();
      registerBuiltInCliTools(registry);
      return registry;
    }();
  }

  /// Injects runtime services (model catalogs, …) after storage bootstrap.
  void configure(CliBootstrap bootstrap) {
    _bootstrap = bootstrap;
    registerBuiltInCliTools(this, bootstrap: _bootstrap);
  }

  CliBootstrap get bootstrap => _bootstrap;

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

  /// CLIs that may back [TeamMode.native] (first-party multi-agent teams).
  Iterable<CliToolDefinition> get nativeTeamLaunchable => launchable.where(
    (d) => capability<NativeTeamCapability>(d.id) != null,
  );

  bool supportsNativeTeam(CliTool id) =>
      capability<NativeTeamCapability>(id) != null;

  MemberAgentPresetStyle? memberAgentPresetStyle(CliTool id) =>
      capability<MemberAgentPresetCapability>(id)?.style;

  bool supportsMemberAgentPreset(CliTool id) =>
      memberAgentPresetStyle(id) != null;

  Iterable<CliToolDefinition> get all => _definitions.values;

  Iterable<CliToolDefinition> withCapability<T extends CliCapability>() =>
      _definitions.values.where(
        (d) => d.capabilities.any((c) => c is T),
      );
}
