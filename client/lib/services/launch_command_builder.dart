import 'dart:async';
import 'dart:io';

import '../models/team_config.dart';

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

  static List<String> buildArguments(
    TeamConfig team,
    TeamMemberConfig member, {
    String? sessionTeam,
    String? workingDirectory,
  }) {
    final teamFlag = sessionTeam ?? team.name.trim();
    final wd = workingDirectory ?? '';

    final args = <String>[
      if (wd.isNotEmpty) ...['--dir', wd],
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
  }) {
    return [
      executable,
      ...buildArguments(team, member, sessionTeam: sessionTeam, workingDirectory: ''),
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
    Map<String, String>? extraEnvironment,
    ProcessStarter starter = Process.start,
  }) async {
    final wd = workingDirectory ?? '';
    final args = buildArguments(team, member, sessionTeam: sessionTeam, workingDirectory: wd);
    final env = extraEnvironment;

    if (Platform.isLinux) {
      if (await _tryStartTerminal(starter, 'x-terminal-emulator', [
        '-e',
        executable,
        ...args,
      ], wd, env)) {
        return;
      }
      if (await _tryStartTerminal(starter, 'gnome-terminal', [
        '--',
        executable,
        ...args,
      ], wd, env)) {
        return;
      }
      if (await _tryStartTerminal(starter, 'konsole', [
        '-e',
        executable,
        ...args,
      ], wd, env)) {
        return;
      }
      if (await _tryStartTerminal(starter, 'xterm', [
        '-e',
        executable,
        ...args,
      ], wd, env)) {
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
          '${_shellQuote(executable)} ${args.map(_shellQuote).join(' ')}';
      if (await _tryStartTerminal(starter, 'open', [
        '-a',
        'Terminal',
        script,
      ], wd, env)) {
        return;
      }
    } else if (Platform.isWindows) {
      // `cmd /c start ... cmd /k` doesn't reliably forward parent env. Prefix
      // explicit `set` commands so flashskyai sees them in the new console.
      final sets = env == null || env.isEmpty
          ? ''
          : '${env.entries.map((e) => 'set ${e.key}=${e.value}').join(' && ')} && ';
      final command =
          '$sets${[executable, ...args].map(_windowsQuote).join(' ')}';
      if (await _tryStartTerminal(starter, 'cmd', [
        '/c',
        'start',
        'FlashskyAI',
        'cmd',
        '/k',
        command,
      ], wd, env)) {
        return;
      }
    }

    await starter(
      executable,
      args,
      workingDirectory: wd,
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
}
