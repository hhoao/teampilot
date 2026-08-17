import 'package:teampilot/models/launch_security_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cursor/capabilities/launch_args.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';

void main() {
  const team = TeamProfile(id: 't', name: 'agent', cli: CliTool.cursor);

  test('fresh launch: --workspace, --model, --force; no identity prompt', () {
    const member = TeamMemberConfig(
      id: 'm',
      name: 'planner',
      model: 'gpt-5.2',
      responsibilities: 'You are the planner.',
      launchSecurityPolicy: LaunchSecurityPolicy.fullAccess,
    );
    final args = const CursorCliToolAdapter().buildArguments(
      CliLaunchContext(
        team: team,
        member: member,
        launchSecurityPolicy: member.launchSecurityPolicy,
        workingDirectory: '/work',
      ),
    );

    expect(args, ['--workspace', '/work', '--model', 'gpt-5.2', '--force']);
    expect(args, isNot(contains('You are the planner.')));
  });

  test('resume: uses --resume without identity prompt', () {
    const member = TeamMemberConfig(
      id: 'm',
      name: 'planner',
      model: 'gpt-5.2',
      responsibilities: 'You are the planner.',
      launchSecurityPolicy: const LaunchSecurityPolicy(),
    );
    final args = const CursorCliToolAdapter().buildArguments(
      CliLaunchContext(
        team: team,
        member: member,
        workingDirectory: '/work',
        resumeSessionId: 'chat-1',
      ),
    );

    expect(args, [
      '--workspace',
      '/work',
      '--resume',
      'chat-1',
      '--model',
      'gpt-5.2',
    ]);
  });

  test('emits nothing when no workspace/model and not resuming', () {
    const member = TeamMemberConfig(
      id: 'm',
      name: 'planner',
      launchSecurityPolicy: const LaunchSecurityPolicy(),
    );
    final args = const CursorCliToolAdapter().buildArguments(
      CliLaunchContext(team: team, member: member),
    );

    expect(args, isEmpty);
  });

  test('mixed: --approve-mcps, no plugin-dir, no identity prompt', () {
    const mixedTeam = TeamProfile(
      id: 't',
      name: 'agent',
      cli: CliTool.cursor,
      teamMode: TeamMode.mixed,
    );
    const member = TeamMemberConfig(
      id: 'm',
      name: 'planner',
      model: 'gpt-5.2',
      responsibilities: 'You are the planner.',
      launchSecurityPolicy: const LaunchSecurityPolicy(),
    );
    final args = const CursorCliToolAdapter().buildArguments(
      CliLaunchContext(
        team: mixedTeam,
        member: member,
        workingDirectory: '/work',
      ),
    );

    expect(args, [
      '--workspace',
      '/work',
      '--model',
      'gpt-5.2',
      '--approve-mcps',
    ]);
    expect(args, isNot(contains('--plugin-dir')));
    expect(args, isNot(contains('You are the planner.')));
  });
}
