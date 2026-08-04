import 'package:flutter/material.dart';

/// Text column inset: row padding + leading slot + gap (matches session tiles).
const double kWorkspaceSidebarGroupTextInset = 8 + 24 + 8;

/// Shared row metrics for workspace sidebar group + session rows.
const double kWorkspaceSidebarRowMinHeight = 32;
const EdgeInsets kWorkspaceSidebarRowPadding = EdgeInsets.fromLTRB(8, 6, 8, 6);

const double kWorkspaceSidebarRowHoverTintAlpha = 0.07;

/// Translucent row hover tint — composites over the sidebar card (`surface`),
/// not a pre-blended `surfaceContainer` chip (that mismatched workspace chrome
/// and flashed when [TpHover] animated from transparent).
Color workspaceSidebarRowHoverFill(ColorScheme cs) {
  return cs.onSurface.withValues(alpha: kWorkspaceSidebarRowHoverTintAlpha);
}
