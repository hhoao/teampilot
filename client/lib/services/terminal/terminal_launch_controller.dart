import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_alacritty/flutter_alacritty.dart';

import '../../cubits/agent_attention_cubit.dart';
import '../../utils/logging/logger.dart';
import '../../utils/terminal/osc_title_extractor.dart';
import '../agent_status/agent_attention_state.dart';
import '../agent_status/agent_status_event.dart';
import '../agent_status/cursor_title_attention.dart';
import '../cli/cli_executable_validator.dart';
import '../team/terminal_activity_tracker.dart';
import 'terminal_startup_failure_detector.dart';
import 'terminal_theme_mapper.dart';
import 'terminal_transport.dart';
import 'terminal_transport_starter.dart';

/// PTY attach → confirm → running. See [onPtyOutput] and [_confirmProcessStarted].
enum TerminalLaunchPhase { idle, spawning, confirming, running, failed }

/// Owns transport spawn, startup timers, and launch-phase state machine.
///
/// SRP: session facade delegates lifecycle; this class does not know about bus,
/// links, or fullscreen input semantics.
final class TerminalLaunchController {
  TerminalLaunchController({
    required this.engine,
    required this.activityTracker,
    required this.defaultExecutable,
    required this.startupDeadline,
    required this.confirmFallback,
    required this.validateLaunch,
    TransportStarter? transportStarter,
    int scrollbackLines = 10000,
    TerminalTheme? Function()? terminalTheme,
  }) : _transportStarter = transportStarter ?? defaultTransportStarter,
       _scrollbackLines = scrollbackLines,
       _terminalTheme = terminalTheme;

  final TerminalEngine engine;
  final TerminalActivityTracker activityTracker;
  final String defaultExecutable;
  final Duration startupDeadline;
  final Duration confirmFallback;
  final bool validateLaunch;
  final TransportStarter _transportStarter;
  final int _scrollbackLines;
  final TerminalTheme? Function()? _terminalTheme;

  TerminalTransport? _transport;
  var _phase = TerminalLaunchPhase.idle;
  var _startFailed = false;
  var _spawnRequested = false;
  var _transportStartGeneration = 0;
  var _disposed = false;
  String? _startupExecutable;
  Timer? _confirmFallbackTimer;
  Timer? _startupDeadlineTimer;
  StreamSubscription<Uint8List>? _outputSubscription;
  int? _pendingPtyResizeCols;
  int? _pendingPtyResizeRows;

  int pendingViewportCols = 80;
  int pendingViewportRows = 24;

  VoidCallback? onProcessStarted;
  void Function(String message)? onProcessFailed;
  VoidCallback? onProcessExited;
  void Function(String text)? writeToDisplay;
  void Function()? onConfirmedRunning;

  /// Cursor-only OSC title → attention binding (null until [bindCursorTitleAttention]).
  String? _cursorSessionId;
  String? _cursorMemberId;
  AgentAttentionCubit? _cursorAttention;
  bool Function()? _cursorSkipPermissions;
  OscTitleExtractor? _cursorOscTitles;
  var _cursorTitleWaiting = false;

  bool get isDisposed => _disposed;

  /// Local PTY pid from the active transport, if any.
  int? get pid => _transport?.pid;

  /// Enable live OSC title attention for a Cursor seat. No-op for other CLIs —
  /// only call when the seat launches Cursor.
  void bindCursorTitleAttention({
    required String sessionId,
    required String memberId,
    required AgentAttentionCubit attention,
    required bool Function() skipPermissions,
  }) {
    _cursorSessionId = sessionId;
    _cursorMemberId = memberId;
    _cursorAttention = attention;
    _cursorSkipPermissions = skipPermissions;
    _cursorOscTitles = OscTitleExtractor();
    _cursorTitleWaiting = false;
  }

  /// Drop Cursor title observation (disconnect / non-Cursor reconnect).
  void clearCursorTitleAttention() {
    _cursorSessionId = null;
    _cursorMemberId = null;
    _cursorAttention = null;
    _cursorSkipPermissions = null;
    _cursorOscTitles?.reset();
    _cursorOscTitles = null;
    _cursorTitleWaiting = false;
  }

  bool get startFailed => _startFailed;
  TerminalLaunchPhase get phase => _phase;

  bool get isRunning =>
      (_phase == TerminalLaunchPhase.running ||
          _phase == TerminalLaunchPhase.confirming ||
          _phase == TerminalLaunchPhase.spawning) &&
      !_startFailed;

  bool get isConnecting =>
      !_startFailed &&
      (_phase == TerminalLaunchPhase.spawning ||
          _phase == TerminalLaunchPhase.confirming);

  bool get isConnected =>
      !_startFailed && _phase == TerminalLaunchPhase.running;

  bool get _starting =>
      _phase == TerminalLaunchPhase.spawning ||
      _phase == TerminalLaunchPhase.confirming;

  bool get transportReadyForIo =>
      _transport != null &&
      (_phase == TerminalLaunchPhase.confirming ||
          _phase == TerminalLaunchPhase.running);

  void markDisposed() => _disposed = true;

  /// Synchronous pre-spawn validation failure (executable/cwd checks).
  void failLaunch(String message) => _handleStartFailure(message);

  void beginStartup(String executable) {
    _startupExecutable = executable;
    _phase = TerminalLaunchPhase.spawning;
    _startFailed = false;
    _armStartupDeadline();
  }

  void spawnTransport({
    required String executable,
    required List<String> args,
    required String cwd,
    required Map<String, String>? environment,
    required int cols,
    required int rows,
  }) {
    if (_spawnRequested || _transport != null) return;
    _spawnRequested = true;
    unawaited(
      _startTransport(
        executable: executable,
        args: args,
        cwd: cwd,
        environment: environment,
        cols: cols,
        rows: rows,
      ),
    );
  }

  void onTerminalPtyResize(int columns, int rows) {
    if (columns < kMinTerminalColumns || rows < kMinTerminalRows) return;
    pendingViewportCols = columns;
    pendingViewportRows = rows;
    if (!transportReadyForIo || _transport == null) {
      _pendingPtyResizeCols = columns;
      _pendingPtyResizeRows = rows;
      return;
    }
    _transport!.resize(rows, columns);
  }

  @visibleForTesting
  void onViewportResize(int columns, int rows) {
    if (columns < kMinTerminalColumns || rows < kMinTerminalRows) return;
    pendingViewportCols = columns;
    pendingViewportRows = rows;
    engine.resize(columns: columns, rows: rows);
    _syncPtyGeometryNow(columns, rows);
    _scheduleLayoutPtyGeometrySettle();
  }

  void writeToPty(Uint8List data) {
    if (transportReadyForIo && _transport != null) {
      _transport!.write(data);
    }
  }

  void feedPtyBytes(Uint8List data) {
    if (data.isEmpty) return;
    if (isConnected) {
      activityTracker.notePtyBytes(data);
    }
    _observeCursorOscTitles(data);
    engine.feed(data);
  }

  void _observeCursorOscTitles(Uint8List data) {
    final extractor = _cursorOscTitles;
    final attention = _cursorAttention;
    final sessionId = _cursorSessionId;
    final memberId = _cursorMemberId;
    final skipPermissions = _cursorSkipPermissions;
    if (extractor == null ||
        attention == null ||
        sessionId == null ||
        memberId == null ||
        skipPermissions == null) {
      return;
    }

    final text = utf8.decode(data, allowMalformed: true);
    for (final title in extractor.push(text)) {
      _applyCursorTitle(title, attention, sessionId, memberId, skipPermissions);
    }
  }

  void _applyCursorTitle(
    String title,
    AgentAttentionCubit attention,
    String sessionId,
    String memberId,
    bool Function() skipPermissions,
  ) {
    // Bare native title is a no-op so per-turn re-emissions cannot clear sticky
    // waiting (Orca rule). Clear only on a non-native title that is not waiting.
    if (isCursorNativeTitle(title)) return;

    final classified = detectCursorTitleAttention(title);
    if (classified == AgentSeatAttention.waiting) {
      final skip = skipPermissions();
      attention.applyEvent(
        sessionId: sessionId,
        memberId: memberId,
        event: const AgentStatusEvent(state: AgentSeatAttention.waiting),
        skipPermissions: skip,
      );
      if (!skip) _cursorTitleWaiting = true;
      return;
    }

    if (_cursorTitleWaiting) {
      attention.applyEvent(
        sessionId: sessionId,
        memberId: memberId,
        event: const AgentStatusEvent(state: AgentSeatAttention.done),
        skipPermissions: skipPermissions(),
      );
      _cursorTitleWaiting = false;
    }
  }

  void disconnect() {
    _transportStartGeneration++;
    _startFailed = false;
    _spawnRequested = false;
    clearCursorTitleAttention();
    _teardownPtyState();
    onProcessFailed = null;
    onProcessExited = null;
    _transport?.close();
    _transport = null;
  }

  void dispose() {
    markDisposed();
    disconnect();
  }

  void _flushPendingPtyResize() {
    final cols = _pendingPtyResizeCols;
    final rows = _pendingPtyResizeRows;
    _pendingPtyResizeCols = null;
    _pendingPtyResizeRows = null;
    if (cols == null || rows == null) return;
    if (!transportReadyForIo || _transport == null) return;
    _transport!.resize(rows, cols);
  }

  void _syncPtyGeometryNow(int cols, int rows) {
    if (cols <= 0 || rows <= 0) return;
    if (_transport == null) return;
    if (!transportReadyForIo) return;
    _transport!.resize(rows, cols);
  }

  void _scheduleLayoutPtyGeometrySettle() {
    Timer(const Duration(milliseconds: 80), () {
      if (_transport == null || !transportReadyForIo) return;
      _syncPtyGeometryNow(pendingViewportCols, pendingViewportRows);
    });
  }

  bool _startTransportAborted(int startGeneration) =>
      _disposed || startGeneration != _transportStartGeneration || !_starting;

  void _enterConfirmingPhase() {
    if (_phase != TerminalLaunchPhase.spawning) return;
    _phase = TerminalLaunchPhase.confirming;
    _flushPendingPtyResize();
    _confirmFallbackTimer?.cancel();
    _confirmFallbackTimer = Timer(confirmFallback, _confirmProcessStarted);
  }

  void _armStartupDeadline() {
    _startupDeadlineTimer?.cancel();
    _startupDeadlineTimer = Timer(startupDeadline, _onStartupDeadline);
  }

  void _onStartupDeadline() {
    if (!_starting || _startFailed) return;
    final cliExecutable = _startupExecutable ?? defaultExecutable;
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

  Future<void> _startTransport({
    required String executable,
    required List<String> args,
    required String cwd,
    required Map<String, String>? environment,
    required int cols,
    required int rows,
  }) async {
    final startGeneration = ++_transportStartGeneration;
    try {
      await Future<void>.delayed(Duration.zero);
      if (_startTransportAborted(startGeneration)) return;

      final startCols = pendingViewportCols;
      final startRows = pendingViewportRows;
      engine.resize(columns: startCols, rows: startRows);
      engine.initializeEmpty(startRows, startCols);
      final theme = _terminalTheme?.call();
      if (theme != null) {
        engine.reconfigure(
          terminalConfigFromTheme(theme, scrollbackLines: _scrollbackLines),
        );
      }

      if (validateLaunch) {
        final validationError =
            await CliExecutableValidator.validateLaunchPathLookupAsync(
              executable,
            );
        if (validationError != null) {
          if (!_startTransportAborted(startGeneration)) {
            _spawnRequested = false;
            _handleStartFailure(validationError);
          }
          return;
        }
        if (_startTransportAborted(startGeneration)) return;
      }

      final transport = await _transportStarter(
        executable,
        arguments: args,
        workingDirectory: cwd,
        columns: cols,
        rows: rows,
        environment: environment,
      );
      if (_startTransportAborted(startGeneration)) {
        transport.close();
        return;
      }
      _transport = transport;
      _enterConfirmingPhase();

      _outputSubscription = transport.output.listen((Uint8List data) {
        if (data.isEmpty) return;
        feedPtyBytes(data);
        final text = utf8.decode(data, allowMalformed: true);
        if (TerminalStartupFailureDetector.looksLikeCliStartupFailure(text)) {
          appLogger.e('[terminal] CLI error: ${text.trim()}');
        }
        if (!_starting || _startFailed) return;
        if (TerminalStartupFailureDetector.looksLikeCliStartupFailure(text)) {
          _handleStartFailure(
            TerminalStartupFailureDetector.launchFailureMessage(
              executable,
              validateLaunch: validateLaunch,
            ),
          );
          return;
        }
        if (TerminalStartupFailureDetector.looksLikeExecFailure(text)) {
          _handleStartFailure(
            TerminalStartupFailureDetector.launchFailureMessage(
              executable,
              validateLaunch: validateLaunch,
            ),
          );
          return;
        }
        _confirmProcessStarted();
      });

      transport.done.then((code) {
        if (_disposed ||
            startGeneration != _transportStartGeneration ||
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
        if (_phase != TerminalLaunchPhase.running) {
          return;
        }
        if (code != 0) {
          final message = '[process exited with code $code]';
          appLogger.w(
            '[terminal] $message '
            '(executable: ${CliExecutableValidator.cliDisplayName(executable)})',
          );
          writeToDisplay?.call('\r\n$message\r\n');
          return;
        }
        if (_transport == transport) {
          transport.close();
          _transport = null;
        }
        _teardownPtyState();
        final callback = onProcessExited;
        onProcessExited = null;
        callback?.call();
      });
    } on Object catch (error, stackTrace) {
      if (_startTransportAborted(startGeneration)) {
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
    if (_phase != TerminalLaunchPhase.confirming ||
        _startFailed ||
        _transport == null) {
      return;
    }
    _phase = TerminalLaunchPhase.running;
    activityTracker.reset();
    _cancelStartupTimers();
    final cliExecutable = _startupExecutable ?? defaultExecutable;
    appLogger.d(
      '[terminal] started ${CliExecutableValidator.cliDisplayName(cliExecutable)}',
    );
    onConfirmedRunning?.call();
    final callback = onProcessStarted;
    onProcessStarted = null;
    callback?.call();
  }

  void _handleStartFailure(
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (_startFailed) return;
    _startFailed = true;
    _phase = TerminalLaunchPhase.failed;
    _spawnRequested = false;
    _cancelStartupTimers();
    _outputSubscription?.cancel();
    _outputSubscription = null;
    onProcessStarted = null;
    onProcessExited = null;
    _transport?.close();
    _transport = null;
    _startupExecutable = null;
    appLogger.e('[terminal] $message', error: error, stackTrace: stackTrace);
    writeToDisplay?.call('\r\n$message\r\n');
    onProcessFailed?.call(message);
    onProcessFailed = null;
  }

  void _teardownPtyState() {
    _spawnRequested = false;
    _pendingPtyResizeCols = null;
    _pendingPtyResizeRows = null;
    _cancelStartupTimers();
    _outputSubscription?.cancel();
    _outputSubscription = null;
    _phase = TerminalLaunchPhase.idle;
    _startupExecutable = null;
    onProcessStarted = null;
    activityTracker.reset();
  }
}
