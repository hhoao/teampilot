import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_executable_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_transport_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/headless_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/plugin_capability.dart';
import 'package:teampilot/services/cli/registry/capabilities/provider_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('grok registers every required capability', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    final def = registry.tryGet(CliTool.grok);
    expect(def, isNotNull);
    expect(def!.isLaunchSupported, isTrue);

    final exe = registry.capability<CliExecutableCapability>(CliTool.grok)!;
    expect(exe.defaultExecutableName, 'grok');
    expect(exe.supportsInstaller, isTrue);

    final acp = registry.capability<AcpCapability>(CliTool.grok)!;
    expect(acp.launchArgCandidates('/usr/bin/grok'), [
      ['/usr/bin/grok', 'agent', 'stdio'],
    ]);
    expect(
      acp.buildEnvironment(
        sessionToolDir: '/runtime/grok',
        workingDirectory: '/work',
      ),
      {'GROK_HOME': '/runtime/grok', 'GROK_DISABLE_AUTOUPDATER': '1'},
    );

    expect(
      registry.capability<CliTransportCapability>(CliTool.grok)!.supported,
      {CliTransport.acp},
    );
    expect(registry.launchesAcpOnly(CliTool.grok), isTrue);
    expect(registry.supportsNativeTeam(CliTool.grok), isFalse);
    expect(registry.supportsMemberAgentPreset(CliTool.grok), isFalse);
    expect(
      registry.capability<AcpNoPtyFallbackCapability>(CliTool.grok),
      isNotNull,
    );
    expect(registry.capability<AcpUsageLogCapability>(CliTool.grok), isNotNull);
    expect(registry.capability<HeadlessCapability>(CliTool.grok), isNotNull);
  });

  test('grok provider presets expose the official xAI row', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    final provider =
        registry.capability<ProviderCapability>(CliTool.grok)!
            as CatalogModelCapability;
    expect(provider.defaultOfficialProviderId, 'xai');
    final preset = provider.presets.single;
    expect(preset.id, 'xai');
    expect(preset.template.isOfficial, isTrue);
    expect(preset.template.defaultModel, 'grok-4.7');
    expect(provider.defaultApiKeyField(), 'api_key');
  });

  test('grok plugin supports the expected components', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);
    final plugin = registry.capability<PluginCapability>(CliTool.grok)!;
    expect(plugin.runtimeOwnership, PluginRuntimeOwnership.teamPilot);
    expect(plugin.memberPluginsSubpath, ['plugins']);
    expect(plugin.supported, {
      PluginComponentKind.skills,
      PluginComponentKind.agents,
      PluginComponentKind.commands,
      PluginComponentKind.hooks,
      PluginComponentKind.mcp,
    });
  });
}
