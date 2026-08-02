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
/// Hover highlight is owned per-row (no parent rebuild) so light-mode does not
/// flash. ↑↓ keeps a keyboard focus ring until the pointer enters a row.
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
  int _keyboardIndex = 0;
  int? _hoveredIndex;
  var _keyboardNavActive = false;

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
    if (_keyboardIndex >= widget.rows.length) {
      _keyboardIndex = widget.rows.isEmpty ? 0 : widget.rows.length - 1;
    }
    if (_hoveredIndex != null && _hoveredIndex! >= widget.rows.length) {
      _hoveredIndex = null;
    }
  }

  int get _activateIndex => _hoveredIndex ?? _keyboardIndex;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || widget.rows.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _keyboardNavActive = true;
        _hoveredIndex = null;
        _keyboardIndex = (_keyboardIndex + 1) % widget.rows.length;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _keyboardNavActive = true;
        _hoveredIndex = null;
        _keyboardIndex =
            (_keyboardIndex - 1 + widget.rows.length) % widget.rows.length;
      });
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      widget.onActivate(widget.rows[_activateIndex].id);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onHoverEnter(int index) {
    _hoveredIndex = index;
    if (!_keyboardNavActive) return;
    // Drop keyboard ring without touching hover-owned row paint.
    setState(() => _keyboardNavActive = false);
  }

  void _onHoverExit(int index) {
    if (_hoveredIndex == index) _hoveredIndex = null;
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
                  key: ValueKey(widget.rows[i].id),
                  row: widget.rows[i],
                  keyboardHighlighted:
                      _keyboardNavActive && _keyboardIndex == i,
                  onHoverEnter: () => _onHoverEnter(i),
                  onHoverExit: () => _onHoverExit(i),
                  onTap: () => widget.onActivate(widget.rows[i].id),
                  foreground: cs.onSurface,
                  styles: styles,
                  // Card-level hover: inset, not page-level subtle (subtle on
                  // workspaceCard reads as a flash in light mode).
                  highlight: cs.workspaceInset,
                  chipFill: cs.workspaceSubtleSurface,
                  outline: cs.outlineVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyRowTile extends StatefulWidget {
  const _EmptyRowTile({
    required this.row,
    required this.keyboardHighlighted,
    required this.onHoverEnter,
    required this.onHoverExit,
    required this.onTap,
    required this.foreground,
    required this.styles,
    required this.highlight,
    required this.chipFill,
    required this.outline,
    super.key,
  });

  final FloatingWorkspaceEmptyRow row;
  final bool keyboardHighlighted;
  final VoidCallback onHoverEnter;
  final VoidCallback onHoverExit;
  final VoidCallback onTap;
  final Color foreground;
  final TpTextStyles styles;
  final Color highlight;
  final Color chipFill;
  final Color outline;

  @override
  State<_EmptyRowTile> createState() => _EmptyRowTileState();
}

class _EmptyRowTileState extends State<_EmptyRowTile> {
  @override
  Widget build(BuildContext context) {
    return TpHover(
      key: ValueKey('floating_empty_row_fill_${widget.row.id}'),
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(8),
      forceHover: widget.keyboardHighlighted,
      hoverColor: widget.highlight,
      onHoverChanged: (hovered) {
        if (hovered) {
          widget.onHoverEnter();
        } else {
          widget.onHoverExit();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(widget.row.icon, size: 20, color: widget.foreground),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.row.label,
                style: widget.styles.mdColored(widget.foreground),
              ),
            ),
            if (widget.row.shortcutLabels.isNotEmpty) ...[
              const SizedBox(width: 8),
              Wrap(
                spacing: 4,
                children: [
                  for (final label in widget.row.shortcutLabels)
                    _KeycapChip(
                      label: label,
                      fill: widget.chipFill,
                      outline: widget.outline,
                      styles: widget.styles,
                      foreground: widget.foreground,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KeycapChip extends StatelessWidget {
  const _KeycapChip({
    required this.label,
    required this.fill,
    required this.outline,
    required this.styles,
    required this.foreground,
  });

  final String label;
  final Color fill;
  final Color outline;
  final TpTextStyles styles;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: outline.withValues(alpha: 0.6)),
      ),
      child: Text(label, style: styles.smColored(foreground)),
    );
  }
}
