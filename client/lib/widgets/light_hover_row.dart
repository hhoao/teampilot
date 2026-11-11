import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Hover surface for dense, lazily-built list rows.
///
/// A minimal alternative to [TpHover]: no focus node, no semantics annotation,
/// no Stack/Positioned fill layer and no implicit animation. On every list
/// rebuild those layers cost five widget builds plus several render proxy
/// boxes per visible row. A row here only needs a hover tint and tap handling,
/// so [MouseRegion] + [GestureDetector] + [DecoratedBox] is enough.
///
/// The keyboard focus ring and the "button" semantics annotation are
/// intentionally omitted; these rows are reached through the surrounding tree
/// rather than tab focus.
///
/// [trailing] / [forceShowTrailing] / [showTrailingOnMobile] mirror
/// [TpHoverRow] so sidebar-style rows that reveal actions on hover can use the
/// same lightweight surface.
class LightHoverRow extends StatefulWidget {
  const LightHoverRow({
    required this.child,
    this.trailing,
    this.trailingWidth,
    this.forceShowTrailing = false,
    this.showTrailingOnMobile = true,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTapDown,
    this.onLongPress,
    this.backgroundColor,
    this.hoverColor,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
    this.padding = EdgeInsets.zero,
    this.forceHover = false,
    this.enabled = true,
    this.cursor,
    this.expandWidth = false,
    this.addButtonSemantics = false,
    this.onHoverChanged,
    super.key,
  });

  final Widget child;

  /// Shown only while hovered (or always on Android, or while pinned).
  final Widget? trailing;
  final double? trailingWidth;

  /// Keeps [trailing] mounted (e.g. while an overflow menu is open).
  final bool forceShowTrailing;

  /// When true, [trailing] stays visible on Android without hover.
  final bool showTrailingOnMobile;

  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final GestureTapDownCallback? onSecondaryTapDown;
  final VoidCallback? onLongPress;

  /// Idle fill. Transparent when null.
  final Color? backgroundColor;

  /// Tint composited over [backgroundColor] while hovered. Null uses
  /// [TpHover.defaultHoverColor] so the tint matches the rest of the app.
  final Color? hoverColor;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  /// Keeps the hover fill visible (e.g. while an anchored menu is open).
  final bool forceHover;

  /// False swallows taps and reports no hover tint.
  final bool enabled;
  final MouseCursor? cursor;

  /// Stretch the surface to the parent's full width (sidebar rows).
  final bool expandWidth;

  /// Adds a `button` semantics node. Dense list rows leave this off — they are
  /// reached through the surrounding tree — but navigation rows opt in so
  /// screen readers still announce them as buttons (what [TpHover] provided).
  final bool addButtonSemantics;

  final ValueChanged<bool>? onHoverChanged;

  @override
  State<LightHoverRow> createState() => _LightHoverRowState();
}

class _LightHoverRowState extends State<LightHoverRow> {
  var _hovered = false;

  bool get _showTrailing {
    if (widget.trailing == null) return false;
    if (widget.forceShowTrailing) return true;
    if (widget.showTrailingOnMobile &&
        defaultTargetPlatform == TargetPlatform.android) {
      return true;
    }
    return _hovered;
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
    widget.onHoverChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final hoverFill = widget.hoverColor ?? TpHover.defaultHoverColor(context);
    final resting = widget.backgroundColor ?? Colors.transparent;
    final hovered = widget.enabled && (widget.forceHover || _hovered);
    final fill = hovered ? Color.alphaBlend(hoverFill, resting) : resting;

    Widget content = widget.child;
    if (widget.trailing != null) {
      content = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: widget.child),
          if (_showTrailing && widget.trailingWidth != null)
            SizedBox(width: widget.trailingWidth, child: widget.trailing!)
          else if (_showTrailing)
            widget.trailing!,
        ],
      );
    }
    if (widget.expandWidth) {
      content = SizedBox(width: double.infinity, child: content);
    }

    Widget surface = MouseRegion(
      cursor: !widget.enabled
          ? MouseCursor.defer
          : (widget.cursor ?? SystemMouseCursors.click),
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.enabled ? widget.onTap : null,
        onDoubleTap: widget.enabled ? widget.onDoubleTap : null,
        onSecondaryTapDown: widget.enabled ? widget.onSecondaryTapDown : null,
        onLongPress: widget.enabled ? widget.onLongPress : null,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: widget.borderRadius,
          ),
          child: Padding(padding: widget.padding, child: content),
        ),
      ),
    );
    if (widget.addButtonSemantics) {
      final onTap = widget.onTap;
      surface = Semantics(
        button: true,
        enabled: widget.enabled,
        onTap: widget.enabled && onTap != null ? onTap : null,
        child: surface,
      );
    }
    return surface;
  }
}
