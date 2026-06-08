import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teampilot/models/ai_feature_setting.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saves and loads a per-feature setting', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = SharedPrefsAppSettingsRepository(prefs);

    await repo.saveAiFeatureSetting(
      AiFeatureId.commitMessage,
      const AiFeatureSetting(
        cli: CliTool.claude,
        providerId: 'claude-official',
        model: 'sonnet',
        effort: 'high',
      ),
    );

    final all = await repo.loadAiFeatureSettings();
    final s = all[AiFeatureId.commitMessage]!;
    expect(s.cli, CliTool.claude);
    expect(s.model, 'sonnet');
    expect(s.effort, 'high');
  });

  test('returns empty map when nothing stored', () async {
    final prefs = await SharedPreferences.getInstance();
    final repo = SharedPrefsAppSettingsRepository(prefs);
    expect(await repo.loadAiFeatureSettings(), isEmpty);
  });

  test('in-memory implementation round-trips', () async {
    final repo = InMemoryAppSettingsRepository();
    await repo.saveAiFeatureSetting(
      AiFeatureId.teamGenerate,
      const AiFeatureSetting(cli: CliTool.codex, providerId: 'p', model: 'm'),
    );
    final all = await repo.loadAiFeatureSettings();
    expect(all[AiFeatureId.teamGenerate]!.cli, CliTool.codex);
  });
}
