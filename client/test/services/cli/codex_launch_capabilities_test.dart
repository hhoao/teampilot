import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/launch_security_policy.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/codex/capabilities/model_launch.dart';
import 'package:teampilot/services/cli/codex/capabilities/permission_launch.dart';
import 'package:teampilot/services/cli/codex/capabilities/session_selection_launch.dart';
import 'package:teampilot/services/cli/codex/capabilities/workspace_access_launch.dart';
import 'package:teampilot/services/cli/codex/codex_tool.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_assembler.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_provider.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_capability_error.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';
import 'package:teampilot/services/cli/registry/launch/user_extra_args_provider.dart';
import 'package:teampilot/services/session/launch_command_builder.dart';

void main() {
  test('fresh Codex launches preserve model and full-access arguments', () {
    expect(
      _assemble(
        team: const TeamProfile(id: 'team', name: 'Team', cli: CliTool.codex),
        member: const TeamMemberConfig(
          id: 'member',
          name: 'Member',
          model: 'gpt-5.2',
          launchSecurityPolicy: LaunchSecurityPolicy.fullAccess,
        ),
        workingDirectory: '/work',
      ),
      [
        '--cd',
        '/work',
        '-m',
        'gpt-5.2',
        '--dangerously-bypass-approvals-and-sandbox',
        '--dangerously-bypass-hook-trust',
      ],
    );
  });

  test('resume and fixed Codex launches use the resume subcommand', () {
    const team = TeamProfile(id: 'team', name: 'Team', cli: CliTool.codex);
    const member = TeamMemberConfig(
      id: 'member',
      name: 'Member',
      launchSecurityPolicy: LaunchSecurityPolicy.fullAccess,
    );

    expect(
      _assemble(team: team, member: member, resumeSessionId: 'resume-id'),
      [
        'resume',
        'resume-id',
        '--dangerously-bypass-approvals-and-sandbox',
        '--dangerously-bypass-hook-trust',
      ],
    );
    expect(_assemble(team: team, member: member, fixedSessionId: 'fixed-id'), [
      'resume',
      'fixed-id',
      '--dangerously-bypass-approvals-and-sandbox',
      '--dangerously-bypass-hook-trust',
    ]);
  });

  test(
    'workspace access repeats add-dir pairs, filters blanks, and normalizes WSL paths',
    () {
      expect(
        _assemble(
          team: const TeamProfile(id: 'team', name: 'Team', cli: CliTool.codex),
          member: const TeamMemberConfig(id: 'member', name: 'Member'),
          workingDirectory: r'C:\work\root',
          additionalDirectories: const [
            ' ',
            r'D:\repo\one',
            '',
            r'E:\repo\two',
          ],
          useWslPaths: true,
          launchSecurityPolicy: LaunchSecurityPolicy.cliDefault,
        ),
        [
          '--cd',
          '/mnt/c/work/root',
          '--add-dir',
          '/mnt/d/repo/one',
          '--add-dir',
          '/mnt/e/repo/two',
        ],
      );
    },
  );

  test('model provider emits the Codex -m pair', () {
    expect(
      _assemble(
        team: const TeamProfile(id: 'team', name: 'Team', cli: CliTool.codex),
        member: const TeamMemberConfig(
          id: 'member',
          name: 'Member',
          model: '  gpt-5.2  ',
        ),
        launchSecurityPolicy: LaunchSecurityPolicy.cliDefault,
      ),
      ['-m', 'gpt-5.2'],
    );
  });

  test(
    'permission provider emits both bypass flags only for exact full access',
    () {
      expect(
        _assemble(
          team: const TeamProfile(id: 'team', name: 'Team', cli: CliTool.codex),
          member: const TeamMemberConfig(id: 'member', name: 'Member'),
        ),
        [
          '--dangerously-bypass-approvals-and-sandbox',
          '--dangerously-bypass-hook-trust',
        ],
      );
      expect(
        _assemble(
          team: const TeamProfile(id: 'team', name: 'Team', cli: CliTool.codex),
          member: const TeamMemberConfig(id: 'member', name: 'Member'),
          launchSecurityPolicy: LaunchSecurityPolicy.cliDefault,
        ),
        isEmpty,
      );
      expect(
        () => _assemble(
          team: const TeamProfile(id: 'team', name: 'Team', cli: CliTool.codex),
          member: const TeamMemberConfig(id: 'member', name: 'Member'),
          launchSecurityPolicy: const LaunchSecurityPolicy(
            approval: LaunchApprovalPolicy.never,
            sandbox: LaunchSandboxPolicy.fullAccess,
            hookTrust: LaunchHookTrustPolicy.trustedOnly,
          ),
        ),
        throwsA(
          isA<CliLaunchCapabilityException>().having(
            (error) => error.cli,
            'cli',
            CliTool.codex,
          ),
        ),
      );
    },
  );

  test('team and member extra args are raw tokens and remain last', () {
    expect(
      _assemble(
        team: const TeamProfile(
          id: 'team',
          name: 'Team',
          cli: CliTool.codex,
          extraArgs: '--team-flag "team value"',
        ),
        member: const TeamMemberConfig(
          id: 'member',
          name: 'Member',
          extraArgs: "--member-flag 'member value'",
        ),
        workingDirectory: '/work',
        launchSecurityPolicy: LaunchSecurityPolicy.cliDefault,
      ),
      [
        '--cd',
        '/work',
        '--team-flag',
        'team value',
        '--member-flag',
        'member value',
      ],
    );
  });

  test('Codex registers named launch providers and no native team flags', () {
    final tool = CodexCliTool();
    final providers = tool.capabilities.whereType<CliLaunchArgProvider>();

    expect(providers, contains(isA<CodexSessionSelectionLaunch>()));
    expect(providers, contains(isA<CodexWorkspaceAccessLaunch>()));
    expect(providers, contains(isA<CodexModelLaunch>()));
    expect(providers, contains(isA<CodexPermissionLaunch>()));
    expect(providers, contains(isA<UserExtraArgsProvider>()));
    expect(providers, hasLength(5));
    expect(tool.teamBehavior.supportsNativeTeam, isFalse);
  });

  test('Codex mixed-mode launch rejects a tool without launch providers', () {
    final context = CliLaunchContext(
      team: const TeamProfile(
        id: 'team',
        name: 'Team',
        cli: CliTool.codex,
        teamMode: TeamMode.mixed,
      ),
      member: const TeamMemberConfig(id: 'member', name: 'Member'),
    );

    expect(
      () => LaunchCommandBuilder.buildArgumentsFromContext(
        context,
        cliRegistry: _registryWithEmptyCodexTool(),
      ),
      throwsA(
        isA<CliLaunchCapabilityException>().having(
          (error) => error.contributionKey,
          'contribution key',
          'launch-arg-provider',
        ),
      ),
    );
  });
}

List<String> _assemble({
  required TeamProfile team,
  required TeamMemberConfig member,
  String? workingDirectory,
  List<String> additionalDirectories = const [],
  String? fixedSessionId,
  String? resumeSessionId,
  bool useWslPaths = false,
  LaunchSecurityPolicy? launchSecurityPolicy,
}) {
  return const CliLaunchArgAssembler().assemble(
    CodexCliTool(),
    CliLaunchContext(
      team: team,
      member: member,
      workingDirectory: workingDirectory,
      additionalDirectories: additionalDirectories,
      fixedSessionId: fixedSessionId,
      resumeSessionId: resumeSessionId,
      useWslPaths: useWslPaths,
      launchSecurityPolicy: launchSecurityPolicy,
    ),
  );
}

CliToolRegistry _registryWithEmptyCodexTool() {
  final registry = CliToolRegistry();
  registry.register(_EmptyCodexTool());
  return registry;
}

final class _EmptyCodexTool implements CliToolDefinition {
  @override
  CliTool get id => CliTool.codex;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => const [];
}
