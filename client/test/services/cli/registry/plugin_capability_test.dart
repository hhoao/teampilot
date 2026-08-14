import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/plugin_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/plugin_manifest_paths.dart';
import 'package:teampilot/services/cli/registry/capabilities/skill_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  // CliToolRegistry.builtIn() exists and calls registerBuiltInCliTools internally.
  CliToolRegistry buildRegistry() => CliToolRegistry.builtIn();

  test('every launchable CLI exposes a PluginCapability', () {
    final registry = buildRegistry();
    for (final cli in CliTool.values) {
      final cap = registry.capability<PluginCapability>(cli);
      expect(cap, isNotNull, reason: '$cli must expose PluginCapability');
    }
  });

  test('manifest paths follow each CLI plugin format', () {
    final registry = buildRegistry();
    PluginManifestPaths? paths(CliTool cli) =>
        registry.capability<PluginCapability>(cli)!.manifestPaths;
    expect(paths(CliTool.claude)?.manifestDirName, '.claude-plugin');
    expect(paths(CliTool.flashskyai)?.manifestDirName, '.flashskyai-plugin');
    expect(paths(CliTool.codex)?.manifestDirName, '.codex-plugin');
    expect(paths(CliTool.cursor)?.manifestDirName, '.cursor-plugin');
    expect(paths(CliTool.opencode), isNull);
  });

  test('member plugins subpath: cursor nests under plugins/local', () {
    final registry = buildRegistry();
    for (final cli in [
      CliTool.claude,
      CliTool.flashskyai,
      CliTool.codex,
      CliTool.opencode,
    ]) {
      expect(
        registry
            .capability<PluginCapability>(cli)!
            .memberPluginsSubpath,
        ['plugins'],
        reason: '$cli',
      );
    }
    expect(
      registry.capability<PluginCapability>(CliTool.cursor)!.memberPluginsSubpath,
      ['plugins', 'local'],
    );
  });

  test('every launchable CLI links plugins as directories', () {
    final registry = buildRegistry();
    for (final cli in CliTool.values) {
      final cap = registry.capability<PluginCapability>(cli)!;
      expect(
        cap.pluginsRepresentation,
        ResourceRepresentation.linkedDirectory,
        reason: '$cli',
      );
      expect(
        cap.pluginsSubdir,
        cli == CliTool.cursor ? 'plugins/local' : 'plugins',
        reason: '$cli',
      );
    }
  });

  test('only claude, flashskyai, and cursor consume marketplaces', () {
    final registry = buildRegistry();
    for (final cli in [CliTool.claude, CliTool.flashskyai, CliTool.cursor]) {
      expect(
        registry.capability<PluginCapability>(cli)!.consumesMarketplaces,
        isTrue,
        reason: '$cli',
      );
    }
    for (final cli in [CliTool.codex, CliTool.opencode]) {
      expect(
        registry.capability<PluginCapability>(cli)!.consumesMarketplaces,
        isFalse,
        reason: '$cli',
      );
    }
  });

  test('only opencode seeds shared plugin deps before reconcile', () {
    final registry = buildRegistry();
    for (final cli in CliTool.values) {
      final expectsSeed = cli == CliTool.opencode;
      expect(
        registry
            .capability<PluginCapability>(cli)!
            .needsSharedPluginDepsBeforeReconcile,
        expectsSeed,
        reason: '$cli',
      );
    }
  });

  test('pluginCapabilityForTool resolves the same instance as the registry', () {
    final registry = buildRegistry();
    for (final cli in CliTool.values) {
      expect(
        pluginCapabilityForTool(cli, registry: registry),
        same(registry.capability<PluginCapability>(cli)),
        reason: '$cli',
      );
    }
  });
}
