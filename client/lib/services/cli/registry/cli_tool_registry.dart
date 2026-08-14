import '../../../models/team_config.dart';
import 'built_in_cli_tools.dart';
import 'capabilities/cli_session_capability.dart';
import 'capabilities/noop_cli_session_capability.dart';
import 'capabilities/provider_capability.dart';
import 'capabilities/team_behavior_capability.dart';
import 'cli_bootstrap.dart';
import 'cli_capability.dart';
import 'cli_tool_definition.dart';

class CliToolRegistry {
  CliToolRegistry._();

  static CliToolRegistry? _builtIn;
  CliBootstrap _bootstrap = const CliBootstrap({});

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
    (d) => capability<TeamBehaviorCapability>(d.id)?.supportsNativeTeam == true,
  );

  bool supportsNativeTeam(CliTool id) =>
      capability<TeamBehaviorCapability>(id)?.supportsNativeTeam == true;

  MemberAgentPresetStyle? memberAgentPresetStyle(CliTool id) =>
      capability<TeamBehaviorCapability>(id)?.agentPresetStyle;

  bool supportsMemberAgentPreset(CliTool id) =>
      memberAgentPresetStyle(id) != null;

  Iterable<CliToolDefinition> get all => _definitions.values;

  Iterable<CliToolDefinition> withCapability<T extends CliCapability>() =>
      _definitions.values.where((d) => d.capabilities.any((c) => c is T));

  /// Session capability for [cli], or a no-op that allows connect immediately.
  CliSessionCapability lifecycleFor(CliTool cli) =>
      capability<CliSessionCapability>(cli) ?? const NoopCliSessionCapability();

  /// Official catalog id used when a Simple launch provider is unset (see
  /// [ProviderCapability.defaultOfficialProviderId]).
  String? defaultOfficialProviderId(CliTool cli) =>
      capability<ProviderCapability>(cli)?.defaultOfficialProviderId;
}
