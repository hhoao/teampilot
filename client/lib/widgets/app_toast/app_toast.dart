import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

import '../../router/app_router.dart';
import '../../services/notification/notification_recorder.dart';
import '../../theme/app_toast_theme.dart';

/// Optional action button on a toast.
final class AppToastAction {
  const AppToastAction({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

/// TeamPilot transient feedback — semantic toasts backed by vendored
/// [toastification] overlay engine.
abstract final class AppToast {
  static DateTime? _lastGlobalShownAt;
  static String? _lastGlobalMessage;

  /// Shows a toast when [context] is available.
  static void show(
    BuildContext context, {
    required String message,
    AppToastVariant variant = AppToastVariant.info,
    AppToastAction? action,
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
    AppToastVariant variant = AppToastVariant.info,
    AppToastAction? action,
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
    toastification.dismissAll(delayForAnimation: false);
  }

  static void _present({
    required BuildContext context,
    required String message,
    required AppToastVariant variant,
    AppToastAction? action,
    Duration? duration,
  }) {
    toastification.dismissAll(delayForAnimation: false);

    final theme = Theme.of(context);
    final style = appToastStyleFor(theme, variant);
    final textTheme = theme.textTheme;
    final effectiveDuration =
        duration ?? defaultAppToastDuration(variant, hasAction: action != null);

    toastification.show(
      context: context,
      type: toastificationTypeFor(variant),
      style: ToastificationStyle.flat,
      autoCloseDuration: effectiveDuration,
      animationDuration: const Duration(milliseconds: 200),
      primaryColor: style.accentColor,
      backgroundColor: style.backgroundColor,
      foregroundColor: style.foregroundColor,
      borderRadius: style.borderRadius,
      borderSide: style.borderSide,
      boxShadow: style.boxShadow,
      padding: style.padding,
      dragToClose: false,
      pauseOnHover: true,
      showIcon: true,
      icon: Icon(
        toastificationTypeFor(variant).icon,
        color: style.accentColor,
        size: 20,
      ),
      closeButton: const ToastCloseButton(showType: CloseButtonShowType.always),
      title: _buildTitle(
        message: message,
        textTheme: textTheme,
        foregroundColor: style.foregroundColor,
        accentColor: style.accentColor,
        action: action,
      ),
      callbacks: ToastificationCallbacks(
        onCloseButtonTap: (item) {
          toastification.dismiss(item, showRemoveAnimation: true);
        },
      ),
    );

    if (variant != AppToastVariant.info) {
      NotificationRecorder.maybeCurrent?.record(
        message: message,
        variant: variant,
      );
    }
  }

  static Widget _buildTitle({
    required String message,
    required TextTheme textTheme,
    required Color foregroundColor,
    required Color accentColor,
    AppToastAction? action,
  }) {
    final messageStyle = (textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: foregroundColor,
      height: 1.35,
    );

    if (action == null) {
      return Text(message, style: messageStyle, maxLines: 3);
    }

    return Row(
      children: [
        Expanded(
          child: Text(message, style: messageStyle, maxLines: 3),
        ),
        TextButton(
          onPressed: () {
            dismiss();
            action.onPressed();
          },
          style: TextButton.styleFrom(
            foregroundColor: accentColor,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: const Size(48, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
          ),
          child: Text(
            action.label,
            style: messageStyle.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

extension AppToastContext on BuildContext {
  void showAppToast(
    String message, {
    AppToastVariant variant = AppToastVariant.info,
    AppToastAction? action,
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
