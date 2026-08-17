import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_tool_adapter.dart';
import 'package:teampilot/services/cli/registry/cli_capability.dart';
import 'package:teampilot/services/cli/registry/cli_tool_definition.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_assembler.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_contribution.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_arg_provider.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_capability_error.dart';

void main() {
  const assembler = CliLaunchArgAssembler();
  final context = CliLaunchContext(
    team: TeamProfile(id: 'team', name: 'Team'),
    member: TeamMemberConfig(id: 'member', name: 'Member'),
  );

  test('assembles contributions by phase and stable provider order', () {
    final tool = FakeCliTool([
      FakeLaunchProvider(
        CliLaunchArgContribution(
          key: 'model',
          phase: LaunchArgPhase.model,
          args: ['--model', 'x'],
        ),
      ),
      FakeLaunchProvider(
        CliLaunchArgContribution(
          key: 'session-a',
          phase: LaunchArgPhase.session,
          args: ['--resume', 'a'],
        ),
      ),
      FakeLaunchProvider(
        CliLaunchArgContribution(
          key: 'session-b',
          phase: LaunchArgPhase.session,
          args: ['--resume', 'b'],
        ),
      ),
    ]);

    expect(assembler.assemble(tool, context), [
      '--resume',
      'a',
      '--resume',
      'b',
      '--model',
      'x',
    ]);
  });

  test('rejects duplicate contribution keys', () {
    final tool = FakeCliTool([
      FakeLaunchProvider(
        CliLaunchArgContribution(
          key: 'session',
          phase: LaunchArgPhase.session,
          args: ['--resume', 'a'],
        ),
      ),
      FakeLaunchProvider(
        CliLaunchArgContribution(
          key: 'session',
          phase: LaunchArgPhase.session,
          args: ['--resume', 'b'],
        ),
      ),
    ]);

    expect(
      () => assembler.assemble(tool, context),
      throwsA(
        isA<CliLaunchCapabilityException>().having(
          (error) => error.contributionKey,
          'contributionKey',
          'session',
        ),
      ),
    );
  });

  test('rejects contributions in the same exclusive group', () {
    final tool = FakeCliTool([
      FakeLaunchProvider(
        CliLaunchArgContribution(
          key: 'resume',
          phase: LaunchArgPhase.session,
          args: ['--resume', 'a'],
          exclusiveGroup: 'session-selection',
        ),
      ),
      FakeLaunchProvider(
        CliLaunchArgContribution(
          key: 'fixed-session',
          phase: LaunchArgPhase.session,
          args: ['--session-id', 'b'],
          exclusiveGroup: 'session-selection',
        ),
      ),
    ]);

    expect(
      () => assembler.assemble(tool, context),
      throwsA(
        isA<CliLaunchCapabilityException>()
            .having(
              (error) => error.exclusiveGroup,
              'exclusiveGroup',
              'session-selection',
            )
            .having(
              (error) => error.conflictingContributionKey,
              'conflictingContributionKey',
              'resume',
            ),
      ),
    );
  });

  test('preserves intra-provider order across a non-provider capability', () {
    final tool = FakeCliTool([
      MultiLaunchProvider([
        CliLaunchArgContribution(
          key: 'first',
          phase: LaunchArgPhase.behavior,
          args: ['--first'],
        ),
        CliLaunchArgContribution(
          key: 'second',
          phase: LaunchArgPhase.behavior,
          args: ['--second'],
        ),
      ]),
      OtherCapability(),
      FakeLaunchProvider(
        CliLaunchArgContribution(
          key: 'third',
          phase: LaunchArgPhase.behavior,
          args: ['--third'],
        ),
      ),
    ]);

    expect(assembler.assemble(tool, context), [
      '--first',
      '--second',
      '--third',
    ]);
  });

  test('ignores providers with no contributions', () {
    final tool = FakeCliTool([
      FakeLaunchProvider(),
      FakeLaunchProvider(
        CliLaunchArgContribution(
          key: 'prompt',
          phase: LaunchArgPhase.prompt,
          args: ['hello'],
        ),
      ),
    ]);

    expect(assembler.assemble(tool, context), ['hello']);
  });

  test('flattens contribution tokens without shell quoting', () {
    final tool = FakeCliTool([
      FakeLaunchProvider(
        CliLaunchArgContribution(
          key: 'raw',
          phase: LaunchArgPhase.user,
          args: ['--message', 'two words', '"quoted"', ''],
        ),
      ),
    ]);

    expect(assembler.assemble(tool, context), [
      '--message',
      'two words',
      '"quoted"',
      '',
    ]);
  });

  test('contributions compare by value and expose immutable args', () {
    final first = CliLaunchArgContribution(
      key: 'model',
      phase: LaunchArgPhase.model,
      args: ['--model', 'x'],
    );
    final second = CliLaunchArgContribution(
      key: 'model',
      phase: LaunchArgPhase.model,
      args: ['--model', 'x'],
    );

    expect(first, second);
    expect(() => first.args.add('extra'), throwsUnsupportedError);
  });

  test('defensively copies caller args at construction', () {
    final originalArgs = ['--model', 'before'];
    final contribution = CliLaunchArgContribution(
      key: 'model',
      phase: LaunchArgPhase.model,
      args: originalArgs,
    );
    final expected = CliLaunchArgContribution(
      key: 'model',
      phase: LaunchArgPhase.model,
      args: ['--model', 'before'],
    );
    final tool = FakeCliTool([FakeLaunchProvider(contribution)]);
    final hashCodeBeforeMutation = contribution.hashCode;

    originalArgs[1] = 'after';
    originalArgs.add('--changed');

    expect(contribution, expected);
    expect(contribution.hashCode, hashCodeBeforeMutation);
    expect(contribution.args, ['--model', 'before']);
    expect(assembler.assemble(tool, context), ['--model', 'before']);
  });
}

final class FakeCliTool implements CliToolDefinition {
  FakeCliTool(this.capabilities);

  @override
  final List<CliCapability> capabilities;

  @override
  CliTool get id => CliTool.claude;

  @override
  bool get isLaunchSupported => true;
}

final class FakeLaunchProvider implements CliLaunchArgProvider {
  FakeLaunchProvider([this.contribution]);

  final CliLaunchArgContribution? contribution;

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  ) sync* {
    if (contribution != null) yield contribution!;
  }
}

final class MultiLaunchProvider implements CliLaunchArgProvider {
  MultiLaunchProvider(this.contributions);

  final List<CliLaunchArgContribution> contributions;

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  ) => contributions;
}

final class OtherCapability implements CliCapability {}
