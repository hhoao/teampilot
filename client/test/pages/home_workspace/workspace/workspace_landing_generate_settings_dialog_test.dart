import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/pages/home_workspace/workspace/workspace_landing_generate_settings_dialog.dart';
import 'package:teampilot/widgets/compose/compose_model_preset_chip.dart';

void main() {
  const codexGenerator = SimpleLaunchFourTuple(
    cli: CliTool.codex,
    providerId: 'openai',
    modelId: 'gpt-5',
    effort: 'high',
  );
  const flashskyGenerator = SimpleLaunchFourTuple(
    cli: CliTool.flashskyai,
    providerId: 'anthropic',
    modelId: 'claude-sonnet',
    effort: '',
  );

  test('native mode clears a generator from another cli', () {
    final constrained = constrainGenerateSettingsGenerator(
      generator: codexGenerator,
      teamMode: TeamMode.native,
      nativeCli: CliTool.claude,
    );

    expect(constrained, isNull);
  });

  test('native mode keeps a generator from nativeCli', () {
    final constrained = constrainGenerateSettingsGenerator(
      generator: flashskyGenerator,
      teamMode: TeamMode.native,
      nativeCli: CliTool.flashskyai,
    );

    expect(constrained, same(flashskyGenerator));
  });

  test('mixed mode keeps a generator from any cli', () {
    final constrained = constrainGenerateSettingsGenerator(
      generator: codexGenerator,
      teamMode: TeamMode.mixed,
      nativeCli: CliTool.claude,
    );

    expect(constrained, same(codexGenerator));
  });
}
