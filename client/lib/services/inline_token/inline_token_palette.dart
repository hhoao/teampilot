import 'package:flutter/material.dart';

/// Background and foreground colors for one inline token chip.
typedef InlineTokenPalette = ({Color background, Color foreground});

/// Resolves chip colors for a matched [token] string.
typedef InlineTokenPaletteResolver =
    InlineTokenPalette Function(String token, ColorScheme colorScheme);

/// Default pattern for compose `@path` and `/skill` tokens.
final RegExp defaultInlineTokenPattern = RegExp(r'@\S+|/\S+');

InlineTokenPalette resolveSlashAtTokenPalette(
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
