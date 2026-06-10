import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/app/error_log_service.dart';
import 'logger_utils.dart';

export 'logger_utils.dart' show AppLogger;

/// App-wide logger — [AppLogger.instance] is the single implementation.
final appLogger = AppLogger.instance;

/// Initializes rotating file logs and global Flutter error hooks.
Future<void> initAppLogging(String appDataRoot) async {
  await AppLogger.instance.initFileLogging(appDataRoot);
  await ErrorLogService.instance.initialize(appDataRoot: appDataRoot);

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    final error = details.exception;
    final stack = details.stack ?? StackTrace.current;
    AppLogger.instance.e(
      '[FlutterError] ${details.summary}',
      error: error,
      stackTrace: stack,
      recordError: false,
    );
    unawaited(
      ErrorLogService.instance.recordError(
        error,
        stack,
        module: 'flutter',
        action: details.library ?? 'framework',
        context: details.context?.toString(),
      ),
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.instance.e(
      '[PlatformDispatcher] unhandled async error',
      error: error,
      stackTrace: stack,
      recordError: false,
    );
    unawaited(
      ErrorLogService.instance.recordError(
        error,
        stack,
        module: 'async',
        action: 'unhandled',
      ),
    );
    return true;
  };
}
