import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;

import '../../services/app/error_log_service.dart';
import 'app_error_utils.dart';

enum AppLogLevel { debug, info, warning, error }

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

  static const int _maxLogFileSize = 5 * 1024 * 1024;
  static const int _maxLogFiles = 5;
  static const int _maxLogAgeDays = 7;

  Logger? _consoleLogger;
  Logger? _fileLogger;
  _FlushingFileOutput? _fileLogOutput;
  File? _logFile;
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

  /// Initializes file logging at `{appDataRoot}/logs/app_YYYY-MM-DD.log`.
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
      _logFile = await _resolveLogFile(logDir);

      _fileLogOutput = _FlushingFileOutput(
        file: _logFile!,
        onWriteError: _handleFileWriteError,
      );
      await _fileLogOutput!.init();
      _fileLogger = Logger(
        printer: _printer(colors: false),
        output: _fileLogOutput!,
        filter: _FileLogFilter(),
      );

      _fileLoggerInitialized = true;
      _consoleLogger!.d('[AppLogger] file logging → ${_logFile!.path}');
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

  Future<File> _resolveLogFile(Directory logDir) async {
    final today = DateTime.now().toIso8601String().split('T').first;
    var file = File(p.join(logDir.path, 'app_$today.log'));
    if (await file.exists() && await file.length() > _maxLogFileSize) {
      final stamp = DateTime.now().millisecondsSinceEpoch;
      file = File(p.join(logDir.path, 'app_${today}_$stamp.log'));
    }
    return file;
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
    final file = _logFile;
    final logDirPath = _logDirPath;
    if (file == null || logDirPath == null || _fileLoggingDisabled) return;

    try {
      if (!await file.exists() || await file.length() <= _maxLogFileSize) {
        return;
      }

      final logDir = Directory(logDirPath);
      await _fileLogOutput?.destroy();
      _logFile = await _resolveLogFile(logDir);
      _fileLogOutput = _FlushingFileOutput(
        file: _logFile!,
        onWriteError: _handleFileWriteError,
      );
      await _fileLogOutput!.init();
      _fileLogger = Logger(
        printer: _printer(colors: false),
        output: _fileLogOutput!,
        filter: _FileLogFilter(),
      );
    } on Object catch (e) {
      if (AppErrorUtils.isStorageError(e)) {
        _disableFileLogging('File logging disabled after rotation: $e');
      }
    }
  }

  Future<void> _cleanOldLogs(Directory logDir) async {
    try {
      final files = <File>[];
      await for (final entity in logDir.list()) {
        if (entity is File &&
            (entity.path.endsWith('.log') || entity.path.endsWith('.jsonl'))) {
          files.add(entity);
        }
      }

      files.sort(
        (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
      );

      final now = DateTime.now();
      var deleted = 0;

      for (final file in files) {
        final age = now.difference(file.lastModifiedSync()).inDays;
        if (deleted >= _maxLogFiles || age > _maxLogAgeDays) {
          await file.delete();
          deleted++;
        }
      }
    } on Object catch (e) {
      _consoleLogger?.w('[AppLogger] failed to clean old logs: $e');
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
    _logFile = null;
    final output = _fileLogOutput;
    _fileLogOutput = null;
    if (output != null) {
      unawaited(output.destroy());
    }
    _consoleLogger?.w(reason);
  }

  /// Ensures buffered file log lines are visible on disk (tests / log viewer).
  @visibleForTesting
  Future<void> flushFileLogging() async {
    await _fileLogOutput?.flush();
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

  /// Sorted newest-first paths under `{appDataRoot}/logs/*.log`.
  Future<List<String>> listLogFiles({String? appDataRoot}) async {
    final dirPath =
        _logDirPath ??
        (appDataRoot != null ? p.join(appDataRoot, 'logs') : null);
    if (dirPath == null) return [];

    final logDir = Directory(dirPath);
    if (!await logDir.exists()) return [];

    final files = <String>[];
    await for (final entity in logDir.list()) {
      if (entity is File &&
          (entity.path.endsWith('.log') || entity.path.endsWith('.jsonl'))) {
        files.add(entity.path);
      }
    }

    files.sort((a, b) {
      return File(b).lastModifiedSync().compareTo(File(a).lastModifiedSync());
    });
    return files;
  }

  String? get currentLogFilePath => _logFile?.path;

  bool getFileLoggerInitialized() => _fileLoggerInitialized;

  /// Alias for [listLogFiles] (includes `app_*.log` and `errors.jsonl`).
  Future<List<String>> getLogFiles({String? appDataRoot}) =>
      listLogFiles(appDataRoot: appDataRoot);

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

/// Append-only file output that buffers lines and writes them off the caller's
/// isolate.
///
/// High-volume diagnostics (ACP frame mirroring emits several lines per model
/// token) must not do a synchronous write-with-flush on the UI isolate: at tens
/// of lines per second the fsyncs starve the frame loop. Lines are batched for
/// [_flushDelay] and written asynchronously; [flush] forces a write (tests, log
/// viewer, rotation, shutdown).
class _FlushingFileOutput extends LogOutput {
  _FlushingFileOutput({required this.file, this.onWriteError});

  final File file;

  /// Called when an asynchronous write fails (the logger disables file
  /// logging on storage errors).
  final void Function(Object error)? onWriteError;

  static const Duration _flushDelay = Duration(milliseconds: 200);

  final StringBuffer _buffer = StringBuffer();
  Timer? _flushTimer;
  Future<void> _pendingWrite = Future<void>.value();

  @override
  Future<void> init() async {}

  @override
  void output(OutputEvent event) {
    if (event.lines.isEmpty) return;
    for (final line in event.lines) {
      _buffer.writeln(line);
    }
    _flushTimer ??= Timer(_flushDelay, () {
      _flushTimer = null;
      unawaited(flush());
    });
  }

  Future<void> flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    final text = _buffer.toString();
    _buffer.clear();
    if (text.isEmpty) return _pendingWrite;
    _pendingWrite = _pendingWrite.then((_) => _append(text));
    return _pendingWrite;
  }

  Future<void> _append(String text) async {
    try {
      await file.writeAsString(text, mode: FileMode.append, flush: true);
    } on Object catch (error) {
      onWriteError?.call(error);
    }
  }

  @override
  Future<void> destroy() => flush();
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
