import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../theme/workspace_surface_layers.dart';

/// One actionable row in the floating workspace empty state.
class FloatingWorkspaceEmptyRow {
  const FloatingWorkspaceEmptyRow({
    required this.id,
    required this.icon,
    required this.label,
    this.shortcutLabels = const [],
  });

  final String id;
  final IconData icon;
  final String label;

  /// Optional keycap chip labels (already formatted, e.g. `Ctrl+``).
  final List<String> shortcutLabels;
}

/// Orca-like empty launcher: icon + label + optional shortcut keycaps.
///
/// Supports ↑↓ + Enter keyboard selection when focused.
class FloatingWorkspaceEmpty extends StatefulWidget {
  const FloatingWorkspaceEmpty({
    required this.rows,
    required this.onActivate,
    this.autofocus = false,
    super.key,
  });

  final List<FloatingWorkspaceEmptyRow> rows;
  final ValueChanged<String> onActivate;
  final bool autofocus;

  @override
  State<FloatingWorkspaceEmpty> createState() => _FloatingWorkspaceEmptyState();
}

class _FloatingWorkspaceEmptyState extends State<FloatingWorkspaceEmpty> {
  late final FocusNode _focusNode;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FloatingWorkspaceEmpty oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_selectedIndex >= widget.rows.length) {
      _selectedIndex = widget.rows.isEmpty ? 0 : widget.rows.length - 1;
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || widget.rows.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1) % widget.rows.length;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex =
            (_selectedIndex - 1 + widget.rows.length) % widget.rows.length;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      widget.onActivate(widget.rows[_selectedIndex].id);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final styles = TpTextStyles.of(context);

    return Focus(
      focusNode: _focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: _onKey,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < widget.rows.length; i++)
                _EmptyRowTile(
                  row: widget.rows[i],
                  selected: i == _selectedIndex,
                  onHover: () => setState(() => _selectedIndex = i),
                  onTap: () {
                    setState(() => _selectedIndex = i);
                    widget.onActivate(widget.rows[i].id);
                  },
                  foreground: cs.onSurface,
                  styles: styles,
                  subtle: cs.workspaceSubtleSurface,
                  outline: cs.outlineVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyRowTile extends StatelessWidget {
  const _EmptyRowTile({
    required this.row,
    required this.selected,
    required this.onHover,
    required this.onTap,
    required this.foreground,
    required this.styles,
    required this.subtle,
    required this.outline,
  });

  final FloatingWorkspaceEmptyRow row;
  final bool selected;
  final VoidCallback onHover;
  final VoidCallback onTap;
  final Color foreground;
  final TpTextStyles styles;
  final Color subtle;
  final Color outline;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: Material(
        color: selected ? subtle : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(row.icon, size: 18, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    row.label,
                    style: styles.smMediumColored(foreground),
                  ),
                ),
                if (row.shortcutLabels.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Wrap(
                    spacing: 4,
                    children: [
                      for (final label in row.shortcutLabels)
                        _KeycapChip(
                          label: label,
                          subtle: subtle,
                          outline: outline,
                          styles: styles,
                          foreground: foreground,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KeycapChip extends StatelessWidget {
  const _KeycapChip({
    required this.label,
    required this.subtle,
    required this.outline,
    required this.styles,
    required this.foreground,
  });

  final String label;
  final Color subtle;
  final Color outline;
  final TpTextStyles styles;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: subtle,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: outline.withValues(alpha: 0.6)),
      ),
      child: Text(label, style: styles.xsSemiboldColored(foreground)),
    );
  }
}
