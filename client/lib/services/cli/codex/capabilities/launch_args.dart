import '../../../../models/team_config.dart';
import '../../cli_tool_adapter.dart';

final class CodexCliToolAdapter implements CliToolAdapter {
  const CodexCliToolAdapter();

  @override
  List<String> buildArguments(CliLaunchContext context) {
    final member = context.member;
    final args = <String>[];

    final resume = context.resumeSessionId?.trim() ?? '';
    final fixed = context.fixedSessionId?.trim() ?? '';
    if (resume.isNotEmpty) {
      args.addAll(['resume', resume]);
    } else if (fixed.isNotEmpty) {
      args.addAll(['resume', fixed]);
    }

    final wd = context.workingDirectory?.trim() ?? '';
    if (wd.isNotEmpty) {
      args.addAll(['--cd', normalizePathForCli(wd, context.useWslPaths)]);
    }

    final model = member.model.trim();
    if (model.isNotEmpty) {
      args.addAll(['-m', model]);
    }

    if (member.dangerouslySkipPermissions) {
      args.add('--dangerously-bypass-approvals-and-sandbox');
    }

    addExtraArgs(args, context.team.extraArgs);
    addExtraArgs(args, member.extraArgs);

    return args;
  }
}
