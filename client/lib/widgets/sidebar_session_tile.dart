import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/chat_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/app_session.dart';
import '../repositories/session_repository.dart';
import '../theme/app_icon_sizes.dart';
import '../theme/app_text_styles.dart';
import '../utils/app_keys.dart';
import '../utils/debounce/debounce.dart';
import 'app_dialog.dart';
import 'app_icon_button.dart';
import 'menu/sidebar_action_menu.dart';
import 'session_working_spinner.dart';

/// Session row for sidebars: rename, delete, overflow menu, and context menu.
class SidebarSessionTile extends StatefulWidget {
  const SidebarSessionTile({
    required this.session,
    required this.onTap,
    this.tapThrottleKeyPrefix = 'sidebar_session',
    this.contentLeftInset = 0,
    this.index = -1,
    super.key,
  });

  final AppSession session;
  final VoidCallback onTap;

  /// Prefix for [throttledTap] keys (`{prefix}_{sessionId}`).
  final String tapThrottleKeyPrefix;
  final double contentLeftInset;

  /// Index in the parent [ReorderableListView]. When >= 0, a drag handle is
  /// shown on hover so the user can reorder sessions by dragging.
  final int index;

  @override
  State<SidebarSessionTile> createState() => _SidebarSessionTileState();
}

class _SidebarSessionTileState extends State<SidebarSessionTile> {
  var _hovered = false;

  /// Keeps the overflow menu mounted while the popup is open; otherwise moving
  /// the pointer onto the overlay triggers [MouseRegion.onExit] and removes
  /// the overflow menu before a menu item can be selected.
  var _menuOpen = false;

  /// First click on delete arms confirmation; second click on [l10n.confirm]
  /// performs the delete (no dialog).
  var _deleteArmed = false;

  Timer? _deleteArmResetTimer;

  static const _deleteArmTimeout = Duration(seconds: 4);

  @override
  void dispose() {
    _deleteArmResetTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SidebarSessionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.sessionId != widget.session.sessionId) {
      _disarmDelete();
    }
  }

  void _armDelete() {
    _deleteArmResetTimer?.cancel();
    setState(() => _deleteArmed = true);
    _deleteArmResetTimer = Timer(_deleteArmTimeout, () {
      if (!mounted) return;
      _disarmDelete();
    });
  }

  void _disarmDelete() {
    _deleteArmResetTimer?.cancel();
    _deleteArmResetTimer = null;
    if (_deleteArmed) {
      setState(() => _deleteArmed = false);
    }
  }

  Future<void> _executeDelete() async {
    if (!mounted) return;
    final repo = context.read<SessionRepository>();
    final chatCubit = context.read<ChatCubit>();
    final sessionId = widget.session.sessionId;
    _disarmDelete();
    await chatCubit.deleteSession(repo, sessionId);
  }

  Future<void> _showSessionContextMenuAtTap(TapDownDetails details) async {
    if (!mounted) return;

    final l10n = context.l10n;
    final session = widget.session;
    setState(() => _menuOpen = true);
    final selected = await showSidebarActionMenuAtTap<String>(
      context: context,
      tapDetails: details,
      itemCount: 2,
      children: [
        SidebarActionMenuPopupItem(
          value: 'rename',
          icon: Icons.drive_file_rename_outline,
          label: l10n.renameConversation,
        ),
        SidebarActionMenuPopupItem(
          value: 'delete',
          icon: Icons.delete_outline,
          label: l10n.deleteConversation,
          destructive: true,
        ),
      ],
    );
    if (!mounted) return;
    setState(() => _menuOpen = false);
    if (selected == null) return;
    switch (selected) {
      case 'rename':
        _showRenameDialog(context, session, l10n);
      case 'delete':
        _armDelete();
    }
  }

  void _showSessionContextMenuFromTap(TapDownDetails details) {
    unawaited(_showSessionContextMenuAtTap(details));
  }

  Future<void> _showSessionContextMenu(Offset globalPosition) async {
    if (!mounted) return;

    final l10n = context.l10n;
    final session = widget.session;
    setState(() => _menuOpen = true);
    final selected = await showSidebarActionMenu<String>(
      context: context,
      globalPosition: globalPosition,
      itemCount: 2,
      children: [
        SidebarActionMenuPopupItem(
          value: 'rename',
          icon: Icons.drive_file_rename_outline,
          label: l10n.renameConversation,
        ),
        SidebarActionMenuPopupItem(
          value: 'delete',
          icon: Icons.delete_outline,
          label: l10n.deleteConversation,
          destructive: true,
        ),
      ],
    );
    if (!mounted) return;
    setState(() => _menuOpen = false);
    if (selected == null) return;
    switch (selected) {
      case 'rename':
        _showRenameDialog(context, session, l10n);
      case 'delete':
        _armDelete();
    }
  }

  void _showSessionContextMenuAtCenter() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final center = box.localToGlobal(
      Offset(box.size.width / 2, box.size.height / 2),
    );
    unawaited(_showSessionContextMenu(center));
  }

  bool get _showSessionActions =>
      _hovered || _menuOpen || _deleteArmed || Platform.isAndroid;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final selected = context.select<ChatCubit, bool>(
      (cubit) => cubit.state.activeSessionId == session.sessionId,
    );
    final working = context.select<ChatCubit, bool>(
      (cubit) => cubit.state.workingSessionIds.contains(session.sessionId),
    );
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    // Leading area: shared 24×24 slot — indicator (idle) ↔ drag handle (hover).
    final Widget leadingWidget;
    if (widget.index >= 0) {
      leadingWidget = ReorderableDragStartListener(
        index: widget.index,
        child: MouseRegion(
          cursor: _hovered ? SystemMouseCursors.grab : SystemMouseCursors.basic,
          child: SizedBox(
            width: 24,
            height: 24,
            child: Stack(
              children: [
                AnimatedOpacity(
                  opacity: _showSessionActions ? 0 : 1,
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  child: Center(
                    child: SessionWorkingIndicator(
                      working: working,
                      size: 13,
                      color: selected ? cs.onPrimaryContainer : cs.primary,
                      idleColor:
                          (selected
                                  ? cs.onPrimaryContainer
                                  : cs.onSurfaceVariant)
                              .withValues(alpha: 0.5),
                    ),
                  ),
                ),
                AnimatedOpacity(
                  opacity: _showSessionActions ? 0.65 : 0,
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  child: Center(
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      leadingWidget = SizedBox(
        width: 24,
        height: 24,
        child: Center(
          child: SessionWorkingIndicator(
            working: working,
            size: 13,
            color: selected ? cs.onPrimaryContainer : cs.primary,
            idleColor: (selected ? cs.onPrimaryContainer : cs.onSurfaceVariant)
                .withValues(alpha: 0.5),
          ),
        ),
      );
    }

    // Trailing row: pin, delete, overflow menu (hover-revealed, no gap when
    // hidden — uses `if` + AnimatedSize instead of AnimatedOpacity).
    final trailing = AnimatedSize(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (session.pinned || _showSessionActions)
            AppIconButton(
              icon: session.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              compact: true,
              size: AppIconButton.kCompactSize,
              tooltip: session.pinned
                  ? l10n.unpinConversation
                  : l10n.pinConversation,
              color: session.pinned ? cs.primary : null,
              onTap: () =>
                  context.read<ChatCubit>().toggleSessionPin(session.sessionId),
            ),
          if (_showSessionActions)
            _deleteArmed
                ? _SessionDeleteConfirmButton(
                    label: l10n.confirm,
                    onConfirm: throttledAsync(
                      'sidebar_delete_session',
                      _executeDelete,
                    ),
                  )
                : AppIconButton(
                    icon: Icons.delete_outline,
                    compact: true,
                    size: AppIconButton.kCompactSize,
                    tooltip: l10n.deleteConversation,
                    color: cs.error,
                    onTap: _armDelete,
                  ),
          if (_showSessionActions)
            SizedBox(
              width: AppIconButton.kDefaultSize,
              height: AppIconButton.kDefaultSize,
              child: SidebarActionMenuIconAnchor(
                icon: Icon(Icons.more_horiz, size: context.appIconSizes.md),
                onOpen: () => setState(() => _menuOpen = true),
                onClose: () => setState(() => _menuOpen = false),
                buildMenuChildren: (context, controller) => [
                  SidebarActionMenuItem(
                    icon: Icons.drive_file_rename_outline,
                    label: l10n.renameConversation,
                    menuController: controller,
                    onTap: () => _showRenameDialog(context, session, l10n),
                  ),
                  SidebarActionMenuItem(
                    icon: Icons.delete_outline,
                    label: l10n.deleteConversation,
                    destructive: true,
                    menuController: controller,
                    onTap: _armDelete,
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: _SidebarTile(
        key: AppKeys.sessionTile(session.sessionId),
        title: session.resolveDisplayTitle(l10n.defaultNewChatSessionTitle),
        selected: selected,
        rowHovered: _hovered || _menuOpen,
        contentLeftInset: widget.contentLeftInset,
        leading: leadingWidget,
        onTap: throttledTap(
          '${widget.tapThrottleKeyPrefix}_${session.sessionId}',
          widget.onTap,
        ),
        onSecondaryTapDown: _showSessionContextMenuFromTap,
        onLongPress: Platform.isAndroid
            ? _showSessionContextMenuAtCenter
            : null,
        trailing: trailing,
      ),
    );
  }

  void _showRenameDialog(
    BuildContext context,
    AppSession session,
    AppLocalizations l10n,
  ) {
    final repo = context.read<SessionRepository>();
    final chatCubit = context.read<ChatCubit>();
    final controller = TextEditingController(
      text: session.resolveDisplayTitle(l10n.defaultNewChatSessionTitle),
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AppDialog(
        maxWidth: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppDialogHeader(title: l10n.renameConversationTitle),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.conversationName),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  unawaited(
                    chatCubit.renameSession(
                      repo,
                      session.sessionId,
                      value.trim(),
                    ),
                  );
                }
                Navigator.of(ctx).pop();
              },
            ),
            AppDialogActions(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: throttledAsync('sidebar_rename_session', () async {
                    final value = controller.text.trim();
                    if (value.isNotEmpty) {
                      await chatCubit.renameSession(
                        repo,
                        session.sessionId,
                        value,
                      );
                    }
                    if (ctx.mounted) Navigator.of(ctx).pop();
                  }),
                  child: Text(l10n.save),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

}

/// Compact red confirm control shown after the user arms session delete.
class _SessionDeleteConfirmButton extends StatelessWidget {
  const _SessionDeleteConfirmButton({
    required this.label,
    required this.onConfirm,
  });

  final String label;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AppIconButton(
      icon: Icons.check,
      compact: true,
      size: AppIconButton.kCompactSize,
      tooltip: label,
      backgroundColor: cs.error,
      color: cs.onError,
      onTap: onConfirm,
    );
  }
}

class _SidebarTile extends StatelessWidget {
  // ignore: unused_element_parameter
  const _SidebarTile({
    required this.title,
    required this.selected,
    // ignore: unused_element_parameter
    this.subtitle = '',
    this.rowHovered = false,
    this.onTap,
    this.onSecondaryTapDown,
    this.onLongPress,
    this.leading,
    this.trailing,
    this.contentLeftInset = 0,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final bool rowHovered;
  final VoidCallback? onTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final VoidCallback? onLongPress;
  final Widget? leading;
  final Widget? trailing;
  final double contentLeftInset;

  Color _materialFillColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hoverTint = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.10);
    if (selected) {
      return rowHovered
          ? Color.alphaBlend(hoverTint, cs.primaryContainer)
          : cs.primaryContainer;
    }
    if (rowHovered) {
      return Color.alphaBlend(hoverTint, cs.surfaceContainer);
    }
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textBase = isDark ? Colors.white : const Color(0xFF111827);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: _materialFillColor(context),
        borderRadius: BorderRadius.circular(8),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onSecondaryTapDown: onSecondaryTapDown,
          onLongPress: onLongPress,
          child: Container(
            padding: EdgeInsets.fromLTRB(8 + contentLeftInset, 6, 8, 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: selected ? Border.all(color: cs.primaryContainer) : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (leading != null) leading!,
                const SizedBox(width: 8),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.of(context).caption.copyWith(
                                color: textBase.withValues(alpha: 0.52),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
