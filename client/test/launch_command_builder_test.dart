import 'package:teampilot/services/launch_command_builder.dart';
import 'package:teampilot/models/team_config.dart';
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
    const team = TeamConfig(id: '1', name: 'agent');

    expect(
      LaunchCommandBuilder.buildArguments(
        team,
        member,
        workingDirectory: '/home/hhoa/git/agent',
      ),
      [
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
      ],
    );
  });

  test('omits --dir when workingDirectory is empty', () {
    const team = TeamConfig(id: '1', name: 'agent');

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
    const team = TeamConfig(id: '1', name: 'agent', loop: false);

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

    expect(
      LaunchCommandBuilder.buildArguments(
        team,
        reviewer,
        workingDirectory: '/home/hhoa/git/agent',
      ),
      [
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
      ],
    );
  });

  test('quotes command preview for display', () {
    const team = TeamConfig(id: '1', name: 'hello team');
    const reviewer = TeamMemberConfig(id: 'member-2', name: 'code reviewer');

    expect(
      LaunchCommandBuilder.preview(team, reviewer, executable: 'flashskyai'),
      "flashskyai --team 'hello team' --member 'code reviewer'",
    );
  });

  test('preview honours the supplied executable path', () {
    const team = TeamConfig(id: '1', name: 'agent');
    const planner = TeamMemberConfig(id: 'm', name: 'planner');

    expect(
      LaunchCommandBuilder.preview(
        team,
        planner,
        executable: '/opt/custom/flashskyai',
      ),
      '/opt/custom/flashskyai --team agent --member planner',
    );
  });

  group('buildSessionPrefixArgs', () {
    test('--resume wins over fixed session id', () {
      expect(
        LaunchCommandBuilder.buildSessionPrefixArgs(
          workingDirectory: '/w',
          additionalDirectories: const ['/a'],
          fixedSessionId: '11111111-1111-1111-1111-111111111111',
          resumeSessionId: '22222222-2222-2222-2222-222222222222',
        ),
        [
          '--resume',
          '22222222-2222-2222-2222-222222222222',
          '--dir',
          '/w',
          '--add-dir',
          '/a',
        ],
      );
    });

    test('first launch uses --session-id only', () {
      expect(
        LaunchCommandBuilder.buildSessionPrefixArgs(
          workingDirectory: '/w',
          additionalDirectories: const ['/extra'],
          fixedSessionId: '33333333-3333-3333-3333-333333333333',
          resumeSessionId: null,
        ),
        [
          '--session-id',
          '33333333-3333-3333-3333-333333333333',
          '--dir',
          '/w',
          '--add-dir',
          '/extra',
        ],
      );
    });

    test('resume-only omits session-id', () {
      expect(
        LaunchCommandBuilder.buildSessionPrefixArgs(
          resumeSessionId: '44444444-4444-4444-4444-444444444444',
        ),
        ['--resume', '44444444-4444-4444-4444-444444444444'],
      );
    });
  });
}
