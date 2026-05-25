import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/app_error_utils.dart';
import '../../utils/logger_utils.dart';
import '../storage/app_storage.dart';
import '../io/filesystem.dart';

/// Persists noteworthy errors locally under `{appDataRoot}/logs/errors.jsonl`.
///
/// TeamPilot has no remote error-reporting API; this file is for support/debug.
class ErrorLogService {
  ErrorLogService({Filesystem? fs})
    : _fs = fs ?? AppStorage.fs;

  static final ErrorLogService instance = ErrorLogService();

  final Filesystem _fs;

  static const _lastRecordedDateKey = 'error_log_last_recorded_date';
  static const _recordedErrorsKey = 'error_log_recorded_errors';

  String? _appDataRoot;
  String? _platformLabel;
  PackageInfo? _packageInfo;
  bool _initialized = false;

  Future<void> initialize({required String appDataRoot}) async {
    _appDataRoot = appDataRoot.trim();
    _platformLabel = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    try {
      _packageInfo = await PackageInfo.fromPlatform();
    } on Object catch (e, stackTrace) {
      AppLogger.instance.e(
        '[ErrorLogService] package info unavailable',
        error: e,
        stackTrace: stackTrace,
        recordError: false,
      );
    }
    _initialized = true;
  }

  Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    String? module,
    String? action,
    String? context,
  }) async {
    final decision = AppErrorUtils.classify(error);
    if (!decision.shouldReport) {
      return;
    }

    AppLogger.instance.e(
      error.toString(),
      error: error,
      stackTrace: stackTrace,
      recordError: false,
    );

    final root = _appDataRoot;
    if (root == null || root.isEmpty) {
      return;
    }
    if (!_initialized) {
      await initialize(appDataRoot: root);
    }

    final errorKey = _errorKey(error, module: module, action: action);
    if (await _hasRecordedToday(errorKey)) {
      return;
    }

    try {
      final logDir = _fs.pathContext.join(root, 'logs');
      await _fs.ensureDir(logDir);

      final record = <String, Object?>{
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'errorType': error.runtimeType.toString(),
        'message': _messageFor(error),
        'stackTrace': stackTrace.toString(),
        'module': module,
        'action': action,
        'context': context,
        'platform': _platformLabel,
        'appVersion': _packageInfo?.version,
        'buildNumber': _packageInfo?.buildNumber,
      };

      final filePath = _fs.pathContext.join(logDir, 'errors.jsonl');
      await _fs.appendString(filePath, '${jsonEncode(record)}\n');

      await _markAsRecorded(errorKey);
    } on Object catch (e, st) {
      if (AppErrorUtils.isStorageError(e)) {
        return;
      }
      AppLogger.instance.e(
        '[ErrorLogService] failed to persist error',
        error: e,
        stackTrace: st,
        recordError: false,
      );
    }
  }

  String _messageFor(Object error) {
    if (error is FlutterError) {
      return error.diagnostics.map((d) => d.toString()).join('\n');
    }
    return error.toString();
  }

  String _errorKey(
    Object error, {
    String? module,
    String? action,
  }) {
    final message = _messageFor(error);
    final hashSource = message.length > 120 ? message.substring(0, 120) : message;
    return '${error.runtimeType}_${module ?? 'app'}_${action ?? 'unknown'}_${hashSource.hashCode}';
  }

  Future<bool> _hasRecordedToday(String errorKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now().toIso8601String().split('T').first;
      final lastRecordedDate = prefs.getString(_lastRecordedDateKey);

      if (lastRecordedDate != today) {
        await prefs.remove(_recordedErrorsKey);
        await prefs.setString(_lastRecordedDateKey, today);
        return false;
      }

      final recorded = prefs.getStringList(_recordedErrorsKey) ?? [];
      return recorded.contains(errorKey);
    } on PlatformException catch (e) {
      if (e.code == 'channel-error') return false;
      return false;
    } on Object {
      return false;
    }
  }

  Future<void> _markAsRecorded(String errorKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recorded = prefs.getStringList(_recordedErrorsKey) ?? [];
      if (!recorded.contains(errorKey)) {
        recorded.add(errorKey);
        await prefs.setStringList(_recordedErrorsKey, recorded);
      }
    } on Object {
      // Best-effort deduplication only.
    }
  }

  Future<void> clearRecordedErrors() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastRecordedDateKey);
    await prefs.remove(_recordedErrorsKey);
  }

  Future<int> getTodayRecordedErrorCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(_recordedErrorsKey) ?? []).length;
    } on Object {
      return 0;
    }
  }
}
