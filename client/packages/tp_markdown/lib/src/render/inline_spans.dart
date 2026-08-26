import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../ir/markdown_block_kind.dart';
import '../ir/markdown_document.dart';
import '../registry/markdown_resolvers.dart';
import '../tokens/markdown_tokens.dart';
import 'highlight_context.dart';
import 'image_raw_blocks.dart';

/// Optional strut for markdown [Text.rich].
///
/// Disabled: A/B showed no reading difference and forced strut amplified
/// first-open cost for mixed UI/mono spans. Line height still comes from
/// [TextStyle.height]. Re-enable only if SelectionArea wrap seams return
/// and are worth the layout cost.
StrutStyle? forcedStrut(TextStyle style) => null;

TextStyle headingStyleForLevel(MarkdownTokens tokens, int level) {
  return tokens.headingStyle(level);
}

List<InlineSpan> inlineSpans(
  List<InlineRun> runs,
  MarkdownTokens tokens,
  TextStyle base,
  MarkdownResolvers resolvers, {
  MarkdownContainerHighlights? highlights,
}) {
  if (highlights == null || highlights.ranges.isEmpty) {
    return [for (final run in runs) inlineSpan(run, tokens, base, resolvers)];
  }
  final cursor = _HighlightCursor(highlights);
  final out = <InlineSpan>[];
  _emitHighlightedRuns(runs, tokens, base, resolvers, cursor, out);
  return out;
}

InlineSpan inlineSpan(
  InlineRun run,
  MarkdownTokens tokens,
  TextStyle base,
  MarkdownResolvers resolvers,
) {
  return switch (run) {
    TextRun(:final text) => TextSpan(text: text, style: base),
    StrongRun(:final children) => TextSpan(
        style: tokens.strongStyle(base),
        children: inlineSpans(
          children,
          tokens,
          tokens.strongStyle(base),
          resolvers,
        ),
      ),
    EmphasisRun(:final children) => TextSpan(
        style: tokens.emphasisStyle(base),
        children: inlineSpans(
          children,
          tokens,
          tokens.emphasisStyle(base),
          resolvers,
        ),
      ),
    StrikeRun(:final children) => TextSpan(
        style: tokens.strikeStyle(base),
        children: inlineSpans(
          children,
          tokens,
          tokens.strikeStyle(base),
          resolvers,
        ),
      ),
    CodeRun(:final text) => TextSpan(
        text: text,
        style: tokens.inlineCodeAt(base),
      ),
    // TextSpan (not WidgetSpan) so SelectionArea keeps a continuous highlight.
    // mouseCursor + TapGestureRecognizer provide click affordance. Recognizer
    // must sit on spans that own text ranges — a children-only parent is not
    // hit-tested for gestures under RenderParagraph.
    LinkRun(:final url, :final title, :final children) => TextSpan(
        style: tokens.link,
        mouseCursor: resolvers.onLinkTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        children: _linkChildren(
          children,
          tokens,
          resolvers,
          resolvers.createLinkRecognizer?.call(url),
        ),
      ),
    ImageRun(:final src, :final alt) => WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: buildMarkdownImage(
          src: src,
          alt: alt,
          tokens: tokens,
          resolvers: resolvers,
          inline: true,
        ),
      ),
  };
}

/// Mutable plain-text offset shared across one container's span build.
class _HighlightCursor {
  _HighlightCursor(this.highlights);

  final MarkdownContainerHighlights highlights;
  int offset = 0;

  TextStyle styleFor(int start, int end, TextStyle base, MarkdownTokens t) {
    final covered =
        highlights.ranges.any((r) => r.start <= start && end <= r.end);
    if (!covered) return base;
    final active = highlights.active;
    final isActive = active != null && active.start <= start && end <= active.end;
    return t.matchHighlight(base, active: isActive);
  }
}

void _emitHighlightedRuns(
  List<InlineRun> runs,
  MarkdownTokens tokens,
  TextStyle base,
  MarkdownResolvers resolvers,
  _HighlightCursor cursor,
  List<InlineSpan> out,
) {
  for (final run in runs) {
    switch (run) {
      case TextRun(:final text):
        _emitSplitLeaf(text, base, tokens, cursor, out);
      case CodeRun(:final text):
        _emitSplitLeaf(text, tokens.inlineCodeAt(base), tokens, cursor, out);
      case StrongRun(:final children):
        _emitMarked(children, tokens.strongStyle(base), tokens, resolvers,
            cursor, out);
      case EmphasisRun(:final children):
        _emitMarked(children, tokens.emphasisStyle(base), tokens, resolvers,
            cursor, out);
      case StrikeRun(:final children):
        _emitMarked(children, tokens.strikeStyle(base), tokens, resolvers,
            cursor, out);
      case LinkRun(:final url, :final children):
        final start = out.length;
        _emitHighlightedRuns(
            children, tokens, tokens.link, resolvers, cursor, out);
        final recognizer = resolvers.createLinkRecognizer?.call(url);
        final cursorIcon = resolvers.onLinkTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.click;
        for (var i = start; i < out.length; i++) {
          out[i] = _withLinkGesture(out[i], recognizer, cursorIcon);
        }
      case ImageRun():
        // WidgetSpan — outside the text flow, unhighlightable. Images
        // contribute zero plain-text offsets in the shared traversal, so
        // emitting them unchanged keeps cursor alignment intact.
        out.add(inlineSpan(run, tokens, base, resolvers));
    }
  }
}

void _emitMarked(
  List<InlineRun> children,
  TextStyle style,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers,
  _HighlightCursor cursor,
  List<InlineSpan> out,
) {
  final inner = <InlineSpan>[];
  _emitHighlightedRuns(children, tokens, style, resolvers, cursor, inner);
  out.add(TextSpan(style: style, children: inner));
}

void _emitSplitLeaf(
  String text,
  TextStyle style,
  MarkdownTokens tokens,
  _HighlightCursor cursor,
  List<InlineSpan> out,
) {
  final start = cursor.offset;
  final end = start + text.length;
  final cuts = <int>{start, end};
  for (final r in cursor.highlights.ranges) {
    if (r.start < end && r.end > start) {
      cuts.add(r.start.clamp(start, end));
      cuts.add(r.end.clamp(start, end));
    }
  }
  final points = cuts.toList()..sort();
  for (var i = 0; i < points.length - 1; i++) {
    final s = points[i];
    final e = points[i + 1];
    if (e <= s) continue;
    out.add(TextSpan(
      text: text.substring(s - start, e - start),
      style: cursor.styleFor(s, e, style, tokens),
    ));
  }
  cursor.offset = end;
}

List<InlineSpan> _linkChildren(
  List<InlineRun> children,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers,
  GestureRecognizer? recognizer,
) {
  final cursor = resolvers.onLinkTap == null
      ? MouseCursor.defer
      : SystemMouseCursors.click;
  return [
    for (final span in inlineSpans(children, tokens, tokens.link, resolvers))
      _withLinkGesture(span, recognizer, cursor),
  ];
}

InlineSpan _withLinkGesture(
  InlineSpan span,
  GestureRecognizer? recognizer,
  MouseCursor cursor,
) {
  if (span is! TextSpan) return span;
  return TextSpan(
    text: span.text,
    style: span.style,
    mouseCursor: cursor,
    recognizer: recognizer ?? span.recognizer,
    children: [
      for (final child in span.children ?? const <InlineSpan>[])
        _withLinkGesture(child, recognizer, cursor),
    ],
  );
}

/// One [Text.rich] for a run of adjacent [ParagraphBlock]s; internal gaps use
/// `\n\n` with height = [gapBetween] paragraph↔paragraph / body fontSize.
Widget buildMergedParagraphs(
  List<ParagraphBlock> paragraphs,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers, {
  List<MarkdownContainerHighlights?> highlights = const [],
}) {
  MarkdownContainerHighlights? at(int i) =>
      i < highlights.length ? highlights[i] : null;
  final spans = <InlineSpan>[];
  for (var i = 0; i < paragraphs.length; i++) {
    if (i > 0) {
      final fontSize = tokens.body.fontSize ?? 14.0;
      final gap = gapBetween(
        MarkdownBlockKind.paragraph,
        MarkdownBlockKind.paragraph,
        tokens,
      );
      spans.add(
        TextSpan(
          text: '\n\n',
          style: tokens.body.copyWith(height: gap / fontSize),
        ),
      );
    }
    spans.add(
      TextSpan(
        style: tokens.body,
        children: inlineSpans(paragraphs[i].runs, tokens, tokens.body,
            resolvers, highlights: at(i)),
      ),
    );
  }
  return Text.rich(
    TextSpan(style: tokens.body, children: spans),
    strutStyle: forcedStrut(tokens.body),
  );
}

Widget buildParagraph(
  ParagraphBlock block,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers, {
  MarkdownContainerHighlights? highlights,
}) {
  return Text.rich(
    TextSpan(
      style: tokens.body,
      children: inlineSpans(block.runs, tokens, tokens.body, resolvers,
          highlights: highlights),
    ),
    strutStyle: forcedStrut(tokens.body),
  );
}

Widget buildHeading(
  HeadingBlock block,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers, {
  MarkdownContainerHighlights? highlights,
}) {
  final style = headingStyleForLevel(tokens, block.level);
  return Text.rich(
    TextSpan(
      style: style,
      children: inlineSpans(block.runs, tokens, style, resolvers,
          highlights: highlights),
    ),
    strutStyle: forcedStrut(style),
  );
}

/// Code-block body text with optional match highlighting (single leaf split).
Text buildHighlightedCode(
  String code,
  TextStyle base,
  MarkdownTokens tokens,
  MarkdownContainerHighlights? highlights,
) {
  if (highlights == null || highlights.ranges.isEmpty) {
    return Text(code, style: base, softWrap: false, strutStyle: forcedStrut(base));
  }
  final cursor = _HighlightCursor(highlights);
  final out = <InlineSpan>[];
  _emitSplitLeaf(code, base, tokens, cursor, out);
  return Text.rich(
    TextSpan(style: base, children: out),
    softWrap: false,
    strutStyle: forcedStrut(base),
  );
}

/// One leaf text piece in document order ([TextRun]/[CodeRun] glyphs).
/// Images render as unsplittable [WidgetSpan]s and are excluded.
class InlineTextPiece {
  const InlineTextPiece(this.text);

  final String text;
}

/// Ordered leaf text pieces of [runs]; the canonical traversal shared by the
/// search-index projection and highlight-aware span splitting.
List<InlineTextPiece> inlineTextPieces(List<InlineRun> runs) {
  final pieces = <InlineTextPiece>[];
  void walk(List<InlineRun> list) {
    for (final run in list) {
      switch (run) {
        case TextRun(:final text):
          pieces.add(InlineTextPiece(text));
        case CodeRun(:final text):
          pieces.add(InlineTextPiece(text));
        case StrongRun(:final children) ||
              EmphasisRun(:final children) ||
              StrikeRun(:final children) ||
              LinkRun(:final children):
          walk(children);
        case ImageRun():
          break;
      }
    }
  }

  walk(runs);
  return pieces;
}

String plainTextFromRuns(List<InlineRun> runs) =>
    inlineTextPieces(runs).map((p) => p.text).join();
