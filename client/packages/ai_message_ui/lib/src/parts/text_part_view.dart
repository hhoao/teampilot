import 'package:flutter/material.dart';

import '../history_render_scope.dart';
import '../markdown/content_compiler.dart';
import '../markdown/ir/markdown_document.dart';
import '../markdown/content_truncate.dart';
import '../markdown/registry/markdown_resolvers.dart';
import '../markdown/render/markdown_view.dart';
import '../strings.dart';
import '../theme.dart';

export '../markdown/streaming_markdown.dart';

/// Streaming-safe markdown aligned with assistant-ui MarkdownText / aui-md.
///
/// Compiles GFM via [compileMarkdown] (cached) and renders with
/// [MarkdownView] (compact profile from [AiMessageTheme.markdown]). Under
/// [AiHistoryRenderScope], long content follows Claude Code webview `oYe`
/// (budgeted IR + Show more / Show less) — widgets beyond the budget are omitted
/// so Flutter does not layout them.
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
    final document = compileMarkdown(text);
    final scope = AiHistoryRenderScope.maybeOf(context);
    if (scope == null) {
      return _ChatMarkdownView(
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

MarkdownResolvers _chatResolvers(MarkdownTapLinkCallback? onTapLink) {
  if (onTapLink == null) return const MarkdownResolvers();
  return MarkdownResolvers(
    onLinkTap: (href) => onTapLink('', href, ''),
  );
}

class _ChatMarkdownView extends StatelessWidget {
  const _ChatMarkdownView({
    required this.document,
    this.onTapLink,
  });

  final MarkdownDocument document;
  final MarkdownTapLinkCallback? onTapLink;

  @override
  Widget build(BuildContext context) {
    final theme = AiMessageTheme.of(context);
    return MarkdownView(
      document: document,
      tokens: theme.markdown,
      resolvers: _chatResolvers(onTapLink),
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

  final MarkdownDocument document;
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
      return _ChatMarkdownView(
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
        _ChatMarkdownView(
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
