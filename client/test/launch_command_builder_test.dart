import 'package:flashskyai_client/services/launch_command_builder.dart';
import 'package:flashskyai_client/models/team_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const member = TeamMemberConfig(
    id: 'member-1',
    name: 'planner',
    provider: 'anthropic',
    model: 'sonnet',
    agent: 'builder',
  );

  test('builds required flashskyai arguments for a member', () {
    const team = TeamConfig(
      id: '1',
      name: 'agent',
      workingDirectory: '/home/hhoa/git/agent',
    );

    expect(LaunchCommandBuilder.buildArguments(team, member), [
      '--dir',
      '/home/hhoa/git/agent',
      '--team',
      'agent',
      '--member',
      'planner',
      '--provider',
      'anthropic',
      '--model',
      'sonnet',
      '--agent',
      'builder',
    ]);
  });

  test('merges team and member extra arguments', () {
    const team = TeamConfig(
      id: '1',
      name: 'agent',
      workingDirectory: '/home/hhoa/git/agent',
      extraArgs: '--permission-mode acceptEdits',
    );
    const reviewer = TeamMemberConfig(
      id: 'member-2',
      name: 'reviewer',
      extraArgs: '--continue --system-prompt "be careful"',
    );

    expect(LaunchCommandBuilder.buildArguments(team, reviewer), [
      '--dir',
      '/home/hhoa/git/agent',
      '--team',
      'agent',
      '--member',
      'reviewer',
      '--permission-mode',
      'acceptEdits',
      '--continue',
      '--system-prompt',
      'be careful',
    ]);
  });

  test('quotes command preview for display', () {
    const team = TeamConfig(
      id: '1',
      name: 'hello team',
      workingDirectory: '/home/hhoa/git/my app',
    );
    const reviewer = TeamMemberConfig(id: 'member-2', name: 'code reviewer');

    expect(
      LaunchCommandBuilder.preview(team, reviewer),
      "flashskyai --dir '/home/hhoa/git/my app' --team 'hello team' --member 'code reviewer'",
    );
  });
}
