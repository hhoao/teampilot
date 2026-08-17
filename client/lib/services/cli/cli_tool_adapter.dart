import 'registry/launch/cli_launch_context.dart';
import 'registry/launch/user_extra_args_provider.dart';

abstract interface class CliToolAdapter {
  List<String> buildArguments(CliLaunchContext context);
}

List<String> buildSessionPrefixArgs(
  CliLaunchContext context, {
  bool includeWorkingDirectory = true,
}) {
  final args = <String>[];
  final resume = context.resumeSessionId?.trim() ?? '';
  final fixed = context.fixedSessionId?.trim() ?? '';
  if (resume.isNotEmpty) {
    args.addAll(['--resume', resume]);
  } else if (fixed.isNotEmpty) {
    args.addAll(['--session-id', fixed]);
  }
  final wd = context.workingDirectory ?? '';
  if (includeWorkingDirectory && wd.isNotEmpty) {
    args.addAll([
      '--dir',
      normalizePathForCli(wd, useWslPaths: context.useWslPaths),
    ]);
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
  return args;
}

void addExtraArgs(List<String> args, String raw) {
  final trimmed = raw.trim();
  if (trimmed.isNotEmpty) {
    args.addAll(splitArgs(trimmed));
  }
}
