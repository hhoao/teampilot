import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;

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
  File? _logFile;
  String? _logDirPath;

  bool _fileLoggerInitialized = false;
  bool _fileLoggerInitializing = false;
  bool _fileLoggingDisabled = false;

  final List<_PendingLog> _pendingFileLogs = [];

  void _ensureConsoleLogger() {
    if (_consoleLogger != null) return;
    _consoleLogger = Logger(
      printer: PrettyPrinter(
        methodCount: 1,
        errorMethodCount: 5,
        lineLength: 100,
        colors: true,
        printEmojis: false,
        dateTimeFormat: DateTimeFormat.dateAndTime,
      ),
      output: ConsoleOutput(),
      filter: _ConsoleLogFilter(),
    );
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

      _fileLogger = Logger(
        printer: PrettyPrinter(
          methodCount: 0,
          errorMethodCount: 8,
          lineLength: 120,
          colors: false,
          printEmojis: false,
          dateTimeFormat: DateTimeFormat.dateAndTime,
        ),
        output: FileOutput(file: _logFile!),
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
    _log(AppLogLevel.info, message, error: error, stackTrace: stackTrace);
  }

  void d(String message, {Object? error, StackTrace? stackTrace}) {
    _log(AppLogLevel.debug, message, error: error, stackTrace: stackTrace);
  }

  void w(String message, {Object? error, StackTrace? stackTrace}) {
    _log(AppLogLevel.warning, message, error: error, stackTrace: stackTrace);
  }

  void e(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    bool recordError = true,
  }) {
    if (recordError && error != null) {
      final decision = AppErrorUtils.classify(error);
      AppErrorUtils.showDecisionMessage(decision);
    }
    _log(
      AppLogLevel.error,
      message,
      error: error,
      stackTrace: stackTrace ?? (error != null ? StackTrace.current : null),
    );
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
      _logFile = await _resolveLogFile(logDir);
      _fileLogger = Logger(
        printer: PrettyPrinter(
          methodCount: 0,
          errorMethodCount: 8,
          lineLength: 120,
          colors: false,
          printEmojis: false,
          dateTimeFormat: DateTimeFormat.dateAndTime,
        ),
        output: FileOutput(file: _logFile!),
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
    _consoleLogger?.w(reason);
  }

  /// Sorted newest-first paths under `{appDataRoot}/logs/*.log`.
  Future<List<String>> listLogFiles() async {
    final dirPath = _logDirPath;
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
  Future<List<String>> getLogFiles() => listLogFiles();

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
