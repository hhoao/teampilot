part of '../context_sidebar.dart';

class _SessionTileEntry extends StatefulWidget {
  const _SessionTileEntry({required this.session});

  final AppSession session;

  @override
  State<_SessionTileEntry> createState() => _SessionTileEntryState();
}

class _SessionTileEntryState extends State<_SessionTileEntry> {
  var _hovered = false;

  /// Keeps the overflow menu mounted while the popup is open; otherwise moving
  /// the pointer onto the overlay triggers [MouseRegion.onExit] and removes
  /// the overflow menu before a menu item can be selected.
  var _menuOpen = false;

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
        _showDeleteDialog(context, session, l10n);
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
        _showDeleteDialog(context, session, l10n);
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

  bool get _showSessionActions => _hovered || _menuOpen || Platform.isAndroid;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final selected = context.select<ChatCubit, bool>(
      (cubit) => cubit.state.activeSessionId == session.sessionId,
    );
    final l10n = context.l10n;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: _SidebarTile(
        key: AppKeys.sessionTile(session.sessionId),
        title: session.resolveDisplayTitle(l10n.defaultNewChatSessionTitle),
        selected: selected,
        rowHovered: _hovered || _menuOpen,
        contentLeftInset: _kSidebarSessionTileInset,
        onTap: throttledTap(
          'context_sidebar_session_${session.sessionId}',
          () => _navigateToSessionInChat(context, session),
        ),
        onSecondaryTapDown: _showSessionContextMenuFromTap,
        onLongPress: Platform.isAndroid
            ? _showSessionContextMenuAtCenter
            : null,
        trailing: SizedBox(
          width: AppIconButton.kDefaultSize,
          height: AppIconButton.kDefaultSize,
          child: _showSessionActions
              ? SidebarActionMenuIconAnchor(
                  icon: const Icon(
                    Icons.more_horiz,
                    size: AppIconButton.kDefaultIconSize,
                  ),
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
                      onTap: () => _showDeleteDialog(context, session, l10n),
                    ),
                  ],
                )
              : null,
        ),
      ),
    );
  }

  void _showRenameDialog(
    BuildContext context,
    AppSession session,
    AppLocalizations l10n,
  ) {
    final repo = context.read<SessionRepository>();
    final controller = TextEditingController(
      text: session.resolveDisplayTitle(l10n.defaultNewChatSessionTitle),
    );
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.renameConversationTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.conversationName),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              unawaited(
                context.read<ChatCubit>().renameSession(
                  repo,
                  session.sessionId,
                  value.trim(),
                ),
              );
            }
            Navigator.of(ctx).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: throttledAsync(
              'context_sidebar_rename_session',
              () async {
                final value = controller.text.trim();
                if (value.isNotEmpty) {
                  await context.read<ChatCubit>().renameSession(
                    repo,
                    session.sessionId,
                    value,
                  );
                }
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(
    BuildContext context,
    AppSession session,
    AppLocalizations l10n,
  ) {
    final repo = context.read<SessionRepository>();
    final name = session.resolveDisplayTitle(l10n.defaultNewChatSessionTitle);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteConversation),
        content: Text(l10n.deleteConversationConfirm(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: throttledAsync(
              'context_sidebar_delete_session',
              () async {
                await context.read<ChatCubit>().deleteSession(
                  repo,
                  session.sessionId,
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }
}
