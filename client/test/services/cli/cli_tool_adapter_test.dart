import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_tool_adapter.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/launch_args_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';

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
        'member-1',
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

  test('claude adapter uses member id for --agent-name', () {
    final args = ClaudeCodeCliToolAdapter().buildArguments(
      CliLaunchContext(
        team: const TeamConfig(
          id: 'team-1',
          name: 'agent',
          cli: CliTool.claude,
        ),
        member: const TeamMemberConfig(
          id: 'm1',
          name: 'My Planner',
          provider: 'anthropic',
          model: 'sonnet',
        ),
      ),
    );

    expect(args, containsAllInOrder(['--agent-name', 'm1', '--agent-id', 'm1@agent']));
  });

  test('claude adapter builds Claude Code team arguments', () {
    final adapter = ClaudeCodeCliToolAdapter();

    expect(
      adapter.buildArguments(
        CliLaunchContext(
          team: const TeamConfig(
            id: 'team-1',
            name: 'agent',
            cli: CliTool.claude,
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
        'member-1',
        '--agent-id',
        'member-1@agent',
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

  test('claude adapter uses bare team-lead agent id for leader tab', () {
    final args = ClaudeCodeCliToolAdapter().buildArguments(
      CliLaunchContext(
        team: const TeamConfig(
          id: 'team-1',
          name: 'agent',
          cli: CliTool.claude,
        ),
        member: const TeamMemberConfig(
          id: 'team-lead',
          name: 'team-lead',
          provider: 'anthropic',
          model: 'sonnet',
        ),
      ),
    );

    expect(
      args,
      containsAllInOrder([
        '--team-name',
        'agent',
        '--agent-name',
        'team-lead',
        '--agent-id',
        'team-lead',
      ]),
    );
  });

  test('flashskyai adapter appends role system prompt file when set', () {
    final args = FlashskyaiCliToolAdapter().buildArguments(
      CliLaunchContext(
        team: flashskyaiTeam,
        member: member,
        appendSystemPromptFile:
            '/tmp/team/flashskyai/prompts/team-lead/role.md',
      ),
    );

    expect(
      args,
      containsAllInOrder([
        '--append-system-prompt-file',
        '/tmp/team/flashskyai/prompts/team-lead/role.md',
      ]),
    );
  });

  test('claude adapter appends role system prompt file when set', () {
    final args = ClaudeCodeCliToolAdapter().buildArguments(
      CliLaunchContext(
        team: const TeamConfig(
          id: 'team-1',
          name: 'agent',
          cli: CliTool.claude,
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
          cli: CliTool.claude,
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
          cli: CliTool.claude,
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
          cli: CliTool.claude,
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
          cli: CliTool.claude,
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

  test('registry resolves launch adapters per tool id', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);

    expect(
      registry.capability<LaunchArgsCapability>(CliTool.flashskyai),
      isA<FlashskyaiCliToolAdapter>(),
    );
    expect(
      registry.capability<LaunchArgsCapability>(CliTool.claude),
      isA<ClaudeCodeCliToolAdapter>(),
    );
    expect(
      registry.capability<LaunchArgsCapability>(CliTool.codex),
      isA<CodexCliToolAdapter>(),
    );
  });

  test('codex adapter emits codex-native flags, not flashskyai team flags', () {
    const adapter = CodexCliToolAdapter();
    const mixedTeam = TeamConfig(
      id: 'team-x',
      name: 'mixers',
      teamMode: TeamMode.mixed,
    );

    final args = adapter.buildArguments(
      CliLaunchContext(
        team: mixedTeam,
        member: member,
        workingDirectory: '/home/hhoa/git/agent',
      ),
    );

    expect(args, containsAllInOrder(['--cd', '/home/hhoa/git/agent']));
    expect(args, containsAllInOrder(['-m', 'sonnet']));
    expect(args, contains('--dangerously-bypass-approvals-and-sandbox'));
    // mixed mode provisions a self-trusted Stop hook → bypass the trust prompt
    expect(args, contains('--dangerously-bypass-hook-trust'));
    // never the flashskyai/claude roster flags
    expect(args, isNot(contains('--team')));
    expect(args, isNot(contains('--member')));
    expect(args, isNot(contains('--session-id')));
    expect(args, isNot(contains('--append-system-prompt-file')));
  });

  test('codex adapter omits hook-trust bypass outside mixed mode', () {
    const adapter = CodexCliToolAdapter();

    final args = adapter.buildArguments(
      CliLaunchContext(team: flashskyaiTeam, member: member),
    );

    expect(args, isNot(contains('--dangerously-bypass-hook-trust')));
  });
}
