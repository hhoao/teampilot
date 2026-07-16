import 'package:flutter/material.dart';

import '../theme.dart';

/// Theme tokens for [CompiledTextPartView] (style-free IR + themed paint).
@immutable
class CompiledMarkdownStyle {
  const CompiledMarkdownStyle({
    required this.body,
    required this.h1,
    required this.h2,
    required this.h3,
    required this.h4,
    required this.h5,
    required this.h6,
    required this.link,
    required this.inlineCode,
    required this.codeBlock,
    required this.codeLanguage,
    required this.listBullet,
    required this.blockquote,
    required this.tableHead,
    required this.tableBody,
    required this.mutedSurface,
    required this.borderColor,
    required this.codeBlockRadius,
    required this.blockSpacing,
    required this.listIndent,
  });

  factory CompiledMarkdownStyle.from(
    ThemeData theme,
    AiMessageTheme aiTheme,
  ) {
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyMedium?.copyWith(height: 1.625) ??
        const TextStyle(fontSize: 14, height: 1.625);
    final muted = aiTheme.resolveMutedSurface(scheme);
    final borderColor = scheme.outlineVariant.withValues(alpha: 0.55);
    return CompiledMarkdownStyle(
      body: body,
      h1: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.25,
          ) ??
          body.copyWith(fontSize: 22, fontWeight: FontWeight.w600),
      h2: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.3,
          ) ??
          body.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      h3: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            height: 1.35,
          ) ??
          body.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      h4: body.copyWith(fontWeight: FontWeight.w600, height: 1.4),
      h5: body.copyWith(fontWeight: FontWeight.w600, height: 1.4),
      h6: body.copyWith(fontWeight: FontWeight.w600, height: 1.4),
      link: body.copyWith(
        color: scheme.primary,
        decoration: TextDecoration.underline,
        decorationColor: scheme.primary,
      ),
      inlineCode: body.copyWith(
        fontFamily: 'monospace',
        backgroundColor: muted.withValues(alpha: 0.55),
      ),
      codeBlock: theme.textTheme.bodySmall?.copyWith(
            fontFamily: 'monospace',
            height: 1.45,
            color: scheme.onSurface,
          ) ??
          body.copyWith(fontFamily: 'monospace', height: 1.45),
      codeLanguage: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ) ??
          body.copyWith(
            fontSize: 12,
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
      listBullet: body,
      blockquote: body.copyWith(color: scheme.onSurfaceVariant),
      tableHead: body.copyWith(fontWeight: FontWeight.w600),
      tableBody: body,
      mutedSurface: muted,
      borderColor: borderColor,
      codeBlockRadius: aiTheme.codeBlockRadius,
      blockSpacing: 12,
      listIndent: 24,
    );
  }

  final TextStyle body;
  final TextStyle h1;
  final TextStyle h2;
  final TextStyle h3;
  final TextStyle h4;
  final TextStyle h5;
  final TextStyle h6;
  final TextStyle link;
  final TextStyle inlineCode;
  final TextStyle codeBlock;
  final TextStyle codeLanguage;
  final TextStyle listBullet;
  final TextStyle blockquote;
  final TextStyle tableHead;
  final TextStyle tableBody;
  final Color mutedSurface;
  final Color borderColor;
  final double codeBlockRadius;
  final double blockSpacing;
  final double listIndent;

  TextStyle headingStyle(int level) {
    return switch (level) {
      1 => h1,
      2 => h2,
      3 => h3,
      4 => h4,
      5 => h5,
      _ => h6,
    };
  }
}
