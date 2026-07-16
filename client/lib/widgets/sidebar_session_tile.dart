import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/automation_cubit.dart';
import '../cubits/automation_state.dart';
import '../cubits/chat_cubit.dart';
import '../l10n/l10n_extensions.dart';
import '../models/app_session.dart';
import '../models/automation_list_scope.dart';
import '../pages/automations/automation_editor_dialog.dart';
import '../pages/automations/automations_dialog.dart';
import '../pages/home_workspace/workspace/workspace_sidebar_row_metrics.dart';
import '../repositories/session_repository.dart';
import '../utils/ui/coarse_relative_time.dart';
import '../utils/debounce/debounce.dart';
import 'session_working_spinner.dart';
import 'package:shared_ui/shared_ui.dart';

/// Session row for sidebars: rename, delete, overflow menu, and context menu.
class SidebarSessionTile extends StatefulWidget {
  const SidebarSessionTile({
    required this.session,
    required this.onTap,
    this.highlightSessionId,
    this.tapThrottleKeyPrefix = 'sidebar_session',
    this.contentLeftInset = 0,
    this.index = -1,
    super.key,
  });

  final AppSession session;
  final VoidCallback onTap;

  /// When set, selection highlight follows this id instead of the global
  /// [ChatState.activeSessionId] (kept-alive background workspace tabs).
  final String? highlightSessionId;

  /// Prefix for [throttledTap] keys (`{prefix}_{sessionId}`).
  final String tapThrottleKeyPrefix;
  final double contentLeftInset;

  /// Index in a parent [ReorderableListView]. When >= 0, a drag handle is shown
  /// on hover so the user can reorder sessions by dragging.
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

  SessionRepository? _repo;
  ChatCubit? _chatCubit;
  var _sessionAutomationCount = 0;

  static const _deleteArmTimeout = Duration(seconds: 4);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _repo = context.read<SessionRepository>();
    _chatCubit = context.read<ChatCubit>();
    _refreshSessionAutomationCount(context.read<AutomationCubit>().state);
  }

  void _refreshSessionAutomationCount(AutomationState state) {
    final session = widget.session;
    final count = state.automations
        .where(
          (a) =>
              a.workspaceId == session.workspaceId &&
              a.sessionId == session.sessionId,
        )
        .length;
    if (count != _sessionAutomationCount && mounted) {
      setState(() => _sessionAutomationCount = count);
    }
  }

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
    if (!_deleteArmed || !mounted) return;
    setState(() => _deleteArmed = false);
  }

  Future<void> _executeDelete() async {
    _deleteArmResetTimer?.cancel();
    _deleteArmResetTimer = null;
    _deleteArmed = false;
    final repo = _repo;
    final chatCubit = _chatCubit;
    if (repo == null || chatCubit == null) return;
    await chatCubit.deleteSession(repo, widget.session.sessionId);
  }

  List<TpActionMenuPopupItem<String>> _contextMenuItems(
    AppLocalizations l10n,
    AppSession session,
  ) {
    final items = <TpActionMenuPopupItem<String>>[
      TpActionMenuPopupItem(
        value: 'rename',
        icon: Icons.drive_file_rename_outline,
        label: l10n.renameConversation,
      ),
      TpActionMenuPopupItem(
        value: 'pin',
        icon: session.pinned ? Icons.push_pin : Icons.push_pin_outlined,
        label: session.pinned ? l10n.unpinConversation : l10n.pinConversation,
      ),
      TpActionMenuPopupItem(
        value: 'schedule',
        icon: Icons.schedule_rounded,
        label: l10n.automationsSessionContextMenu,
      ),
    ];
    if (_sessionAutomationCount > 0) {
      items.add(
        TpActionMenuPopupItem(
          value: 'manage_schedule',
          icon: Icons.event_repeat_rounded,
          label: l10n.automationsManageSessionContextMenu,
        ),
      );
    }
    items.add(
      TpActionMenuPopupItem(
        value: 'delete',
        icon: Icons.delete_outline,
        label: l10n.deleteConversation,
        destructive: true,
      ),
    );
    return items;
  }

  Future<void> _handleContextAction(String selected, AppSession session) async {
    final l10n = context.l10n;
    switch (selected) {
      case 'rename':
        await _showRenameDialog(context, session, l10n);
      case 'pin':
        await _chatCubit?.toggleSessionPin(session.sessionId);
      case 'schedule':
        final title = session.resolveDisplayTitle(
          l10n.defaultNewChatSessionTitle,
        );
        final saved = await AutomationEditorDialog.show(
          context,
          kind: AutomationEditorKind.scheduledMessage,
          workspaceId: session.workspaceId,
          sessionId: session.sessionId,
          defaultName: l10n.automationsSessionDefaultName(title),
        );
        if (saved != null && mounted) {
          _refreshSessionAutomationCount(context.read<AutomationCubit>().state);
        }
      case 'manage_schedule':
        await showAutomationsPanelDialog(
          context,
          listScope: AutomationListScope.session(
            session.workspaceId,
            sessionId: session.sessionId,
          ),
        );
        if (mounted) {
          _refreshSessionAutomationCount(context.read<AutomationCubit>().state);
        }
      case 'delete':
        _armDelete();
    }
  }

  Future<void> _showSessionContextMenuAtTap(TapDownDetails details) async {
    if (!mounted) return;

    final l10n = context.l10n;
    final session = widget.session;
    final menuItems = _contextMenuItems(l10n, session);
    setState(() => _menuOpen = true);
    final selected = await showTpActionMenuAtTap<String>(
      context: context,
      tapDetails: details,
      itemCount: menuItems.length,
      children: menuItems,
    );
    if (!mounted) return;
    setState(() => _menuOpen = false);
    if (selected == null) return;
    await _handleContextAction(selected, session);
  }

  void _showSessionContextMenuFromTap(TapDownDetails details) {
    unawaited(_showSessionContextMenuAtTap(details));
  }

  Future<void> _showSessionContextMenu(Offset globalPosition) async {
    if (!mounted) return;

    final l10n = context.l10n;
    final session = widget.session;
    final menuItems = _contextMenuItems(l10n, session);
    setState(() => _menuOpen = true);
    final selected = await showTpActionMenu<String>(
      context: context,
      globalPosition: globalPosition,
      itemCount: menuItems.length,
      children: menuItems,
    );
    if (!mounted) return;
    setState(() => _menuOpen = false);
    if (selected == null) return;
    await _handleContextAction(selected, session);
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
    final selected = widget.highlightSessionId != null
        ? widget.highlightSessionId == session.sessionId
        : context.select<ChatCubit, bool>(
            (cubit) => cubit.state.activeSessionId == session.sessionId,
          );
    final working = context.select<ChatCubit, bool>(
      (cubit) => cubit.state.workingSessionIds.contains(session.sessionId),
    );
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;

    // Leading area: shared 24×24 slot — indicator (idle) ↔ drag handle (hover).
    final Widget indicator = SessionWorkingIndicator(
      working: working,
      size: 13,
      color: cs.primary,
      idleColor: (selected ? cs.primary : cs.onSurfaceVariant).withValues(
        alpha: 0.5,
      ),
    );
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
                  child: Center(child: indicator),
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
        child: Center(child: indicator),
      );
    }

    // Trailing: coarse relative time + pin mark (idle), or delete + overflow (hover).
    final int activityMs = session.updatedAt > 0
        ? session.updatedAt
        : session.createdAt;
    final Widget? trailing = _showSessionActions
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SessionDeleteAction(
                armed: _deleteArmed,
                confirmLabel: l10n.confirm,
                deleteTooltip: l10n.deleteConversation,
                onArm: _armDelete,
                onConfirm: throttledAsync(
                  'sidebar_delete_session_${session.sessionId}',
                  _executeDelete,
                ),
              ),
              SizedBox(
                width: TpIconButton.kDefaultSize,
                height: TpIconButton.kDefaultSize,
                child: TpActionMenuIconAnchor(
                  icon: Icon(Icons.more_horiz, size: context.tpIconSizes.md),
                  onOpen: () => setState(() => _menuOpen = true),
                  onClose: () => setState(() => _menuOpen = false),
                  buildMenuChildren: (context, controller) => [
                    TpActionMenuItem(
                      icon: Icons.drive_file_rename_outline,
                      label: l10n.renameConversation,
                      menuController: controller,
                      onTap: () =>
                          unawaited(_showRenameDialog(context, session, l10n)),
                    ),
                    TpActionMenuItem(
                      icon: session.pinned
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                      label: session.pinned
                          ? l10n.unpinConversation
                          : l10n.pinConversation,
                      menuController: controller,
                      onTap: () => unawaited(
                        context.read<ChatCubit>().toggleSessionPin(
                          session.sessionId,
                        ),
                      ),
                    ),
                    TpActionMenuItem(
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
          )
        : (activityMs > 0 || session.pinned)
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (activityMs > 0)
                _SessionCoarseRelativeTime(
                  timestampMs: activityMs,
                  selected: selected,
                ),
              if (session.pinned) const _SessionPinnedMark(),
            ],
          )
        : null;

    final Widget tile = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: _SidebarTile(
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

    // Inside a [ReorderableListView] (index >= 0), suppress action-button
    // tooltips: any position shift reparents the row via the list's GlobalKey,
    // and a live [RawTooltip]'s global pointer route then recreates its ticker
    // on a SingleTickerProviderStateMixin ("multiple tickers were created").
    // Tooltips stay enabled in every non-reorderable context.
    final child = widget.index >= 0
        ? TooltipVisibility(visible: false, child: tile)
        : tile;
    return BlocListener<AutomationCubit, AutomationState>(
      listener: (context, state) => _refreshSessionAutomationCount(state),
      child: child,
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    AppSession session,
    AppLocalizations l10n,
  ) async {
    final repo = context.read<SessionRepository>();
    final chatCubit = context.read<ChatCubit>();
    final name = await showTpTextPromptDialog(
      context,
      title: l10n.renameConversationTitle,
      initialText: session.resolveDisplayTitle(l10n.defaultNewChatSessionTitle),
      labelText: l10n.conversationName,
      confirmLabel: l10n.save,
    );
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    await chatCubit.renameSession(repo, session.sessionId, name.trim());
  }
}

/// Muted coarse relative time shown on the trailing edge when actions are hidden.
class _SessionCoarseRelativeTime extends StatelessWidget {
  const _SessionCoarseRelativeTime({
    required this.timestampMs,
    required this.selected,
  });

  final int timestampMs;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textBase = cs.onSurface;
    final label = formatCoarseRelativeTime(
      context.l10n,
      DateTime.fromMillisecondsSinceEpoch(timestampMs),
    );
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TpTextStyles.of(
          context,
        ).xsColored(textBase.withValues(alpha: 0.52)),
      ),
    );
  }
}

/// Trailing pin glyph for pinned conversations (idle state only).
class _SessionPinnedMark extends StatelessWidget {
  const _SessionPinnedMark();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Icon(
        Icons.push_pin,
        size: context.tpIconSizes.sm,
        color: cs.onSurfaceVariant.withValues(alpha: 0.55),
      ),
    );
  }
}

/// Delete control with a stable subtree: first tap arms, second tap confirms.
class _SessionDeleteAction extends StatelessWidget {
  const _SessionDeleteAction({
    required this.armed,
    required this.confirmLabel,
    required this.deleteTooltip,
    required this.onArm,
    required this.onConfirm,
  });

  final bool armed;
  final String confirmLabel;
  final String deleteTooltip;
  final VoidCallback onArm;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TpIconButton(
      icon: armed ? Icons.check : Icons.delete_outline,
      compact: true,
      size: TpIconButton.kCompactSize,
      tooltip: armed ? confirmLabel : deleteTooltip,
      color: armed ? cs.onError : cs.error,
      backgroundColor: armed ? cs.error : null,
      onTap: armed ? onConfirm : onArm,
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

  static const _selectedFillAlpha = 0.10;

  Color _selectedFillColor(ColorScheme cs) {
    return Color.alphaBlend(
      cs.primary.withValues(alpha: _selectedFillAlpha),
      cs.surfaceContainer,
    );
  }

  Color _materialFillColor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (selected) {
      final base = _selectedFillColor(cs);
      return rowHovered
          ? Color.alphaBlend(
              cs.onSurface.withValues(
                alpha: kWorkspaceSidebarRowHoverTintAlpha,
              ),
              base,
            )
          : base;
    }
    if (rowHovered) {
      return workspaceSidebarRowHoverFill(cs);
    }
    return Colors.transparent;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textBase = cs.onSurface;
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
              border: selected
                  ? Border.all(color: cs.primary.withValues(alpha: 0.28))
                  : null,
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
                          TpTooltip(
                            message: title,
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TpTextStyles.of(context).mdColored(textBase,),
                            ),
                          ),
                          if (subtitle.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TpTextStyles.of(context).xsColored(textBase.withValues(alpha: 0.52),
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
