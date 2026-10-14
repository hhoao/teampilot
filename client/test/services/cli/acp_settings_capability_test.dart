import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/claude/capabilities/acp_adapter_installer.dart';
import 'package:teampilot/services/cli/codex/capabilities/acp_adapter_installer.dart';
import 'package:teampilot/services/cli/registry/capabilities/acp_settings_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  final registry = CliToolRegistry.builtIn();

  test('Claude and Codex declare a separate ACP adapter', () {
    final claude = registry.capability<AcpSettingsCapability>(CliTool.claude)!;
    expect(claude.usesSeparateAdapter, isTrue);
    expect(claude.adapterExecutableName, 'claude-agent-acp');
    expect(claude.adapterInstaller, isA<ClaudeAcpAdapterInstaller>());
    expect(claude.showsPersonalAcpSwitch, isTrue);

    final codex = registry.capability<AcpSettingsCapability>(CliTool.codex)!;
    expect(codex.usesSeparateAdapter, isTrue);
    expect(codex.adapterExecutableName, 'codex-acp');
    expect(codex.adapterInstaller, isA<CodexAcpAdapterInstaller>());
  });

  test('Cursor and OpenCode reuse the CLI binary and show the switch', () {
    for (final cli in [CliTool.cursor, CliTool.opencode]) {
      final settings = registry.capability<AcpSettingsCapability>(cli)!;
      expect(settings.usesSeparateAdapter, isFalse);
      expect(settings.adapterExecutableName, isNull);
      expect(settings.adapterInstaller, isNull);
      expect(settings.showsPersonalAcpSwitch, isTrue);
    }
  });

  test('Gemini has ACP but no personal-ACP settings capability', () {
    expect(
      registry.capability<AcpSettingsCapability>(CliTool.gemini),
      isNull,
    );
  });
}
