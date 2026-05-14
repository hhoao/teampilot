import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:logger/logger.dart';
import 'package:xterm/xterm.dart';

import 'cli_invocation.dart';
import 'launch_command_builder.dart';
import '../models/team_config.dart';

abstract class TerminalPtyHandle {
  Stream<Uint8List> get output;
  Future<int> get exitCode;

  void write(Uint8List data);
  void resize(int rows, int columns);
  void kill();
}

typedef TerminalPtyStarter =
    TerminalPtyHandle Function(
      String executable, {
      required List<String> arguments,
      required String workingDirectory,
      required int columns,
      required int rows,
      Map<String, String>? environment,
    });

class _FlutterPtyHandle implements TerminalPtyHandle {
  _FlutterPtyHandle(this._pty);

  final Pty _pty;

  @override
  Stream<Uint8List> get output => _pty.output;

  @override
  Future<int> get exitCode => _pty.exitCode;

  @override
  void kill() {
    _pty.kill();
  }

  @override
  void resize(int rows, int columns) {
    _pty.resize(rows, columns);
  }

  @override
  void write(Uint8List data) {
    _pty.write(data);
  }
}

TerminalPtyHandle _startFlutterPty(
  String executable, {
  required List<String> arguments,
  required String workingDirectory,
  required int columns,
  required int rows,
  Map<String, String>? environment,
}) {
  return _FlutterPtyHandle(
    Pty.start(
      executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      columns: columns,
      rows: rows,
      environment: environment,
    ),
  );
}

class TerminalSession {
  TerminalSession({required this.executable, TerminalPtyStarter? ptyStarter})
    : _ptyStarter = ptyStarter ?? _startFlutterPty,
      terminal = Terminal(
        maxLines: 10000,
        platform: switch (defaultTargetPlatform) {
          TargetPlatform.macOS => TerminalTargetPlatform.macos,
          TargetPlatform.windows => TerminalTargetPlatform.windows,
          _ => TerminalTargetPlatform.linux,
        },
      );

  final String executable;
  final TerminalPtyStarter _ptyStarter;
  final Terminal terminal;
  TerminalPtyHandle? _pty;
  var _running = false;
  var _starting = false;
  Map<String, String>? _extraEnvironment;
  Map<String, String>? _ptyEnvironment;
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
    final invocation = CliInvocation.fromExecutable(executable);
    final ptyWorkingDirectory = LaunchCommandBuilder.workingDirectoryForProcess(
      workingDirectory,
      useWslPaths: invocation.usesWsl,
    );
    _extraEnvironment = LaunchCommandBuilder.normalizeEnvironmentForCli(
      extraEnvironment,
      useWslPaths: invocation.usesWsl,
    );
    _ptyEnvironment = buildPtyEnvironment(_extraEnvironment);
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
          useWslPaths: invocation.usesWsl,
        ),
      );
    } else {
      args.addAll(
        LaunchCommandBuilder.buildSessionPrefixArgs(
          workingDirectory: workingDirectory.isNotEmpty
              ? workingDirectory
              : null,
          additionalDirectories: additionalDirectories,
          fixedSessionId: fixedSessionId,
          resumeSessionId: resumeSessionId,
          useWslPaths: invocation.usesWsl,
        ),
      );
    }
    final launchArgs = invocation.withArgs(
      args,
      environment: _extraEnvironment,
    );

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
          executable: invocation.executable,
          args: launchArgs,
          cwd: ptyWorkingDirectory,
          cols: width,
          rows: height,
        );
      } else if (_running && width > 0 && height > 0) {
        _pty!.resize(height, width);
      }
    };
    _spawnPty(
      executable: invocation.executable,
      args: launchArgs,
      cwd: ptyWorkingDirectory,
      cols: 80,
      rows: 24,
    );
  }

  void _spawnPty({
    required String executable,
    required List<String> args,
    required String cwd,
    required int cols,
    required int rows,
  }) {
    try {
      _pty = _ptyStarter(
        executable,
        arguments: args,
        workingDirectory: cwd,
        columns: cols,
        rows: rows,
        environment: _ptyEnvironment,
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
    } on Object catch (error, stackTrace) {
      Logger().e('Failed to start flashskyai: $error', stackTrace: stackTrace);
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
    _ptyEnvironment = null;
    terminal.onOutput = null;
    terminal.onResize = null;
    _pty?.kill();
    _pty = null;
  }

  void dispose() {
    disconnect();
  }

  static Map<String, String>? buildPtyEnvironment(
    Map<String, String>? environment,
  ) {
    if (!Platform.isWindows) {
      return environment;
    }
    final merged = <String, String>{...Platform.environment};
    final path = merged['Path'] ?? merged['PATH'];
    if (path != null && path.isNotEmpty) {
      merged['PATH'] = path;
    }
    if (environment != null) {
      merged.addAll(environment);
    }
    return merged;
  }
}
