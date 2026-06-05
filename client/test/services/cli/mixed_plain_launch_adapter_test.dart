import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/models/team_config.dart';
import 'package:teampilot/services/cli/cli_tool_adapter.dart';

void main() {
  const member = TeamMemberConfig(id: 'm', name: 'p', model: 'sonnet');

  group('claude adapter', () {
    test('native keeps team flags', () {
      const team = TeamConfig(id: 't', name: 'agent', cli: CliTool.claude);
      final args = const ClaudeCodeCliToolAdapter().buildArguments(
        CliLaunchContext(team: team, member: member),
      );
      expect(args, contains('--team-name'));
      expect(args, contains('--agent-name'));
      expect(args, contains('--agent-id'));
    });

    test('mixed drops all team flags, keeps model', () {
      const team = TeamConfig(
        id: 't',
        name: 'agent',
        cli: CliTool.claude,
        teamMode: TeamMode.mixed,
      );
      final args = const ClaudeCodeCliToolAdapter().buildArguments(
        CliLaunchContext(team: team, member: member),
      );
      expect(args, isNot(contains('--team-name')));
      expect(args, isNot(contains('--agent-name')));
      expect(args, isNot(contains('--agent-id')));
      expect(args, containsAllInOrder(['--model', 'sonnet']));
    });
  });

  group('flashskyai adapter', () {
    test('native keeps --team/--member', () {
      const team = TeamConfig(id: 't', name: 'agent', cli: CliTool.flashskyai);
      final args = const FlashskyaiCliToolAdapter().buildArguments(
        CliLaunchContext(team: team, member: member),
      );
      expect(args, contains('--team'));
      expect(args, contains('--member'));
    });

    test('mixed drops --team/--member/--loop, keeps model', () {
      const team = TeamConfig(
        id: 't',
        name: 'agent',
        cli: CliTool.flashskyai,
        teamMode: TeamMode.mixed,
        loop: true,
      );
      final args = const FlashskyaiCliToolAdapter().buildArguments(
        CliLaunchContext(team: team, member: member),
      );
      expect(args, isNot(contains('--team')));
      expect(args, isNot(contains('--member')));
      expect(args, isNot(contains('--loop')));
      expect(args, containsAllInOrder(['--model', 'sonnet']));
    });
  });
}
