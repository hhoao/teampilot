import 'package:flutter/material.dart';

/// Single selectable row in an AppFlowy-style dropdown menu.
class DropdownMenuItemButton extends StatefulWidget {
  const DropdownMenuItemButton({
    super.key,
    required this.child,
    required this.onTap,
    required this.padding,
    required this.highlightColor,
    required this.selectedColor,
    this.isSelected = false,
    this.borderRadius,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color highlightColor;
  final Color selectedColor;
  final bool isSelected;
  final BorderRadius? borderRadius;
  final bool enabled;

  @override
  State<DropdownMenuItemButton> createState() =>
      _DropdownMenuItemButtonState();
}

class _DropdownMenuItemButtonState extends State<DropdownMenuItemButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(6);
    Color background = Colors.transparent;
    if (widget.isSelected) {
      background = widget.selectedColor;
    } else if (_isHovering) {
      background = widget.highlightColor;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      cursor: widget.enabled && widget.onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: background,
            borderRadius: radius,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
