import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import 'launch_command_builder.dart';
import '../models/team_config.dart';

class TerminalSession {
  TerminalSession()
    : terminal = Terminal(
        maxLines: 10000,
        platform: defaultTargetPlatform == TargetPlatform.macOS
            ? TerminalTargetPlatform.macos
            : TerminalTargetPlatform.linux,
      );

  final Terminal terminal;
  Pty? _pty;
  var _running = false;
  var _starting = false;

  bool get isRunning => _running || _starting;

  void connect({
    required String workingDirectory,
    String? resumeSessionId,
    TeamConfig? team,
    TeamMemberConfig? member,
    String? sessionTeam,
  }) {
    if (_running || _starting) {
      disconnect();
    }

    final args = <String>[];
    if (workingDirectory.isNotEmpty) {
      args.addAll(['--dir', workingDirectory]);
    }
    if (resumeSessionId != null) {
      args.addAll(['--resume', resumeSessionId]);
    }
    if (team != null && member != null) {
      final teamFlag = sessionTeam ?? team.name.trim();
      args.addAll(['--team', teamFlag, '--member', member.name.trim()]);
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
        args.addAll(LaunchCommandBuilder.splitArgs(team.extraArgs.trim()));
      }
      if (member.extraArgs.trim().isNotEmpty) {
        args.addAll(LaunchCommandBuilder.splitArgs(member.extraArgs.trim()));
      }
    }

    _starting = true;

    terminal.onOutput = (String data) {
      if (_running && _pty != null) {
        _pty!.write(Uint8List.fromList(utf8.encode(data)));
      }
    };

    terminal.onResize = (int width, int height, int pw, int ph) {
      if (_pty == null) {
        if (!_starting || width <= 0 || height <= 0) return;
        _spawnPty(
          args: args,
          cwd: workingDirectory,
          cols: width,
          rows: height,
        );
      } else if (_running) {
        _pty!.resize(height, width);
      }
    };
  }

  void _spawnPty({
    required List<String> args,
    required String cwd,
    required int cols,
    required int rows,
  }) {
    try {
      _pty = Pty.start(
        LaunchCommandBuilder.executable,
        arguments: args,
        workingDirectory: cwd,
        columns: cols,
        rows: rows,
      );

      _pty!.output.listen((data) {
        _writeOutput(data, label: 'connect');
      });

      _pty!.exitCode.then((_) {
        if (_running) {
          terminal.write('\r\n[process exited]\r\n');
        }
        _running = false;
        _starting = false;
      });

      _running = true;
      _starting = false;
    } on Object catch (error) {
      terminal.write('\r\n[Failed to start flashskyai: $error]\r\n');
      _running = false;
      _starting = false;
      _pty = null;
    }
  }

  void write(String text) {
    if (_running && _pty != null) {
      _pty!.write(Uint8List.fromList(utf8.encode(text)));
    }
  }

  void writeln(String text) {
    write('$text\r');
  }

  void _writeOutput(Uint8List data, {required String label}) {
    final sw = Stopwatch()..start();
    final text = utf8.decode(data, allowMalformed: true);
    terminal.write(text);
    sw.stop();
  }

  void disconnect() {
    _running = false;
    _starting = false;
    terminal.onOutput = null;
    terminal.onResize = null;
    _pty?.kill();
    _pty = null;
  }

  void dispose() {
    disconnect();
  }
}
