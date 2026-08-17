import 'cli_launch_arg_contribution.dart';
import 'cli_launch_arg_provider.dart';
import 'cli_launch_context.dart';

/// Emits the user-controlled team and member argument escape hatches last.
final class UserExtraArgsProvider implements CliLaunchArgProvider {
  const UserExtraArgsProvider();

  @override
  Iterable<CliLaunchArgContribution> buildLaunchArgs(
    CliLaunchContext context,
  ) sync* {
    final teamArgs = splitArgs(context.team.extraArgs);
    if (teamArgs.isNotEmpty) {
      yield CliLaunchArgContribution(
        key: 'user-extra-args.team',
        phase: LaunchArgPhase.user,
        args: teamArgs,
      );
    }

    final memberArgs = splitArgs(context.member.extraArgs);
    if (memberArgs.isNotEmpty) {
      yield CliLaunchArgContribution(
        key: 'user-extra-args.member',
        phase: LaunchArgPhase.user,
        args: memberArgs,
      );
    }
  }
}

/// Splits shell-like user input into raw argv tokens without shell quoting.
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
