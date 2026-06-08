import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/ai/team_config_prompt.dart';

void main() {
  test('native prompt: rubric + schema, no cli/model/effort/skillIds fields', () {
    final p = buildTeamConfigPrompt(
      mode: TeamMode.native,
      description: 'Flutter frontend team',
    );
    expect(p, contains('Flutter frontend team'));
    expect(p, contains('NATIVE team'));
    expect(p, contains('"responsibilities"'));
    expect(p, contains('"workingMethod"'));
    expect(p, contains('"description"'));
    expect(p, contains('Do NOT'));
    expect(p, contains('exactly one member named "team-lead"'));
    // none of these fields are generated
    expect(p.contains('"cli"'), isFalse);
    expect(p.contains('"model"'), isFalse);
    expect(p.contains('"effort"'), isFalse);
    expect(p.contains('"skillIds"'), isFalse);
  });

  test('mixed prompt: bus context, no cli/model/effort fields', () {
    final p = buildTeamConfigPrompt(
      mode: TeamMode.mixed,
      description: 'cross-cli team',
    );
    expect(p, contains('MIXED team'));
    expect(p, contains('teammate bus'));
    expect(p.contains('"cli"'), isFalse);
    expect(p.contains('"model"'), isFalse);
    expect(p.contains('"effort"'), isFalse);
  });

  test('rubric cites open-source playbooks; language lock in both modes', () {
    final n = buildTeamConfigPrompt(mode: TeamMode.native, description: 'x');
    final m = buildTeamConfigPrompt(mode: TeamMode.mixed, description: 'x');
    expect(n, contains('superpowers'));
    expect(m, contains('oh-my-openagent'));
    expect(n, contains('SAME language as the Description'));
    expect(m, contains('SAME language as the Description'));
  });
}
