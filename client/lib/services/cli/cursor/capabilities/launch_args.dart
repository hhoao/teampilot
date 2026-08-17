import '../../../../models/team_config.dart';
import '../../cli_tool_adapter.dart';
import '../../registry/launch/cli_launch_context.dart';

final class CursorCliToolAdapter implements CliToolAdapter {
  const CursorCliToolAdapter();

  @override
  List<String> buildArguments(CliLaunchContext context) {
    final member = context.member;
    final mixed = context.team.teamMode == TeamMode.mixed;
    final args = <String>[];

    final wd = context.workingDirectory?.trim() ?? '';
    if (wd.isNotEmpty) {
      args.addAll([
        '--workspace',
        normalizePathForCli(wd, useWslPaths: context.useWslPaths),
      ]);
    }

    final resume = context.resumeSessionId?.trim() ?? '';
    if (resume.isNotEmpty) {
      args.addAll(['--resume', resume]);
    }

    for (final path in context.additionalDirectories) {
      final trimmed = path.trim();
      if (trimmed.isNotEmpty) {
        args.addAll([
          '--add-dir',
          normalizePathForCli(trimmed, useWslPaths: context.useWslPaths),
        ]);
      }
    }

    final model = member.model.trim();
    if (model.isNotEmpty) {
      args.addAll(['--model', model]);
    }

    if (mixed) {
      args.add('--approve-mcps');
    }

    if (member.dangerouslySkipPermissions) {
      args.add('--force');
    }

    addExtraArgs(args, context.team.extraArgs);
    addExtraArgs(args, member.extraArgs);

    return args;
  }
}
