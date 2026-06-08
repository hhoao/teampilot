import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ai_feature_setting.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/ai/team_config_draft.dart';
import 'package:teampilot/services/ai/team_config_generator.dart';

const _setting = AiFeatureSetting(
  cli: CliTool.claude,
  providerId: 'p',
  model: 'm',
);

const _allowed = TeamDraftAllowedOptions(
  models: ['sonnet'],
  efforts: ['high'],
  skillIds: [],
  defaultModel: 'sonnet',
);

void main() {
  test('returns a parsed draft on first success', () async {
    final gen = TeamConfigGenerator(
      runHeadless: ({required setting, required prompt, required expectJson}) async =>
          '{"members":[{"name":"Dev","role":"dev","model":"sonnet"}]}',
    );

    final draft = await gen.generate(
      setting: _setting,
      description: 'team',
      allowed: _allowed,
      granularity: TeamGenGranularity.rosterOnly,
      joinedAt: 1,
    );

    expect(draft.members.single.name, 'Dev');
  });

  test('retries once on bad JSON then succeeds', () async {
    var calls = 0;
    final gen = TeamConfigGenerator(
      runHeadless: ({required setting, required prompt, required expectJson}) async {
        calls++;
        return calls == 1
            ? 'garbage'
            : '{"members":[{"name":"Dev","role":"dev","model":"sonnet"}]}';
      },
    );

    final draft = await gen.generate(
      setting: _setting,
      description: 'team',
      allowed: _allowed,
      granularity: TeamGenGranularity.rosterOnly,
      joinedAt: 1,
    );

    expect(calls, 2);
    expect(draft.members, hasLength(1));
  });

  test('throws after two bad JSON attempts', () async {
    final gen = TeamConfigGenerator(
      runHeadless: ({required setting, required prompt, required expectJson}) async =>
          'still garbage',
    );

    expect(
      () => gen.generate(
        setting: _setting,
        description: 'team',
        allowed: _allowed,
        granularity: TeamGenGranularity.rosterOnly,
        joinedAt: 1,
      ),
      throwsA(isA<TeamDraftFormatException>()),
    );
  });
}
