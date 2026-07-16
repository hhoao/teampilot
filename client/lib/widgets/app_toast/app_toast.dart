import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../router/app_router.dart';
import '../../services/notification/notification_recorder.dart';

/// TeamPilot transient feedback — product facade over [TpToast].
abstract final class AppToast {
  static DateTime? _lastGlobalShownAt;
  static String? _lastGlobalMessage;

  /// Shows a toast when [context] is available.
  static void show(
    BuildContext context, {
    required String message,
    TpToastVariant variant = TpToastVariant.info,
    TpToastAction? action,
    Duration? duration,
  }) {
    final trimmed = message.trim();
    if (trimmed.isEmpty || !context.mounted) return;

    _present(
      context: context,
      message: trimmed,
      variant: variant,
      action: action,
      duration: duration,
    );
  }

  /// Shows a toast without [BuildContext] (services, error utils).
  static void showGlobal({
    required String message,
    TpToastVariant variant = TpToastVariant.info,
    TpToastAction? action,
    Duration? duration,
    bool deduplicate = true,
  }) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    if (deduplicate) {
      final now = DateTime.now();
      if (_lastGlobalMessage == trimmed &&
          _lastGlobalShownAt != null &&
          now.difference(_lastGlobalShownAt!) < const Duration(seconds: 2)) {
        return;
      }
      _lastGlobalMessage = trimmed;
      _lastGlobalShownAt = now;
    }

    final context = appRouter.routerDelegate.navigatorKey.currentContext;
    if (context == null || !context.mounted) return;

    _present(
      context: context,
      message: trimmed,
      variant: variant,
      action: action,
      duration: duration,
    );
  }

  /// Dismisses any visible toast.
  static void dismiss() {
    TpToast.dismiss();
  }

  static void _present({
    required BuildContext context,
    required String message,
    required TpToastVariant variant,
    TpToastAction? action,
    Duration? duration,
  }) {
    TpToast.show(
      context,
      message: message,
      variant: variant,
      action: action,
      duration: duration,
    );

    if (variant != TpToastVariant.info) {
      NotificationRecorder.maybeCurrent?.record(
        message: message,
        variant: variant,
      );
    }
  }
}

extension AppToastContext on BuildContext {
  void showAppToast(
    String message, {
    TpToastVariant variant = TpToastVariant.info,
    TpToastAction? action,
    Duration? duration,
  }) {
    AppToast.show(
      this,
      message: message,
      variant: variant,
      action: action,
      duration: duration,
    );
  }
}
