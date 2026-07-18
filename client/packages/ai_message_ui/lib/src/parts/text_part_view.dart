import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../history_render_scope.dart';
import '../markdown/compiled_text_part_view.dart';
import '../markdown/content_compiler.dart';
import '../markdown/content_ir.dart';
import '../markdown/content_truncate.dart';
import '../strings.dart';
import '../theme.dart';

export '../markdown/streaming_markdown.dart';

/// Streaming-safe markdown aligned with assistant-ui MarkdownText / aui-md.
///
/// Compiles GFM via [compileMessageContent] (cached) and renders with
/// [CompiledTextPartView]. Under [AiHistoryRenderScope], long content follows
/// Claude Code webview `oYe` (budgeted IR + Show more / Show less) — widgets
/// beyond the budget are omitted so Flutter does not layout them.
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
    final scope = AiHistoryRenderScope.maybeOf(context);
    if (scope == null) {
      return CompiledTextPartView(
        document: document,
        onTapLink: onTapLink,
      );
    }
    return _ExpandableHistoryMarkdown(
      document: document,
      onTapLink: onTapLink,
      budget: scope.contentBudget,
    );
  }
}

/// Claude Code `oYe`-aligned expandable markdown (IR omit, not CSS clip).
class _ExpandableHistoryMarkdown extends StatefulWidget {
  const _ExpandableHistoryMarkdown({
    required this.document,
    required this.budget,
    this.onTapLink,
  });

  final MessageContentDocument document;
  final ContentCollapseBudget budget;
  final MarkdownTapLinkCallback? onTapLink;

  @override
  State<_ExpandableHistoryMarkdown> createState() =>
      _ExpandableHistoryMarkdownState();
}

class _ExpandableHistoryMarkdownState extends State<_ExpandableHistoryMarkdown> {
  var _expanded = false;

  @override
  void didUpdateWidget(covariant _ExpandableHistoryMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.document != widget.document) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final truncated = truncateMessageContent(
      widget.document,
      budget: widget.budget,
    );
    if (!truncated.wasTruncated) {
      return CompiledTextPartView(
        document: widget.document,
        onTapLink: widget.onTapLink,
      );
    }

    final shown = _expanded ? widget.document : truncated.document;
    final strings = AiMessageStrings.of(context);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        CompiledTextPartView(
          document: shown,
          onTapLink: widget.onTapLink,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() => _expanded = !_expanded),
            style: TextButton.styleFrom(
              foregroundColor: scheme.primary,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(_expanded ? strings.showLess : strings.showMore),
          ),
        ),
      ],
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
