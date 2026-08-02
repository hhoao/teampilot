import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/material.dart';

/// Applies line-spaced selection highlight height for [SelectionArea] text.
///
/// Uses [BoxHeightStyle.includeLineSpacingMiddle] so extra [TextStyle.height]
/// leading is split above/below the glyphs (less “empty top, tight bottom”
/// than [BoxHeightStyle.includeLineSpacingTop], while still covering wrap
/// seams better than [BoxHeightStyle.tight]).
///
/// Requires Flutter with [DefaultSelectionStyle.selectionHeightStyle]
/// (`docs/flutter-patches.md`). Nested [Theme] must forward the ambient
/// height style (patched) — chat wraps messages in [Theme] for
/// [AiMessageTheme] and would otherwise wipe this back to tight.
/// Apply with `./tool/flutter_patches/apply_flutter_patches.sh`.
class AiLineSpacedSelectionStyle extends StatelessWidget {
  const AiLineSpacedSelectionStyle({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DefaultSelectionStyle(
      // Middle balances padding; framework paint honors this style and joins
      // residual wrap seams (see selection_height_style.patch).
      selectionHeightStyle: BoxHeightStyle.includeLineSpacingMiddle,
      child: child,
    );
  }
}
