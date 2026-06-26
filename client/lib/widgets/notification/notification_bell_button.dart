import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../cubits/notification_cubit.dart';
import '../../l10n/l10n_extensions.dart';
import '../../theme/app_icon_sizes.dart';
import '../dropdown/popover/app_popover.dart';
import '../menu/sidebar_action_menu.dart';
import 'notification_list_tile.dart';

const _dropdownWidth = 560.0;
const _dropdownListMaxHeight = 360.0;
const _bellWidth = 34.0;

/// Title-bar bell with unread badge and notification dropdown.
class NotificationBellButton extends StatefulWidget {
  const NotificationBellButton({super.key});

  @override
  State<NotificationBellButton> createState() => _NotificationBellButtonState();
}

class _NotificationBellButtonState extends State<NotificationBellButton> {
  final _popoverController = AppPopoverController();

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
    final l10n = context.l10n;

    return ActionMenuPopoverAnchor(
      controller: _popoverController,
      fixedPanelWidth: _dropdownWidth,
      anchor: const AppAnchorAuto(
        offset: Offset(-(_dropdownWidth - _bellWidth), 8),
        followerAnchor: Alignment.topLeft,
        targetAnchor: Alignment.bottomLeft,
      ),
      popoverBuilder: (context, controller) =>
          const _NotificationDropdownPanel(),
      child: _BellGlyph(
        unread: unread,
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
                hasUnread ? Icons.notifications : Icons.notifications_outlined,
                size: context.appIconSizes.md,
                color: hasUnread ? cs.primary : cs.onSurfaceVariant,
              ),
              if (hasUnread)
                Positioned(
                  top: 2,
                  right: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    constraints: const BoxConstraints(
                      minWidth: 14,
                      minHeight: 14,
                    ),
                    decoration: BoxDecoration(
                      color: cs.error,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      badgeLabel,
                      style: TextStyle(
                        color: cs.onError,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        height: 1,
                      ),
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

class _NotificationDropdownPanel extends StatelessWidget {
  const _NotificationDropdownPanel();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final cubit = context.read<NotificationCubit>();
    final items = context.select((NotificationCubit c) => c.state.items);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _dropdownWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.notificationCenterTitle,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: l10n.notificationMarkAllRead,
                onPressed: items.isEmpty ? null : () => cubit.markAllRead(),
                icon: const Icon(Icons.done_all, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SidebarActionMenuDivider(),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                l10n.notificationEmpty,
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: _dropdownListMaxHeight,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          color: cs.outlineVariant.withValues(alpha: 0.25),
                        ),
                      NotificationListTile(
                        notification: items[i],
                        onMarkRead: () => cubit.markRead(items[i].id),
                        onDelete: () => cubit.delete(items[i].id),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SidebarActionMenuDivider(),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: items.isEmpty ? null : () => cubit.clearAll(),
              child: Text(l10n.notificationClearAll),
            ),
          ),
        ],
      ),
    );
  }
}
