import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_security_policy.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/claude/claude_tool.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_assembler.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_provider.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_capability_error.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';

void main() {
  const member = TeamMemberConfig(
    id: 'member-1',
    name: 'planner',
    model: 'sonnet',
    extraArgs: '--continue --system-prompt "be careful"',
  );

  test('assembles Claude startup arguments from registered capabilities', () {
    const team = TeamProfile(
      id: 'team-1',
      name: 'agent',
      cli: CliTool.claude,
      extraArgs: '--permission-mode acceptEdits',
    );

    expect(
      _assemble(
        team: team,
        member: const TeamMemberConfig(
          id: 'member-1',
          name: 'planner',
          model: 'sonnet',
          extraArgs: '--continue --system-prompt "be careful"',
        ),
        workingDirectory: '/home/hhoa/git/agent',
        additionalDirectories: const ['/home/hhoa/git/shared'],
        resumeSessionId: '22222222-2222-2222-2222-222222222222',
        settingsPath: '/tmp/team/claude/settings/planner.json',
        appendSystemPromptFile: '/tmp/team/claude/prompts/planner/role.md',
        launchSecurityPolicy: LaunchSecurityPolicy.fullAccess,
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
        '--settings',
        '/tmp/team/claude/settings/planner.json',
        '--dangerously-skip-permissions',
        '--append-system-prompt-file',
        '/tmp/team/claude/prompts/planner/role.md',
        '--permission-mode',
        'acceptEdits',
        '--continue',
        '--system-prompt',
        'be careful',
      ],
    );
  });

  test('Claude emits native identity only for native teams', () {
    final nativeArgs = _assemble(
      team: const TeamProfile(
        id: 'team-1',
        name: 'agent',
        cli: CliTool.claude,
        teamMode: TeamMode.native,
      ),
      member: member,
    );
    final mixedArgs = _assemble(
      team: const TeamProfile(
        id: 'team-1',
        name: 'agent',
        cli: CliTool.claude,
        teamMode: TeamMode.mixed,
      ),
      member: member,
    );
    final simpleArgs = _assemble(
      team: const TeamProfile(
        id: 'simple',
        name: 'simple',
        cli: CliTool.claude,
        teamMode: TeamMode.native,
      ),
      member: member,
      nativeAgentTeam: false,
    );

    expect(nativeArgs, containsAllInOrder(['--team-name', 'agent']));
    expect(nativeArgs, containsAllInOrder(['--agent-name', 'member-1']));
    expect(nativeArgs, contains('--agent-id'));
    expect(mixedArgs, isNot(contains('--team-name')));
    expect(mixedArgs, isNot(contains('--agent-name')));
    expect(mixedArgs, contains('--disallowedTools'));
    expect(simpleArgs, isNot(contains('--team-name')));
    expect(simpleArgs, containsAllInOrder(['--disallowedTools', 'Agent']));
  });

  test('Claude omits --dir and keeps the primary workspace as process cwd', () {
    final args = _assemble(
      team: const TeamProfile(id: 'team-1', name: 'agent', cli: CliTool.claude),
      member: member,
      workingDirectory: '/home/hhoa/git/agent',
    );

    expect(args, isNot(contains('--dir')));
    expect(args, isNot(contains('/home/hhoa/git/agent')));
  });

  test('Claude normalizes WSL paths and repeats additional directories', () {
    final args = _assemble(
      team: const TeamProfile(id: 'team-1', name: 'agent', cli: CliTool.claude),
      member: member,
      workingDirectory: r'C:\work\agent',
      additionalDirectories: const [r'D:\repo\a', '', r'D:\repo\b'],
      useWslPaths: true,
    );

    expect(args, isNot(contains('--dir')));
    expect(args, isNot(contains('/mnt/c/work/agent')));
    expect(
      args,
      containsAllInOrder([
        '--add-dir',
        '/mnt/d/repo/a',
        '--add-dir',
        '/mnt/d/repo/b',
      ]),
    );
  });

  test(
    'Claude maps supported safe policies and rejects unsupported tuples',
    () {
      final readOnly = _assemble(
        team: const TeamProfile(id: 'team-1', name: 'agent'),
        member: member,
        launchSecurityPolicy: LaunchSecurityPolicy.askReadOnlyTrusted,
      );
      final workspaceWrite = _assemble(
        team: const TeamProfile(id: 'team-1', name: 'agent'),
        member: member,
        launchSecurityPolicy:
            LaunchSecurityPolicy.autoApproveWorkspaceWriteTrusted,
      );

      expect(readOnly, containsAllInOrder(['--permission-mode', 'plan']));
      expect(
        workspaceWrite,
        containsAllInOrder(['--permission-mode', 'acceptEdits']),
      );
      expect(
        () => _assemble(
          team: const TeamProfile(id: 'team-1', name: 'agent'),
          member: member,
          launchSecurityPolicy: const LaunchSecurityPolicy(
            approval: LaunchApprovalPolicy.never,
            sandbox: LaunchSandboxPolicy.workspaceWrite,
            hookTrust: LaunchHookTrustPolicy.trustedOnly,
          ),
        ),
        throwsA(isA<CliLaunchCapabilityException>()),
      );
    },
  );

  test('Claude registers one launch provider per semantic capability', () {
    final providers = ClaudeCliTool().capabilities
        .whereType<CliLaunchArgProvider>()
        .toList();

    expect(providers, hasLength(7));
  });
}

List<String> _assemble({
  required TeamProfile team,
  required TeamMemberConfig member,
  String? workingDirectory,
  List<String> additionalDirectories = const [],
  String? fixedSessionId,
  String? resumeSessionId,
  String? settingsPath,
  String? appendSystemPromptFile,
  bool useWslPaths = false,
  bool? nativeAgentTeam,
  LaunchSecurityPolicy? launchSecurityPolicy,
}) {
  return const CliLaunchArgAssembler().assemble(
    ClaudeCliTool(),
    CliLaunchContext(
      team: team,
      member: member,
      workingDirectory: workingDirectory,
      additionalDirectories: additionalDirectories,
      fixedSessionId: fixedSessionId,
      resumeSessionId: resumeSessionId,
      settingsPath: settingsPath,
      appendSystemPromptFile: appendSystemPromptFile,
      useWslPaths: useWslPaths,
      nativeAgentTeam: nativeAgentTeam,
      launchSecurityPolicy: launchSecurityPolicy,
    ),
  );
}
