import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_security_policy.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/flashskyai/flashskyai_tool.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_assembler.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_provider.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_capability_error.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';

void main() {
  const member = TeamMemberConfig(
    id: 'member-1',
    name: 'planner',
    provider: 'anthropic',
    model: 'sonnet',
    agent: 'builder',
    extraArgs: '--continue --system-prompt "be careful"',
  );

  test('assembles FlashskyAI startup arguments from capabilities', () {
    const team = TeamProfile(
      id: 'team-1',
      name: 'agent',
      cli: CliTool.flashskyai,
      loop: false,
      extraArgs: '--permission-mode acceptEdits',
    );

    expect(
      _assemble(
        team: team,
        member: member,
        workingDirectory: '/home/hhoa/git/agent',
        additionalDirectories: const ['/home/hhoa/git/shared'],
        fixedSessionId: '11111111-1111-1111-1111-111111111111',
        appendSystemPromptFile: '/tmp/team/flashskyai/prompts/planner/role.md',
        launchSecurityPolicy: LaunchSecurityPolicy.fullAccess,
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
        '--append-system-prompt-file',
        '/tmp/team/flashskyai/prompts/planner/role.md',
      ],
    );
  });

  test('FlashskyAI emits native identity only for native teams', () {
    final nativeArgs = _assemble(
      team: const TeamProfile(
        id: 'team-1',
        name: 'agent',
        cli: CliTool.flashskyai,
        teamMode: TeamMode.native,
        loop: true,
      ),
      member: member,
    );
    final mixedArgs = _assemble(
      team: const TeamProfile(
        id: 'team-1',
        name: 'agent',
        cli: CliTool.flashskyai,
        teamMode: TeamMode.mixed,
        loop: true,
      ),
      member: member,
    );
    final simpleArgs = _assemble(
      team: const TeamProfile(
        id: 'simple',
        name: 'simple',
        cli: CliTool.flashskyai,
        teamMode: TeamMode.native,
        loop: false,
      ),
      member: member,
      nativeAgentTeam: false,
    );

    expect(nativeArgs, containsAllInOrder(['--team', 'agent', '--member']));
    expect(nativeArgs, containsAllInOrder(['--loop', 'true']));
    expect(mixedArgs, isNot(contains('--team')));
    expect(mixedArgs, isNot(contains('--member')));
    expect(mixedArgs, isNot(contains('--loop')));
    expect(simpleArgs, isNot(contains('--team')));
    expect(simpleArgs, isNot(contains('--member')));
    expect(simpleArgs, isNot(contains('--loop')));
    expect(simpleArgs, containsAllInOrder(['--disallowedTools', 'Agent']));
  });

  test(
    'FlashskyAI normalizes WSL paths and repeats additional directories',
    () {
      expect(
        _assemble(
          team: const TeamProfile(id: 'team-1', name: 'agent'),
          member: member,
          workingDirectory: r'C:\work\agent',
          additionalDirectories: const [r'D:\repo\a', '', r'D:\repo\b'],
          useWslPaths: true,
        ),
        containsAllInOrder([
          '--dir',
          '/mnt/c/work/agent',
          '--add-dir',
          '/mnt/d/repo/a',
          '--add-dir',
          '/mnt/d/repo/b',
        ]),
      );
    },
  );

  test(
    'FlashskyAI maps supported safe policies and rejects unsupported tuples',
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

  test('FlashskyAI registers one launch provider per semantic capability', () {
    final providers = FlashskyaiCliTool().capabilities
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
  String? appendSystemPromptFile,
  bool useWslPaths = false,
  bool? nativeAgentTeam,
  LaunchSecurityPolicy? launchSecurityPolicy,
}) {
  return const CliLaunchArgAssembler().assemble(
    FlashskyaiCliTool(),
    CliLaunchContext(
      team: team,
      member: member,
      workingDirectory: workingDirectory,
      additionalDirectories: additionalDirectories,
      fixedSessionId: fixedSessionId,
      resumeSessionId: resumeSessionId,
      appendSystemPromptFile: appendSystemPromptFile,
      useWslPaths: useWslPaths,
      nativeAgentTeam: nativeAgentTeam,
      launchSecurityPolicy: launchSecurityPolicy,
    ),
  );
}
