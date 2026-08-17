import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_assembler.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_contribution.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_provider.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';
import 'package:teampilot/services/cli/registry/launch/user_extra_args_provider.dart';

void main() {
  final context = CliLaunchContext(
    team: TeamProfile(
      id: 'team',
      name: 'Team',
      extraArgs: '--team-flag "team value"',
    ),
    member: TeamMemberConfig(
      id: 'member',
      name: 'Member',
      extraArgs: r"--member-flag 'member value' --literal=two\ words",
    ),
  );

  test('emits team extra args before member extra args in user phase', () {
    final contributions = const UserExtraArgsProvider()
        .buildLaunchArgs(context)
        .toList();

    expect(contributions.map((contribution) => contribution.key), [
      'user-extra-args.team',
      'user-extra-args.member',
    ]);
    expect(contributions.map((contribution) => contribution.phase), [
      LaunchArgPhase.user,
      LaunchArgPhase.user,
    ]);
    expect(contributions.expand((contribution) => contribution.args), [
      '--team-flag',
      'team value',
      '--member-flag',
      'member value',
      r'--literal=two words',
    ]);
  });

  test('filters blank extra args without adding empty contributions', () {
    final blankContext = CliLaunchContext(
      team: TeamProfile(id: 'team', name: 'Team', extraArgs: '  '),
      member: TeamMemberConfig(id: 'member', name: 'Member', extraArgs: ''),
    );

    expect(
      const UserExtraArgsProvider().buildLaunchArgs(blankContext),
      isEmpty,
    );
  });

  test('assembler preserves raw token boundaries and user phase ordering', () {
    final tool = _FakeCliTool([
      const UserExtraArgsProvider(),
      _EarlierProvider(),
    ]);

    expect(const CliLaunchArgAssembler().assemble(tool, context), [
      '--built-in',
      '--team-flag',
      'team value',
      '--member-flag',
      'member value',
      r'--literal=two words',
    ]);
  });
}

final class _FakeCliTool implements CliToolDefinition {
  _FakeCliTool(this.capabilities);

  @override
  final List<CliCapability> capabilities;

  @override
  CliTool get id => CliTool.claude;

  @override
  bool get isLaunchSupported => true;
}

final class _EarlierProvider implements CliLaunchArgProvider {
  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(CliLaunchContext context) {
    return [
      CliLaunchArgContribution(
        key: 'built-in',
        phase: LaunchArgPhase.behavior,
        args: ['--built-in'],
      ),
    ];
  }
}
