import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/plugin.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/capabilities/plugin_provisioner_capability.dart';
import 'package:teampilot/services/plugin/plugin_cli_support.dart';

void main() {
  const hooksOnly = PluginCapabilities(
    hooks: [PluginHook(event: 'Stop', matcher: '.*')],
  );

  const skillsAndCommands = PluginCapabilities(
    skills: [PluginSkillRef(name: 's1')],
    commands: [PluginCommand(name: 'cmd')],
  );

  test('hooks-only plugin is not applicable on opencode', () {
    final status = analyzePluginCliSupport(
      capabilities: hooksOnly,
      tool: CliTool.opencode,
    );
    expect(status.level, PluginCliSupportLevel.notApplicable);
    expect(status.dropped, {PluginComponentKind.hooks});
  });

  test('hooks-only plugin is fully supported on claude', () {
    final status = analyzePluginCliSupport(
      capabilities: hooksOnly,
      tool: CliTool.claude,
    );
    expect(status.level, PluginCliSupportLevel.fullySupported);
    expect(status.dropped, isEmpty);
  });

  test('skills+commands partially supported on codex drops commands', () {
    final status = analyzePluginCliSupport(
      capabilities: skillsAndCommands,
      tool: CliTool.codex,
    );
    expect(status.level, PluginCliSupportLevel.partiallySupported);
    expect(status.dropped, {PluginComponentKind.commands});
  });

  test('empty capabilities yields not applicable', () {
    final status = analyzePluginCliSupport(
      capabilities: const PluginCapabilities(),
      tool: CliTool.claude,
    );
    expect(status.level, PluginCliSupportLevel.notApplicable);
  });
}
