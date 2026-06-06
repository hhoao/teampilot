import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_tool_adapter.dart';

void main() {
  const team = TeamConfig(id: 't', name: 'agent', cli: CliTool.cursor);

  test('fresh launch: --workspace, --model, --force, identity prompt last', () {
    const member = TeamMemberConfig(
      id: 'm',
      name: 'planner',
      model: 'gpt-5.2',
      prompt: 'You are the planner.',
      dangerouslySkipPermissions: true,
    );
    final args = const CursorCliToolAdapter().buildArguments(
      CliLaunchContext(
        team: team,
        member: member,
        workingDirectory: '/work',
      ),
    );

    expect(args, [
      '--workspace',
      '/work',
      '--model',
      'gpt-5.2',
      '--force',
      'You are the planner.',
    ]);
  });

  test('resume: uses --resume and does NOT re-seed the identity prompt', () {
    const member = TeamMemberConfig(
      id: 'm',
      name: 'planner',
      model: 'gpt-5.2',
      prompt: 'You are the planner.',
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

  test('emits nothing when no workspace/model/prompt and not resuming', () {
    const member = TeamMemberConfig(id: 'm', name: 'planner');
    final args = const CursorCliToolAdapter().buildArguments(
      CliLaunchContext(team: team, member: member),
    );

    expect(args, isEmpty);
  });

  test('mixed: no plugin-dir, identity NOT seeded as initial prompt', () {
    const mixedTeam = TeamConfig(
      id: 't',
      name: 'agent',
      cli: CliTool.cursor,
      teamMode: TeamMode.mixed,
    );
    const member = TeamMemberConfig(
      id: 'm',
      name: 'planner',
      model: 'gpt-5.2',
      prompt: 'You are the planner.',
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
