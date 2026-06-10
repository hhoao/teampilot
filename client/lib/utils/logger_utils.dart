import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;

import '../services/app/error_log_service.dart';
import 'app_error_utils.dart';

enum AppLogLevel { debug, info, warning, error }

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

  /// Frames inside [AppLogger] itself — stripped so [PrettyPrinter] shows the
  /// real call site.
  static const _excludePaths = [
    'package:teampilot/utils/logger_utils.dart',
  ];

  static PrettyPrinter _printer({
    required int methodCount,
    required int errorMethodCount,
    required int lineLength,
    required bool colors,
  }) {
    return PrettyPrinter(
      methodCount: methodCount,
      errorMethodCount: errorMethodCount,
      lineLength: lineLength,
      colors: colors,
      printEmojis: false,
      dateTimeFormat: DateTimeFormat.dateAndTime,
      excludePaths: _excludePaths,
    );
  }

  void _ensureConsoleLogger() {
    if (_consoleLogger != null) return;
    _consoleLogger = Logger(
      printer: _printer(
        methodCount: 2,
        errorMethodCount: 8,
        lineLength: 100,
        colors: true,
      ),
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

      _fileLogOutput = _FlushingFileOutput(file: _logFile!);
      await _fileLogOutput!.init();
      _fileLogger = Logger(
        printer: _printer(
          methodCount: 1,
          errorMethodCount: 8,
          lineLength: 120,
          colors: false,
        ),
        output: _fileLogOutput!,
        filter: _FileLogFilter(),
      );

      _fileLoggerInitialized = true;
      _consoleLogger!.i('[AppLogger] file logging → ${_logFile!.path}');
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
      stackTrace: stackTrace ?? StackTrace.current,
    );
  }

  void d(String message, {Object? error, StackTrace? stackTrace}) {
    _log(
      AppLogLevel.debug,
      message,
      error: error,
      stackTrace: stackTrace ?? StackTrace.current,
    );
  }

  void w(String message, {Object? error, StackTrace? stackTrace}) {
    _log(
      AppLogLevel.warning,
      message,
      error: error,
      stackTrace: stackTrace ?? StackTrace.current,
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
    _log(AppLogLevel.error, message, error: error, stackTrace: trace);
  }

  void _log(
    AppLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    _ensureConsoleLogger();

    final console = _consoleLogger!;
    switch (level) {
      case AppLogLevel.debug:
        console.d(message, error: error, stackTrace: stackTrace);
      case AppLogLevel.info:
        console.i(message, error: error, stackTrace: stackTrace);
      case AppLogLevel.warning:
        console.w(message, error: error, stackTrace: stackTrace);
      case AppLogLevel.error:
        console.e(message, error: error, stackTrace: stackTrace);
    }

    _writeToFile(level, message, error: error, stackTrace: stackTrace);
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
      unawaited(_rotateIfNeeded());
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
      _fileLogOutput = _FlushingFileOutput(file: _logFile!);
      await _fileLogOutput!.init();
      _fileLogger = Logger(
        printer: _printer(
          methodCount: 1,
          errorMethodCount: 8,
          lineLength: 120,
          colors: false,
        ),
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
    final ts = entry.timestamp.toIso8601String();
    final level = entry.level.name.toUpperCase();
    final buffer = StringBuffer('$ts | $level | ${entry.message}');
    if (entry.error != null) {
      buffer.writeln();
      buffer.write('Error: ${entry.error}');
    }
    if (entry.stackTrace != null) {
      buffer.writeln();
      buffer.write(entry.stackTrace);
    }
    return buffer.toString();
  }
}

/// Append-only file output with `flush: true` so Windows readers see full lines.
class _FlushingFileOutput extends LogOutput {
  _FlushingFileOutput({required this.file});

  final File file;

  @override
  Future<void> init() async {}

  @override
  void output(OutputEvent event) {
    if (event.lines.isEmpty) return;
    file.writeAsStringSync(
      '${event.lines.join('\n')}\n',
      mode: FileMode.append,
      flush: true,
    );
  }

  Future<void> flush() async {}

  @override
  Future<void> destroy() async {}
}

class _ConsoleLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    if (kDebugMode) return true;
    return event.level.index >= Level.info.index;
  }
}

class _FileLogFilter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    if (kDebugMode) return true;
    return event.level.index >= Level.info.index;
  }
}
