import 'dart:ui' show BoxHeightStyle;

import 'package:flutter/material.dart';

/// Applies browser-like selection highlight height for [SelectionArea] text.
///
/// Requires Flutter with [DefaultSelectionStyle.selectionHeightStyle]
/// (`docs/flutter-patches.md`). Apply with
/// `./tool/flutter_patches/apply_flutter_patches.sh`.
class AiLineSpacedSelectionStyle extends StatelessWidget {
  const AiLineSpacedSelectionStyle({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DefaultSelectionStyle(
      // Top puts line-spacing into each box's top edge so wrapped lines overlap
      // slightly; combined with the SDK paint gap-close this removes hairlines.
      selectionHeightStyle: BoxHeightStyle.includeLineSpacingTop,
      child: child,
    );
  }
}
