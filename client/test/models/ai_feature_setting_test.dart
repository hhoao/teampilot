import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ai_feature_setting.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  test('AiFeatureId.tryParse maps keys and rejects junk', () {
    expect(AiFeatureId.tryParse('commitMessage'), AiFeatureId.commitMessage);
    expect(AiFeatureId.tryParse('teamGenerate'), AiFeatureId.teamGenerate);
    expect(AiFeatureId.tryParse('nope'), isNull);
  });

  test('round-trips through json', () {
    const setting = AiFeatureSetting(
      cli: CliTool.claude,
      providerId: 'claude-official',
      model: 'sonnet',
      effort: 'high',
    );
    final restored = AiFeatureSetting.fromJson(setting.toJson());
    expect(restored.cli, CliTool.claude);
    expect(restored.providerId, 'claude-official');
    expect(restored.model, 'sonnet');
    expect(restored.effort, 'high');
  });

  test('fromJson tolerates missing fields', () {
    final s = AiFeatureSetting.fromJson(const {});
    expect(s.cli, CliTool.claude);
    expect(s.providerId, '');
    expect(s.model, '');
    expect(s.effort, '');
  });

  test('copyWith overrides selected fields', () {
    const s = AiFeatureSetting(cli: CliTool.claude, providerId: 'p', model: 'm');
    final s2 = s.copyWith(model: 'opus', effort: 'low');
    expect(s2.model, 'opus');
    expect(s2.effort, 'low');
    expect(s2.providerId, 'p');
  });
}
