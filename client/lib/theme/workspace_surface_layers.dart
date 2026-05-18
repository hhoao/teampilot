import 'package:flutter/material.dart';

/// Material 3 surface nesting for workspace-style UI.
///
/// Level 0 [workspacePage] -> scaffold / split backdrop.
/// Level 1 [workspaceSubtleSurface] -> quiet panels or rows directly on page.
/// Level 2 [workspaceCard] -> list & detail shells, settings cards.
/// Level 3 [workspaceInset] -> rows, chips, controls inside a card.
/// Level 4 [workspaceCode] -> JSON / code blocks.
extension WorkspaceSurfaceLayers on ColorScheme {
  Color get workspacePage => surface;

  Color get workspaceSubtleSurface => surfaceContainerLow;

  Color get workspaceCard => surfaceContainer;

  Color get workspaceInset => surfaceContainerHigh;

  Color get workspaceCode => surfaceContainerHighest;
}

BoxDecoration workspaceCardDecoration(
  ColorScheme cs, {
  double radius = 10,
  double borderAlpha = 1,
}) {
  return BoxDecoration(
    color: cs.workspaceCard,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: cs.outlineVariant.withValues(alpha: borderAlpha)),
  );
}

BoxDecoration workspaceInsetDecoration(ColorScheme cs, {double radius = 8}) {
  return BoxDecoration(
    color: cs.workspaceInset,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
  );
}

BoxDecoration workspaceCodeDecoration(ColorScheme cs, {double radius = 8}) {
  return BoxDecoration(
    color: cs.workspaceCode,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.45)),
  );
}
