import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Default pattern for compose `@path` and `/skill` tokens.
final RegExp defaultInlineTokenPattern = RegExp(r'@\S+|/\S+');

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
