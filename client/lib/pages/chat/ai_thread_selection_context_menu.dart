import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/menu/sidebar_action_menu.dart';

/// [SelectionArea] toolbar that opens [SidebarActionMenu] (same as editor /
/// terminal context menus) instead of the platform Material text toolbar.
Widget buildAiThreadSelectionContextMenu(
  BuildContext context,
  SelectableRegionState selectableRegionState,
) {
  return _AiThreadSelectionContextMenu(state: selectableRegionState);
}

class _AiThreadSelectionContextMenu extends StatefulWidget {
  const _AiThreadSelectionContextMenu({required this.state});

  final SelectableRegionState state;

  @override
  State<_AiThreadSelectionContextMenu> createState() =>
      _AiThreadSelectionContextMenuState();
}

class _AiThreadSelectionContextMenuState
    extends State<_AiThreadSelectionContextMenu> {
  var _opened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _opened) return;
      _opened = true;
      unawaited(_openMenu());
    });
  }

  Future<void> _openMenu() async {
    final state = widget.state;
    final items = state.contextMenuButtonItems;
    if (items.isEmpty) {
      state.hideToolbar();
      return;
    }

    final specs = <SidebarActionMenuSpec>[
      for (final item in items)
        SidebarActionMenuSpec.item(
          icon: _iconFor(item.type),
          label: item.label ?? _fallbackLabel(context, item.type),
          onAction: () => item.onPressed?.call(),
        ),
    ];

    await showSidebarActionMenuFromSpecs<void>(
      context: context,
      globalPosition: state.contextMenuAnchors.primaryAnchor,
      specs: specs,
    );
    if (!mounted) return;
    state.hideToolbar();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

IconData _iconFor(ContextMenuButtonType type) {
  return switch (type) {
    ContextMenuButtonType.copy => Icons.content_copy,
    ContextMenuButtonType.cut => Icons.content_cut,
    ContextMenuButtonType.paste => Icons.content_paste,
    ContextMenuButtonType.selectAll => Icons.select_all,
    ContextMenuButtonType.delete => Icons.delete_outline,
    ContextMenuButtonType.lookUp => Icons.menu_book_outlined,
    ContextMenuButtonType.searchWeb => Icons.search,
    ContextMenuButtonType.share => Icons.share_outlined,
    ContextMenuButtonType.liveTextInput => Icons.text_fields,
    ContextMenuButtonType.custom => Icons.more_horiz,
  };
}

String _fallbackLabel(BuildContext context, ContextMenuButtonType type) {
  final mloc = MaterialLocalizations.of(context);
  return switch (type) {
    ContextMenuButtonType.copy => mloc.copyButtonLabel,
    ContextMenuButtonType.cut => mloc.cutButtonLabel,
    ContextMenuButtonType.paste => mloc.pasteButtonLabel,
    ContextMenuButtonType.selectAll => mloc.selectAllButtonLabel,
    ContextMenuButtonType.delete => mloc.deleteButtonTooltip,
    _ => type.name,
  };
}
