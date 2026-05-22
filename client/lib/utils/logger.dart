import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../services/error_log_service.dart';
import 'app_error_utils.dart';
import 'logger_utils.dart';

/// Drop-in facade matching [package:logger](https://pub.dev/packages/logger) call sites.
class TeamPilotLogger {
  void i(dynamic message, {Object? error, StackTrace? stackTrace}) {
    AppLogger.instance.i(
      message.toString(),
      error: error,
      stackTrace: stackTrace,
    );
  }

  void d(dynamic message, {Object? error, StackTrace? stackTrace}) {
    AppLogger.instance.d(
      message.toString(),
      error: error,
      stackTrace: stackTrace,
    );
  }

  void w(dynamic message, {Object? error, StackTrace? stackTrace}) {
    AppLogger.instance.w(
      message.toString(),
      error: error,
      stackTrace: stackTrace,
    );
  }

  void e(
    dynamic message, {
    Object? error,
    StackTrace? stackTrace,
    bool recordError = true,
  }) {
    final resolvedError = error;
    final resolvedStack = stackTrace ?? (resolvedError != null ? StackTrace.current : null);

    if (recordError && resolvedError != null) {
      final decision = AppErrorUtils.classify(resolvedError);
      AppErrorUtils.showDecisionMessage(decision);
      if (decision.shouldReport) {
        unawaited(
          ErrorLogService.instance.recordError(
            resolvedError,
            resolvedStack ?? StackTrace.current,
            module: 'app',
            action: message.toString(),
          ),
        );
      }
    }

    AppLogger.instance.e(
      message.toString(),
      error: resolvedError,
      stackTrace: resolvedStack,
      recordError: false,
    );
  }
}

final appLogger = TeamPilotLogger();

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
