import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Close control for tab strips — explicit hover tint so it stays readable on
/// active tab backgrounds ([ColorScheme.surfaceContainerHigh], etc.).
class TabCloseButton extends StatelessWidget {
  const TabCloseButton({
    super.key,
    required this.onTap,
    this.active = false,
    this.tint,
  });

  final VoidCallback? onTap;
  final bool active;

  /// Icon color. When null, uses [ColorScheme.onSurface] if [active] else
  /// [ColorScheme.onSurfaceVariant].
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveTint = tint ?? (active ? cs.onSurface : cs.onSurfaceVariant);
    // Stronger hover on active tabs where the chip background is already filled.
    final hoverAlpha = active ? 0.14 : 0.08;

    return TpHover(
      borderRadius: BorderRadius.circular(5),
      padding: const EdgeInsets.all(2),
      hoverColor: cs.onSurface.withValues(alpha: hoverAlpha),
      onTap: onTap,
      child: Icon(
        Icons.close,
        size: context.tpIconSizes.md,
        color: effectiveTint,
      ),
    );
  }
}
