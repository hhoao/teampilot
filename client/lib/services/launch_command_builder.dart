import 'dart:async';
import 'dart:io';

import '../models/team_config.dart';

typedef ProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      bool runInShell,
    });

class LaunchCommandBuilder {
  static const executable = 'flashskyai';

  const LaunchCommandBuilder._();

  static List<String> buildArguments(TeamConfig team, TeamMemberConfig member) {
    final teamFlag = member.isolated
        ? '${team.name.trim()}::${member.name.trim()}'
        : team.name.trim();

    final args = <String>[
      '--dir',
      team.workingDirectory.trim(),
      '--team',
      teamFlag,
      '--member',
      member.name.trim(),
    ];

    if (member.provider.trim().isNotEmpty) {
      args.addAll(['--provider', member.provider.trim()]);
    }
    if (member.model.trim().isNotEmpty) {
      args.addAll(['--model', member.model.trim()]);
    }
    if (member.agent.trim().isNotEmpty) {
      args.addAll(['--agent', member.agent.trim()]);
    }
    if (team.extraArgs.trim().isNotEmpty) {
      args.addAll(splitArgs(team.extraArgs.trim()));
    }
    if (member.extraArgs.trim().isNotEmpty) {
      args.addAll(splitArgs(member.extraArgs.trim()));
    }

    return args;
  }

  static String preview(TeamConfig team, TeamMemberConfig member) {
    return [
      executable,
      ...buildArguments(team, member),
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
    ProcessStarter starter = Process.start,
  }) async {
    final args = buildArguments(team, member);
    final workingDirectory = team.workingDirectory.trim();

    if (Platform.isLinux) {
      if (await _tryStartTerminal(starter, 'x-terminal-emulator', [
        '-e',
        executable,
        ...args,
      ], workingDirectory)) {
        return;
      }
      if (await _tryStartTerminal(starter, 'gnome-terminal', [
        '--',
        executable,
        ...args,
      ], workingDirectory)) {
        return;
      }
      if (await _tryStartTerminal(starter, 'konsole', [
        '-e',
        executable,
        ...args,
      ], workingDirectory)) {
        return;
      }
      if (await _tryStartTerminal(starter, 'xterm', [
        '-e',
        executable,
        ...args,
      ], workingDirectory)) {
        return;
      }
    } else if (Platform.isMacOS) {
      final script =
          'cd ${_shellQuote(workingDirectory)} && '
          '${_shellQuote(executable)} ${args.map(_shellQuote).join(' ')}';
      if (await _tryStartTerminal(starter, 'open', [
        '-a',
        'Terminal',
        script,
      ], workingDirectory)) {
        return;
      }
    } else if (Platform.isWindows) {
      final command = [executable, ...args].map(_windowsQuote).join(' ');
      if (await _tryStartTerminal(starter, 'cmd', [
        '/c',
        'start',
        'FlashskyAI',
        'cmd',
        '/k',
        command,
      ], workingDirectory)) {
        return;
      }
    }

    await starter(
      executable,
      args,
      workingDirectory: workingDirectory,
      runInShell: true,
    );
  }

  static Future<bool> _tryStartTerminal(
    ProcessStarter starter,
    String terminal,
    List<String> args,
    String workingDirectory,
  ) async {
    try {
      await starter(
        terminal,
        args,
        workingDirectory: workingDirectory,
        runInShell: true,
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
