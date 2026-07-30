import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../cubits/notification_cubit.dart';
import '../../cubits/progress_activity_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import 'notification_center_panel.dart';

const _bellWidth = 34.0;

/// Title-bar bell with unread badge and notification dropdown.
class NotificationBellButton extends StatefulWidget {
  const NotificationBellButton({super.key});

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

    return TpActionMenuAnchor(
      controller: _popoverController,
      fixedPanelWidth: notificationCenterPanelWidth,
      anchor: const TpAnchor(
        childAlignment: Alignment.topLeft,
        overlayAlignment: Alignment.bottomLeft,
        offset: Offset(-(notificationCenterPanelWidth - _bellWidth), 8),
      ),
      popoverBuilder: (context, controller) =>
          NotificationCenterPanel(onClose: controller.close),
      child: _BellGlyph(
        unread: badgeCount,
        tooltip: l10n.notificationCenterTitle,
        onTap: _popoverController.toggle,
      ),
    );
  }
}

class _BellGlyph extends StatefulWidget {
  const _BellGlyph({
    required this.unread,
    required this.onTap,
    required this.tooltip,
  });

  final int unread;
  final VoidCallback onTap;
  final String tooltip;

  @override
  State<_BellGlyph> createState() => _BellGlyphState();
}

class _BellGlyphState extends State<_BellGlyph> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);
    final hasUnread = widget.unread > 0;
    final badgeLabel = widget.unread > 9 ? '9+' : '${widget.unread}';

    Widget glyph = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: _hovered
                ? cs.onSurface.withValues(alpha: 0.07)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
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
      ),
    );
    return Tooltip(message: widget.tooltip, child: glyph);
  }
}
