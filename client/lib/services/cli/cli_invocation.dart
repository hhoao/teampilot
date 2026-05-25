import 'dart:io';

class CliInvocation {
  const CliInvocation({
    required this.executable,
    this.prefixArgs = const [],
    this.usesWsl = false,
  });

  final String executable;
  final List<String> prefixArgs;
  final bool usesWsl;

  List<String> withArgs(List<String> args, {Map<String, String>? environment}) {
    final commandArgs = [...prefixArgs, ...args];
    if (!usesWsl || environment == null || environment.isEmpty) {
      return commandArgs;
    }
    return _addWslEnvironment(commandArgs, environment);
  }

  static CliInvocation fromExecutable(String value) {
    final parts = splitCommand(value.trim());
    if (parts.isEmpty) {
      return const CliInvocation(executable: 'flashskyai');
    }

    final executable = parts.first;
    final wslUncExecutable = Platform.isWindows
        ? _wslUncPathToLinux(executable)
        : null;
    if (wslUncExecutable != null) {
      return CliInvocation(
        executable: 'wsl.exe',
        prefixArgs: [wslUncExecutable, ...parts.skip(1)],
        usesWsl: true,
      );
    }

    final executableName = executable
        .split(RegExp(r'[\\/]'))
        .last
        .toLowerCase();
    final usesWsl =
        Platform.isWindows &&
        (executableName == 'wsl' || executableName == 'wsl.exe');

    return CliInvocation(
      executable: executable,
      prefixArgs: parts.skip(1).toList(growable: false),
      usesWsl: usesWsl,
    );
  }

  static List<String> _addWslEnvironment(
    List<String> args,
    Map<String, String> environment,
  ) {
    final envArgs = [
      'env',
      ...environment.entries.map((e) => '${e.key}=${e.value}'),
    ];
    return [...envArgs, ...args];
  }

  static String? _wslUncPathToLinux(String path) {
    final normalized = path.replaceAll('/', r'\');
    final match = RegExp(
      r'^\\+(?:wsl\.localhost|wsl\$)\\[^\\]+\\(.+)$',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (match == null) return null;
    return '/${match.group(1)!.replaceAll(r'\', '/')}';
  }

  static List<String> splitCommand(String input) {
    final args = <String>[];
    final buffer = StringBuffer();
    String? quote;
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (char == r'\') {
        final next = i + 1 < input.length ? input[i + 1] : '';
        if (next.isNotEmpty &&
            (next == '"' ||
                next == "'" ||
                next == r'\' ||
                next.trim().isEmpty)) {
          buffer.write(next);
          i++;
        } else {
          buffer.write(char);
        }
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

    if (buffer.isNotEmpty) {
      args.add(buffer.toString());
    }
    return args;
  }
}
