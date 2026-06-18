import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_tool_adapter.dart';
import 'package:teampilot/services/session/member_role_provision.dart';

void main() {
  const team = TeamIdentity(id: 't', name: 'agent', cli: CliTool.cursor);

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
      MemberRoleProvision.composeRolePrompt(member: member).trim(),
    ]);
  });

  test('resume: uses --resume and does NOT re-seed the identity prompt', () {
    const member = TeamMemberConfig(
      id: 'm',
      name: 'planner',
      model: 'gpt-5.2',
      prompt: 'You are the planner.',
      dangerouslySkipPermissions: false,
    );
    final args = const CursorCliToolAdapter().buildArguments(
      CliLaunchContext(
        team: team,
        member: member,
        workingDirectory: '/work',
        resumeSessionId: 'chat-1',
        // Resuming a chat that already has history: identity already lives in
        // the conversation, so it must not be re-seeded.
        isFreshConversation: false,
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
    const member = TeamMemberConfig(id: 'm', name: 'planner', dangerouslySkipPermissions: false);
    final args = const CursorCliToolAdapter().buildArguments(
      CliLaunchContext(team: team, member: member),
    );

    expect(args, isEmpty);
  });

  test('mixed: no plugin-dir, identity NOT seeded as initial prompt', () {
    const mixedTeam = TeamIdentity(
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
      dangerouslySkipPermissions: false,
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
