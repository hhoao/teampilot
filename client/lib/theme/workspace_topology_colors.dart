import 'package:flutter/material.dart';

import '../models/workspace_topology.dart';

/// Shared topology accent colors for tabs, chips, and menus.
///
/// Remote and mixed hues are muted and blended with [ColorScheme.onSurfaceVariant]
/// so they read as hints rather than traffic-light accents.
abstract final class WorkspaceTopologyColors {
  static const _remoteLight = Color(0xFF4A8B57);
  static const _remoteDark = Color(0xFF8FB89A);
  static const _mixedLight = Color(0xFFB08A42);
  static const _mixedDark = Color(0xFFC9A85A);

  static Color remote(Brightness brightness) {
    return brightness == Brightness.dark ? _remoteDark : _remoteLight;
  }

  static Color mixed(Brightness brightness) {
    return brightness == Brightness.dark ? _mixedDark : _mixedLight;
  }

  static Color of({
    required WorkspaceTopology topology,
    required ColorScheme colorScheme,
    required Brightness brightness,
  }) {
    return switch (topology) {
      WorkspaceTopology.local => colorScheme.primary,
      WorkspaceTopology.remote => _tone(
        accent: remote(brightness),
        colorScheme: colorScheme,
      ),
      WorkspaceTopology.mixed => _tone(
        accent: mixed(brightness),
        colorScheme: colorScheme,
      ),
    };
  }

  /// Pull accent toward neutral foreground so topology stays subtle on any preset.
  @visibleForTesting
  static Color toneForTest({
    required Color accent,
    required ColorScheme colorScheme,
  }) =>
      _tone(accent: accent, colorScheme: colorScheme);

  static Color _tone({
    required Color accent,
    required ColorScheme colorScheme,
    double accentWeight = 0.70,
  }) {
    return Color.lerp(
      colorScheme.onSurfaceVariant,
      accent,
      accentWeight,
    )!;
  }

  static Color borderAlpha(Color color, {double alpha = 0.38}) {
    return color.withValues(alpha: alpha);
  }
}
