import 'package:flutter/material.dart';

/// Text column inset: row padding + leading slot + gap (matches session tiles).
const double kWorkspaceSidebarGroupTextInset = 8 + 24 + 8;

/// Shared row metrics for workspace sidebar group + session rows.
const double kWorkspaceSidebarRowMinHeight = 32;
const EdgeInsets kWorkspaceSidebarRowPadding = EdgeInsets.fromLTRB(8, 6, 8, 6);

const double kWorkspaceSidebarRowHoverTintAlpha = 0.07;

Color workspaceSidebarRowHoverFill(ColorScheme cs) {
  return Color.alphaBlend(
    cs.onSurface.withValues(alpha: kWorkspaceSidebarRowHoverTintAlpha),
    cs.surfaceContainer,
  );
}
