import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/opencode/capabilities/agent_launch.dart';
import 'package:teampilot/services/cli/opencode/capabilities/model_launch.dart';
import 'package:teampilot/services/cli/opencode/capabilities/permission_launch.dart';
import 'package:teampilot/services/cli/opencode/capabilities/session_selection_launch.dart';
import 'package:teampilot/services/cli/opencode/capabilities/team_behavior.dart';
import 'package:teampilot/services/cli/opencode/capabilities/user_extra_args_launch.dart';
import 'package:teampilot/services/cli/opencode/opencode_tool.dart';
import 'package:teampilot/services/cli/registry/capabilities/team_behavior_capability.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/cli_tool_registry.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_assembler.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_provider.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_capability_error.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';
import 'package:teampilot/services/session/launch_command_builder.dart';

void main() {
  test('assembles OpenCode session, provider/model, agent, and raw extras', () {
    expect(
      _assemble(
        team: const TeamProfile(
          id: 'team',
          name: 'Team',
          cli: CliTool.opencode,
          extraArgs: '--team-flag "team value"',
        ),
        member: const TeamMemberConfig(
          id: 'member',
          name: 'Member',
          provider: ' anthropic ',
          model: ' claude-sonnet-4 ',
          agent: ' build ',
          extraArgs: "--member-flag 'member value'",
        ),
        workingDirectory: '/work',
        additionalDirectories: const ['/repo/a', '/repo/b'],
        resumeSessionId: 'session-1',
      ),
      [
        '--session',
        'session-1',
        '--model',
        'anthropic/claude-sonnet-4',
        '--agent',
        'build',
        '--team-flag',
        'team value',
        '--member-flag',
        'member value',
      ],
    );
  });

  test('OpenCode omits absent session and agent and supports bare models', () {
    expect(
      _assemble(
        team: const TeamProfile(
          id: 'team',
          name: 'Team',
          cli: CliTool.opencode,
        ),
        member: const TeamMemberConfig(
          id: 'member',
          name: 'Member',
          model: 'gpt-5',
        ),
      ),
      ['--model', 'gpt-5'],
    );
  });

  test('OpenCode rejects a provider without a model', () {
    expect(
      () => _assemble(
        team: const TeamProfile(
          id: 'team',
          name: 'Team',
          cli: CliTool.opencode,
        ),
        member: const TeamMemberConfig(
          id: 'member',
          name: 'Member',
          provider: 'anthropic',
        ),
      ),
      throwsA(
        isA<CliLaunchCapabilityException>().having(
          (error) => error.cli,
          'cli',
          CliTool.opencode,
        ),
      ),
    );
  });

  test('OpenCode rejects fixed session ids instead of dropping them', () {
    expect(
      () => _assemble(
        team: const TeamProfile(
          id: 'team',
          name: 'Team',
          cli: CliTool.opencode,
        ),
        member: const TeamMemberConfig(id: 'member', name: 'Member'),
        fixedSessionId: 'fixed-session',
      ),
      throwsA(
        isA<CliLaunchCapabilityException>().having(
          (error) => error.cli,
          'cli',
          CliTool.opencode,
        ),
      ),
    );
  });

  test('OpenCode rejects security policies it cannot represent', () {
    expect(
      () => _assemble(
        team: const TeamProfile(
          id: 'team',
          name: 'Team',
          cli: CliTool.opencode,
        ),
        member: const TeamMemberConfig(
          id: 'member',
          name: 'Member',
          launchSecurityPolicy: LaunchSecurityPolicy.askReadOnlyTrusted,
        ),
      ),
      throwsA(
        isA<CliLaunchCapabilityException>()
            .having((error) => error.cli, 'cli', CliTool.opencode)
            .having(
              (error) => error.contributionKey,
              'contributionKey',
              'opencode-permission',
            ),
      ),
    );
  });

  test('OpenCode explicitly accepts its permissive full-access default', () {
    expect(
      _assemble(
        team: const TeamProfile(
          id: 'team',
          name: 'Team',
          cli: CliTool.opencode,
        ),
        member: const TeamMemberConfig(
          id: 'member',
          name: 'Member',
          launchSecurityPolicy: LaunchSecurityPolicy.fullAccess,
        ),
      ),
      isEmpty,
    );
  });

  test(
    'OpenCode registers session/model/agent/user providers, not workspace',
    () {
      final tool = OpencodeCliTool();
      final providers = tool.capabilities.whereType<CliLaunchArgProvider>();

      expect(providers, contains(isA<OpencodeSessionSelectionLaunch>()));
      expect(providers, contains(isA<OpencodeModelLaunch>()));
      expect(providers, contains(isA<OpencodeAgentLaunch>()));
      expect(providers, contains(isA<OpencodeUserExtraArgsLaunch>()));
      expect(providers, contains(isA<OpencodePermissionLaunch>()));
      expect(providers, hasLength(5));
      expect(tool.capabilities.whereType<OpencodeTeamBehavior>(), hasLength(1));
      expect(
        tool.capabilities.whereType<TeamBehaviorCapability>(),
        hasLength(1),
      );
    },
  );

  test('OpenCode launch rejects a tool without launch providers', () {
    final context = CliLaunchContext(
      team: const TeamProfile(id: 'team', name: 'Team', cli: CliTool.opencode),
      member: const TeamMemberConfig(id: 'member', name: 'Member'),
      nativeAgentTeam: false,
    );

    expect(
      () => LaunchCommandBuilder.buildArgumentsFromContext(
        context,
        cliRegistry: _registryWithEmptyOpencodeTool(),
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
}) {
  return const CliLaunchArgAssembler().assemble(
    OpencodeCliTool(),
    CliLaunchContext(
      team: team,
      member: member,
      workingDirectory: workingDirectory,
      additionalDirectories: additionalDirectories,
      fixedSessionId: fixedSessionId,
      resumeSessionId: resumeSessionId,
    ),
  );
}

CliToolRegistry _registryWithEmptyOpencodeTool() {
  final registry = CliToolRegistry();
  registry.register(_EmptyOpencodeTool());
  return registry;
}

final class _EmptyOpencodeTool implements CliToolDefinition {
  @override
  CliTool get id => CliTool.opencode;

  @override
  bool get isLaunchSupported => true;

  @override
  Iterable<CliCapability> get capabilities => const [];
}
