import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_tool_adapter.dart';

void main() {
  const team = TeamProfile(
    id: 't',
    name: 'team',
    cli: CliTool.codex,
    members: [TeamMemberConfig(id: 'm', name: 'planner')],
  );
  const member = TeamMemberConfig(
    id: 'm',
    name: 'planner',
    model: 'gpt-5.2',
    dangerouslySkipPermissions: false,
  );

  test('fresh launch: --cd + -m, no resume subcommand', () {
    final args = const CodexCliToolAdapter().buildArguments(
      CliLaunchContext(team: team, member: member, workingDirectory: '/work'),
    );
    expect(args, ['--cd', '/work', '-m', 'gpt-5.2']);
  });

  test('resume: leads argv with the `resume <id>` subcommand', () {
    final args = const CodexCliToolAdapter().buildArguments(
      CliLaunchContext(
        team: team,
        member: member,
        workingDirectory: '/work',
        resumeSessionId: 'sess-42',
        isFreshConversation: false,
      ),
    );
    expect(args, ['resume', 'sess-42', '--cd', '/work', '-m', 'gpt-5.2']);
  });
}
