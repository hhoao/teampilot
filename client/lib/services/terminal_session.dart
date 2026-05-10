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

  bool get isRunning => _running;

  void connectResume(String sessionId) {
    if (_running) {
      disconnect();
    }

    try {
      _pty = Pty.start(
        LaunchCommandBuilder.executable,
        arguments: ['--resume', sessionId],
      );

      _pty!.output.listen((data) {
        terminal.write(utf8.decode(data, allowMalformed: true));
      });

      terminal.onOutput = (String data) {
        if (_running && _pty != null) {
          _pty!.write(Uint8List.fromList(utf8.encode(data)));
        }
      };

      terminal.onResize = (int width, int height, int pw, int ph) {
        if (_running && _pty != null) {
          _pty!.resize(height, width);
        }
      };

      _pty!.exitCode.then((_) {
        if (_running) {
          terminal.write('\r\n[process exited]\r\n');
        }
        _running = false;
      });

      _running = true;
    } on Object catch (error) {
      terminal.write('\r\n[Failed to start flashskyai: $error]\r\n');
      _running = false;
    }
  }

  void connect(TeamConfig team, TeamMemberConfig member) {
    if (_running) {
      disconnect();
    }

    final args = LaunchCommandBuilder.buildArguments(team, member);
    final workingDir = team.workingDirectory.trim();

    try {
      _pty = Pty.start(
        LaunchCommandBuilder.executable,
        arguments: args,
        workingDirectory: workingDir,
      );

      _pty!.output.listen((data) {
        terminal.write(utf8.decode(data, allowMalformed: true));
      });

      terminal.onOutput = (String data) {
        if (_running && _pty != null) {
          _pty!.write(Uint8List.fromList(utf8.encode(data)));
        }
      };

      terminal.onResize = (int width, int height, int pw, int ph) {
        if (_running && _pty != null) {
          _pty!.resize(height, width);
        }
      };

      _pty!.exitCode.then((_) {
        if (_running) {
          terminal.write('\r\n[process exited]\r\n');
        }
        _running = false;
      });

      _running = true;
    } on Object catch (error) {
      terminal.write('\r\n[Failed to start flashskyai: $error]\r\n');
      _running = false;
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

  void disconnect() {
    _running = false;
    terminal.onOutput = null;
    _pty?.kill();
    _pty = null;
  }

  void dispose() {
    disconnect();
  }
}
