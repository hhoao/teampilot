import 'dart:async';
import 'dart:io';

import '../models/team_config.dart';
import 'cli_invocation.dart';

typedef ProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      bool runInShell,
      Map<String, String>? environment,
      bool includeParentEnvironment,
    });

class LaunchCommandBuilder {
  const LaunchCommandBuilder._();

  /// CLI flags for `--resume` / `--session-id`, `--dir`, and repeated `--add-dir`.
  /// When [resumeSessionId] is non-empty, `--resume` wins over [fixedSessionId].
  static List<String> buildSessionPrefixArgs({
    String? workingDirectory,
    List<String> additionalDirectories = const [],
    String? fixedSessionId,
    String? resumeSessionId,
    bool useWslPaths = false,
  }) {
    final args = <String>[];
    final resume = resumeSessionId?.trim() ?? '';
    final fixed = fixedSessionId?.trim() ?? '';
    if (resume.isNotEmpty) {
      args.addAll(['--resume', resume]);
    } else if (fixed.isNotEmpty) {
      args.addAll(['--session-id', fixed]);
    }
    final wd = workingDirectory ?? '';
    if (wd.isNotEmpty) {
      args.addAll(['--dir', normalizePathForCli(wd, useWslPaths: useWslPaths)]);
    }
    for (final path in additionalDirectories) {
      final t = path.trim();
      if (t.isNotEmpty) {
        args.addAll([
          '--add-dir',
          normalizePathForCli(t, useWslPaths: useWslPaths),
        ]);
      }
    }
    return args;
  }

  static List<String> buildArguments(
    TeamConfig team,
    TeamMemberConfig member, {
    String? sessionTeam,
    String? workingDirectory,
    List<String> additionalDirectories = const [],
    String? fixedSessionId,
    String? resumeSessionId,
    bool useWslPaths = false,
  }) {
    final teamFlag = sessionTeam ?? team.name.trim();
    final wd = workingDirectory ?? '';

    final args = <String>[
      ...buildSessionPrefixArgs(
        workingDirectory: wd.isNotEmpty ? wd : null,
        additionalDirectories: additionalDirectories,
        fixedSessionId: fixedSessionId,
        resumeSessionId: resumeSessionId,
        useWslPaths: useWslPaths,
      ),
      '--team',
      teamFlag,
      '--member',
      member.name.trim(),
    ];

    final loop = team.loop;
    if (loop != null) {
      args.addAll(['--loop', loop ? 'true' : 'false']);
    }

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
    if (team.extraArgs.trim().isNotEmpty) {
      args.addAll(splitArgs(team.extraArgs.trim()));
    }
    if (member.extraArgs.trim().isNotEmpty) {
      args.addAll(splitArgs(member.extraArgs.trim()));
    }

    return args;
  }

  static String preview(
    TeamConfig team,
    TeamMemberConfig member, {
    String? sessionTeam,
    required String executable,
    List<String> additionalDirectories = const [],
    String? fixedSessionId,
    String? resumeSessionId,
  }) {
    final invocation = CliInvocation.fromExecutable(executable);
    return [
      invocation.executable,
      ...invocation.prefixArgs,
      ...buildArguments(
        team,
        member,
        sessionTeam: sessionTeam,
        workingDirectory: '',
        additionalDirectories: additionalDirectories,
        fixedSessionId: fixedSessionId,
        resumeSessionId: resumeSessionId,
        useWslPaths: invocation.usesWsl,
      ),
    ].map(_quoteForPreview).join(' ');
  }

  static List<String> splitArgs(String input) {
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

  static Future<void> launch(
    TeamConfig team, {
    required TeamMemberConfig member,
    required String executable,
    String? sessionTeam,
    String? workingDirectory,
    List<String> additionalDirectories = const [],
    String? fixedSessionId,
    String? resumeSessionId,
    Map<String, String>? extraEnvironment,
    ProcessStarter starter = Process.start,
  }) async {
    final wd = workingDirectory ?? '';
    final invocation = CliInvocation.fromExecutable(executable);
    final processWorkingDirectory = workingDirectoryForProcess(
      wd,
      useWslPaths: invocation.usesWsl,
    );
    final args = buildArguments(
      team,
      member,
      sessionTeam: sessionTeam,
      workingDirectory: wd,
      additionalDirectories: additionalDirectories,
      fixedSessionId: fixedSessionId,
      resumeSessionId: resumeSessionId,
      useWslPaths: invocation.usesWsl,
    );
    final env = invocation.usesWsl
        ? normalizeEnvironmentForCli(extraEnvironment, useWslPaths: true)
        : extraEnvironment;
    final launchArgs = invocation.withArgs(args, environment: env);

    if (Platform.isLinux) {
      if (await _tryStartTerminal(
        starter,
        'x-terminal-emulator',
        ['-e', invocation.executable, ...launchArgs],
        processWorkingDirectory,
        env,
      )) {
        return;
      }
      if (await _tryStartTerminal(
        starter,
        'gnome-terminal',
        ['--', invocation.executable, ...launchArgs],
        processWorkingDirectory,
        env,
      )) {
        return;
      }
      if (await _tryStartTerminal(
        starter,
        'konsole',
        ['-e', invocation.executable, ...launchArgs],
        processWorkingDirectory,
        env,
      )) {
        return;
      }
      if (await _tryStartTerminal(
        starter,
        'xterm',
        ['-e', invocation.executable, ...launchArgs],
        processWorkingDirectory,
        env,
      )) {
        return;
      }
    } else if (Platform.isMacOS) {
      // `open -a Terminal` does not propagate parent env to the spawned shell.
      // Inline `export` so flashskyai sees the values we want.
      final exports = env == null || env.isEmpty
          ? ''
          : '${env.entries.map((e) => 'export ${e.key}=${_shellQuote(e.value)}').join('; ')}; ';
      final script =
          '${exports}cd ${_shellQuote(wd)} && '
          '${_shellQuote(invocation.executable)} ${launchArgs.map(_shellQuote).join(' ')}';
      if (await _tryStartTerminal(
        starter,
        'open',
        ['-a', 'Terminal', script],
        processWorkingDirectory,
        env,
      )) {
        return;
      }
    } else if (Platform.isWindows) {
      // `cmd /c start ... cmd /k` doesn't reliably forward parent env. Prefix
      // explicit `set` commands so flashskyai sees them in the new console.
      final sets = env == null || env.isEmpty
          ? ''
          : '${env.entries.map((e) => 'set ${e.key}=${e.value}').join(' && ')} && ';
      final command =
          '$sets${[invocation.executable, ...launchArgs].map(_windowsQuote).join(' ')}';
      if (await _tryStartTerminal(
        starter,
        'cmd',
        ['/c', 'start', 'FlashskyAI', 'cmd', '/k', command],
        processWorkingDirectory,
        env,
      )) {
        return;
      }
    }

    await starter(
      invocation.executable,
      launchArgs,
      workingDirectory: processWorkingDirectory,
      runInShell: true,
      environment: env,
      includeParentEnvironment: true,
    );
  }

  static Future<bool> _tryStartTerminal(
    ProcessStarter starter,
    String terminal,
    List<String> args,
    String workingDirectory,
    Map<String, String>? environment,
  ) async {
    try {
      await starter(
        terminal,
        args,
        workingDirectory: workingDirectory,
        runInShell: true,
        environment: environment,
        includeParentEnvironment: true,
      );
      return true;
    } on IOException {
      return false;
    }
  }

  static String _quoteForPreview(String value) {
    if (value.isEmpty) {
      return "''";
    }
    if (!value.contains(RegExp(r'\s'))) {
      return value;
    }
    return _shellQuote(value);
  }

  static String _shellQuote(String value) {
    return "'${value.replaceAll("'", r"'\''")}'";
  }

  static String _windowsQuote(String value) {
    if (!value.contains(RegExp(r'\s'))) {
      return value;
    }
    return '"${value.replaceAll('"', r'\"')}"';
  }

  static String normalizePathForCli(String path, {required bool useWslPaths}) {
    if (!useWslPaths) return path;
    return windowsPathToWsl(path) ?? path;
  }

  static String? windowsPathToWsl(String path) {
    final trimmed = path.trim();
    final uncMatch = RegExp(
      r'^\\+(?:wsl\.localhost|wsl\$)\\[^\\]+\\(.+)$',
      caseSensitive: false,
    ).firstMatch(trimmed.replaceAll('/', r'\'));
    if (uncMatch != null) {
      return '/${uncMatch.group(1)!.replaceAll(r'\', '/')}';
    }

    final match = RegExp(r'^([a-zA-Z]):[\\/]*(.*)$').firstMatch(trimmed);
    if (match == null) return null;
    final drive = match.group(1)!.toLowerCase();
    final rest = match.group(2)!.replaceAll('\\', '/');
    return rest.isEmpty ? '/mnt/$drive' : '/mnt/$drive/$rest';
  }

  static String workingDirectoryForProcess(
    String workingDirectory, {
    required bool useWslPaths,
  }) {
    if (!useWslPaths) return workingDirectory;
    if (!Platform.isWindows) return workingDirectory;
    final trimmed = workingDirectory.trim();
    if (trimmed.isNotEmpty &&
        windowsPathToWsl(trimmed) == null &&
        !trimmed.startsWith(r'\\')) {
      return trimmed;
    }
    return Platform.environment['USERPROFILE'] ??
        Platform.environment['SystemRoot'] ??
        Directory.current.path;
  }

  static Map<String, String>? normalizeEnvironmentForCli(
    Map<String, String>? environment, {
    required bool useWslPaths,
  }) {
    if (environment == null || !useWslPaths) return environment;
    return {
      for (final entry in environment.entries)
        entry.key: normalizePathForCli(entry.value, useWslPaths: true),
    };
  }
}
