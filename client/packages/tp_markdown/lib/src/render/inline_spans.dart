import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../ir/markdown_block_kind.dart';
import '../ir/markdown_document.dart';
import '../registry/markdown_resolvers.dart';
import '../tokens/markdown_tokens.dart';
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
  MarkdownResolvers resolvers,
) {
  return [
    for (final run in runs) inlineSpan(run, tokens, base, resolvers),
  ];
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
  MarkdownResolvers resolvers,
) {
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
        children: inlineSpans(
          paragraphs[i].runs,
          tokens,
          tokens.body,
          resolvers,
        ),
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
  MarkdownResolvers resolvers,
) {
  return Text.rich(
    TextSpan(
      style: tokens.body,
      children: inlineSpans(block.runs, tokens, tokens.body, resolvers),
    ),
    strutStyle: forcedStrut(tokens.body),
  );
}

Widget buildHeading(
  HeadingBlock block,
  MarkdownTokens tokens,
  MarkdownResolvers resolvers,
) {
  final style = headingStyleForLevel(tokens, block.level);
  return Text.rich(
    TextSpan(
      style: style,
      children: inlineSpans(block.runs, tokens, style, resolvers),
    ),
    strutStyle: forcedStrut(style),
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
