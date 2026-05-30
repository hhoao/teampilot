import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/app_provider_config.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/config_profile_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/launch_args_capability.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_id.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

class _EchoCapability implements CliCapability {
  const _EchoCapability(this.value);
  final String value;
}

class _FakeTool implements CliToolDefinition {
  _FakeTool(this.id, this.isLaunchSupported, this.capabilities);
  @override
  final CliToolId id;
  @override
  final bool isLaunchSupported;
  @override
  final Iterable<CliCapability> capabilities;
  @override
  AppProviderCli? get providerCatalogCli => null;
}

void main() {
  test('capability returns registered implementation', () {
    final registry = CliToolRegistry();
    registry.register(
      _FakeTool('flashskyai', true, [const _EchoCapability('ok')]),
    );
    expect(
      registry.capability<_EchoCapability>('flashskyai')?.value,
      'ok',
    );
    expect(registry.capability<_EchoCapability>('missing'), isNull);
  });

  test('launchable filters isLaunchSupported', () {
    final registry = CliToolRegistry();
    registry.register(_FakeTool('a', true, const []));
    registry.register(_FakeTool('b', false, const []));
    expect(registry.launchable.map((d) => d.id), ['a']);
  });

  test('built-in launchable tools have LaunchArgsCapability', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    for (final def in registry.launchable) {
      expect(registry.capability<LaunchArgsCapability>(def.id), isNotNull);
    }
  });

  test('built-in launchable tools have ConfigProfileCapability', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    for (final def in registry.launchable) {
      expect(registry.capability<ConfigProfileCapability>(def.id), isNotNull);
    }
  });
}
