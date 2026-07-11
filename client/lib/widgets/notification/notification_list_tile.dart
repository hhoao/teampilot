import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../l10n/l10n_extensions.dart';
import '../../models/app_notification.dart';
import '../../theme/app_text_styles.dart';
import '../../theme/app_toast_theme.dart';
import '../app_toast/app_toast.dart';

const _collapsedMessageMaxLines = 2;
const _expandableMessageCharThreshold = 96;

String formatNotificationTime(BuildContext context, DateTime time) {
  final l10n = context.l10n;
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inMinutes < 1) return l10n.notificationTimeJustNow;
  if (diff.inHours < 1) {
    return l10n.notificationTimeMinutesAgo(diff.inMinutes);
  }
  if (diff.inHours < 24) {
    return l10n.notificationTimeHoursAgo(diff.inHours);
  }
  return DateFormat.yMMMd(context.l10n.localeName).format(time);
}

bool notificationMessageIsExpandable(String message) {
  if (message.contains('\n')) return true;
  return message.length > _expandableMessageCharThreshold;
}

IconData notificationVariantIcon(AppToastVariant variant) => switch (variant) {
  AppToastVariant.info => Icons.info_outline,
  AppToastVariant.success => Icons.check_circle_outline,
  AppToastVariant.warning => Icons.warning_amber_outlined,
  AppToastVariant.error => Icons.error_outline,
};

Color notificationVariantAccent(ColorScheme scheme, AppToastVariant variant) =>
    appToastAccentColor(scheme, variant);

/// Shared notification row for the bell dropdown.
class NotificationListTile extends StatefulWidget {
  const NotificationListTile({
    required this.notification,
    required this.onMarkRead,
    required this.onDelete,
    super.key,
  });

  final AppNotification notification;
  final VoidCallback onMarkRead;
  final VoidCallback onDelete;

  @override
  State<NotificationListTile> createState() => _NotificationListTileState();
}

class _NotificationListTileState extends State<NotificationListTile> {
  var _expanded = false;

  Future<void> _copyMessage() async {
    final n = widget.notification;
    final text = n.hasTitle ? '${n.title}\n${n.message}' : n.message;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    AppToast.show(
      context,
      message: context.l10n.initErrorCopied,
      variant: AppToastVariant.info,
    );
  }

  void _toggleExpanded() {
    if (!notificationMessageIsExpandable(widget.notification.message)) return;
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = AppTextStyles.of(context);
    final accent = notificationVariantAccent(cs, widget.notification.variant);
    final l10n = context.l10n;
    final notification = widget.notification;
    final message = notification.message;
    final hasTitle = notification.hasTitle;
    final expandable = notificationMessageIsExpandable(message);
    final titleStyle = styles.mdSemiboldTightSnugColored(cs.onSurface);
    final messageStyle = styles.mdColored(
      hasTitle ? cs.onSurfaceVariant : cs.onSurface,
    );

    Widget messageBody;
    if (_expanded) {
      messageBody = SelectableText(message, style: messageStyle);
    } else {
      messageBody = Text(
        message,
        maxLines: _collapsedMessageMaxLines,
        overflow: TextOverflow.ellipsis,
        style: messageStyle,
      );
    }

    return Material(
      color: notification.isRead
          ? Colors.transparent
          : cs.primaryContainer.withValues(alpha: 0.22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                notificationVariantIcon(notification.variant),
                size: 20,
                color: accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: expandable ? _toggleExpanded : null,
                behavior: HitTestBehavior.opaque,
                child: MouseRegion(
                  cursor: expandable
                      ? SystemMouseCursors.click
                      : SystemMouseCursors.basic,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasTitle) ...[
                        Text(
                          notification.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: titleStyle,
                        ),
                        const SizedBox(height: 4),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: messageBody),
                          if (expandable)
                            Padding(
                              padding: const EdgeInsets.only(left: 4, top: 2),
                              child: Icon(
                                _expanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 18,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        formatNotificationTime(context, notification.createdAt),
                        style: styles.mutedXs,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (!notification.isRead)
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 6, right: 4),
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
              ),
            IconButton(
              tooltip: l10n.copy,
              onPressed: _copyMessage,
              icon: const Icon(Icons.copy_outlined, size: 18),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              tooltip: l10n.notificationMarkRead,
              onPressed: widget.notification.isRead ? null : widget.onMarkRead,
              icon: const Icon(Icons.check_circle_outline, size: 18),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            IconButton(
              tooltip: l10n.notificationDelete,
              onPressed: widget.onDelete,
              icon: Icon(Icons.close, size: 18, color: cs.error),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
}
