import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:logger/logger.dart';
import 'package:xterm/xterm.dart';

import 'cli_executable_validator.dart';
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
  var _startFailed = false;
  Map<String, String>? _extraEnvironment;
  Map<String, String>? _ptyEnvironment;
  VoidCallback? _onProcessStarted;
  VoidCallback? _onProcessFailed;
  StreamSubscription<Uint8List>? _outputSubscription;
  Timer? _startConfirmationTimer;
  Timer? _spawnWatchdogTimer;
  Timer? _ptyGeometryTimer;
  Timer? _ptyGeometrySettleTimer;
  var _spawnRequested = false;
  var _terminalListenerAttached = false;
  var _hasPendingLayoutGeometry = false;
  int _pendingViewportCols = 0;
  int _pendingViewportRows = 0;
  int _lastSyncedCols = 0;
  int _lastSyncedRows = 0;
  String? _launchExecutable;
  List<String>? _launchArgs;
  String? _launchCwd;

  static const _layoutGeometryDebounceMs = 150;
  static const _outputGeometryDebounceMs = 80;
  static const _geometrySettleDelayMs = 120;

  bool get isRunning => (_running || _starting) && !_startFailed;

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
    VoidCallback? onProcessFailed,
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
    _onProcessFailed = onProcessFailed;
    _startFailed = false;

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

    final validationError = CliExecutableValidator.validateLaunch(
      executable: invocation.executable,
      workingDirectory: ptyWorkingDirectory,
    );
    if (validationError != null) {
      _handleStartFailure(validationError);
      return;
    }

    _starting = true;

    _attachTerminalViewportListener();

    terminal.onOutput = (String data) {
      if (_running && _pty != null) {
        _pty!.write(Uint8List.fromList(utf8.encode(data)));
      }
    };

    _launchExecutable = invocation.executable;
    _launchArgs = launchArgs;
    _launchCwd = ptyWorkingDirectory;

    terminal.onResize = (int width, int height, int pw, int ph) {
      if (width <= 0 || height <= 0) return;
      // Debounce rapid layout changes (e.g. maximize) so the CLI only redraws
      // once at the final geometry instead of at intermediate sizes.
      _schedulePtyGeometry(cols: width, rows: height, fromLayout: true);
    };
  }

  void _attachTerminalViewportListener() {
    if (_terminalListenerAttached) return;
    terminal.addListener(_schedulePtyViewportSync);
    _terminalListenerAttached = true;
  }

  void _detachTerminalViewportListener() {
    if (!_terminalListenerAttached) return;
    terminal.removeListener(_schedulePtyViewportSync);
    _terminalListenerAttached = false;
    _cancelPtyGeometryTimers();
  }

  void _cancelPtyGeometryTimers() {
    _ptyGeometryTimer?.cancel();
    _ptyGeometryTimer = null;
    _ptyGeometrySettleTimer?.cancel();
    _ptyGeometrySettleTimer = null;
  }

  /// Re-sync PTY rows/cols after emulator output so full-screen TUIs redraw
  /// against the same geometry the UI is painting.
  void _schedulePtyViewportSync() {
    _schedulePtyGeometry(fromLayout: false);
  }

  void _schedulePtyGeometry({
    int? cols,
    int? rows,
    bool fromLayout = false,
  }) {
    if (cols != null && rows != null) {
      _pendingViewportCols = cols;
      _pendingViewportRows = rows;
      _hasPendingLayoutGeometry = true;
    }
    if (_pty == null && (!_starting || _spawnRequested)) {
      if (cols == null) return;
    } else if (_pty != null && !_running) {
      return;
    }

    _ptyGeometryTimer?.cancel();
    final debounceMs = fromLayout || cols != null
        ? _layoutGeometryDebounceMs
        : _outputGeometryDebounceMs;
    _ptyGeometryTimer = Timer(Duration(milliseconds: debounceMs), () {
      _ptyGeometryTimer = null;
      _applyPtyGeometry();
    });
  }

  void _applyPtyGeometry() {
    final cols = _hasPendingLayoutGeometry
        ? _pendingViewportCols
        : terminal.viewWidth;
    final rows = _hasPendingLayoutGeometry
        ? _pendingViewportRows
        : terminal.viewHeight;
    _hasPendingLayoutGeometry = false;

    if (cols <= 0 || rows <= 0) return;

    if (_pty == null) {
      if (!_starting || _spawnRequested) return;
      final executable = _launchExecutable;
      final args = _launchArgs;
      final cwd = _launchCwd;
      if (executable == null || args == null || cwd == null) return;
      _spawnPty(
        executable: executable,
        args: args,
        cwd: cwd,
        cols: cols,
        rows: rows,
      );
      return;
    }

    if (!_running) return;
    _lastSyncedCols = cols;
    _lastSyncedRows = rows;
    _pty!.resize(rows, cols);
    _schedulePtyGeometrySettle();
  }

  /// After layout/output settles, nudge the PTY once more so TUIs fully redraw
  /// (clears ghost columns after maximize).
  void _schedulePtyGeometrySettle() {
    if (!_running || _pty == null) return;
    if (_lastSyncedCols <= 0 || _lastSyncedRows <= 0) return;
    _ptyGeometrySettleTimer?.cancel();
    _ptyGeometrySettleTimer = Timer(
      const Duration(milliseconds: _geometrySettleDelayMs),
      () {
        _ptyGeometrySettleTimer = null;
        if (!_running || _pty == null) return;
        _pty!.resize(_lastSyncedRows, _lastSyncedCols);
      },
    );
  }

  void _spawnPty({
    required String executable,
    required List<String> args,
    required String cwd,
    required int cols,
    required int rows,
  }) {
    if (_spawnRequested || _pty != null) return;
    _spawnRequested = true;

    final validationError = CliExecutableValidator.validateLaunch(
      executable: executable,
      workingDirectory: cwd,
    );
    if (validationError != null) {
      _spawnRequested = false;
      _handleStartFailure(validationError);
      return;
    }

    _startPtyProcess(
      executable: executable,
      args: args,
      cwd: cwd,
      cols: cols,
      rows: rows,
    );
  }

  void _startPtyProcess({
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
      _running = true;
      _starting = true;

      _outputSubscription = _pty!.output.listen((data) {
        _writeOutput(data, label: 'connect');
        if (_looksLikeExecFailure(utf8.decode(data, allowMalformed: true))) {
          _handleStartFailure(_execFailureMessage(executable));
        }
      });

      // Do not timeout [exitCode] for long-running shells — it only completes
      // when the process exits. A timeout here falsely disconnects healthy sessions.
      _pty!.exitCode.then((code) {
        if (_running && code != 0) {
          _handleStartFailure(_execFailureMessage(executable));
          return;
        }
        if (_running) {
          terminal.write('\r\n[process exited]\r\n');
        }
        _teardownPtyState();
      });

      _spawnWatchdogTimer = Timer(const Duration(seconds: 8), () {
        if (_startFailed || !_starting) return;
        _handleStartFailure(
          '${_execFailureMessage(executable)}\r\n'
          '  (PTY did not become ready)',
        );
      });

      _startConfirmationTimer = Timer(
        const Duration(milliseconds: 450),
        _confirmProcessStarted,
      );
    } on Object catch (error, stackTrace) {
      Logger().e('Failed to start flashskyai: $error', stackTrace: stackTrace);
      _handleStartFailure('[Failed to start flashskyai: $error]');
    }
  }

  void _confirmProcessStarted() {
    if (!_running || _startFailed || _pty == null) return;
    _starting = false;
    _spawnWatchdogTimer?.cancel();
    _spawnWatchdogTimer = null;
    final callback = _onProcessStarted;
    _onProcessStarted = null;
    callback?.call();
  }

  void _handleStartFailure(String message) {
    if (_startFailed) return;
    _startFailed = true;
    _spawnWatchdogTimer?.cancel();
    _spawnWatchdogTimer = null;
    _startConfirmationTimer?.cancel();
    _startConfirmationTimer = null;
    _outputSubscription?.cancel();
    _outputSubscription = null;
    _onProcessStarted = null;
    _pty?.kill();
    _pty = null;
    _running = false;
    _starting = false;
    terminal.write('\r\n$message\r\n');
    _onProcessFailed?.call();
    _onProcessFailed = null;
  }

  void _teardownPtyState() {
    _spawnWatchdogTimer?.cancel();
    _spawnWatchdogTimer = null;
    _startConfirmationTimer?.cancel();
    _startConfirmationTimer = null;
    _outputSubscription?.cancel();
    _outputSubscription = null;
    _running = false;
    _starting = false;
    _onProcessStarted = null;
  }

  static bool _looksLikeExecFailure(String text) {
    return text.contains('execvp:') ||
        text.contains('No such file or directory') ||
        text.contains('没有那个文件或目录');
  }

  static String _execFailureMessage(String executable) {
    return CliExecutableValidator.validateLaunch(
          executable: executable,
          workingDirectory: '',
        ) ??
        '[无法启动 flashskyai: 未找到可执行文件 "$executable"。\n'
            '  请在「设置 → 会话」中配置 flashskyai CLI 的绝对路径，'
            '或确保其已在 PATH 中（从文件管理器启动 AppImage 时 PATH 可能很短）。]';
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
    _schedulePtyViewportSync();
  }

  void disconnect() {
    _startFailed = false;
    _spawnRequested = false;
    _cancelPtyGeometryTimers();
    _launchExecutable = null;
    _launchArgs = null;
    _launchCwd = null;
    _detachTerminalViewportListener();
    _teardownPtyState();
    _onProcessFailed = null;
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
