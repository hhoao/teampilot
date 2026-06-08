import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/ai/team_config_draft.dart';
import 'package:teampilot/services/ai/team_config_prompt.dart';

void main() {
  const native = TeamDraftAllowedOptions(
    clis: [
      CliModelOptions(
        cli: CliTool.claude,
        models: ['sonnet', 'opus'],
        efforts: ['low', 'high'],
        defaultModel: 'sonnet',
      ),
    ],
    skillIds: ['code-review'],
  );

  const mixed = TeamDraftAllowedOptions(
    clis: [
      CliModelOptions(
        cli: CliTool.claude,
        models: ['sonnet'],
        efforts: ['high'],
        defaultModel: 'sonnet',
      ),
      CliModelOptions(
        cli: CliTool.codex,
        models: ['gpt-x'],
        efforts: ['medium'],
        defaultModel: 'gpt-x',
      ),
    ],
    skillIds: ['code-review'],
  );

  test('native prompt: rubric, schema fields, single cli, no cli field', () {
    final p = buildTeamConfigPrompt(
      mode: TeamMode.native,
      description: 'Flutter frontend team',
      allowed: native,
    );
    expect(p, contains('Flutter frontend team'));
    expect(p, contains('NATIVE team'));
    expect(p, contains('"responsibilities"'));
    expect(p, contains('"workingMethod"'));
    expect(p, contains('"description"'));
    expect(p, contains('Do NOT'));
    expect(p, contains('exactly one member named "team-lead"'));
    expect(p, contains('sonnet'));
    expect(p, contains('code-review'));
    expect(p.contains('"cli"'), isFalse);
  });

  test('mixed prompt: bus context, per-cli model lists, cli field', () {
    final p = buildTeamConfigPrompt(
      mode: TeamMode.mixed,
      description: 'cross-cli team',
      allowed: mixed,
    );
    expect(p, contains('MIXED team'));
    expect(p, contains('teammate bus'));
    expect(p, contains('"cli"'));
    expect(p, contains('claude'));
    expect(p, contains('codex'));
    expect(p, contains('gpt-x'));
  });

  test('language lock is present in both modes', () {
    final n = buildTeamConfigPrompt(
      mode: TeamMode.native,
      description: 'x',
      allowed: native,
    );
    final m = buildTeamConfigPrompt(
      mode: TeamMode.mixed,
      description: 'x',
      allowed: mixed,
    );
    expect(n, contains('SAME language as the Description'));
    expect(m, contains('SAME language as the Description'));
  });
}
