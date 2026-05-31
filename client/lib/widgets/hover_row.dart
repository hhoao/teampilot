import 'dart:io';

import 'package:flutter/material.dart';

import 'hover_widget.dart';

export 'hover_widget.dart';

/// A full-width row with hover background and optional trailing actions that
/// appear on hover (always visible on Android where hover is unavailable).
class HoverRow extends StatefulWidget {
  const HoverRow({
    super.key,
    required this.child,
    this.trailing,
    this.trailingWidth,
    this.forceShowTrailing = false,
    this.showTrailingOnMobile = true,
    this.height,
    this.hoverColor,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.onHoverChanged,
  });

  final Widget child;
  final Widget? trailing;
  final double? trailingWidth;

  /// Keeps [trailing] mounted (e.g. while an overflow menu is open).
  final bool forceShowTrailing;

  /// When true, [trailing] stays visible on Android without hover.
  final bool showTrailingOnMobile;
  final double? height;
  final Color? hoverColor;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final ValueChanged<bool>? onHoverChanged;

  @override
  State<HoverRow> createState() => _HoverRowState();
}

class _HoverRowState extends State<HoverRow> {
  var _hovered = false;

  bool get _showTrailing {
    if (widget.trailing == null) return false;
    if (widget.forceShowTrailing) return true;
    if (widget.showTrailingOnMobile && Platform.isAndroid) return true;
    return _hovered;
  }

  @override
  Widget build(BuildContext context) {
    return HoverWidget(
      hoverColor: widget.hoverColor,
      padding: widget.padding,
      borderRadius: widget.borderRadius,
      onTap: widget.onTap,
      onHoverChanged: (hovered) {
        setState(() => _hovered = hovered);
        widget.onHoverChanged?.call(hovered);
      },
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: widget.child),
            if (_showTrailing && widget.trailingWidth != null)
              SizedBox(
                width: widget.trailingWidth,
                child: widget.trailing!,
              )
            else if (_showTrailing)
              widget.trailing!,
          ],
        ),
      ),
    );
  }
}
