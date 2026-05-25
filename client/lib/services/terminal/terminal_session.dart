import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';
import '../cli/cli_executable_validator.dart';
import '../cli/cli_invocation.dart';
import '../cli/cli_tool_locator.dart';
import '../session/launch_command_builder.dart';
import 'local_pty_transport.dart';
import 'pty_launch_environment.dart';
import 'terminal_transport.dart';
import '../../models/team_config.dart';
import '../../utils/first_user_line_capture.dart';
import '../../utils/logger.dart';

typedef TransportStarter =
    Future<TerminalTransport> Function(
      String executable, {
      required List<String> arguments,
      required String workingDirectory,
      required int columns,
      required int rows,
      Map<String, String>? environment,
    });

/// PTY attach → confirm → running. See [_handlePtyOutput] and [_confirmProcessStarted].
enum _LaunchPhase { idle, spawning, confirming, running, failed }

class TerminalSession {
  TerminalSession({
    required this.executable,
    this.validateLaunch = true,
    this.parseExecutable = true,
    this.startupDeadline = const Duration(seconds: 15),
    this.confirmFallback = const Duration(milliseconds: 150),
    TransportStarter? transportStarter,
    int scrollbackLines = 10000,
    @Deprecated('Use transportStarter instead') dynamic ptyStarter,
  }) : _transportStarter = transportStarter ?? _defaultTransportStarter,
       terminal = Terminal(
         maxLines: scrollbackLines,
         platform: switch (defaultTargetPlatform) {
           TargetPlatform.macOS => TerminalTargetPlatform.macos,
           TargetPlatform.windows => TerminalTargetPlatform.windows,
           _ => TerminalTargetPlatform.linux,
         },
       );

  final String executable;
  final bool validateLaunch;
  final bool parseExecutable;
  final Duration startupDeadline;
  final Duration confirmFallback;
  final TransportStarter _transportStarter;
  final Terminal terminal;
  TerminalTransport? _transport;
  var _launchPhase = _LaunchPhase.idle;
  var _startFailed = false;
  String? _startupExecutable;
  Map<String, String>? _extraEnvironment;
  Map<String, String>? _ptyEnvironment;
  VoidCallback? _onProcessStarted;
  void Function(String message)? _onProcessFailed;
  VoidCallback? _onProcessExited;
  StreamSubscription<String>? _outputSubscription;
  FirstUserLineCapture? _firstUserLineCapture;
  Timer? _confirmFallbackTimer;
  Timer? _startupDeadlineTimer;
  Timer? _ptyGeometryTimer;
  Timer? _ptyGeometrySettleTimer;
  var _spawnRequested = false;
  var _transportStartGeneration = 0;
  var _terminalListenerAttached = false;
  var _hasPendingLayoutGeometry = false;
  int _pendingViewportCols = 0;
  int _pendingViewportRows = 0;
  int _lastSyncedCols = 0;
  int _lastSyncedRows = 0;

  /// Trailing settle after layout resize (apps may react to SIGWINCH in two phases).
  static const _layoutGeometrySettleMs = 80;
  static const _outputGeometryDebounceMs = 80;

  bool get isRunning =>
      (_launchPhase == _LaunchPhase.running ||
          _launchPhase == _LaunchPhase.confirming ||
          _launchPhase == _LaunchPhase.spawning) &&
      !_startFailed;

  bool get _starting =>
      _launchPhase == _LaunchPhase.spawning ||
      _launchPhase == _LaunchPhase.confirming;

  bool get _running => _transport != null && _launchPhase != _LaunchPhase.idle;

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
    void Function(String message)? onProcessFailed,
    VoidCallback? onProcessExited,
    void Function(String line)? onFirstUserLineSubmitted,
  }) {
    if (_running || _starting) {
      disconnect();
    }
    final invocation = parseExecutable
        ? CliInvocation.fromExecutable(executable)
        : CliInvocation(executable: executable);
    final ptyWorkingDirectory = LaunchCommandBuilder.workingDirectoryForProcess(
      workingDirectory,
      useWslPaths: invocation.usesWsl,
    );
    _extraEnvironment = LaunchCommandBuilder.normalizeEnvironmentForCli(
      extraEnvironment,
      useWslPaths: invocation.usesWsl,
    );
    final settingsPath = LaunchCommandBuilder.settingsPathFromEnvironment(
      _extraEnvironment,
    );
    final appendSystemPromptFile =
        LaunchCommandBuilder.appendSystemPromptFileFromEnvironment(
          _extraEnvironment,
        );
    _extraEnvironment = LaunchCommandBuilder.launchEnvironmentForProcess(
      _extraEnvironment,
    );
    _ptyEnvironment = buildPtyEnvironment(_extraEnvironment);
    _onProcessStarted = onProcessStarted;
    _onProcessFailed = onProcessFailed;
    _onProcessExited = onProcessExited;
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
          settingsPath: settingsPath,
          appendSystemPromptFile: appendSystemPromptFile,
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

    if (validateLaunch) {
      final validationError = CliExecutableValidator.validateLaunch(
        executable: invocation.executable,
        workingDirectory: ptyWorkingDirectory,
      );
      if (validationError != null) {
        _handleStartFailure(validationError);
        return;
      }
    }

    _beginStartup(invocation.executable);

    _attachTerminalViewportListener();

    _firstUserLineCapture = onFirstUserLineSubmitted == null
        ? null
        : FirstUserLineCapture(onFirstUserLineSubmitted);

    terminal.onOutput = (String data) {
      _firstUserLineCapture?.feed(data);
      if (_transportReadyForIo && _transport != null) {
        _transport!.write(Uint8List.fromList(utf8.encode(data)));
      }
    };

    terminal.onResize = (int width, int height, int pw, int ph) {
      if (width <= 0 || height <= 0) return;
      _pendingViewportCols = width;
      _pendingViewportRows = height;
      _hasPendingLayoutGeometry = true;
      _syncPtyGeometryNow(width, height);
      _scheduleLayoutPtyGeometrySettle();
    };

    // Spawn immediately with this connect()'s args so concurrent member shells
    // (each with its own TerminalSession) are not racing on shared launch fields.
    _spawnTransport(
      executable: invocation.executable,
      args: launchArgs,
      cwd: ptyWorkingDirectory,
      cols: terminal.viewWidth,
      rows: terminal.viewHeight,
    );
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

  void _schedulePtyViewportSync() {
    _schedulePtyGeometry();
  }

  void _schedulePtyGeometry({int? cols, int? rows}) {
    if (cols != null && rows != null) {
      _pendingViewportCols = cols;
      _pendingViewportRows = rows;
      _hasPendingLayoutGeometry = true;
      _syncPtyGeometryNow(cols, rows);
      _scheduleLayoutPtyGeometrySettle();
      return;
    }
    if (_transport == null) {
      return;
    }
    if (!_transportReadyForIo) return;

    _ptyGeometryTimer?.cancel();
    _ptyGeometryTimer = Timer(
      Duration(milliseconds: _outputGeometryDebounceMs),
      () {
        _ptyGeometryTimer = null;
        _applyOutputPtyGeometry();
      },
    );
  }

  /// Layout-driven resize: SIGWINCH immediately so the shell reflows with the UI.
  void _syncPtyGeometryNow(int cols, int rows) {
    if (cols <= 0 || rows <= 0) return;
    if (_transport == null) {
      return;
    }
    if (!_transportReadyForIo) return;
    if (cols == _lastSyncedCols && rows == _lastSyncedRows) return;
    _lastSyncedCols = cols;
    _lastSyncedRows = rows;
    _transport!.resize(rows, cols);
  }

  void _scheduleLayoutPtyGeometrySettle() {
    if (_transport == null || !_transportReadyForIo) return;
    _ptyGeometrySettleTimer?.cancel();
    _ptyGeometrySettleTimer = Timer(
      const Duration(milliseconds: _layoutGeometrySettleMs),
      () {
        _ptyGeometrySettleTimer = null;
        if (_transport == null || !_transportReadyForIo) return;
        final cols = _hasPendingLayoutGeometry
            ? _pendingViewportCols
            : terminal.viewWidth;
        final rows = _hasPendingLayoutGeometry
            ? _pendingViewportRows
            : terminal.viewHeight;
        _hasPendingLayoutGeometry = false;
        _syncPtyGeometryNow(cols, rows);
      },
    );
  }

  void _applyOutputPtyGeometry() {
    final cols = _hasPendingLayoutGeometry
        ? _pendingViewportCols
        : terminal.viewWidth;
    final rows = _hasPendingLayoutGeometry
        ? _pendingViewportRows
        : terminal.viewHeight;
    _hasPendingLayoutGeometry = false;

    if (cols <= 0 || rows <= 0) return;
    if (_transport == null) return;
    if (!_transportReadyForIo) return;
    _syncPtyGeometryNow(cols, rows);
  }

  void _spawnTransport({
    required String executable,
    required List<String> args,
    required String cwd,
    required int cols,
    required int rows,
  }) {
    if (_spawnRequested || _transport != null) return;
    _spawnRequested = true;

    if (validateLaunch) {
      final validationError = CliExecutableValidator.validateLaunch(
        executable: executable,
        workingDirectory: cwd,
      );
      if (validationError != null) {
        _spawnRequested = false;
        _handleStartFailure(validationError);
        return;
      }
    }

    _startTransport(
      executable: executable,
      args: args,
      cwd: cwd,
      cols: cols,
      rows: rows,
    );
  }

  bool get _transportReadyForIo =>
      _transport != null &&
      (_launchPhase == _LaunchPhase.confirming ||
          _launchPhase == _LaunchPhase.running);

  void _beginStartup(String executable) {
    _startupExecutable = executable;
    _launchPhase = _LaunchPhase.spawning;
    _startFailed = false;
    _armStartupDeadline();
  }

  void _enterConfirmingPhase() {
    if (_launchPhase != _LaunchPhase.spawning) return;
    _launchPhase = _LaunchPhase.confirming;
    _confirmFallbackTimer?.cancel();
    _confirmFallbackTimer = Timer(confirmFallback, _confirmProcessStarted);
  }

  void _armStartupDeadline() {
    _startupDeadlineTimer?.cancel();
    _startupDeadlineTimer = Timer(startupDeadline, _onStartupDeadline);
  }

  void _onStartupDeadline() {
    if (!_starting || _startFailed) return;
    final cliExecutable = _startupExecutable ?? this.executable;
    final cliName = CliExecutableValidator.cliDisplayName(cliExecutable);
    if (_transport == null) {
      _handleStartFailure('[Failed to start $cliName: spawn timed out]');
      return;
    }
    _handleStartFailure('[Failed to start $cliName: startup timed out]');
  }

  void _cancelStartupTimers() {
    _confirmFallbackTimer?.cancel();
    _confirmFallbackTimer = null;
    _startupDeadlineTimer?.cancel();
    _startupDeadlineTimer = null;
  }

  void _handlePtyOutput(String text, String executable) {
    _writeOutput(text);
    if (!_starting || _startFailed) return;
    if (_looksLikeExecFailure(text)) {
      _handleStartFailure(_launchFailureMessage(executable));
      return;
    }
  }

  Future<void> _startTransport({
    required String executable,
    required List<String> args,
    required String cwd,
    required int cols,
    required int rows,
  }) async {
    final startGeneration = ++_transportStartGeneration;
    try {
      final transport = await _transportStarter(
        executable,
        arguments: args,
        workingDirectory: cwd,
        columns: cols,
        rows: rows,
        environment: _ptyEnvironment,
      );
      if (startGeneration != _transportStartGeneration || !_starting) {
        transport.close();
        return;
      }
      _transport = transport;
      _enterConfirmingPhase();

      if (_hasPendingLayoutGeometry &&
          _pendingViewportCols > 0 &&
          _pendingViewportRows > 0) {
        _lastSyncedCols = _pendingViewportCols;
        _lastSyncedRows = _pendingViewportRows;
        transport.resize(_pendingViewportRows, _pendingViewportCols);
        _hasPendingLayoutGeometry = false;
      }

      _outputSubscription = transport.output
          .map<List<int>>((data) => data)
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((text) {
            _handlePtyOutput(text, executable);
            if (_starting && !_startFailed && text.isNotEmpty) {
              _confirmProcessStarted();
            }
          });

      transport.done.then((code) {
        if (startGeneration != _transportStartGeneration ||
            _transport != transport) {
          return;
        }
        if (_starting && !_startFailed) {
          _handleStartFailure(
            code == 0
                ? '[process exited unexpectedly during startup]'
                : '[process exited with code $code during startup]',
          );
          return;
        }
        if (_launchPhase != _LaunchPhase.running) {
          return;
        }
        if (code != 0) {
          terminal.write('\r\n[process exited with code $code]\r\n');
          return;
        }
        if (_transport == transport) {
          transport.close();
          _transport = null;
        }
        _teardownPtyState();
        final callback = _onProcessExited;
        _onProcessExited = null;
        callback?.call();
      });
    } on Object catch (error, stackTrace) {
      if (startGeneration != _transportStartGeneration || !_starting) {
        return;
      }
      final cliName = CliExecutableValidator.cliDisplayName(executable);
      _handleStartFailure(
        '[Failed to start $cliName: $error]',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _confirmProcessStarted() {
    if (_launchPhase != _LaunchPhase.confirming ||
        _startFailed ||
        _transport == null) {
      return;
    }
    _launchPhase = _LaunchPhase.running;
    _cancelStartupTimers();
    final cliExecutable = _startupExecutable ?? this.executable;
    appLogger.i(
      '[terminal] started ${CliExecutableValidator.cliDisplayName(cliExecutable)}',
    );
    final callback = _onProcessStarted;
    _onProcessStarted = null;
    callback?.call();
  }

  void _handleStartFailure(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (_startFailed) return;
    _startFailed = true;
    _launchPhase = _LaunchPhase.failed;
    _cancelStartupTimers();
    _outputSubscription?.cancel();
    _outputSubscription = null;
    _onProcessStarted = null;
    _onProcessExited = null;
    _transport?.close();
    _transport = null;
    _startupExecutable = null;
    appLogger.e(
      '[terminal] $message',
      error: error,
      stackTrace: stackTrace,
    );
    terminal.write('\r\n$message\r\n');
    _onProcessFailed?.call(message);
    _onProcessFailed = null;
  }

  void _teardownPtyState() {
    _cancelStartupTimers();
    _outputSubscription?.cancel();
    _outputSubscription = null;
    _launchPhase = _LaunchPhase.idle;
    _startupExecutable = null;
    _onProcessStarted = null;
  }

  void write(String text) {
    if (_transportReadyForIo && _transport != null) {
      _transport!.write(Uint8List.fromList(utf8.encode(text)));
    }
  }

  void writeln(String text) {
    write('$text\r');
  }

  void _writeOutput(String text) {
    terminal.write(text);
    _schedulePtyViewportSync();
  }

  static bool _looksLikeExecFailure(String text) {
    return text.contains('execvp:') ||
        text.contains('No such file or directory') ||
        text.contains('没有那个文件或目录');
  }

  String _launchFailureMessage(String executable) {
    final cliName = CliExecutableValidator.cliDisplayName(executable);
    if (!validateLaunch) {
      return '[无法启动远端 $cliName: "$executable"。\n'
          '  请检查 SSH Profile 中的远端路径、PATH、工作目录和执行权限。]';
    }
    return _execFailureMessage(executable);
  }

  static String _execFailureMessage(String executable) {
    final cliName = CliExecutableValidator.cliDisplayName(executable);
    return CliExecutableValidator.validateLaunch(
          executable: executable,
          workingDirectory: '',
        ) ??
        '[无法启动 $cliName: 未找到可执行文件 "$executable"。\n'
            '  请在「设置 → 会话」中配置 $cliName CLI 的绝对路径，'
            '或确保其已在 PATH 中（从文件管理器启动 AppImage 时 PATH 可能很短）。]';
  }

  void disconnect() {
    _transportStartGeneration++;
    _startFailed = false;
    _spawnRequested = false;
    _cancelPtyGeometryTimers();
    _hasPendingLayoutGeometry = false;
    _detachTerminalViewportListener();
    _teardownPtyState();
    _onProcessFailed = null;
    _onProcessExited = null;
    _ptyEnvironment = null;
    _firstUserLineCapture = null;
    terminal.onOutput = null;
    terminal.onResize = null;
    _transport?.close();
    _transport = null;
  }

  void dispose() {
    disconnect();
  }

  /// Full process environment for [Pty.start], including OSC 8 identity hints.
  static Map<String, String> buildPtyEnvironment(
    Map<String, String>? environment,
  ) {
    final merged = <String, String>{
      ...Platform.environment,
      if (environment != null) ...environment,
    };
    PtyLaunchEnvironment.applyHyperlinkIdentity(merged);
    if (Platform.isWindows) {
      final path = merged['Path'] ?? merged['PATH'];
      if (path != null && path.isNotEmpty) {
        merged['PATH'] = path;
      }
    }
    return merged;
  }

  static Future<TerminalTransport> _defaultTransportStarter(
    String executable, {
    required List<String> arguments,
    required String workingDirectory,
    required int columns,
    required int rows,
    Map<String, String>? environment,
  }) async {
    final spawnExecutable = CliToolLocator.resolveSpawnExecutable(executable);
    appLogger.i(
      '[terminal] starting transport: '
      'executable=$spawnExecutable '
      'args=${arguments.join(' ')} '
      'cwd=$workingDirectory',
    );
    final pty = Pty.start(
      spawnExecutable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      columns: columns,
      rows: rows,
      environment: environment,
    );
    return LocalPtyTransport(pty);
  }
}
