import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../parts/text_part_view.dart';
import '../strings.dart';
import '../theme.dart';
import 'compiled_markdown_style.dart';
import 'content_ir.dart';

/// Renders a style-free [MessageContentDocument] with cheap [Text.rich] /
/// lite table / code chrome. Parent should wrap with [SelectionArea]; leaves
/// are non-selectable [Text] / [Text.rich].
class CompiledTextPartView extends StatelessWidget {
  const CompiledTextPartView({
    required this.document,
    this.onTapLink,
    this.style,
    super.key,
  });

  final MessageContentDocument document;
  final MarkdownTapLinkCallback? onTapLink;
  final CompiledMarkdownStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiTheme = AiMessageTheme.of(context);
    final resolved = style ?? CompiledMarkdownStyle.from(theme, aiTheme);

    final children = <Widget>[];
    final blocks = document.blocks;
    var i = 0;
    while (i < blocks.length) {
      final block = blocks[i];
      if (_isMergeableTextual(block)) {
        final mergeEnd = _mergeableRunEnd(blocks, i);
        children.add(
          _buildMergedTextual(blocks.sublist(i, mergeEnd), resolved),
        );
        i = mergeEnd;
        continue;
      }
      children.add(_buildBlock(context, block, resolved, theme, aiTheme));
      i++;
    }

    if (children.isEmpty) return const SizedBox.shrink();
    if (children.length == 1) return children.single;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var c = 0; c < children.length; c++) ...[
          if (c > 0) SizedBox(height: resolved.blockSpacing),
          children[c],
        ],
      ],
    );
  }

  bool _isMergeableTextual(ContentBlock block) =>
      block is ParagraphBlock || block is HeadingBlock;

  int _mergeableRunEnd(List<ContentBlock> blocks, int start) {
    var end = start + 1;
    while (end < blocks.length && _isMergeableTextual(blocks[end])) {
      end++;
    }
    return end;
  }

  Widget _buildMergedTextual(
    List<ContentBlock> blocks,
    CompiledMarkdownStyle style,
  ) {
    final spans = <InlineSpan>[];
    for (var i = 0; i < blocks.length; i++) {
      if (i > 0) {
        spans.add(TextSpan(text: '\n\n', style: style.body));
      }
      final block = blocks[i];
      if (block is HeadingBlock) {
        spans.add(
          TextSpan(
            style: style.headingStyle(block.level),
            children: _inlineSpans(
              block.runs,
              style,
              style.headingStyle(block.level),
            ),
          ),
        );
      } else if (block is ParagraphBlock) {
        spans.add(
          TextSpan(
            style: style.body,
            children: _inlineSpans(block.runs, style, style.body),
          ),
        );
      }
    }
    return Text.rich(TextSpan(children: spans));
  }

  Widget _buildBlock(
    BuildContext context,
    ContentBlock block,
    CompiledMarkdownStyle style,
    ThemeData theme,
    AiMessageTheme aiTheme,
  ) {
    return switch (block) {
      ParagraphBlock(:final runs) => Text.rich(
          TextSpan(
            style: style.body,
            children: _inlineSpans(runs, style, style.body),
          ),
        ),
      HeadingBlock(:final level, :final runs) => Text.rich(
          TextSpan(
            style: style.headingStyle(level),
            children: _inlineSpans(runs, style, style.headingStyle(level)),
          ),
        ),
      ListBlock(:final ordered, :final items) => _CompiledList(
          ordered: ordered,
          items: items,
          style: style,
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
              document: MessageContentDocument(blocks: blocks),
              onTapLink: onTapLink,
              style: style,
            ),
          ),
        ),
      HorizontalRuleBlock() => Divider(color: style.borderColor),
      CodeBlock(:final language, :final text) => _CompiledCodeBlock(
          language: language ?? '',
          code: text,
          style: style,
        ),
      TableBlock(:final headers, :final rows) => _CompiledTable(
          headers: headers,
          rows: rows,
          style: style,
          onTapLink: onTapLink,
        ),
      UnsupportedBlock(:final rawMarkdown) => MarkdownBody(
          data: rawMarkdown,
          styleSheet: aiTheme.markdownStyleSheet ??
              defaultAiMarkdownSheet(theme, aiTheme),
          onTapLink: onTapLink,
          selectable: false,
        ),
    };
  }

  List<InlineSpan> _inlineSpans(
    List<InlineRun> runs,
    CompiledMarkdownStyle style,
    TextStyle base,
  ) {
    return [
      for (final run in runs) _inlineSpan(run, style, base),
    ];
  }

  InlineSpan _inlineSpan(
    InlineRun run,
    CompiledMarkdownStyle style,
    TextStyle base,
  ) {
    return switch (run) {
      TextRun(:final text) => TextSpan(text: text, style: base),
      StrongRun(:final children) => TextSpan(
          style: base.copyWith(fontWeight: FontWeight.w700),
          children: _inlineSpans(
            children,
            style,
            base.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      EmphasisRun(:final children) => TextSpan(
          style: base.copyWith(fontStyle: FontStyle.italic),
          children: _inlineSpans(
            children,
            style,
            base.copyWith(fontStyle: FontStyle.italic),
          ),
        ),
      StrikeRun(:final children) => TextSpan(
          style: base.copyWith(decoration: TextDecoration.lineThrough),
          children: _inlineSpans(
            children,
            style,
            base.copyWith(decoration: TextDecoration.lineThrough),
          ),
        ),
      CodeRun(:final text) => TextSpan(text: text, style: style.inlineCode),
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
                style: style.link,
                children: _inlineSpans(children, style, style.link),
              ),
            ),
          ),
        ),
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
    required this.style,
    required this.depth,
    required this.onTapLink,
  });

  final bool ordered;
  final List<ContentListItem> items;
  final CompiledMarkdownStyle style;
  final int depth;
  final MarkdownTapLinkCallback? onTapLink;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) SizedBox(height: style.blockSpacing * 0.35),
          _buildItem(items[i], i),
        ],
      ],
    );
  }

  Widget _buildItem(ContentListItem item, int index) {
    final marker = _marker(item, index);
    final content = CompiledTextPartView(
      document: MessageContentDocument(
        blocks: [ParagraphBlock(runs: item.runs)],
      ),
      onTapLink: onTapLink,
      style: style,
    );

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: style.listIndent,
          child: Text(marker, style: style.listBullet),
        ),
        Expanded(child: content),
      ],
    );

    if (item.children.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(left: depth * style.listIndent),
        child: row,
      );
    }

    return Padding(
      padding: EdgeInsets.only(left: depth * style.listIndent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row,
          SizedBox(height: style.blockSpacing * 0.35),
          for (final child in item.children)
            switch (child) {
              ListBlock(:final ordered, :final items) => _CompiledList(
                  ordered: ordered,
                  items: items,
                  style: style,
                  depth: depth + 1,
                  onTapLink: onTapLink,
                ),
              _ => Padding(
                  padding: EdgeInsets.only(left: style.listIndent),
                  child: CompiledTextPartView(
                    document: MessageContentDocument(blocks: [child]),
                    onTapLink: onTapLink,
                    style: style,
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
    required this.style,
    required this.onTapLink,
  });

  final List<InlineDocument> headers;
  final List<List<InlineDocument>> rows;
  final CompiledMarkdownStyle style;
  final MarkdownTapLinkCallback? onTapLink;

  @override
  Widget build(BuildContext context) {
    final colCount = headers.isNotEmpty
        ? headers.length
        : (rows.isNotEmpty ? rows.first.length : 0);
    if (colCount == 0) return const SizedBox.shrink();

    // Column+Row with Expanded beats Flutter Table/RenderTable layout cost
    // on history fling (see post-compile DevTools: _CompiledTable / RenderTable).
    final border = BorderSide(color: style.borderColor, width: 1);

    Widget cellRow(List<InlineDocument> cells, {required bool isHeader}) {
      final cellStyle = isHeader ? style.tableHead : style.tableBody;
      return ColoredBox(
        color: isHeader
            ? style.mutedSurface.withValues(alpha: 0.85)
            : Colors.transparent,
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Text.rich(
                      TextSpan(
                        style: cellStyle,
                        children: _cellSpans(
                          c < cells.length ? cells[c].runs : const [],
                          cellStyle,
                        ),
                      ),
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
      CodeRun(:final text) => TextSpan(text: text, style: style.inlineCode),
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
                style: style.link,
                children: _cellSpans(children, style.link),
              ),
            ),
          ),
        ),
    };
  }
}

class _CompiledCodeBlock extends StatefulWidget {
  const _CompiledCodeBlock({
    required this.language,
    required this.code,
    required this.style,
  });

  final String language;
  final String code;
  final CompiledMarkdownStyle style;

  @override
  State<_CompiledCodeBlock> createState() => _CompiledCodeBlockState();
}

class _CompiledCodeBlockState extends State<_CompiledCodeBlock> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final strings = AiMessageStrings.of(context);
    final muted = widget.style.mutedSurface;
    final radius = widget.style.codeBlockRadius;
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
                      child: Text(lang, style: widget.style.codeLanguage),
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
              child: Text(widget.code, style: widget.style.codeBlock),
            ),
          ),
        ],
      ),
    );
  }
}
