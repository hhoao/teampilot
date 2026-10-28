import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

TpTokenPalette resolveSlashAtTokenPalette(
  String token,
  ColorScheme colorScheme,
) {
  final isSlash = token.startsWith('/');
  return (
    background: isSlash
        ? colorScheme.tertiaryContainer.withValues(alpha: 0.95)
        : colorScheme.secondaryContainer.withValues(alpha: 0.95),
    foreground: isSlash
        ? colorScheme.onTertiaryContainer
        : colorScheme.onSecondaryContainer,
  );
}
