import 'package:flutter/material.dart';

import '../ir/markdown_block_kind.dart';
import '../ir/markdown_document.dart';
import '../registry/markdown_resolvers.dart';
import '../tokens/markdown_tokens.dart';

/// Match [flutter_markdown_plus] `_buildRichText`: force a uniform line box so
/// mixed CJK / Latin / mono weights cannot open selection seams between wraps.
StrutStyle forcedStrut(TextStyle style) {
  return StrutStyle(
    fontFamily: style.fontFamily,
    fontFamilyFallback: style.fontFamilyFallback,
    fontSize: style.fontSize,
    height: style.height,
    leading: 0,
    forceStrutHeight: true,
  );
}

TextStyle headingStyleForLevel(MarkdownTokens tokens, int level) {
  return switch (level) {
    1 => tokens.h1,
    2 => tokens.h2,
    3 => tokens.h3,
    4 => tokens.h4,
    5 => tokens.h5,
    _ => tokens.h6,
  };
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
        style: base.copyWith(fontWeight: FontWeight.w700),
        children: inlineSpans(
          children,
          tokens,
          base.copyWith(fontWeight: FontWeight.w700),
          resolvers,
        ),
      ),
    EmphasisRun(:final children) => TextSpan(
        style: base.copyWith(fontStyle: FontStyle.italic),
        children: inlineSpans(
          children,
          tokens,
          base.copyWith(fontStyle: FontStyle.italic),
          resolvers,
        ),
      ),
    StrikeRun(:final children) => TextSpan(
        style: base.copyWith(decoration: TextDecoration.lineThrough),
        children: inlineSpans(
          children,
          tokens,
          base.copyWith(decoration: TextDecoration.lineThrough),
          resolvers,
        ),
      ),
    CodeRun(:final text) => TextSpan(text: text, style: tokens.inlineCode),
    // WidgetSpan + GestureDetector so link taps win under parent SelectionArea.
    LinkRun(:final url, :final title, :final children) => WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: resolvers.onLinkTap == null
              ? null
              : () => resolvers.onLinkTap!(url),
          child: Text.rich(
            TextSpan(
              style: tokens.link,
              children: inlineSpans(children, tokens, tokens.link, resolvers),
            ),
            strutStyle: forcedStrut(tokens.link),
          ),
        ),
      ),
    ImageRun(:final alt) => TextSpan(text: alt ?? '', style: base),
  };
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

String plainTextFromRuns(List<InlineRun> runs) {
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
        case ImageRun(:final alt):
          buffer.write(alt ?? '');
      }
    }
  }

  walk(runs);
  return buffer.toString();
}
