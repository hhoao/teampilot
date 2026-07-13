import 'package:flutter/material.dart';

/// assistant-ui composer shell focus-within chrome (border + light shadow).
///
/// Idle: softer [borderColor] + soft shadow.
/// Focused: higher-contrast onSurface edge + lifted shadow.
/// Dark: no shadow; border strengthens on focus.
/// [floating]: same border treatment (history overlay still shows an idle edge).
class ComposeFocusShell extends StatelessWidget {
  const ComposeFocusShell({
    required this.focusNode,
    required this.color,
    required this.borderColor,
    required this.child,
    this.floating = false,
    this.borderRadius = 20,
    super.key,
  });

  final FocusNode focusNode;
  final Color color;
  final Color borderColor;
  final Widget child;
  final bool floating;
  final double borderRadius;

  static const _duration = Duration(milliseconds: 150);

  /// Fixed width so focus never shifts layout.
  static const _borderWidth = 1.5;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        final radius = BorderRadius.circular(borderRadius);
        return AnimatedContainer(
          duration: _duration,
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: color,
            borderRadius: radius,
            border: Border.fromBorderSide(
              _borderSide(
                focused: focused,
                isDark: isDark,
                onSurface: scheme.onSurface,
              ),
            ),
            boxShadow: _shadows(focused: focused, isDark: isDark),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: child,
          ),
        );
      },
    );
  }

  BorderSide _borderSide({
    required bool focused,
    required bool isDark,
    required Color onSurface,
  }) {
    if (!focused) {
      return BorderSide(
        color: borderColor.withValues(alpha: isDark ? 0.2 : 0.55),
        width: _borderWidth,
      );
    }
    // Brighter than outlineVariant — readable focus ring without primary glow.
    return BorderSide(
      color: onSurface.withValues(alpha: isDark ? 0.55 : 0.42),
      width: _borderWidth,
    );
  }

  List<BoxShadow>? _shadows({required bool focused, required bool isDark}) {
    if (isDark) return null;
    if (focused) {
      return const [
        BoxShadow(
          color: Color(0x2E000000),
          blurRadius: 28,
          offset: Offset(0, 8),
          spreadRadius: -6,
        ),
        BoxShadow(
          color: Color(0x14000000),
          blurRadius: 4,
          offset: Offset(0, 1),
        ),
      ];
    }
    return const [
      BoxShadow(
        color: Color(0x14000000),
        blurRadius: 16,
        offset: Offset(0, 4),
        spreadRadius: -8,
      ),
      BoxShadow(
        color: Color(0x0A000000),
        blurRadius: 2,
        offset: Offset(0, 1),
      ),
    ];
  }
}
