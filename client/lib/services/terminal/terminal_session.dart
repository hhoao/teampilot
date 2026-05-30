import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';
import 'package:flutter_pty/flutter_pty.dart';
import '../cli/cli_executable_validator.dart';
import '../cli/cli_invocation.dart';
import '../cli/cli_tool_locator.dart';
import '../session/launch_command_builder.dart';
import 'local_pty_transport.dart';
import 'pty_launch_environment.dart';
import 'terminal_transport.dart';
import '../../models/team_config.dart';
import '../team/terminal_activity_tracker.dart';
import '../../utils/first_user_line_capture.dart';
import '../../utils/logger.dart';
import 'terminal_theme_mapper.dart';
import 'workspace_interactive_shell.dart';

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
    TerminalTheme? terminalTheme,
    @Deprecated('Use transportStarter instead') dynamic ptyStarter,
  }) : _transportStarter = transportStarter ?? _defaultTransportStarter,
       _scrollbackLines = scrollbackLines,
       engine = TerminalEngine(
         config: terminalTheme == null
             ? TerminalConfig.defaults().copyWith(
                 scrolling: TerminalConfig.defaults().scrolling.copyWith(
                   history: scrollbackLines,
                 ),
               )
             : terminalConfigFromTheme(
                 terminalTheme,
                 scrollbackLines: scrollbackLines,
               ),
       ) {
    _terminalTheme = terminalTheme;
  }

  final int _scrollbackLines;
  TerminalTheme? _terminalTheme;

  final String executable;
  final bool validateLaunch;
  final bool parseExecutable;
  final Duration startupDeadline;
  final Duration confirmFallback;
  final TransportStarter _transportStarter;

  /// Alacritty-backed terminal engine (replaces xterm [Terminal]).
  final TerminalEngine engine;

  final TerminalActivityTracker activityTracker = TerminalActivityTracker();
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
  StreamSubscription<Uint8List>? _engineOutputSubscription;
  FirstUserLineCapture? _firstUserLineCapture;
  Timer? _confirmFallbackTimer;
  Timer? _startupDeadlineTimer;
  Timer? _ptyGeometryTimer;
  Timer? _ptyGeometrySettleTimer;
  var _spawnRequested = false;
  var _transportStartGeneration = 0;
  var _hasPendingLayoutGeometry = false;
  int _pendingViewportCols = 80;
  int _pendingViewportRows = 24;
  int _lastSyncedCols = 0;
  int _lastSyncedRows = 0;

  int get viewWidth => _pendingViewportCols;
  int get viewHeight => _pendingViewportRows;

  /// Trailing settle after layout resize (apps may react to SIGWINCH in two phases).
  static const _layoutGeometrySettleMs = 80;
  static const _outputGeometryDebounceMs = 80;

  bool get isRunning =>
      (_launchPhase == _LaunchPhase.running ||
          _launchPhase == _LaunchPhase.confirming ||
          _launchPhase == _LaunchPhase.spawning) &&
      !_startFailed;

  /// Spawning or awaiting first output confirmation.
  bool get isConnecting =>
      !_startFailed &&
      (_launchPhase == _LaunchPhase.spawning ||
          _launchPhase == _LaunchPhase.confirming);

  /// PTY confirmed running (agent may still be idle).
  bool get isConnected => !_startFailed && _launchPhase == _LaunchPhase.running;

  bool get _starting =>
      _launchPhase == _LaunchPhase.spawning ||
      _launchPhase == _LaunchPhase.confirming;

  bool get _running => _transport != null && _launchPhase != _LaunchPhase.idle;

  /// Writes PTY output bytes into the display engine.
  void write(String text) => _writeOutput(text);

  /// Push TeamPilot layout colors into the Rust engine palette (ANSI + default fg/bg).
  ///
  /// [TerminalView.theme] only affects selection/search chrome; cell colors come
  /// from the engine until this is called (xterm parity).
  void applyTerminalTheme(TerminalTheme theme) {
    _terminalTheme = theme;
    if (_running || _starting) {
      _reconfigureEngineColors(theme);
    }
  }

  void _reconfigureEngineColors(TerminalTheme theme) {
    engine.reconfigure(
      terminalConfigFromTheme(theme, scrollbackLines: _scrollbackLines),
    );
  }

  /// Called from [TerminalView.onViewportResize] when the cell grid changes.
  void onViewportResize(int columns, int rows) {
    if (columns <= 0 || rows <= 0) return;
    _pendingViewportCols = columns;
    _pendingViewportRows = rows;
    _hasPendingLayoutGeometry = true;
    engine.resize(columns: columns, rows: rows);
    _syncPtyGeometryNow(columns, rows);
    _scheduleLayoutPtyGeometrySettle();
  }

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

    appLogger.i(
      '--------------------------------\n'
      'Starting transport:\n'
      '--------------------------------\n'
      'Executable: $invocation.executable,\n'
      'Arguments: ${launchArgs.join(' ')},\n'
      'WorkingDirectory: $ptyWorkingDirectory,\n'
      'Environment: ${_extraEnvironment?.entries.map((e) => '${e.key}=${e.value}').join(', ')}\n'
      '--------------------------------\n',
    );

    _beginStartup(invocation.executable);

    _firstUserLineCapture = onFirstUserLineSubmitted == null
        ? null
        : FirstUserLineCapture(onFirstUserLineSubmitted);

    _engineOutputSubscription?.cancel();
    _engineOutputSubscription = engine.output.listen((Uint8List data) {
      _firstUserLineCapture?.feed(utf8.decode(data));
      if (_transportReadyForIo && _transport != null) {
        _transport!.write(data);
      }
    });

    _spawnTransport(
      executable: invocation.executable,
      args: launchArgs,
      cwd: ptyWorkingDirectory,
      cols: viewWidth,
      rows: viewHeight,
    );
  }

  /// Interactive login shell for the workspace terminal panel (no CLI flags).
  void connectShell({
    required String workingDirectory,
    VoidCallback? onProcessStarted,
    void Function(String message)? onProcessFailed,
    VoidCallback? onProcessExited,
  }) {
    if (_running || _starting) {
      disconnect();
    }
    final executable = WorkspaceInteractiveShell.executable();
    final ptyWorkingDirectory = workingDirectory.trim().isNotEmpty
        ? LaunchCommandBuilder.workingDirectoryForProcess(
            workingDirectory,
            useWslPaths: false,
          )
        : LaunchCommandBuilder.workingDirectoryForProcess(
            Directory.current.path,
            useWslPaths: false,
          );
    _extraEnvironment = null;
    _ptyEnvironment = buildPtyEnvironment(null);
    _onProcessStarted = onProcessStarted;
    _onProcessFailed = onProcessFailed;
    _onProcessExited = onProcessExited;
    _startFailed = false;

    final launchArgs = WorkspaceInteractiveShell.launchArguments(executable);

    _beginStartup(executable);

    _firstUserLineCapture = null;

    _engineOutputSubscription?.cancel();
    _engineOutputSubscription = engine.output.listen((Uint8List data) {
      if (_transportReadyForIo && _transport != null) {
        _transport!.write(data);
      }
    });

    _spawnTransport(
      executable: executable,
      args: launchArgs,
      cwd: ptyWorkingDirectory,
      cols: viewWidth,
      rows: viewHeight,
    );
  }

  void _schedulePtyGeometry({int? cols, int? rows}) {
    if (cols != null && rows != null) {
      onViewportResize(cols, rows);
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
            : viewWidth;
        final rows = _hasPendingLayoutGeometry
            ? _pendingViewportRows
            : viewHeight;
        _hasPendingLayoutGeometry = false;
        _syncPtyGeometryNow(cols, rows);
      },
    );
  }

  void _applyOutputPtyGeometry() {
    final cols = _hasPendingLayoutGeometry ? _pendingViewportCols : viewWidth;
    final rows = _hasPendingLayoutGeometry ? _pendingViewportRows : viewHeight;
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
      // Yield to the event loop so the loading animation can paint before the
      // synchronous Rust FFI call (engineNew) blocks the main thread.
      await Future<void>.delayed(Duration.zero);
      if (startGeneration != _transportStartGeneration || !_starting) return;

      engine.resize(columns: cols, rows: rows);
      engine.initializeEmpty(rows, cols);
      final theme = _terminalTheme;
      if (theme != null) {
        _reconfigureEngineColors(theme);
      }

      if (validateLaunch) {
        final validationError = await CliExecutableValidator.validateLaunchAsync(
          executable: executable,
          workingDirectory: cwd,
        );
        if (validationError != null) {
          if (startGeneration == _transportStartGeneration && _starting) {
            _spawnRequested = false;
            _handleStartFailure(validationError);
          }
          return;
        }
      }
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
          write('\r\n[process exited with code $code]\r\n');
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
    activityTracker.reset();
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
    appLogger.e('[terminal] $message', error: error, stackTrace: stackTrace);
    write('\r\n$message\r\n');
    _onProcessFailed?.call(message);
    _onProcessFailed = null;
  }

  void _teardownPtyState() {
    _cancelStartupTimers();
    _ptyGeometryTimer?.cancel();
    _ptyGeometryTimer = null;
    _ptyGeometrySettleTimer?.cancel();
    _ptyGeometrySettleTimer = null;
    _outputSubscription?.cancel();
    _outputSubscription = null;
    _launchPhase = _LaunchPhase.idle;
    _startupExecutable = null;
    _onProcessStarted = null;
    activityTracker.reset();
  }

  void writeToPty(String text) {
    if (_transportReadyForIo && _transport != null) {
      _transport!.write(Uint8List.fromList(utf8.encode(text)));
    }
  }

  void writeln(String text) {
    writeToPty('$text\r');
  }

  void _writeOutput(String text) {
    if (text.isNotEmpty && isConnected) {
      activityTracker.markActive();
    }
    engine.feed(Uint8List.fromList(utf8.encode(text)));
    _schedulePtyGeometry();
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
    _hasPendingLayoutGeometry = false;
    _teardownPtyState();
    _onProcessFailed = null;
    _onProcessExited = null;
    _ptyEnvironment = null;
    _firstUserLineCapture = null;
    _engineOutputSubscription?.cancel();
    _engineOutputSubscription = null;
    _transport?.close();
    _transport = null;
  }

  void dispose() {
    disconnect();
    engine.dispose();
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
    final pty = Pty.start(
      spawnExecutable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      columns: columns,
      rows: rows,
      environment: environment,
    );
    appLogger.i("Pty started");
    return LocalPtyTransport(pty);
  }
}
