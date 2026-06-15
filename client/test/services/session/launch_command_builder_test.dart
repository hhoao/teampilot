import 'dart:io';

import 'package:teampilot/models/project_profile.dart';
import 'package:teampilot/services/cli/cli_tool_adapter.dart';
import 'package:teampilot/services/cli/registry/config_profile/config_profile_context.dart';
import 'package:teampilot/services/session/launch_command_builder.dart';
import 'package:teampilot/services/session/shell_launch_spec.dart';
import 'package:teampilot/services/cli/registry/config_profile/claude_config_profile_capability.dart';
import 'package:teampilot/services/session/member_role_provision.dart';
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
    const team = TeamConfig(id: '1', name: 'agent', cli: CliTool.flashskyai);

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
        'member-1',
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
    const team = TeamConfig(id: '1', name: 'agent', cli: CliTool.flashskyai);

    expect(LaunchCommandBuilder.buildArguments(team, member), [
      '--team',
      'agent',
      '--member',
      'member-1',
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
      cli: CliTool.flashskyai,
      loop: false,
    );

    expect(LaunchCommandBuilder.buildArguments(team, member), [
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
    ]);
  });

  test('adds --dangerously-skip-permissions when member requests it', () {
    const team = TeamConfig(id: '1', name: 'agent', cli: CliTool.flashskyai);
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
      'member-1',
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
      cli: CliTool.flashskyai,
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
        'member-2',
        '--permission-mode',
        'acceptEdits',
        '--continue',
        '--system-prompt',
        'be careful',
      ],
    );
  });

  test('quotes command preview for display', () {
    const team = TeamConfig(
      id: '1',
      name: 'hello team',
      cli: CliTool.flashskyai,
    );
    const reviewer = TeamMemberConfig(id: 'member-2', name: 'code reviewer');

    expect(
      LaunchCommandBuilder.preview(team, reviewer, executable: 'flashskyai'),
      "flashskyai --team 'hello team' --member member-2",
    );
  });

  test('preview honours the supplied executable path', () {
    const team = TeamConfig(id: '1', name: 'agent', cli: CliTool.flashskyai);
    const planner = TeamMemberConfig(id: 'm', name: 'planner');

    expect(
      LaunchCommandBuilder.preview(
        team,
        planner,
        executable: '/opt/custom/flashskyai',
      ),
      '/opt/custom/flashskyai --team agent --member m',
    );
  });

  test('mixed member cli overrides; native ignores member cli', () {
    const member = TeamMemberConfig(
      id: 'm',
      name: 'planner',
      provider: 'anthropic',
      model: 'sonnet',
      agent: 'builder',
      cli: CliTool.flashskyai,
    );
    const nativeClaude = TeamConfig(id: '1', name: 'agent', cli: CliTool.claude);
    const mixedClaude = TeamConfig(
      id: '1',
      name: 'agent',
      cli: CliTool.claude,
      teamMode: TeamMode.mixed,
    );

    expect(
      LaunchCommandBuilder.buildArguments(nativeClaude, member),
      contains('--team-name'),
    );
    final mixedArgs = LaunchCommandBuilder.buildArguments(mixedClaude, member);
    expect(mixedArgs, isNot(contains('--team')));
    expect(mixedArgs, isNot(contains('--team-name')));
    expect(
      mixedArgs,
      containsAllInOrder(['--provider', 'anthropic', '--model', 'sonnet']),
    );
  });

  test('preview delegates argument construction for Claude teams', () {
    const team = TeamConfig(id: '1', name: 'agent', cli: CliTool.claude);
    const planner = TeamMemberConfig(
      id: 'm',
      name: 'planner',
      provider: 'anthropic',
      model: 'sonnet',
      agent: 'builder',
    );

    expect(
      LaunchCommandBuilder.preview(team, planner, executable: 'claude'),
      'claude --team-name agent --agent-name m '
      '--agent-id m@agent --model sonnet',
    );
  });

  test(
    'launch passes Claude settings as argument and strips internal env',
    () async {
      const team = TeamConfig(id: '1', name: 'agent', cli: CliTool.claude);
      List<String>? capturedArgs;
      Map<String, String>? capturedEnv;

      try {
        await LaunchCommandBuilder.launch(
          team,
          member: member,
          executable: 'claude',
          launchInExternalTerminal: false,
          extraEnvironment: const {
            'CLAUDE_CONFIG_DIR': '/tmp/team/claude',
            ClaudeConfigProfileCapability.settingsFileEnvKey:
                '/tmp/team/claude/settings/planner.json',
          },
          starter:
              (
                executable,
                arguments, {
                workingDirectory,
                runInShell = false,
                environment,
                includeParentEnvironment = true,
              }) async {
                capturedArgs ??= List<String>.from(arguments);
                capturedEnv ??= environment == null
                    ? null
                    : Map<String, String>.from(environment);
                throw const ProcessException('stop', []);
              },
        );
      } on ProcessException {
        // Expected: the fake starter records launch data, then prevents spawn.
      }

      expect(
        capturedArgs,
        containsAllInOrder([
          '--settings',
          '/tmp/team/claude/settings/planner.json',
        ]),
      );
      expect(capturedEnv?['CLAUDE_CONFIG_DIR'], '/tmp/team/claude');
      expect(
        capturedEnv?.containsKey(ClaudeConfigProfileCapability.settingsFileEnvKey),
        isFalse,
      );
    },
  );

  test(
    'launch passes append-system-prompt-file and strips internal env',
    () async {
      const team = TeamConfig(id: '1', name: 'agent', cli: CliTool.claude);
      List<String>? capturedArgs;
      Map<String, String>? capturedEnv;

      try {
        await LaunchCommandBuilder.launch(
          team,
          member: member,
          executable: 'claude',
          launchInExternalTerminal: false,
          extraEnvironment: const {
            'CLAUDE_CONFIG_DIR': '/tmp/team/claude',
            MemberRoleProvision.appendSystemPromptFileEnvKey:
                '/tmp/team/claude/prompts/team-lead/role.md',
          },
          starter:
              (
                executable,
                arguments, {
                workingDirectory,
                runInShell = false,
                environment,
                includeParentEnvironment = true,
              }) async {
                capturedArgs ??= List<String>.from(arguments);
                capturedEnv ??= environment == null
                    ? null
                    : Map<String, String>.from(environment);
                throw const ProcessException('stop', []);
              },
        );
      } on ProcessException {
        // Expected.
      }

      expect(
        capturedArgs,
        containsAllInOrder([
          '--append-system-prompt-file',
          '/tmp/team/claude/prompts/team-lead/role.md',
        ]),
      );
      expect(
        capturedEnv?.containsKey(
          MemberRoleProvision.appendSystemPromptFileEnvKey,
        ),
        isFalse,
      );
    },
  );

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

  test('workingDirectoryForProcess uses native Windows cwd for WSL PTY', () {
    if (!Platform.isWindows) return;
    final cwd = LaunchCommandBuilder.workingDirectoryForProcess(
      '/mnt/c/Users/dev/repo',
      useWslPaths: true,
    );
    expect(cwd, isNot(startsWith('/')));
    expect(Directory(cwd).existsSync(), isTrue);
  });

  test('ShellLaunchSpec builds full personal CLI launch args', () {
    // TODO: migrate to presets — cli, model, providerIdsByTool removed
    const profile = ProjectProfile(
      projectId: 'proj-1',
      agent: ProjectAgentConfig(agent: 'builder'),
    );
    const sessionTeam = 'sess-personal-1';
    final shellLaunch = ShellLaunchSpec(
      plan: LaunchPlan(
        env: {
          ClaudeConfigProfileCapability.settingsFileEnvKey: '/tmp/settings.json',
        },
        resume: false,
        taskId: sessionTeam,
        cliTeamName: sessionTeam,
        memberConfigDir: '/tmp/claude',
        resolvedRoots: const [],
      ),
      launchContext: CliLaunchContext(
        team: standaloneTeamFromProfile(
          profile,
          projectId: profile.projectId,
          sessionTeamName: sessionTeam,
        ),
        member: standaloneMemberFromProfile(profile),
        sessionTeam: sessionTeam,
        workingDirectory: '/home/dev/project',
      ),
      sessionTeam: sessionTeam,
    );

    expect(
      LaunchCommandBuilder.buildShellArguments(
        shellLaunch,
        fixedSessionId: sessionTeam,
        environment: shellLaunch.plan.env,
      ),
      [
        '--session-id',
        sessionTeam,
        '--team-name',
        sessionTeam,
        '--agent-name',
        'builder',
        '--agent-id',
        'builder@$sessionTeam',
        '--model',
        'sonnet',
        '--settings',
        '/tmp/settings.json',
      ],
    );
  });
}
