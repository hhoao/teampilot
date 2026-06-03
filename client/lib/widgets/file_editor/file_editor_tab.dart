import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:teampilot/theme/app_icon_sizes.dart';

import '../../l10n/l10n_extensions.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/file_icon.dart';
import '../menu/sidebar_action_menu.dart';

/// Single open-file tab in the editor tab bar (icon, label, close, context menu).
class FileEditorTab extends StatefulWidget {
  const FileEditorTab({
    super.key,
    required this.fileName,
    required this.filePath,
    required this.selected,
    required this.dirty,
    required this.onTap,
    required this.onClose,
    required this.onCloseOthers,
    required this.onCloseRight,
  });

  final String fileName;
  final String filePath;
  final bool selected;
  final bool dirty;
  final VoidCallback onTap;
  final VoidCallback onClose;
  final VoidCallback onCloseOthers;
  final VoidCallback onCloseRight;

  @override
  State<FileEditorTab> createState() => _FileEditorTabState();
}

class _FileEditorTabState extends State<FileEditorTab> {
  void _handleMenuSelection(String value) {
    switch (value) {
      case 'close':
        widget.onClose();
      case 'closeOthers':
        widget.onCloseOthers();
      case 'closeRight':
        widget.onCloseRight();
    }
  }

  List<SidebarActionMenuSpec> _menuSpecs(BuildContext menuContext) {
    final l10n = menuContext.l10n;
    return [
      SidebarActionMenuSpec.item(
        value: 'close',
        icon: Icons.close,
        label: l10n.closeTab,
      ),
      SidebarActionMenuSpec.item(
        value: 'closeOthers',
        icon: Icons.tab_unselected,
        label: l10n.closeOtherTabs,
      ),
      SidebarActionMenuSpec.item(
        value: 'closeRight',
        icon: Icons.arrow_forward,
        label: l10n.closeRightTabs,
      ),
    ];
  }

  Future<void> _showContextMenuAtTap(TapDownDetails details) async {
    if (!mounted) return;
    final selected = await showSidebarActionMenuFromSpecsAtTap<String>(
      context: context,
      tapDetails: details,
      specs: _menuSpecs(context),
    );
    if (!mounted || selected == null) return;
    _handleMenuSelection(selected);
  }

  void _showContextMenuFromTap(TapDownDetails details) {
    unawaited(_showContextMenuAtTap(details));
  }

  void _showContextMenuAtCenter() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final center = box.localToGlobal(
      Offset(box.size.width / 2, box.size.height / 2),
    );
    unawaited(_showContextMenuAtPosition(center));
  }

  Future<void> _showContextMenuAtPosition(Offset globalPosition) async {
    if (!mounted) return;
    final selected = await showSidebarActionMenuFromSpecs<String>(
      context: context,
      globalPosition: globalPosition,
      specs: _menuSpecs(context),
    );
    if (!mounted || selected == null) return;
    _handleMenuSelection(selected);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = widget.dirty ? '${widget.fileName} •' : widget.fileName;
    final labelColor = widget.selected ? cs.onSecondaryContainer : cs.onSurface;
    final closeColor = widget.selected
        ? cs.onSecondaryContainer
        : cs.iconMuted;

    return Tooltip(
      message: widget.filePath,
      child: Material(
        color: widget.selected ? cs.secondaryContainer : Colors.transparent,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onSecondaryTapDown: _showContextMenuFromTap,
          onLongPress: Platform.isAndroid ? _showContextMenuAtCenter : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  fileIconForFileName(widget.fileName),
                  size: AppIconSizes.sm,
                  color: labelColor,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppTextStyles.of(context).body.copyWith(
                    fontWeight: widget.selected
                        ? FontWeight.w600
                        : FontWeight.w500,
                    color: labelColor,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: widget.onClose,
                  child: Icon(
                    Icons.close,
                    size: AppIconSizes.md,
                    color: closeColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
