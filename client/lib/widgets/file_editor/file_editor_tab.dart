import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../l10n/l10n_extensions.dart';
import '../file_icon_widget.dart';
import '../tab_close_button.dart';

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

  List<TpActionMenuSpec> _menuSpecs(BuildContext menuContext) {
    final l10n = menuContext.l10n;
    return [
      TpActionMenuSpec.item(
        value: 'close',
        icon: Icons.close,
        label: l10n.closeTab,
      ),
      TpActionMenuSpec.item(
        value: 'closeOthers',
        icon: Icons.tab_unselected,
        label: l10n.closeOtherTabs,
      ),
      TpActionMenuSpec.item(
        value: 'closeRight',
        icon: Icons.arrow_forward,
        label: l10n.closeRightTabs,
      ),
    ];
  }

  Future<void> _showContextMenuAtTap(TapDownDetails details) async {
    if (!mounted) return;
    final selected = await showTpActionMenuFromSpecsAtTap<String>(
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
    final selected = await showTpActionMenuFromSpecs<String>(
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
    final closeColor = widget.selected ? cs.onSecondaryContainer : cs.tpIconMuted;

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
                FileIconWidget(
                  fileName: widget.fileName,
                  size: context.tpIconSizes.sm,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: widget.selected
                      ? TpTextStyles.of(context).mdSemiboldColored(labelColor)
                      : TpTextStyles.of(context).mdMediumColored(labelColor),
                ),
                const SizedBox(width: 4),
                TabCloseButton(
                  active: widget.selected,
                  tint: closeColor,
                  onTap: widget.onClose,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
