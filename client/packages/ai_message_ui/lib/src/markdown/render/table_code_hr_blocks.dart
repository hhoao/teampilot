import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../strings.dart';
import '../ir/markdown_document.dart';
import '../registry/markdown_resolvers.dart';
import '../tokens/markdown_tokens.dart';
import 'inline_spans.dart';

Widget buildHorizontalRule(MarkdownTokens tokens) {
  return Divider(color: tokens.borderColor);
}

Widget buildTable(
  TableBlock block,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers,
) {
  return _MarkdownTable(
    headers: block.headers,
    rows: block.rows,
    tokens: tokens,
    resolvers: resolvers,
  );
}

Widget buildCodeBlock(CodeBlock block, MarkdownTokens tokens) {
  return _MarkdownCodeBlock(
    language: block.language ?? '',
    code: block.text,
    tokens: tokens,
  );
}

class _MarkdownTable extends StatelessWidget {
  const _MarkdownTable({
    required this.headers,
    required this.rows,
    required this.tokens,
    required this.resolvers,
  });

  final List<InlineDocument> headers;
  final List<List<InlineDocument>> rows;
  final MarkdownTokens tokens;
  final MarkdownResolvers resolvers;

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
                        children: inlineSpans(
                          c < cells.length ? cells[c].runs : const [],
                          tokens,
                          cellStyle,
                          resolvers,
                        ),
                      ),
                      strutStyle: forcedStrut(cellStyle),
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

    return DecoratedBox(
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
    );
  }
}

class _MarkdownCodeBlock extends StatefulWidget {
  const _MarkdownCodeBlock({
    required this.language,
    required this.code,
    required this.tokens,
  });

  final String language;
  final String code;
  final MarkdownTokens tokens;

  @override
  State<_MarkdownCodeBlock> createState() => _MarkdownCodeBlockState();
}

class _MarkdownCodeBlockState extends State<_MarkdownCodeBlock> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final strings = AiMessageStrings.of(context);
    final muted = widget.tokens.mutedSurface;
    final radius = widget.tokens.codeBlockRadius;
    final borderColor = widget.tokens.borderColor;
    final lang = widget.language.isEmpty
        ? strings.code
        : widget.language.toLowerCase();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: muted,
            borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
            border: Border(
              top: BorderSide(color: borderColor),
              left: BorderSide(color: borderColor),
              right: BorderSide(color: borderColor),
            ),
          ),
          child: SelectionContainer.disabled(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
                      color: widget.tokens.codeLanguage.color,
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
            border: Border.all(color: borderColor),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Text(
              widget.code,
              style: widget.tokens.codeBlock,
              strutStyle: forcedStrut(widget.tokens.codeBlock),
            ),
          ),
        ),
      ],
    );
  }
}
