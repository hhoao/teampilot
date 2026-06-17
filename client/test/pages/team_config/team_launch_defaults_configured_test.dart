import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/team_config/team_config_helpers.dart';

void main() {
  const codexPreset = CliPreset(
    id: 'preset-codex',
    name: 'Codex Default',
    cli: CliTool.codex,
    provider: 'openai-official',
    model: 'gpt-5.4',
    effort: '',
    createdAt: 0,
    updatedAt: 0,
  );

  test('teamLaunchDefaultsConfigured accepts mixed-team preset for non-default CLI',
      () {
    const team = TeamConfig(
      id: 'team',
      name: 'Mixed',
      teamMode: TeamMode.mixed,
      cli: CliTool.claude,
      activePresetId: 'preset-codex',
    );

    expect(
      teamLaunchDefaultsConfigured(
        team: team,
        presets: const [codexPreset],
        catalogCli: CliTool.claude,
      ),
      isTrue,
    );
  });

  test('teamLaunchDefaultsConfigured still requires preset to exist', () {
    const team = TeamConfig(
      id: 'team',
      name: 'Mixed',
      teamMode: TeamMode.mixed,
      cli: CliTool.claude,
      activePresetId: 'missing',
    );

    expect(
      teamLaunchDefaultsConfigured(
        team: team,
        presets: const [codexPreset],
        catalogCli: CliTool.claude,
      ),
      isFalse,
    );
  });
}
