import '../../../../models/team_config.dart';
import '../../cli_tool_adapter.dart';

final class FlashskyaiCliToolAdapter implements CliToolAdapter {
  const FlashskyaiCliToolAdapter();

  @override
  List<String> buildArguments(CliLaunchContext context) {
    final args = <String>[
      ...buildSessionPrefixArgs(context),
      if (context.usesNativeAgentTeam) ...[
        '--team',
        context.teamName,
        '--member',
        context.memberCliId,
      ],
      if (context.nativeAgentTeam == false) ...[
        '--disallowedTools',
        'Agent',
      ],
    ];

    final loop = context.team.loop;
    if (context.usesNativeAgentTeam && loop != null) {
      args.addAll(['--loop', loop ? 'true' : 'false']);
    }

    final member = context.member;
    if (member.provider.trim().isNotEmpty) {
      args.addAll(['--provider', member.provider.trim()]);
    }
    if (member.model.trim().isNotEmpty) {
      args.addAll(['--model', member.model.trim()]);
    }
    if (member.agent.trim().isNotEmpty) {
      args.addAll(['--agent', member.agent.trim()]);
    }
    if (member.dangerouslySkipPermissions) {
      args.add('--dangerously-skip-permissions');
    }
    addExtraArgs(args, context.team.extraArgs);
    addExtraArgs(args, member.extraArgs);

    final appendFile = context.appendSystemPromptFile?.trim() ?? '';
    if (appendFile.isNotEmpty) {
      args.addAll(['--append-system-prompt-file', appendFile]);
    }

    return args;
  }
}
