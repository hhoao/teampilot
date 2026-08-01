import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../strings.dart';
import '../theme.dart';
import 'ir/markdown_document.dart';
import 'tokens/markdown_tokens.dart';

/// Match [flutter_markdown_plus] `_buildRichText`: force a uniform line box so
/// mixed CJK / Latin / mono weights cannot open selection seams between wraps.
StrutStyle _forcedStrut(TextStyle style) {
  return StrutStyle(
    fontFamily: style.fontFamily,
    fontFamilyFallback: style.fontFamilyFallback,
    fontSize: style.fontSize,
    height: style.height,
    leading: 0,
    forceStrutHeight: true,
  );
}

/// Renders a style-free [MarkdownDocument] with cheap [Text.rich] /
/// lite table / code chrome. Parent should wrap with [SelectionArea]; leaves
/// are non-selectable [Text] / [Text.rich].
class CompiledTextPartView extends StatelessWidget {
  const CompiledTextPartView({
    required this.document,
    this.onTapLink,
    this.style,
    super.key,
  });

  final MarkdownDocument document;
  final MarkdownTapLinkCallback? onTapLink;
  final MarkdownTokens? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiTheme = AiMessageTheme.of(context);
    final resolved = style ?? aiTheme.markdown;

    final children = <Widget>[];
    final gapsBefore = <double>[];
    final blocks = document.blocks;
    MarkdownBlock? previousBlock;
    var i = 0;
    while (i < blocks.length) {
      final block = blocks[i];
      final gap = previousBlock == null
          ? 0.0
          : _blockGap(previousBlock, block, resolved);
      if (_isMergeableTextual(block)) {
        final mergeEnd = _mergeableRunEnd(blocks, i);
        final merged = blocks.sublist(i, mergeEnd);
        children.add(_buildMergedTextual(merged, resolved));
        gapsBefore.add(gap);
        previousBlock = merged.last;
        i = mergeEnd;
        continue;
      }
      children.add(_buildBlock(context, block, resolved, theme, aiTheme));
      gapsBefore.add(gap);
      previousBlock = block;
      i++;
    }

    if (children.isEmpty) return const SizedBox.shrink();
    if (children.length == 1) return children.single;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var c = 0; c < children.length; c++) ...[
          if (gapsBefore[c] > 0) SizedBox(height: gapsBefore[c]),
          children[c],
        ],
      ],
    );
  }

  /// Incoming headings use [MarkdownTokens.headingTop]; other pairs use
  /// [gapBetween].
  double _blockGap(
    MarkdownBlock previous,
    MarkdownBlock next,
    MarkdownTokens tokens,
  ) {
    return gapBetween(previous.kind, next.kind, tokens);
  }

  bool _isMergeableTextual(MarkdownBlock block) =>
      block is ParagraphBlock || block is HeadingBlock;

  int _mergeableRunEnd(List<MarkdownBlock> blocks, int start) {
    var end = start + 1;
    while (end < blocks.length && _isMergeableTextual(blocks[end])) {
      end++;
    }
    return end;
  }

  Widget _buildMergedTextual(
    List<MarkdownBlock> blocks,
    MarkdownTokens tokens,
  ) {
    final spans = <InlineSpan>[];
    for (var i = 0; i < blocks.length; i++) {
      if (i > 0) {
        final fontSize = tokens.body.fontSize ?? 14.0;
        final gap = gapBetween(blocks[i - 1].kind, blocks[i].kind, tokens);
        spans.add(
          TextSpan(
            text: '\n\n',
            style: tokens.body.copyWith(height: gap / fontSize),
          ),
        );
      }
      final block = blocks[i];
      if (block is HeadingBlock) {
        spans.add(
          TextSpan(
            style: tokens.headingStyle(block.level),
            children: _inlineSpans(
              block.runs,
              tokens,
              tokens.headingStyle(block.level),
            ),
          ),
        );
      } else if (block is ParagraphBlock) {
        spans.add(
          TextSpan(
            style: tokens.body,
            children: _inlineSpans(block.runs, tokens, tokens.body),
          ),
        );
      }
    }
    return Text.rich(
      TextSpan(style: tokens.body, children: spans),
      strutStyle: _forcedStrut(tokens.body),
    );
  }

  Widget _buildBlock(
    BuildContext context,
    MarkdownBlock block,
    MarkdownTokens tokens,
    ThemeData theme,
    AiMessageTheme aiTheme,
  ) {
    return switch (block) {
      ParagraphBlock(:final runs) => Text.rich(
          TextSpan(
            style: tokens.body,
            children: _inlineSpans(runs, tokens, tokens.body),
          ),
          strutStyle: _forcedStrut(tokens.body),
        ),
      HeadingBlock(:final level, :final runs) => Text.rich(
          TextSpan(
            style: tokens.headingStyle(level),
            children: _inlineSpans(runs, tokens, tokens.headingStyle(level)),
          ),
          strutStyle: _forcedStrut(tokens.headingStyle(level)),
        ),
      ListBlock(:final ordered, :final items) => _CompiledList(
          ordered: ordered,
          items: items,
          tokens: tokens,
          depth: 0,
          onTapLink: onTapLink,
        ),
      BlockquoteBlock(:final blocks) => DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: 3,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: CompiledTextPartView(
              document: MarkdownDocument(blocks: blocks),
              onTapLink: onTapLink,
              style: tokens,
            ),
          ),
        ),
      HorizontalRuleBlock() => Divider(color: tokens.borderColor),
      CodeBlock(:final language, :final text) => _CompiledCodeBlock(
          language: language ?? '',
          code: text,
          tokens: tokens,
        ),
      TableBlock(:final headers, :final rows) => _CompiledTable(
          headers: headers,
          rows: rows,
          tokens: tokens,
          onTapLink: onTapLink,
        ),
      ImageBlock(:final src, :final alt) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.image_outlined,
                size: (tokens.body.fontSize ?? 14) + 2,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  alt ?? src,
                  style: tokens.body.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                  strutStyle: _forcedStrut(tokens.body),
                ),
              ),
            ],
          ),
        ),
      RawLiteralBlock(:final rawMarkdown) => MarkdownBody(
          data: rawMarkdown,
          styleSheet: aiTheme.markdown.toMarkdownStyleSheet(),
          onTapLink: onTapLink,
          selectable: false,
        ),
    };
  }

  List<InlineSpan> _inlineSpans(
    List<InlineRun> runs,
    MarkdownTokens tokens,
    TextStyle base,
  ) {
    return [
      for (final run in runs) _inlineSpan(run, tokens, base),
    ];
  }

  InlineSpan _inlineSpan(
    InlineRun run,
    MarkdownTokens tokens,
    TextStyle base,
  ) {
    return switch (run) {
      TextRun(:final text) => TextSpan(text: text, style: base),
      StrongRun(:final children) => TextSpan(
          style: base.copyWith(fontWeight: FontWeight.w700),
          children: _inlineSpans(
            children,
            tokens,
            base.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      EmphasisRun(:final children) => TextSpan(
          style: base.copyWith(fontStyle: FontStyle.italic),
          children: _inlineSpans(
            children,
            tokens,
            base.copyWith(fontStyle: FontStyle.italic),
          ),
        ),
      StrikeRun(:final children) => TextSpan(
          style: base.copyWith(decoration: TextDecoration.lineThrough),
          children: _inlineSpans(
            children,
            tokens,
            base.copyWith(decoration: TextDecoration.lineThrough),
          ),
        ),
      CodeRun(:final text) => TextSpan(text: text, style: tokens.inlineCode),
      // WidgetSpan + GestureDetector so link taps win under parent SelectionArea
      // (TextSpan TapGestureRecognizer loses the arena to SelectableRegion).
      LinkRun(:final url, :final title, :final children) => WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: onTapLink == null
                ? null
                : () => onTapLink!(
                      _plainText(children),
                      url,
                      title ?? '',
                    ),
            child: Text.rich(
              TextSpan(
                style: tokens.link,
                children: _inlineSpans(children, tokens, tokens.link),
              ),
              strutStyle: _forcedStrut(tokens.link),
            ),
          ),
        ),
      ImageRun(:final src, :final alt) =>
        TextSpan(text: alt ?? src, style: base),
    };
  }
}

String _plainText(List<InlineRun> runs) {
  final buffer = StringBuffer();
  void walk(List<InlineRun> list) {
    for (final run in list) {
      switch (run) {
        case TextRun(:final text):
          buffer.write(text);
        case CodeRun(:final text):
          buffer.write(text);
        case StrongRun(:final children) ||
              EmphasisRun(:final children) ||
              StrikeRun(:final children) ||
              LinkRun(:final children):
          walk(children);
        case ImageRun(:final alt, :final src):
          buffer.write(alt ?? src);
      }
    }
  }

  walk(runs);
  return buffer.toString();
}

class _CompiledList extends StatelessWidget {
  const _CompiledList({
    required this.ordered,
    required this.items,
    required this.tokens,
    required this.depth,
    required this.onTapLink,
  });

  final bool ordered;
  final List<ContentListItem> items;
  final MarkdownTokens tokens;
  final int depth;
  final MarkdownTapLinkCallback? onTapLink;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0 && tokens.listItemGap > 0)
            SizedBox(height: tokens.listItemGap),
          _buildItem(items[i], i),
        ],
      ],
    );
  }

  Widget _buildItem(ContentListItem item, int index) {
    final marker = _marker(item, index);
    // Bullet is non-selectable so the body stays one SelectionArea fragment
    // (separate bullet Text caused misaligned / gapped highlights). Strut on
    // the body matches MarkdownBody preview line boxes.
    final content = CompiledTextPartView(
      document: MarkdownDocument(
        blocks: [ParagraphBlock(runs: item.runs)],
      ),
      onTapLink: onTapLink,
      style: tokens,
    );

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectionContainer.disabled(
          child: SizedBox(
            width: tokens.listIndent,
            child: Text(
              marker,
              style: tokens.listBullet,
              strutStyle: _forcedStrut(tokens.listBullet),
            ),
          ),
        ),
        Expanded(child: content),
      ],
    );

    if (item.children.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(left: depth * tokens.listIndent),
        child: row,
      );
    }

    return Padding(
      padding: EdgeInsets.only(left: depth * tokens.listIndent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row,
          if (tokens.listItemGap > 0) SizedBox(height: tokens.listItemGap),
          for (final child in item.children)
            switch (child) {
              ListBlock(:final ordered, :final items) => _CompiledList(
                  ordered: ordered,
                  items: items,
                  tokens: tokens,
                  depth: depth + 1,
                  onTapLink: onTapLink,
                ),
              _ => Padding(
                  padding: EdgeInsets.only(left: tokens.listIndent),
                  child: CompiledTextPartView(
                    document: MarkdownDocument(blocks: [child]),
                    onTapLink: onTapLink,
                    style: tokens,
                  ),
                ),
            },
        ],
      ),
    );
  }

  String _marker(ContentListItem item, int index) {
    if (item.isTaskChecked != null) {
      return item.isTaskChecked! ? '☑' : '☐';
    }
    if (ordered) return '${index + 1}.';
    return '•';
  }
}

class _CompiledTable extends StatelessWidget {
  const _CompiledTable({
    required this.headers,
    required this.rows,
    required this.tokens,
    required this.onTapLink,
  });

  final List<InlineDocument> headers;
  final List<List<InlineDocument>> rows;
  final MarkdownTokens tokens;
  final MarkdownTapLinkCallback? onTapLink;

  @override
  Widget build(BuildContext context) {
    final colCount = headers.isNotEmpty
        ? headers.length
        : (rows.isNotEmpty ? rows.first.length : 0);
    if (colCount == 0) return const SizedBox.shrink();

    // Column+Row with Expanded beats Flutter Table/RenderTable layout cost
    // on history fling (see post-compile DevTools: _CompiledTable / RenderTable).
    final border = BorderSide(color: tokens.borderColor, width: 1);

    Widget cellRow(List<InlineDocument> cells, {required bool isHeader}) {
      final cellStyle = isHeader ? tokens.tableHead : tokens.tableBody;
      return ColoredBox(
        color: isHeader
            ? (tokens.tableHeadBackground ??
                tokens.mutedSurface.withValues(alpha: 0.85))
            : tokens.tableBodyBackground,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < colCount; c++)
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(
                      right: c < colCount - 1 ? border : BorderSide.none,
                    ),
                  ),
                  child: Padding(
                    padding: tokens.tableCellsPadding,
                    child: Text.rich(
                      TextSpan(
                        style: cellStyle,
                        children: _cellSpans(
                          c < cells.length ? cells[c].runs : const [],
                          cellStyle,
                        ),
                      ),
                      strutStyle: _forcedStrut(cellStyle),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final rowWidgets = <Widget>[
      if (headers.isNotEmpty) cellRow(headers, isHeader: true),
      for (final row in rows) cellRow(row, isHeader: false),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border.fromBorderSide(border)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < rowWidgets.length; i++)
              DecoratedBox(
                decoration: BoxDecoration(
                  border: i < rowWidgets.length - 1
                      ? Border(bottom: border)
                      : null,
                ),
                child: rowWidgets[i],
              ),
          ],
        ),
      ),
    );
  }

  List<InlineSpan> _cellSpans(List<InlineRun> runs, TextStyle base) {
    // Inline-only cell rendering (no nested CompiledTextPartView) so bold
    // weight lands on leaf TextSpans the widget tests assert against.
    return [
      for (final run in runs) _cellSpan(run, base),
    ];
  }

  InlineSpan _cellSpan(InlineRun run, TextStyle base) {
    return switch (run) {
      TextRun(:final text) => TextSpan(text: text, style: base),
      StrongRun(:final children) => TextSpan(
          style: base.copyWith(fontWeight: FontWeight.w700),
          children: _cellSpans(
            children,
            base.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      EmphasisRun(:final children) => TextSpan(
          style: base.copyWith(fontStyle: FontStyle.italic),
          children: _cellSpans(
            children,
            base.copyWith(fontStyle: FontStyle.italic),
          ),
        ),
      StrikeRun(:final children) => TextSpan(
          style: base.copyWith(decoration: TextDecoration.lineThrough),
          children: _cellSpans(
            children,
            base.copyWith(decoration: TextDecoration.lineThrough),
          ),
        ),
      CodeRun(:final text) => TextSpan(text: text, style: tokens.inlineCode),
      LinkRun(:final url, :final title, :final children) => WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: onTapLink == null
                ? null
                : () => onTapLink!(
                      _plainText(children),
                      url,
                      title ?? '',
                    ),
            child: Text.rich(
              TextSpan(
                style: tokens.link,
                children: _cellSpans(children, tokens.link),
              ),
              strutStyle: _forcedStrut(tokens.link),
            ),
          ),
        ),
      ImageRun(:final src, :final alt) => TextSpan(text: alt ?? src, style: base),
    };
  }
}

class _CompiledCodeBlock extends StatefulWidget {
  const _CompiledCodeBlock({
    required this.language,
    required this.code,
    required this.tokens,
  });

  final String language;
  final String code;
  final MarkdownTokens tokens;

  @override
  State<_CompiledCodeBlock> createState() => _CompiledCodeBlockState();
}

class _CompiledCodeBlockState extends State<_CompiledCodeBlock> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final strings = AiMessageStrings.of(context);
    final muted = widget.tokens.mutedSurface;
    final radius = widget.tokens.codeBlockRadius;
    final lang = widget.language.isEmpty
        ? strings.code
        : widget.language.toLowerCase();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: muted,
              borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
              border: Border(
                top: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
                left: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
                right: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            child: SelectionContainer.disabled(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(lang, style: widget.tokens.codeLanguage),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: _copied ? strings.copied : strings.copy,
                      iconSize: 16,
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: widget.code),
                        );
                        if (!mounted) return;
                        setState(() => _copied = true);
                        await Future<void>.delayed(
                          const Duration(milliseconds: 1600),
                        );
                        if (!mounted) return;
                        setState(() => _copied = false);
                      },
                      icon: Icon(
                        _copied ? Icons.check_rounded : Icons.copy_rounded,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: muted,
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(radius)),
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Text(
                widget.code,
                style: widget.tokens.codeBlock,
                strutStyle: _forcedStrut(widget.tokens.codeBlock),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
