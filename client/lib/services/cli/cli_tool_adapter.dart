import 'registry/launch/cli_launch_context.dart';

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

List<String> splitArgs(String input) {
  final args = <String>[];
  final buffer = StringBuffer();
  String? quote;
  var escaping = false;

  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    if (escaping) {
      buffer.write(char);
      escaping = false;
      continue;
    }
    if (char == r'\') {
      escaping = true;
      continue;
    }
    if (quote != null) {
      if (char == quote) {
        quote = null;
      } else {
        buffer.write(char);
      }
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char.trim().isEmpty) {
      if (buffer.isNotEmpty) {
        args.add(buffer.toString());
        buffer.clear();
      }
      continue;
    }
    buffer.write(char);
  }

  if (escaping) {
    buffer.write(r'\');
  }
  if (buffer.isNotEmpty) {
    args.add(buffer.toString());
  }
  return args;
}
