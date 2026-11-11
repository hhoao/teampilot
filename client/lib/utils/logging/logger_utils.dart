import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;

import '../../services/app/error_log_service.dart';
import 'app_error_utils.dart';
import 'app_log_level.dart';
import 'log_file_sink.dart';

export 'app_log_level.dart';

class _LogStyle {
  const _LogStyle(this.line);

  /// When null the record is printed without ANSI (e.g. unknown level).
  final String? line;
}

/// ANSI escapes for console output only (file logger uses [colors: false]).
abstract final class _Ansi {
  static const reset = '\u001b[0m';
  static const dim = '\u001b[90m';
  static const cyan = '\u001b[36m';
  static const yellow = '\u001b[33m';
  static const red = '\u001b[31m';
}

class _PendingLog {
  _PendingLog({
    required this.timestamp,
    required this.level,
    required this.message,
    this.error,
    this.stackTrace,
  });

  final DateTime timestamp;
  final AppLogLevel level;
  final String message;
  final Object? error;
  final StackTrace? stackTrace;
}

/// log4j-style single-line records with an IDE-clickable source column:
/// `2026-06-26 00:58:08.513 |  INFO 3992904 | package:teampilot/.../terminal_session.dart:831:15 | message`
class _Log4jStylePrinter extends LogPrinter {
  _Log4jStylePrinter({required this.colors});

  final bool colors;

  static const _excludePaths = [
    'package:teampilot/utils/logging/logger_utils.dart',
    'package:logger/',
  ];

  static int? _cachedPid;

  static int get _processId {
    if (kIsWeb) return 0;
    try {
      return _cachedPid ??= pid;
    } on Object {
      return 0;
    }
  }

  @override
  List<String> log(LogEvent event) {
    final time = event.time;
    final level = _levelLabel(event.level);
    final caller = _callerLocationFromStack(event.stackTrace);
    final source = caller ?? '?:?';
    final pid = _processId;
    final style = _styleFor(event.level);

    final body = StringBuffer()
      ..write(_formatTimestamp(time))
      ..write(' | ')
      ..write(level)
      ..write(' ')
      ..write(pid)
      ..write(' | ')
      ..write(source)
      ..write(' | ')
      ..write(event.message);

    if (event.error != null) {
      body.write(' | ${event.error}');
    }

    final lines = <String>[_colorize(body.toString(), style.line)];

    if (event.level.index >= Level.warning.index &&
        event.stackTrace != null &&
        _stackHasDiagnosticFrames(event.stackTrace!)) {
      lines.add(_colorize(event.stackTrace.toString().trimRight(), style.line));
    }

    return lines;
  }

  String _colorize(String text, String? ansiCode) {
    if (!colors || ansiCode == null) return text;
    return '$ansiCode$text${_Ansi.reset}';
  }

  static _LogStyle _styleFor(Level level) {
    return switch (level) {
      Level.debug => const _LogStyle(_Ansi.dim),
      Level.info => const _LogStyle(_Ansi.cyan),
      Level.warning => const _LogStyle(_Ansi.yellow),
      Level.error => const _LogStyle(_Ansi.red),
      _ => const _LogStyle(null),
    };
  }

  static String _levelLabel(Level level) {
    final raw = switch (level) {
      Level.debug => 'DEBUG',
      Level.info => 'INFO',
      Level.warning => 'WARN',
      Level.error => 'ERROR',
      _ => level.name.toUpperCase(),
    };
    return raw.padLeft(5);
  }

  static String _formatTimestamp(DateTime time) {
    final y = time.year.toString().padLeft(4, '0');
    final mo = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final h = time.hour.toString().padLeft(2, '0');
    final mi = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    final ms = time.millisecond.toString().padLeft(3, '0');
    return '$y-$mo-$d $h:$mi:$s.$ms';
  }

  static bool _stackHasDiagnosticFrames(StackTrace trace) {
    for (final line in trace.toString().split('\n')) {
      if (line.trim().isEmpty) continue;
      if (_isExcludedFrame(line)) continue;
      return true;
    }
    return false;
  }

  static String? _callerLocationFromStack(StackTrace? trace) {
    if (trace == null) return null;
    for (final line in trace.toString().split('\n')) {
      if (line.trim().isEmpty || _isExcludedFrame(line)) continue;
      final location = _parseFrameLocation(line);
      if (location != null) return location;
    }
    return null;
  }

  static bool _isExcludedFrame(String line) {
    for (final path in _excludePaths) {
      if (line.contains(path)) return true;
    }
    return false;
  }

  static final _framePattern = RegExp(r'^#\d+\s+(.+?)\s+\((.+)\)\s*$');

  static String? _parseFrameLocation(String line) {
    final match = _framePattern.firstMatch(line.trim());
    if (match == null) return null;
    return _sourceLink(match.group(2)!.trim());
  }

  /// Keeps `package:…/file.dart:line:col` intact so Cursor/VS Code can linkify.
  static String _sourceLink(String raw) {
    final trimmed = raw.trim();
    if (trimmed.startsWith('package:')) return trimmed;
    if (trimmed.startsWith('file://')) {
      try {
        return Uri.parse(trimmed).toFilePath(windows: Platform.isWindows);
      } on Object {
        // VM stack frames may use file URIs without a full path on Windows.
        return trimmed;
      }
    }
    return trimmed;
  }
}

/// Console + rotating file logging under `{appDataRoot}/logs/`.
class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  static const int _maxLogFiles = 5;
  static const int _maxLogAgeDays = 7;

  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  @visibleForTesting
  int maxLogFileSize = 5 * 1024 * 1024;

  @visibleForTesting
  bool? writeDebugFilesForTest;

  Logger? _consoleLogger;
  Logger? _fileLogger;
  LevelFanoutOutput? _fanout;
  List<LogFileSink> _sinks = [];
  String? _logDirPath;

  bool _fileLoggerInitialized = false;
  bool _fileLoggerInitializing = false;
  bool _fileLoggingDisabled = false;

  final List<_PendingLog> _pendingFileLogs = [];

  LogPrinter _printer({required bool colors}) =>
      _Log4jStylePrinter(colors: colors);

  void _ensureConsoleLogger() {
    if (_consoleLogger != null) return;
    _consoleLogger = Logger(
      printer: _printer(colors: true),
      output: ConsoleOutput(),
      filter: _ConsoleLogFilter(),
    );
  }

  /// Waits for or starts file logging (safe to call from the log viewer).
  Future<void> ensureFileLogging(String appDataRoot) async {
    if (_fileLoggerInitialized || _fileLoggingDisabled) return;
    while (_fileLoggerInitializing) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (!_fileLoggerInitialized && !_fileLoggingDisabled) {
      await initFileLogging(appDataRoot);
    }
  }

  /// Initializes cascade file logging at `{appDataRoot}/logs/{level}/latest.log`.
  Future<void> initFileLogging(String appDataRoot) async {
    _ensureConsoleLogger();

    if (_fileLoggerInitialized ||
        _fileLoggerInitializing ||
        _fileLoggingDisabled) {
      return;
    }

    _fileLoggerInitializing = true;
    try {
      final logDir = Directory(p.join(appDataRoot, 'logs'));
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      _logDirPath = logDir.path;
      await _cleanOldLogs(logDir);

      final includeDebug = writeDebugFilesForTest ?? kDebugMode;
      final levels = <AppLogLevel>[
        if (includeDebug) AppLogLevel.debug,
        AppLogLevel.info,
        AppLogLevel.warning,
        AppLogLevel.error,
      ];
      _sinks = [
        for (final level in levels)
          LogFileSink(
            logsRoot: logDir.path,
            level: level,
            clock: () => clock(),
            maxLogFileSize: maxLogFileSize,
            onWriteError: _handleFileWriteError,
          ),
      ];
      for (final sink in _sinks) {
        await sink.init();
      }
      _fanout = LevelFanoutOutput(_sinks);
      _fileLogger = Logger(
        printer: _printer(colors: false),
        output: _fanout!,
        filter: _FileLogFilter(),
      );

      _fileLoggerInitialized = true;
      _consoleLogger!.d('[AppLogger] file logging → $currentLogFilePath');
      await _flushPendingFileLogs();
    } on Object catch (e) {
      if (AppErrorUtils.isStorageError(e)) {
        _disableFileLogging('File logging disabled (storage): $e');
      } else {
        _consoleLogger!.w('[AppLogger] file logging init failed: $e');
      }
    } finally {
      _fileLoggerInitializing = false;
    }
  }

  void i(String message, {Object? error, StackTrace? stackTrace}) {
    _log(
      AppLogLevel.info,
      message,
      error: error,
      stackTrace: stackTrace,
      captureCaller: stackTrace == null,
    );
  }

  void d(String message, {Object? error, StackTrace? stackTrace}) {
    _log(
      AppLogLevel.debug,
      message,
      error: error,
      stackTrace: stackTrace,
      captureCaller: stackTrace == null,
    );
  }

  void w(String message, {Object? error, StackTrace? stackTrace}) {
    _log(
      AppLogLevel.warning,
      message,
      error: error,
      stackTrace: stackTrace,
      captureCaller: stackTrace == null,
    );
  }

  void e(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    bool recordError = true,
  }) {
    final trace = stackTrace ?? StackTrace.current;
    if (recordError && error != null) {
      final decision = AppErrorUtils.classify(error);
      AppErrorUtils.showDecisionMessage(decision);
      if (decision.shouldReport) {
        unawaited(
          ErrorLogService.instance.recordError(
            error,
            trace,
            module: 'app',
            action: message,
          ),
        );
      }
    }
    _log(
      AppLogLevel.error,
      message,
      error: error,
      stackTrace: trace,
      captureCaller: stackTrace == null,
    );
  }

  void _log(
    AppLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    required bool captureCaller,
  }) {
    _ensureConsoleLogger();

    final trace = captureCaller ? StackTrace.current : stackTrace;
    final console = _consoleLogger!;
    switch (level) {
      case AppLogLevel.debug:
        console.d(message, error: error, stackTrace: trace);
      case AppLogLevel.info:
        console.i(message, error: error, stackTrace: trace);
      case AppLogLevel.warning:
        console.w(message, error: error, stackTrace: trace);
      case AppLogLevel.error:
        console.e(message, error: error, stackTrace: trace);
    }

    _writeToFile(level, message, error: error, stackTrace: trace);
  }

  void _writeToFile(
    AppLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (_fileLoggingDisabled) return;

    if (!_fileLoggerInitialized || _fileLogger == null) {
      _pendingFileLogs.add(
        _PendingLog(
          timestamp: DateTime.now(),
          level: level,
          message: message,
          error: error,
          stackTrace: stackTrace,
        ),
      );
      return;
    }

    try {
      switch (level) {
        case AppLogLevel.debug:
          _fileLogger!.d(message, error: error, stackTrace: stackTrace);
        case AppLogLevel.info:
          _fileLogger!.i(message, error: error, stackTrace: stackTrace);
        case AppLogLevel.warning:
          _fileLogger!.w(message, error: error, stackTrace: stackTrace);
        case AppLogLevel.error:
          _fileLogger!.e(message, error: error, stackTrace: stackTrace);
      }
      _maybeRotate();
    } on Object catch (e) {
      if (AppErrorUtils.isStorageError(e)) {
        _disableFileLogging('File logging disabled after write failure: $e');
        _pendingFileLogs.add(
          _PendingLog(
            timestamp: DateTime.now(),
            level: level,
            message: message,
            error: error,
            stackTrace: stackTrace,
          ),
        );
      }
    }
  }

  Future<void> _flushPendingFileLogs() async {
    if (_fileLogger == null || _pendingFileLogs.isEmpty) return;

    final pending = List<_PendingLog>.from(_pendingFileLogs);
    _pendingFileLogs.clear();

    for (final entry in pending) {
      _writeToFile(
        entry.level,
        entry.message,
        error: entry.error,
        stackTrace: entry.stackTrace,
      );
    }
  }

  /// Size-checks the log file at most once per [_rotateCheckInterval] — every
  /// buffered line used to trigger a stat pair, which is pure overhead while a
  /// chatty agent streams.
  static const Duration _rotateCheckInterval = Duration(seconds: 5);
  DateTime? _lastRotateCheck;

  void _maybeRotate() {
    final now = DateTime.now();
    final last = _lastRotateCheck;
    if (last != null && now.difference(last) < _rotateCheckInterval) return;
    _lastRotateCheck = now;
    unawaited(_rotateIfNeeded());
  }

  Future<void> _rotateIfNeeded() async {
    if (_fileLoggingDisabled) return;
    try {
      for (final sink in _sinks) {
        final ok = await sink.rotateIfNeeded();
        if (!ok) {
          _consoleLogger?.w(
            '[AppLogger] failed to archive ${sink.latestFile.path}; keeping latest.log',
          );
        }
      }
    } on Object catch (e) {
      if (AppErrorUtils.isStorageError(e)) {
        _disableFileLogging('File logging disabled after rotation: $e');
      }
    }
  }

  @visibleForTesting
  Future<void> checkRotationForTest() async {
    _lastRotateCheck = null;
    await _rotateIfNeeded();
  }

  Future<void> _cleanOldLogs(Directory logDir) async {
    try {
      final includeDebug = writeDebugFilesForTest ?? kDebugMode;
      final dirs = <Directory>[
        for (final level in [
          if (includeDebug) AppLogLevel.debug,
          AppLogLevel.info,
          AppLogLevel.warning,
          AppLogLevel.error,
        ])
          Directory(p.join(logDir.path, level.directoryName)),
      ];
      for (final dir in dirs) {
        await _cleanDirectory(dir, dropByAgeAndCount: true);
      }
      await _cleanDirectory(logDir, dropByAgeAndCount: false, recursive: false);
    } on Object catch (e) {
      _consoleLogger?.w('[AppLogger] failed to clean old logs: $e');
    }
  }

  Future<void> _cleanDirectory(
    Directory dir, {
    required bool dropByAgeAndCount,
    bool recursive = true,
  }) async {
    if (!await dir.exists()) return;
    final files = <File>[];
    await for (final entity in dir.list(recursive: recursive)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name == 'latest.log' || name == 'errors.jsonl') continue;
      if (!name.endsWith('.log')) continue;
      files.add(entity);
    }
    files.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );
    final now = clock();
    var kept = 0;
    for (final file in files) {
      final age = now.difference(file.lastModifiedSync()).inDays;
      final dropAge = age > _maxLogAgeDays;
      final dropCount = dropByAgeAndCount && kept >= _maxLogFiles;
      if (dropAge || dropCount) {
        await file.delete();
      } else {
        kept++;
      }
    }
  }

  /// File writes happen off the logging call site, so write failures surface
  /// here instead of the `_writeToFile` try/catch.
  void _handleFileWriteError(Object error) {
    if (_fileLoggingDisabled) return;
    if (AppErrorUtils.isStorageError(error)) {
      _disableFileLogging('File logging disabled after write failure: $error');
    }
  }

  void _disableFileLogging(String reason) {
    _fileLoggingDisabled = true;
    _fileLoggerInitialized = false;
    _fileLogger = null;
    _sinks = [];
    final fanout = _fanout;
    _fanout = null;
    if (fanout != null) {
      unawaited(fanout.destroy());
    }
    _consoleLogger?.w(reason);
  }

  /// Ensures buffered file log lines are visible on disk (tests / log viewer).
  @visibleForTesting
  Future<void> flushFileLogging() async {
    await _fanout?.flush();
  }

  /// Reads log text (tail of large files) with a timeout.
  Future<List<String>> readLogFileLines(
    String filePath, {
    Duration timeout = const Duration(seconds: 20),
    int maxBytes = 512 * 1024,
  }) {
    Future<List<String>> read() async {
      final file = File(filePath);
      if (!await file.exists()) return const [];

      final length = await file.length();
      if (length == 0) return const [];

      final start = length > maxBytes ? length - maxBytes : 0;
      final raf = await file.open(mode: FileMode.read);
      try {
        if (start > 0) {
          await raf.setPosition(start);
        }
        final bytes = await raf.read(length - start);
        var text = utf8.decode(bytes, allowMalformed: true);
        if (start > 0) {
          final firstNewline = text.indexOf('\n');
          if (firstNewline >= 0) {
            text = text.substring(firstNewline + 1);
          }
        }
        return text.split('\n');
      } finally {
        await raf.close();
      }
    }

    return read().timeout(
      timeout,
      onTimeout: () =>
          throw TimeoutException('Reading log file timed out', timeout),
    );
  }

  /// Sorted paths under one `{appDataRoot}/logs/{level}/` directory.
  ///
  /// Omit [level] to list the full-timeline directory (`debug` in debug
  /// builds, `info` otherwise). `latest.log` is first when present.
  Future<List<String>> listLogFiles({
    String? appDataRoot,
    AppLogLevel? level,
  }) async {
    final dirPath =
        _logDirPath ??
        (appDataRoot != null ? p.join(appDataRoot, 'logs') : null);
    if (dirPath == null) return [];
    final includeDebug = writeDebugFilesForTest ?? kDebugMode;
    final resolved = level ?? fullTimelineLogLevel(includeDebug: includeDebug);
    return listLogFilesIn(Directory(p.join(dirPath, resolved.directoryName)));
  }

  String? get currentLogFilePath {
    final includeDebug = writeDebugFilesForTest ?? kDebugMode;
    final wanted = fullTimelineLogLevel(includeDebug: includeDebug);
    for (final sink in _sinks) {
      if (sink.level == wanted) return sink.latestFile.path;
    }
    return _sinks.isEmpty ? null : _sinks.first.latestFile.path;
  }

  bool getFileLoggerInitialized() => _fileLoggerInitialized;

  /// Alias for [listLogFiles].
  Future<List<String>> getLogFiles({
    String? appDataRoot,
    AppLogLevel? level,
  }) => listLogFiles(appDataRoot: appDataRoot, level: level);

  @visibleForTesting
  Future<void> resetForTest() async {
    _fileLoggingDisabled = false;
    _fileLoggerInitialized = false;
    _fileLoggerInitializing = false;
    _pendingFileLogs.clear();
    _fileLogger = null;
    _consoleLogger = null;
    _logDirPath = null;
    _lastRotateCheck = null;
    clock = DateTime.now;
    maxLogFileSize = 5 * 1024 * 1024;
    writeDebugFilesForTest = null;
    final fanout = _fanout;
    _fanout = null;
    _sinks = [];
    if (fanout != null) {
      await fanout.destroy();
    }
  }

  Future<void> clearOldLogs() async {
    final dirPath = _logDirPath;
    if (dirPath == null) return;
    await _cleanOldLogs(Directory(dirPath));
  }

  int get pendingLogCount => _pendingFileLogs.length;

  String getFormattedPendingLogs() {
    if (_pendingFileLogs.isEmpty) {
      return '（暂无待写入磁盘的日志）';
    }
    final buffer = StringBuffer();
    for (final entry in _pendingFileLogs) {
      buffer.writeln(_formatPendingEntry(entry));
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  Future<List<String>> getPendingLogLines() async {
    return _pendingFileLogs.map(_formatPendingEntry).toList();
  }

  String _formatPendingEntry(_PendingLog entry) {
    final printer = _Log4jStylePrinter(colors: false);
    final level = switch (entry.level) {
      AppLogLevel.debug => Level.debug,
      AppLogLevel.info => Level.info,
      AppLogLevel.warning => Level.warning,
      AppLogLevel.error => Level.error,
    };
    return printer
        .log(
          LogEvent(
            level,
            entry.message,
            time: entry.timestamp,
            error: entry.error,
            stackTrace: entry.stackTrace,
          ),
        )
        .join('\n');
  }
}

class _ConsoleLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    // Debug builds: full console tracing. Release/profile: warnings and errors only.
    final minLevel = kDebugMode ? Level.debug : Level.warning;
    return event.level.index >= minLevel.index;
  }
}

class _FileLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    // Debug builds: persist DEBUG for the in-app log viewer. Release: INFO+ only.
    final minLevel = kDebugMode ? Level.debug : Level.info;
    return event.level.index >= minLevel.index;
  }
}
