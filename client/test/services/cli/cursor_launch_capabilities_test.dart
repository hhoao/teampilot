import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cursor/capabilities/model_launch.dart';
import 'package:teampilot/services/cli/cursor/capabilities/permission_launch.dart';
import 'package:teampilot/services/cli/cursor/capabilities/session_selection_launch.dart';
import 'package:teampilot/services/cli/cursor/capabilities/team_behavior.dart';
import 'package:teampilot/services/cli/cursor/capabilities/workspace_base_info.dart';
import 'package:teampilot/services/cli/cursor/cursor_tool.dart';
import 'package:teampilot/services/cli/registry/capabilities/cli_launch_security_capability.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_assembler.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_provider.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_capability_error.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';
import 'package:teampilot/services/cli/registry/launch/user_extra_args_provider.dart';
import 'package:teampilot/services/chat/session/launch_command_builder.dart';

void main() {
  test('assembles Cursor startup arguments from named providers', () {
    expect(
      _assemble(
        team: const TeamProfile(
          id: 'team',
          name: 'Team',
          cli: CliTool.cursor,
          teamMode: TeamMode.mixed,
          extraArgs: '--team-flag "team value"',
        ),
        member: const TeamMemberConfig(
          id: 'member',
          name: 'Member',
          model: '  gpt-5.2  ',
          extraArgs: "--member-flag 'member value'",
        ),
        workingDirectory: '/work',
        additionalDirectories: const ['/repo/a', '/repo/b'],
        resumeSessionId: 'session-1',
      ),
      [
        '--resume',
        'session-1',
        '--workspace',
        '/work',
        '--add-dir',
        '/repo/a',
        '--add-dir',
        '/repo/b',
        '--approve-mcps',
        '--force',
        '--team-flag',
        'team value',
        '--member-flag',
        'member value',
      ],
    );
  });

  test('Cursor filters blank directories and normalizes WSL paths', () {
    expect(
      _assemble(
        team: const TeamProfile(id: 'team', name: 'Team', cli: CliTool.cursor),
        member: const TeamMemberConfig(id: 'member', name: 'Member'),
        workingDirectory: r'C:\work\root',
        additionalDirectories: const [' ', r'D:\repo\one', '', r'E:\repo\two'],
        useWslPaths: true,
      ),
      [
        '--workspace',
        '/mnt/c/work/root',
        '--add-dir',
        '/mnt/d/repo/one',
        '--add-dir',
        '/mnt/e/repo/two',
        '--force',
      ],
    );
  });

  test('Cursor omits --model; picker id is stamped into cli-config only', () {
    expect(
      _assemble(
        team: const TeamProfile(id: 'team', name: 'Team', cli: CliTool.cursor),
        member: const TeamMemberConfig(
          id: 'member',
          name: 'Member',
          model: 'composer-2.5',
        ),
      ),
      isNot(contains('--model')),
    );
    expect(
      _assemble(
        team: const TeamProfile(id: 'team', name: 'Team', cli: CliTool.cursor),
        member: const TeamMemberConfig(
          id: 'member',
          name: 'Member',
          model: 'cursor-grok-4.6-high',
        ),
      ),
      isNot(contains('--model')),
    );
    expect(
      _assemble(
        team: const TeamProfile(id: 'team', name: 'Team', cli: CliTool.cursor),
        member: const TeamMemberConfig(
          id: 'member',
          name: 'Member',
          model: 'auto',
        ),
      ),
      isNot(contains('--model')),
    );
  });

  test('Cursor permission provider emits --force only for full access', () {
    expect(
      _assemble(
        team: const TeamProfile(id: 'team', name: 'Team', cli: CliTool.cursor),
        member: const TeamMemberConfig(id: 'member', name: 'Member'),
      ),
      ['--force'],
    );
  });

  test('Cursor assembler rejects every non-full-access policy', () {
    for (final policy in const [
      LaunchSecurityPolicy.cliDefault,
      LaunchSecurityPolicy.askReadOnlyTrusted,
      LaunchSecurityPolicy.autoApproveWorkspaceWriteTrusted,
    ]) {
      expect(
        () => _assemble(
          team: const TeamProfile(
            id: 'team',
            name: 'Team',
            cli: CliTool.cursor,
          ),
          member: const TeamMemberConfig(id: 'member', name: 'Member'),
          launchSecurityPolicy: policy,
        ),
        throwsA(
          isA<CliLaunchCapabilityException>()
              .having((error) => error.cli, 'cli', CliTool.cursor)
              .having(
                (error) => error.contributionKey,
                'contributionKey',
                'launch-security-policy',
              ),
        ),
        reason: describeLaunchSecurityPolicy(policy),
      );
    }
  });

  test('Cursor permission provider rejects non-full access directly', () {
    final context = CliLaunchContext(
      team: const TeamProfile(id: 'team', name: 'Team', cli: CliTool.cursor),
      member: const TeamMemberConfig(id: 'member', name: 'Member'),
      launchSecurityPolicy: LaunchSecurityPolicy.cliDefault,
    );

    expect(
      () => const CursorPermissionLaunch().buildLaunchArgs(context),
      throwsA(
        isA<CliLaunchCapabilityException>().having(
          (error) => error.contributionKey,
          'contributionKey',
          'cursor-permission',
        ),
      ),
    );
  });

  test(
    'Cursor rejects fixed session ids instead of silently dropping them',
    () {
      expect(
        () => _assemble(
          team: const TeamProfile(
            id: 'team',
            name: 'Team',
            cli: CliTool.cursor,
          ),
          member: const TeamMemberConfig(id: 'member', name: 'Member'),
          fixedSessionId: 'fixed-session',
        ),
        throwsA(
          isA<CliLaunchCapabilityException>().having(
            (error) => error.cli,
            'cli',
            CliTool.cursor,
          ),
        ),
      );
    },
  );

  test(
    'Cursor registers named launch providers and team behavior provider',
    () {
      final tool = CursorCliTool();
      final providers = tool.capabilities.whereType<CliLaunchArgProvider>();

      expect(providers, contains(isA<CursorTeamBehavior>()));
      expect(providers, contains(isA<CursorSessionSelectionLaunch>()));
      expect(providers, contains(isA<CursorWorkspaceBaseInfo>()));
      expect(providers, contains(isA<CursorModelLaunch>()));
      expect(providers, contains(isA<CursorPermissionLaunch>()));
      expect(providers, contains(isA<UserExtraArgsProvider>()));
      expect(providers, hasLength(6));
    },
  );

  test('Cursor mixed-mode launch rejects a tool without launch providers', () {
    final context = CliLaunchContext(
      team: const TeamProfile(
        id: 'team',
        name: 'Team',
        cli: CliTool.cursor,
        teamMode: TeamMode.mixed,
      ),
      member: const TeamMemberConfig(id: 'member', name: 'Member'),
    );

    expect(
      () => LaunchCommandBuilder.buildArgumentsFromContext(
        context,
        cliRegistry: _registryWithEmptyCursorTool(),
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
    CursorCliTool(),
    CliLaunchContext(
      team: team,
      member: member,
      workingDirectory: workingDirectory,
      additionalDirectories: additionalDirectories,
      fixedSessionId: fixedSessionId,
      resumeSessionId: resumeSessionId,
      useWslPaths: useWslPaths,
      launchSecurityPolicy:
          launchSecurityPolicy ?? LaunchSecurityPolicy.fullAccess,
    ),
  );
}

CliToolRegistry _registryWithEmptyCursorTool() {
  final registry = CliToolRegistry();
  registry.register(_EmptyCursorTool());
  return registry;
}

final class _EmptyCursorTool implements CliToolDefinition {
  @override
  CliTool get id => CliTool.cursor;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => const [
    FullAccessOnlyCliLaunchSecurityCapability(),
  ];
}
