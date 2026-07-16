import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../markdown/compiled_text_part_view.dart';
import '../markdown/content_compiler.dart';
import '../theme.dart';

export '../markdown/streaming_markdown.dart';

/// Streaming-safe markdown aligned with assistant-ui MarkdownText / aui-md.
///
/// Compiles GFM via [compileMessageContent] (cached) and renders with
/// [CompiledTextPartView]. Unsupported slices fall back to [MarkdownBody]
/// inside the compiled renderer.
class AiTextPartView extends StatelessWidget {
  const AiTextPartView({
    required this.text,
    this.onTapLink,
    super.key,
  });

  final String text;

  /// Optional; package does not launch URLs itself.
  final MarkdownTapLinkCallback? onTapLink;

  @override
  Widget build(BuildContext context) {
    final document = compileMessageContent(text);
    return CompiledTextPartView(
      document: document,
      onTapLink: onTapLink,
    );
  }
}

/// Style sheet for unsupported [MarkdownBody] fallback slices.
MarkdownStyleSheet defaultAiMarkdownSheet(
  ThemeData theme,
  AiMessageTheme aiTheme,
) {
  final scheme = theme.colorScheme;
  final base = MarkdownStyleSheet.fromTheme(theme);
  final body = theme.textTheme.bodyMedium?.copyWith(height: 1.625);
  final muted = aiTheme.resolveMutedSurface(scheme);
  final borderColor = scheme.outlineVariant.withValues(alpha: 0.55);
  return base.copyWith(
    p: body?.copyWith(height: 1.625),
    h1: theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.25,
    ),
    h2: theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    h3: theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.35,
    ),
    // assistant-ui aui-md: inter-block spacing via element margins (`my-3`),
    // not empty spacer widgets. Here blockSpacing → top Padding on siblings.
    blockSpacing: 12,
    h1Padding: const EdgeInsets.only(top: 8),
    h2Padding: const EdgeInsets.only(top: 8),
    h3Padding: const EdgeInsets.only(top: 4),
    listIndent: 24,
    listBullet: body,
    a: body?.copyWith(
      color: scheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: scheme.primary,
    ),
    // Same size/height as body — mismatched inline code metrics fragment
    // SelectionArea highlights (copy still works; it only looks gapped).
    code: body?.copyWith(
      fontFamily: 'monospace',
      backgroundColor: muted.withValues(alpha: 0.55),
    ),
    codeblockDecoration: BoxDecoration(
      color: muted,
      borderRadius: BorderRadius.circular(aiTheme.codeBlockRadius),
    ),
    codeblockPadding: EdgeInsets.zero,
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(
          color: scheme.outlineVariant,
          width: 3,
        ),
      ),
    ),
    blockquotePadding: const EdgeInsets.only(left: 12),
    tableHead: body?.copyWith(fontWeight: FontWeight.w600),
    tableBody: body,
    tableHeadAlign: TextAlign.start,
    tableBorder: TableBorder.all(color: borderColor, width: 1),
    tableColumnWidth: const IntrinsicColumnWidth(),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    tableHeadCellsDecoration: BoxDecoration(color: muted.withValues(alpha: 0.85)),
    tableCellsDecoration: const BoxDecoration(),
    tablePadding: const EdgeInsets.symmetric(vertical: 8),
  );
}
