import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli_tool_adapter.dart';

void main() {
  const member = TeamMemberConfig(
    id: 'member-1',
    name: 'planner',
    provider: 'anthropic',
    model: 'sonnet',
    agent: 'builder',
    extraArgs: '--continue --system-prompt "be careful"',
    dangerouslySkipPermissions: true,
  );

  const flashskyaiTeam = TeamConfig(
    id: 'team-1',
    name: 'agent',
    extraArgs: '--permission-mode acceptEdits',
    loop: false,
  );

  test('flashskyai adapter preserves existing argument order and flags', () {
    final adapter = FlashskyaiCliToolAdapter();

    expect(
      adapter.buildArguments(
        CliLaunchContext(
          team: flashskyaiTeam,
          member: member,
          workingDirectory: '/home/hhoa/git/agent',
          additionalDirectories: const ['/home/hhoa/git/shared'],
          fixedSessionId: '11111111-1111-1111-1111-111111111111',
        ),
      ),
      [
        '--session-id',
        '11111111-1111-1111-1111-111111111111',
        '--dir',
        '/home/hhoa/git/agent',
        '--add-dir',
        '/home/hhoa/git/shared',
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
        '--dangerously-skip-permissions',
        '--permission-mode',
        'acceptEdits',
        '--continue',
        '--system-prompt',
        'be careful',
      ],
    );
  });

  test('claude adapter builds Claude Code team arguments', () {
    final adapter = ClaudeCodeCliToolAdapter();

    expect(
      adapter.buildArguments(
        CliLaunchContext(
          team: const TeamConfig(
            id: 'team-1',
            name: 'agent',
            cli: TeamCli.claude,
            extraArgs: '--permission-mode acceptEdits',
            loop: true,
          ),
          member: member,
          workingDirectory: '/home/hhoa/git/agent',
          additionalDirectories: const ['/home/hhoa/git/shared'],
          resumeSessionId: '22222222-2222-2222-2222-222222222222',
        ),
      ),
      [
        '--resume',
        '22222222-2222-2222-2222-222222222222',
        '--add-dir',
        '/home/hhoa/git/shared',
        '--team-name',
        'agent',
        '--agent-name',
        'planner',
        '--agent-id',
        'planner@agent',
        '--model',
        'sonnet',
        '--dangerously-skip-permissions',
        '--permission-mode',
        'acceptEdits',
        '--continue',
        '--system-prompt',
        'be careful',
      ],
    );
  });

  test('claude adapter appends role system prompt file when set', () {
    final args = ClaudeCodeCliToolAdapter().buildArguments(
      CliLaunchContext(
        team: const TeamConfig(
          id: 'team-1',
          name: 'agent',
          cli: TeamCli.claude,
        ),
        member: member,
        appendSystemPromptFile: '/tmp/team/claude/prompts/team-lead/role.md',
      ),
    );

    expect(
      args,
      containsAllInOrder([
        '--append-system-prompt-file',
        '/tmp/team/claude/prompts/team-lead/role.md',
      ]),
    );
  });

  test('claude adapter appends member settings file argument', () {
    final args = ClaudeCodeCliToolAdapter().buildArguments(
      CliLaunchContext(
        team: const TeamConfig(
          id: 'team-1',
          name: 'agent',
          cli: TeamCli.claude,
        ),
        member: member,
        settingsPath: '/tmp/team/claude/settings/planner.json',
      ),
    );

    expect(
      args,
      containsAllInOrder([
        '--settings',
        '/tmp/team/claude/settings/planner.json',
      ]),
    );
  });

  test('claude adapter relies on env instead of unsupported --agent-teams', () {
    final args = ClaudeCodeCliToolAdapter().buildArguments(
      CliLaunchContext(
        team: const TeamConfig(
          id: 'team-1',
          name: 'agent',
          cli: TeamCli.claude,
        ),
        member: member,
      ),
    );

    expect(args, isNot(contains('--agent-teams')));
  });

  test('claude adapter does not pass unsupported --dir option', () {
    final args = ClaudeCodeCliToolAdapter().buildArguments(
      CliLaunchContext(
        team: const TeamConfig(
          id: 'team-1',
          name: 'agent',
          cli: TeamCli.claude,
        ),
        member: member,
        workingDirectory: '/home/hhoa/git/agent',
      ),
    );

    expect(args, isNot(contains('--dir')));
    expect(args, isNot(contains('/home/hhoa/git/agent')));
  });

  test('claude adapter omits flashskyai-only flags', () {
    final args = ClaudeCodeCliToolAdapter().buildArguments(
      CliLaunchContext(
        team: const TeamConfig(
          id: 'team-1',
          name: 'agent',
          cli: TeamCli.claude,
          loop: false,
        ),
        member: member,
      ),
    );

    expect(args, isNot(contains('--team')));
    expect(args, isNot(contains('--member')));
    expect(args, isNot(contains('--provider')));
    expect(args, isNot(contains('--agent')));
    expect(args, isNot(contains('--loop')));
  });

  test('registry resolves supported adapters and falls back to flashskyai', () {
    final registry = CliToolAdapterRegistry();

    expect(
      registry.forCli(TeamCli.flashskyai),
      isA<FlashskyaiCliToolAdapter>(),
    );
    expect(registry.forCli(TeamCli.claude), isA<ClaudeCodeCliToolAdapter>());
    expect(registry.forCli(TeamCli.codex), isA<FlashskyaiCliToolAdapter>());
  });
}
