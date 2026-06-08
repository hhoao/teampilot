import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/ai_feature_setting.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/ai/team_config_draft.dart';
import 'package:teampilot/services/ai/team_config_generator.dart';
import 'package:teampilot/utils/team_member_naming.dart';

const _setting = AiFeatureSetting(
  cli: CliTool.claude,
  providerId: 'p',
  model: 'm',
);

void main() {
  test('returns a parsed draft on first success', () async {
    String? seenPrompt;
    final gen = TeamConfigGenerator(
      runHeadless: ({required setting, required prompt, required expectJson}) async {
        seenPrompt = prompt;
        return '{"members":[{"name":"team-lead"},'
            '{"name":"Dev","role":"dev"}]}';
      },
    );

    final draft = await gen.generate(
      setting: _setting,
      description: 'team',
      mode: TeamMode.native,
      joinedAt: 1,
    );

    expect(seenPrompt, contains('NATIVE team'));
    expect(draft.members.first.id, TeamMemberNaming.teamLeadName);
    expect(draft.members.map((m) => m.name), contains('Dev'));
  });

  test('mixed mode builds the mixed prompt', () async {
    String? seenPrompt;
    final gen = TeamConfigGenerator(
      runHeadless: ({required setting, required prompt, required expectJson}) async {
        seenPrompt = prompt;
        return '{"members":[{"name":"team-lead"}]}';
      },
    );
    await gen.generate(
      setting: _setting,
      description: 'team',
      mode: TeamMode.mixed,
      joinedAt: 1,
    );
    expect(seenPrompt, contains('MIXED team'));
  });

  test('retries once on bad JSON then succeeds', () async {
    var calls = 0;
    final gen = TeamConfigGenerator(
      runHeadless: ({required setting, required prompt, required expectJson}) async {
        calls++;
        return calls == 1 ? 'garbage' : '{"members":[{"name":"team-lead"}]}';
      },
    );

    final draft = await gen.generate(
      setting: _setting,
      description: 'team',
      mode: TeamMode.native,
      joinedAt: 1,
    );

    expect(calls, 2);
    expect(draft.members, isNotEmpty);
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
        mode: TeamMode.native,
        joinedAt: 1,
      ),
      throwsA(isA<TeamDraftFormatException>()),
    );
  });
}
