import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/cli_preset.dart';
import 'package:teampilot/models/simple_launch_identity.dart';
import 'package:teampilot/models/team_config.dart';

void main() {
  test('resolve prefers preset fields over explicit launch values', () {
    const preset = CliPreset(
      id: 'preset-1',
      name: 'Cursor Fast',
      cli: CliTool.cursor,
      provider: 'cursor-account',
      model: 'gpt-5.5',
      effort: 'high',
      createdAt: 1,
      updatedAt: 2,
    );

    final identity = SimpleLaunchIdentity.resolve(
      cli: CliTool.claude,
      preset: preset,
      provider: 'claude-official',
      model: 'claude-sonnet',
      effort: 'medium',
      expertKey: 'expert/key',
    );

    expect(identity.cli, CliTool.cursor);
    expect(identity.provider, 'cursor-account');
    expect(identity.model, 'gpt-5.5');
    expect(identity.effort, 'high');
    expect(identity.expertKey, 'expert/key');
    expect(identity.presetId, 'preset-1');
  });

  test('resolve keeps explicit preset id when supplied', () {
    const preset = CliPreset(
      id: 'stored-preset',
      name: 'Codex',
      cli: CliTool.codex,
      provider: 'openai-official',
      model: 'gpt-5.5',
      createdAt: 1,
      updatedAt: 2,
    );

    final identity = SimpleLaunchIdentity.resolve(
      preset: preset,
      presetId: 'requested-preset',
    );

    expect(identity.presetId, 'requested-preset');
  });

  test('resolve fills official provider defaults via injected resolver', () {
    String? resolveOfficial(CliTool cli) => switch (cli) {
      CliTool.claude => 'claude-official',
      CliTool.cursor => 'cursor-account',
      CliTool.codex => 'openai-official',
      CliTool.opencode => 'opencode',
      CliTool.flashskyai => null,
    };
    expect(
      SimpleLaunchIdentity.resolve(
        cli: CliTool.claude,
        officialProviderId: resolveOfficial,
      ).provider,
      'claude-official',
    );
    expect(
      SimpleLaunchIdentity.resolve(
        cli: CliTool.cursor,
        officialProviderId: resolveOfficial,
      ).provider,
      'cursor-account',
    );
    expect(
      SimpleLaunchIdentity.resolve(
        cli: CliTool.codex,
        officialProviderId: resolveOfficial,
      ).provider,
      'openai-official',
    );
    expect(
      SimpleLaunchIdentity.resolve(
        cli: CliTool.opencode,
        officialProviderId: resolveOfficial,
      ).provider,
      'opencode',
    );
    expect(
      SimpleLaunchIdentity.resolve(
        cli: CliTool.flashskyai,
        officialProviderId: resolveOfficial,
      ).provider,
      isEmpty,
    );
  });

  test('resolve leaves provider empty without an injected resolver', () {
    expect(SimpleLaunchIdentity.resolve(cli: CliTool.claude).provider, isEmpty);
  });

  test('withOfficialDefaultProvider back-fills only an empty provider', () {
    const empty = SimpleLaunchIdentity(cli: CliTool.claude);
    expect(
      empty.withOfficialDefaultProvider((cli) => 'claude-official').provider,
      'claude-official',
    );
    const set = SimpleLaunchIdentity(cli: CliTool.claude, provider: 'custom');
    expect(
      set.withOfficialDefaultProvider((cli) => 'claude-official').provider,
      'custom',
    );
  });
}
