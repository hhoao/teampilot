import '../../../../models/team_config.dart';
import '../../../../utils/team/team_member_naming.dart';
import '../../../session/member_role_provision.dart';
import '../../cli_tool_adapter.dart';
import '../../registry/launch/cli_launch_context.dart';

final class ClaudeCodeCliToolAdapter implements CliToolAdapter {
  const ClaudeCodeCliToolAdapter();

  @override
  List<String> buildArguments(CliLaunchContext context) {
    final member = context.member;
    final mixed = context.team.teamMode == TeamMode.mixed;
    final args = <String>[
      ...buildSessionPrefixArgs(context, includeWorkingDirectory: false),
      if (context.usesNativeAgentTeam) ...[
        '--team-name',
        context.teamName,
        '--agent-name',
        context.memberCliId,
        '--agent-id',
        TeamMemberNaming.cliAgentId(
          memberId: context.memberCliId,
          cliTeamName: context.teamName,
        ),
      ],
      if (context.nativeAgentTeam == false) ...['--disallowedTools', 'Agent'],
    ];

    if (mixed) {
      final denied = MemberRoleProvision.disallowedToolsForMixedClaude(
        isLead: TeamMemberNaming.isTeamLead(member),
      );
      args.addAll(['--disallowedTools', ...denied]);
    }

    if (member.model.trim().isNotEmpty) {
      args.addAll(['--model', member.model.trim()]);
    }
    final settings = context.settingsPath?.trim() ?? '';
    if (settings.isNotEmpty) {
      args.addAll(['--settings', settings]);
    }
    final appendFile = context.appendSystemPromptFile?.trim() ?? '';
    if (appendFile.isNotEmpty) {
      args.addAll(['--append-system-prompt-file', appendFile]);
    }
    if (context.launchSecurityPolicy.requiresDangerousExecution) {
      args.add('--dangerously-skip-permissions');
    }
    addExtraArgs(args, context.team.extraArgs);
    addExtraArgs(args, member.extraArgs);

    return args;
  }
}
