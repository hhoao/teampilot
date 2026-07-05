import 'package:flutter/material.dart';

import '../../../theme/workspace_surface_layers.dart';

/// Shared surface, border, and foreground tokens for the landing compose UI.
@immutable
class WorkspaceChatLandingPalette {
  WorkspaceChatLandingPalette(ColorScheme cs)
    : elevated = cs.workspaceCard,
      chipFill = cs.workspaceInset,
      border = cs.outlineVariant.withValues(alpha: 0.7),
      muted = cs.workspaceMutedText,
      hint = cs.workspaceMutedText.withValues(alpha: 0.72),
      disabled = cs.workspaceMutedText.withValues(alpha: 0.38),
      sendIdle = cs.onSurfaceVariant.withValues(alpha: 0.18),
      sendActive = cs.onSurface,
      sendIcon = cs.surface;

  final Color elevated;
  final Color chipFill;
  final Color border;
  final Color muted;
  final Color hint;
  final Color disabled;
  final Color sendIdle;
  final Color sendActive;
  final Color sendIcon;
}
