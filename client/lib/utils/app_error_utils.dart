import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../router/app_router.dart';

enum AppErrorKind {
  unexpected,
  network,
  storage,
  ssh,
  cancelled,
}

class AppErrorDecision {
  const AppErrorDecision({
    required this.kind,
    required this.shouldReport,
    this.userMessage,
  });

  final AppErrorKind kind;
  final bool shouldReport;
  final String? userMessage;

  bool get shouldNotifyUser =>
      userMessage != null && userMessage!.trim().isNotEmpty;
}

/// Classifies errors for logging, deduplication, and optional UI hints.
class AppErrorUtils {
  static DateTime? _lastShownAt;
  static String? _lastShownMessage;

  static AppErrorDecision classify(Object error) {
    if (_isCancelledError(error)) {
      return const AppErrorDecision(
        kind: AppErrorKind.cancelled,
        shouldReport: false,
      );
    }

    if (_isNetworkError(error)) {
      return const AppErrorDecision(
        kind: AppErrorKind.network,
        shouldReport: false,
        userMessage: '网络异常，请检查网络后重试',
      );
    }

    if (_isSshError(error)) {
      return const AppErrorDecision(
        kind: AppErrorKind.ssh,
        shouldReport: false,
        userMessage: 'SSH 连接失败，请检查服务器配置与网络',
      );
    }

    if (_isStorageError(error)) {
      return const AppErrorDecision(
        kind: AppErrorKind.storage,
        shouldReport: false,
        userMessage: '存储空间不足或应用数据不可写，请清理空间后重试',
      );
    }

    if (_isPluginRaceError(error)) {
      return const AppErrorDecision(
        kind: AppErrorKind.unexpected,
        shouldReport: false,
      );
    }

    return const AppErrorDecision(
      kind: AppErrorKind.unexpected,
      shouldReport: true,
    );
  }

  static bool isStorageError(Object error) {
    return classify(error).kind == AppErrorKind.storage;
  }

  static void showDecisionMessage(AppErrorDecision decision) {
    if (!decision.shouldNotifyUser) return;
    showUserMessage(decision.userMessage!);
  }

  static void showUserMessage(String message) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    final now = DateTime.now();
    if (_lastShownMessage == trimmed &&
        _lastShownAt != null &&
        now.difference(_lastShownAt!) < const Duration(seconds: 2)) {
      return;
    }

    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      return;
    }

    _lastShownMessage = trimmed;
    _lastShownAt = now;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(trimmed),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static bool _isCancelledError(Object error) {
    if (error is StateError) {
      final message = error.message.toLowerCase();
      if (message.contains('cancel') || message.contains('aborted')) {
        return true;
      }
    }
    final raw = error.toString().toLowerCase();
    return raw.contains('operation was cancelled') ||
        raw.contains('request cancelled') ||
        raw.contains('user cancelled');
  }

  static bool _isNetworkError(Object error) {
    if (error is SocketException ||
        error is HandshakeException ||
        error is http.ClientException ||
        error is HttpException ||
        error is TlsException) {
      return true;
    }

    final raw = error.toString().toLowerCase();
    return raw.contains('failed host lookup') ||
        raw.contains('connection error') ||
        raw.contains('connection timeout') ||
        raw.contains('connection refused') ||
        raw.contains('connection reset') ||
        raw.contains('socketexception') ||
        raw.contains('handshakeexception') ||
        raw.contains('clientexception') ||
        raw.contains('httpexception') ||
        raw.contains('broken pipe') ||
        raw.contains('certificate_verify_failed');
  }

  static bool _isSshError(Object error) {
    final raw = error.toString().toLowerCase();
    return raw.contains('ssh') &&
        (raw.contains('authentication') ||
            raw.contains('connection') ||
            raw.contains('timeout') ||
            raw.contains('failed') ||
            raw.contains('refused') ||
            raw.contains('host key'));
  }

  static bool _isStorageError(Object error) {
    if (error is FileSystemException) {
      final osMessage = error.osError?.message.toLowerCase() ?? '';
      final message = error.message.toLowerCase();
      if (osMessage.contains('no space left on device') ||
          osMessage.contains('permission denied') ||
          osMessage.contains('operation not permitted') ||
          message.contains('cannot copy') ||
          message.contains('cannot delete') ||
          message.contains('cannot open file')) {
        return true;
      }
    }

    final raw = error.toString().toLowerCase();
    return raw.contains('sqlite_full') ||
        raw.contains('no space left on device') ||
        raw.contains('database or disk is full') ||
        raw.contains('readonly database') ||
        raw.contains('permission denied') ||
        raw.contains('/logs/app_') ||
        raw.contains('/logs/errors');
  }

  static bool _isPluginRaceError(Object error) {
    return error is PlatformException && error.code == 'SESSION_NOT_FOUND';
  }
}
