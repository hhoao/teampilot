import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/models/team_generation_settings.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

void main() {
  test('native snapshot filters by native cli and ranks after filtering', () {
    const settings = TeamGenerationSettings(
      teamMode: TeamMode.native,
      nativeCli: CliTool.claude,
      modelPool: [
        GenerateModelPoolEntry(presetId: 'codex', description: '', tags: []),
        GenerateModelPoolEntry(
          presetId: 'claude-strong',
          description: 'lead',
          tags: ['strong'],
        ),
      ],
    );

    final snapshot = resolveTeamGenerationSettingsSnapshot(
      settings: settings,
      presets: [
        _preset('codex', CliTool.codex),
        _preset('claude-strong', CliTool.claude),
      ],
      registry: CliToolRegistry.builtIn(),
      capturedAt: 42,
    );

    expect(snapshot.modelPool.single.rank, 1);
    expect(snapshot.modelPool.single.preset.id, 'claude-strong');
    expect(snapshot.capturedAt, 42);
  });
}

CliPreset _preset(String id, CliTool cli) {
  return CliPreset(
    id: id,
    name: id,
    cli: cli,
    provider: '${cli.value}-provider',
    model: '$id-model',
    createdAt: 1,
    updatedAt: 1,
  );
}
