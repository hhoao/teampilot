import 'package:flutter/material.dart';

import '../models/workspace_topology.dart';

/// Shared topology accent colors for tabs, chips, and menus.
///
/// Remote and mixed hues are muted and blended with [ColorScheme.onSurfaceVariant]
/// so they read as hints rather than traffic-light accents.
abstract final class WorkspaceTopologyColors {
  static const _remoteLight = Color(0xFF5F7A68);
  static const _remoteDark = Color(0xFF7E9486);
  static const _mixedLight = Color(0xFF8F7650);
  static const _mixedDark = Color(0xFF9E8B62);

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
    double accentWeight = 0.58,
  }) {
    return Color.lerp(
      colorScheme.onSurfaceVariant,
      accent,
      accentWeight,
    )!;
  }

  static Color borderAlpha(Color color, {double alpha = 0.35}) {
    return color.withValues(alpha: alpha);
  }
}
