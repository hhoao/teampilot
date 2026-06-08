import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/cubits/ai_feature_settings_cubit.dart';
import 'package:teampilot/models/ai_feature_setting.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/repositories/app_settings_repository.dart';

void main() {
  test('load hydrates state from the repository', () async {
    final repo = InMemoryAppSettingsRepository();
    await repo.saveAiFeatureSetting(
      AiFeatureId.commitMessage,
      const AiFeatureSetting(cli: CliTool.claude, providerId: 'p', model: 'm'),
    );
    final cubit = AiFeatureSettingsCubit(repository: repo);

    await cubit.load();

    expect(cubit.state.settingFor(AiFeatureId.commitMessage)?.model, 'm');
  });

  test('settingFor returns null for unconfigured feature', () {
    final cubit = AiFeatureSettingsCubit(
      repository: InMemoryAppSettingsRepository(),
    );
    expect(cubit.state.settingFor(AiFeatureId.teamGenerate), isNull);
  });

  test('updateSetting persists and updates state', () async {
    final repo = InMemoryAppSettingsRepository();
    final cubit = AiFeatureSettingsCubit(repository: repo);

    await cubit.updateSetting(
      AiFeatureId.teamGenerate,
      const AiFeatureSetting(cli: CliTool.codex, providerId: 'p', model: 'm'),
    );

    expect(cubit.state.settingFor(AiFeatureId.teamGenerate)?.cli, CliTool.codex);
    expect(
      (await repo.loadAiFeatureSettings())[AiFeatureId.teamGenerate]?.cli,
      CliTool.codex,
    );
  });
}
