import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/claude/capabilities/launch_args.dart';
import 'package:teampilot/services/cli/claude/capabilities/session.dart';
import 'package:teampilot/services/cli/codex/capabilities/launch_args.dart';
import 'package:teampilot/services/cli/codex/capabilities/session.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/launch_args.dart';
import 'package:teampilot/services/cli/flashskyai/capabilities/session.dart';
import 'package:teampilot/services/cli/registry/built_in_cli_tools.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_session_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';
import 'package:teampilot/services/session/member_role_provision.dart';

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

  const flashskyaiTeam = TeamProfile(
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
        team: const TeamProfile(
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

    expect(
      args,
      containsAllInOrder(['--agent-name', 'm1', '--agent-id', 'm1@agent']),
    );
  });

  test('claude adapter builds Claude Code team arguments', () {
    final adapter = ClaudeCodeCliToolAdapter();

    expect(
      adapter.buildArguments(
        CliLaunchContext(
          team: const TeamProfile(
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
        team: const TeamProfile(
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
        team: const TeamProfile(
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
        team: const TeamProfile(
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
        team: const TeamProfile(
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
        team: const TeamProfile(
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
        team: const TeamProfile(
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

  test('registry resolves session capabilities per tool id', () {
    final registry = CliToolRegistry();
    registerBuiltInCliTools(registry);

    expect(
      registry.capability<CliSessionCapability>(CliTool.flashskyai),
      isA<FlashskyaiCliSessionCapability>(),
    );
    expect(
      registry.capability<CliSessionCapability>(CliTool.claude),
      isA<ClaudeCliSessionCapability>(),
    );
    expect(
      registry.capability<CliSessionCapability>(CliTool.codex),
      isA<CodexCliSessionCapability>(),
    );
  });

  test('codex adapter emits codex-native flags, not flashskyai team flags', () {
    const adapter = CodexCliToolAdapter();
    const mixedTeam = TeamProfile(
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
    // TeamPilot-provisioned hooks (Stop / agent-status) → bypass trust prompt
    expect(args, contains('--dangerously-bypass-hook-trust'));
    // never the flashskyai/claude roster flags
    expect(args, isNot(contains('--team')));
    expect(args, isNot(contains('--member')));
    expect(args, isNot(contains('--session-id')));
    expect(args, isNot(contains('--append-system-prompt-file')));
  });

  test('codex adapter bypasses hook-trust outside mixed mode too', () {
    const adapter = CodexCliToolAdapter();

    final args = adapter.buildArguments(
      CliLaunchContext(team: flashskyaiTeam, member: member),
    );

    // Simple/native also stamp agent-status hooks into CODEX_HOME.
    expect(args, contains('--dangerously-bypass-hook-trust'));
  });

  test('claude mixed worker gets shared disallowedTools without Agent', () {
    const adapter = ClaudeCodeCliToolAdapter();
    const mixedTeam = TeamProfile(
      id: 'team-x',
      name: 'mixers',
      cli: CliTool.claude,
      teamMode: TeamMode.mixed,
    );
    const worker = TeamMemberConfig(id: 'worker-1', name: 'Worker');

    final args = adapter.buildArguments(
      CliLaunchContext(team: mixedTeam, member: worker),
    );

    expect(args, isNot(contains('--team-name')));
    final flagAt = args.indexOf('--disallowedTools');
    expect(flagAt, isNonNegative);
    final tools = args.sublist(flagAt + 1);
    // Stop at next flag if any trailing flags exist after the tool list.
    final nextFlag = tools.indexWhere((t) => t.startsWith('--'));
    final denied = nextFlag < 0 ? tools : tools.sublist(0, nextFlag);
    expect(denied, containsAll(MemberRoleProvision.mixedClaudeDisallowedTools));
    expect(denied, isNot(contains('Agent')));
  });

  test('claude mixed team-lead disallowedTools includes Agent', () {
    const adapter = ClaudeCodeCliToolAdapter();
    const mixedTeam = TeamProfile(
      id: 'team-x',
      name: 'mixers',
      cli: CliTool.claude,
      teamMode: TeamMode.mixed,
    );
    const lead = TeamMemberConfig(id: 'team-lead', name: 'team-lead');

    final args = adapter.buildArguments(
      CliLaunchContext(team: mixedTeam, member: lead),
    );

    final flagAt = args.indexOf('--disallowedTools');
    expect(flagAt, isNonNegative);
    final tools = args.sublist(flagAt + 1);
    final nextFlag = tools.indexWhere((t) => t.startsWith('--'));
    final denied = nextFlag < 0 ? tools : tools.sublist(0, nextFlag);
    expect(denied, containsAll(MemberRoleProvision.mixedClaudeDisallowedTools));
    expect(denied, contains('Agent'));
  });

  test('claude native omits disallowedTools', () {
    const adapter = ClaudeCodeCliToolAdapter();
    final args = adapter.buildArguments(
      CliLaunchContext(
        team: const TeamProfile(
          id: 'team-1',
          name: 'agent',
          cli: CliTool.claude,
        ),
        member: const TeamMemberConfig(id: 'm1', name: 'My Planner'),
      ),
    );

    expect(args, isNot(contains('--disallowedTools')));
    expect(args, contains('--team-name'));
  });

  test('claude simple/personal omits native agent-team flags', () {
    const adapter = ClaudeCodeCliToolAdapter();
    final args = adapter.buildArguments(
      CliLaunchContext(
        team: const TeamProfile(
          id: 'workspace-1',
          name: 'session-1',
          cli: CliTool.claude,
          teamMode: TeamMode.native,
          members: [TeamMemberConfig(id: 'session-1', name: 'session-1')],
        ),
        member: const TeamMemberConfig(id: 'session-1', name: 'session-1'),
        sessionTeam: 'session-1',
        nativeAgentTeam: false,
      ),
    );

    expect(args, isNot(contains('--team-name')));
    expect(args, isNot(contains('--agent-name')));
    expect(args, isNot(contains('--agent-id')));
    expect(args, containsAllInOrder(['--disallowedTools', 'Agent']));
  });

  test('flashskyai simple/personal omits native team/member flags', () {
    const adapter = FlashskyaiCliToolAdapter();
    final args = adapter.buildArguments(
      CliLaunchContext(
        team: const TeamProfile(
          id: 'workspace-1',
          name: 'session-1',
          cli: CliTool.flashskyai,
          teamMode: TeamMode.native,
          loop: false,
          members: [TeamMemberConfig(id: 'session-1', name: 'session-1')],
        ),
        member: const TeamMemberConfig(
          id: 'session-1',
          name: 'session-1',
          provider: 'mock-simple',
        ),
        sessionTeam: 'session-1',
        nativeAgentTeam: false,
      ),
    );

    expect(args, isNot(contains('--team')));
    expect(args, isNot(contains('--member')));
    expect(args, isNot(contains('--loop')));
    expect(args, containsAllInOrder(['--disallowedTools', 'Agent']));
    expect(args, containsAllInOrder(['--provider', 'mock-simple']));
  });
}
