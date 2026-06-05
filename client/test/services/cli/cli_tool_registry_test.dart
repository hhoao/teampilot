import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/config_profile_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/installer_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/launch_args_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_catalog_capability.dart';
import 'package:teampilot/services/cli/registry/installer/claude_installer_capability.dart';
import 'package:teampilot/services/cli/registry/installer/codex_installer_capability.dart';
import 'package:teampilot/services/cli/registry/installer/opencode_installer_capability.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

class _EchoCapability implements CliCapability {
  const _EchoCapability(this.value);
  final String value;
}

class _FakeTool implements CliToolDefinition {
  const _FakeTool(this.id, this.isLaunchSupported, this.capabilities);
  @override
  final CliTool id;
  @override
  final bool isLaunchSupported;
  @override
  final Iterable<CliCapability> capabilities;
}

void main() {
  test('capability returns registered implementation', () {
    final registry = CliToolRegistry();
    registry.register(
      const _FakeTool(CliTool.flashskyai, true, [_EchoCapability('ok')]),
    );
    expect(
      registry.capability<_EchoCapability>(CliTool.flashskyai)?.value,
      'ok',
    );
    expect(registry.capability<_EchoCapability>(CliTool.claude), isNull);
  });

  test('launchable filters isLaunchSupported', () {
    final registry = CliToolRegistry();
    registry.register(const _FakeTool(CliTool.claude, true, []));
    registry.register(const _FakeTool(CliTool.codex, false, []));
    expect(registry.launchable.map((d) => d.id), [CliTool.claude]);
  });

  test('built-in registry covers every CliTool value', () {
    final registry = CliToolRegistry.builtIn();
    expect(registry.all.length, CliTool.values.length);
    for (final cli in CliTool.values) {
      expect(registry.tryGet(cli), isNotNull, reason: cli.value);
    }
  });

  test('built-in launchable tools have LaunchArgsCapability', () {
    final registry = CliToolRegistry.builtIn();
    for (final def in registry.launchable) {
      expect(registry.capability<LaunchArgsCapability>(def.id), isNotNull);
    }
  });

  test('claude built-in has InstallerCapability with install support', () {
    final registry = CliToolRegistry.builtIn();
    final installer = registry.capability<InstallerCapability>(CliTool.claude);
    expect(installer, isA<ClaudeInstallerCapability>());
    expect(installer!.supportsInstaller, isTrue);
  });

  test('codex built-in has npm InstallerCapability with install support', () {
    final registry = CliToolRegistry.builtIn();
    final installer = registry.capability<InstallerCapability>(CliTool.codex);
    expect(installer, isA<CodexInstallerCapability>());
    expect(installer!.supportsInstaller, isTrue);
  });

  test('opencode built-in has npm InstallerCapability with install support', () {
    final registry = CliToolRegistry.builtIn();
    final installer = registry.capability<InstallerCapability>(
      CliTool.opencode,
    );
    expect(installer, isA<OpencodeInstallerCapability>());
    expect(installer!.supportsInstaller, isTrue);
  });

  test('built-in launchable tools have ConfigProfileCapability', () {
    final registry = CliToolRegistry.builtIn();
    for (final def in registry.launchable) {
      expect(registry.capability<ConfigProfileCapability>(def.id), isNotNull);
    }
  });

  test('opencode has no ProviderCatalogCapability', () {
    final registry = CliToolRegistry.builtIn();
    expect(
      registry.capability<ProviderCatalogCapability>(CliTool.opencode),
      isNull,
    );
  });
}
