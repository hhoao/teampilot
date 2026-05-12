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
    );

    expect(LaunchCommandBuilder.buildArguments(team, member, workingDirectory: '/home/hhoa/git/agent'), [
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

  test('omits --dir when workingDirectory is empty', () {
    const team = TeamConfig(
      id: '1',
      name: 'agent',
    );

    expect(LaunchCommandBuilder.buildArguments(team, member), [
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

  test('adds --loop after --member when team.loop is set', () {
    const team = TeamConfig(
      id: '1',
      name: 'agent',
      loop: false,
    );

    expect(LaunchCommandBuilder.buildArguments(team, member), [
      '--team',
      'agent',
      '--member',
      'planner',
      '--loop',
      'false',
      '--provider',
      'anthropic',
      '--model',
      'sonnet',
      '--agent',
      'builder',
    ]);
  });

  test('adds --dangerously-skip-permissions when member requests it', () {
    const team = TeamConfig(id: '1', name: 'agent');
    const risky = TeamMemberConfig(
      id: 'member-1',
      name: 'planner',
      provider: 'anthropic',
      model: 'sonnet',
      agent: 'builder',
      dangerouslySkipPermissions: true,
    );

    expect(LaunchCommandBuilder.buildArguments(team, risky), [
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
      '--dangerously-skip-permissions',
    ]);
  });

  test('merges team and member extra arguments', () {
    const team = TeamConfig(
      id: '1',
      name: 'agent',
      extraArgs: '--permission-mode acceptEdits',
    );
    const reviewer = TeamMemberConfig(
      id: 'member-2',
      name: 'reviewer',
      extraArgs: '--continue --system-prompt "be careful"',
    );

    expect(LaunchCommandBuilder.buildArguments(team, reviewer, workingDirectory: '/home/hhoa/git/agent'), [
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
    );
    const reviewer = TeamMemberConfig(id: 'member-2', name: 'code reviewer');

    expect(
      LaunchCommandBuilder.preview(team, reviewer),
      "flashskyai --team 'hello team' --member 'code reviewer'",
    );
  });
}
