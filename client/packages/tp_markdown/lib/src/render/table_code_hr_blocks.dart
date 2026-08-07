import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ir/markdown_document.dart';
import '../markdown_display_mode_scope.dart';
import '../registry/markdown_resolvers.dart';
import '../strings.dart';
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
  /// Code blocks longer than this collapse behind a "first N lines + chevron"
  /// mask (Claude Code-style per-block "show more").
  static const int _kCollapseChars = 6000;
  /// Collapsed preview shows only this many lines; the rest is hidden entirely
  /// (no clipped overflow text in the tree — this is what caused the vertical
  /// "text spills off screen" in the file preview's flatten view).
  static const int _kCollapsedLines = 6;
  static const double _kExpandedMaxHeight = 420;

  bool _copied = false;
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final strings = MarkdownStrings.of(context);
    final muted = widget.tokens.mutedSurface;
    final radius = widget.tokens.codeBlockRadius;
    final borderColor = widget.tokens.borderColor;
    final lang = widget.language.isEmpty
        ? strings.code
        : widget.language.toLowerCase();
    final mode = MarkdownDisplayModeScope.codeBlockOf(context);
    final huge = widget.code.length > _kCollapseChars;

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
        if (!huge || mode == ContentDisplayMode.flatten)
          // Short code, or flatten mode: always full natural height, no mask.
          DecoratedBox(
            decoration: BoxDecoration(
              color: muted,
              borderRadius:
                  BorderRadius.vertical(bottom: Radius.circular(radius)),
              border: Border.all(color: borderColor),
            ),
            child: _codeBody(widget.code),
          )
        else
          _buildMaskedBody(
            context,
            strings,
            muted,
            radius,
            borderColor,
            expandFull: mode == ContentDisplayMode.foldExpandFull,
          ),
      ],
    );
  }

  /// Oversized code: collapsed shows the first [_kCollapsedLines] lines (the
  /// rest is hidden entirely, no clipped overflow text), with a centered
  /// chevron below. Expanded renders in a fixed-height scroll shell
  /// ([expandFull] false) or at full natural height ([expandFull] true).
  Widget _buildMaskedBody(
    BuildContext context,
    MarkdownStrings strings,
    Color muted,
    double radius,
    Color borderColor, {
    required bool expandFull,
  }) {
    final code = _expanded ? widget.code : _firstCodeLines(widget.code);
    final iconColor =
        (widget.tokens.codeBlock.color ?? Colors.black54).withValues(
          alpha: 0.6,
        );

    // Collapsed: naturally short preview (first N lines). foldFixedHeight
    // expanded: fixed scroll shell. foldExpandFull expanded: full height.
    final Widget body;
    if (!_expanded) {
      body = _codeBody(code);
    } else if (expandFull) {
      body = _codeBody(code);
    } else {
      body = ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: _kExpandedMaxHeight),
        child: SingleChildScrollView(child: _codeBody(code)),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: muted,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
        border: Border.all(color: borderColor),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          body,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _FadeChevronOverlay(
              icon: _expanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              tooltip: _expanded ? strings.showLess : strings.showMore,
              fadeColor: muted,
              color: iconColor,
              onTap: () => setState(() => _expanded = !_expanded),
            ),
          ),
        ],
      ),
    );
  }

  /// First [_kCollapsedLines] lines of [code]; the rest is hidden entirely.
  String _firstCodeLines(String code) {
    final lines = code.split('\n');
    if (lines.length <= _kCollapsedLines) return code;
    return lines.take(_kCollapsedLines).join('\n');
  }

  /// Code body: `white-space: pre` (no wrapping) with horizontal scrolling for
  /// long lines — long lines never wrap into a tall blob (the vertical-overflow
  /// cause).
  Widget _codeBody(String code) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Text(
          code,
          style: widget.tokens.codeBlock,
          softWrap: false,
          strutStyle: forcedStrut(widget.tokens.codeBlock),
        ),
      ),
    );
  }
}

/// Bottom fade strip + centered chevron overlay for a collapsed/expanded code
/// block mask — matches Write/Edit's `AiFadeExpandBody` visual, including the
/// hover affordance: the whole strip shows a click cursor and brightens on
/// hover (fade + icon), and is the tap target for expand/collapse.
class _FadeChevronOverlay extends StatefulWidget {
  const _FadeChevronOverlay({
    required this.icon,
    required this.tooltip,
    required this.fadeColor,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color fadeColor;
  final Color color;
  final VoidCallback onTap;

  @override
  State<_FadeChevronOverlay> createState() => _FadeChevronOverlayState();
}

class _FadeChevronOverlayState extends State<_FadeChevronOverlay> {
  var _hovering = false;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final fadeEnd = _hovering
        ? Color.alphaBlend(onSurface.withValues(alpha: 0.14), widget.fadeColor)
        : widget.fadeColor;
    final iconColor = _hovering
        ? Color.alphaBlend(onSurface.withValues(alpha: 0.30), widget.color)
        : widget.color;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Tooltip(
        message: widget.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: SizedBox(
            height: 36,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [fadeEnd.withValues(alpha: 0), fadeEnd],
                        ),
                      ),
                    ),
                  ),
                ),
                Icon(widget.icon, size: 20, color: iconColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
