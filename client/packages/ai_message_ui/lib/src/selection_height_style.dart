import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/material.dart';

/// Applies browser-like selection highlight height for [SelectionArea] text.
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
      // Top includes line-spacing; Skia still only overlaps ~0.1px — the SDK
      // paint path forces ≥0.5px overlap so DPR/AA cannot leave a hairline.
      selectionHeightStyle: BoxHeightStyle.includeLineSpacingTop,
      child: child,
    );
  }
}
