import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/notification_cubit.dart';
import '../../cubits/progress_activity_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import 'notification_center_panel.dart';

/// Title-bar bell with unread badge and notification dropdown.
class NotificationBellButton extends StatefulWidget {
  const NotificationBellButton({
    this.size = TpIconButton.kDefaultSize,
    super.key,
  });

  /// Square hit target; keep in sync with title-bar tab chip height when used
  /// in [HomeTitleBar].
  final double size;

  @override
  State<NotificationBellButton> createState() => _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<NotificationBellButton> {
  final _popoverController = TpPopoverController();

  @override
  void dispose() {
    _popoverController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unread = context.select(
      (NotificationCubit cubit) => cubit.state.unreadCount,
    );
    final ongoingCount = context.select(
      (ProgressActivityCubit cubit) => cubit.state.activities.length,
    );
    final badgeCount = unread + ongoingCount;
    final l10n = context.l10n;
    // Horizontal pad (1+1) around the square glyph for popover alignment math.
    final anchorWidth = widget.size + 2;

    return TpActionMenuAnchor(
      controller: _popoverController,
      fixedPanelWidth: notificationCenterPanelWidth,
      anchor: TpAnchor(
        childAlignment: Alignment.topLeft,
        overlayAlignment: Alignment.bottomLeft,
        offset: Offset(-(notificationCenterPanelWidth - anchorWidth), 8),
      ),
      popoverBuilder: (context, controller) =>
          NotificationCenterPanel(onClose: controller.close),
      child: _BellGlyph(
        unread: badgeCount,
        size: widget.size,
        tooltip: l10n.notificationCenterTitle,
        onTap: _popoverController.toggle,
      ),
    );
  }
}

class _BellGlyph extends StatelessWidget {
  const _BellGlyph({
    required this.unread,
    required this.size,
    required this.onTap,
    required this.tooltip,
  });

  final int unread;
  final double size;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final hasUnread = unread > 0;
    final badgeLabel = unread > 9 ? '9+' : '$unread';

    final glyph = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: TpHover(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        hoverColor: cs.onSurface.withValues(alpha: 0.07),
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Icon(
              Icons.notifications_outlined,
              size: context.tpIconSizes.md,
              color: hasUnread ? cs.primary : cs.onSurfaceVariant,
            ),
            if (hasUnread)
              Positioned(
                top: 1,
                right: 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  constraints: const BoxConstraints(
                    minWidth: 12,
                    minHeight: 12,
                  ),
                  decoration: BoxDecoration(
                    color: cs.error,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  // Pastel error seeds often resolve onError to black in both
                  // modes; ink opposite the theme brightness reads clearly.
                  child: Text(
                    badgeLabel,
                    textAlign: TextAlign.center,
                    textScaler: const TextScaler.linear(0.78),
                    style: styles.xsSemiboldSnugColored(
                      cs.brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black,
                    ).copyWith(height: 1.0),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return Tooltip(message: tooltip, child: glyph);
  }
}
