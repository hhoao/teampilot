import 'package:teampilot/models/launch_security_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/codex/capabilities/launch_args.dart';
import 'package:teampilot/services/cli/registry/launch/cli_launch_context.dart';

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
    launchSecurityPolicy: LaunchSecurityPolicy.fullAccess,
  );

  test('fresh launch: --cd + -m, no resume subcommand', () {
    final args = const CodexCliToolAdapter().buildArguments(
      CliLaunchContext(
        team: team,
        member: member,
        launchSecurityPolicy: member.launchSecurityPolicy,
        workingDirectory: '/work',
      ),
    );
    expect(args, [
      '--cd',
      '/work',
      '-m',
      'gpt-5.2',
      '--dangerously-bypass-approvals-and-sandbox',
      '--dangerously-bypass-hook-trust',
    ]);
  });

  test('resume: leads argv with the `resume <id>` subcommand', () {
    final args = const CodexCliToolAdapter().buildArguments(
      CliLaunchContext(
        team: team,
        member: member,
        launchSecurityPolicy: member.launchSecurityPolicy,
        workingDirectory: '/work',
        resumeSessionId: 'sess-42',
      ),
    );
    expect(args, [
      'resume',
      'sess-42',
      '--cd',
      '/work',
      '-m',
      'gpt-5.2',
      '--dangerously-bypass-approvals-and-sandbox',
      '--dangerously-bypass-hook-trust',
    ]);
  });
}
