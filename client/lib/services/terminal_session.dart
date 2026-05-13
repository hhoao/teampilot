import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import 'launch_command_builder.dart';
import '../models/team_config.dart';

class TerminalSession {
  TerminalSession({required this.executable})
    : terminal = Terminal(
        maxLines: 10000,
        platform: defaultTargetPlatform == TargetPlatform.macOS
            ? TerminalTargetPlatform.macos
            : TerminalTargetPlatform.linux,
      );

  final String executable;
  final Terminal terminal;
  Pty? _pty;
  var _running = false;
  var _starting = false;
  Map<String, String>? _extraEnvironment;
  VoidCallback? _onProcessStarted;

  bool get isRunning => _running || _starting;

  void connect({
    required String workingDirectory,
    List<String> additionalDirectories = const [],
    String? fixedSessionId,
    String? resumeSessionId,
    TeamConfig? team,
    TeamMemberConfig? member,
    String? sessionTeam,
    Map<String, String>? extraEnvironment,
    VoidCallback? onProcessStarted,
  }) {
    if (_running || _starting) {
      disconnect();
    }
    _extraEnvironment = extraEnvironment;
    _onProcessStarted = onProcessStarted;

    final args = <String>[];
    if (team != null && member != null) {
      args.addAll(
        LaunchCommandBuilder.buildArguments(
          team,
          member,
          sessionTeam: sessionTeam,
          workingDirectory: workingDirectory,
          additionalDirectories: additionalDirectories,
          fixedSessionId: fixedSessionId,
          resumeSessionId: resumeSessionId,
        ),
      );
    } else {
      args.addAll(
        LaunchCommandBuilder.buildSessionPrefixArgs(
          workingDirectory: workingDirectory.isNotEmpty ? workingDirectory : null,
          additionalDirectories: additionalDirectories,
          fixedSessionId: fixedSessionId,
          resumeSessionId: resumeSessionId,
        ),
      );
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
        executable,
        arguments: args,
        workingDirectory: cwd,
        columns: cols,
        rows: rows,
        environment: _extraEnvironment,
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
      _onProcessStarted?.call();
      _onProcessStarted = null;
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
    final text = utf8.decode(data, allowMalformed: true);
    terminal.write(text);
  }

  void disconnect() {
    _running = false;
    _starting = false;
    _onProcessStarted = null;
    terminal.onOutput = null;
    terminal.onResize = null;
    _pty?.kill();
    _pty = null;
  }

  void dispose() {
    disconnect();
  }
}
