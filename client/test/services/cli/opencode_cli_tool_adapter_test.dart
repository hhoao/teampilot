import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_tool_adapter.dart';

void main() {
  const team = TeamConfig(id: 't', name: 'agent', cli: TeamCli.opencode);

  test('builds --model provider/model, --agent, and --session on resume', () {
    const member = TeamMemberConfig(
      id: 'm',
      name: 'planner',
      provider: 'anthropic',
      model: 'claude-sonnet-4',
      agent: 'build',
    );
    final args = const OpencodeCliToolAdapter().buildArguments(
      CliLaunchContext(
        team: team,
        member: member,
        workingDirectory: '/work',
        resumeSessionId: 'sess-1',
      ),
    );

    expect(args, [
      '--session',
      'sess-1',
      '--model',
      'anthropic/claude-sonnet-4',
      '--agent',
      'build',
    ]);
  });

  test('omits --session and --agent when absent; bare model has no provider', () {
    const member = TeamMemberConfig(
      id: 'm',
      name: 'planner',
      provider: '',
      model: 'gpt-5',
      agent: '',
    );
    final args = const OpencodeCliToolAdapter().buildArguments(
      CliLaunchContext(team: team, member: member, workingDirectory: '/work'),
    );

    expect(args, ['--model', 'gpt-5']);
  });

  test('emits nothing when no model/agent/resume', () {
    const member = TeamMemberConfig(id: 'm', name: 'planner');
    final args = const OpencodeCliToolAdapter().buildArguments(
      CliLaunchContext(team: team, member: member),
    );

    expect(args, isEmpty);
  });
}
