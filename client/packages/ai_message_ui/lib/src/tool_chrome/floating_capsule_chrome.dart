import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Floating-overlay capsule chrome shared across the session's top-right
/// surfaces — the task board pill/card and the icon view toggle that docks
/// into it: soft two-layer shadow over an outlined surfaceContainerHigh fill.
class AiFloatingCapsuleChrome extends StatelessWidget {
  const AiFloatingCapsuleChrome({
    required this.borderRadius,
    required this.child,
    super.key,
  });

  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.10 : 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.38 : 0.16),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: scheme.surfaceContainerHigh,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: borderRadius,
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.9),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: child,
      ),
    );
  }
}
