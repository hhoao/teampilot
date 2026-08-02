import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../ir/markdown_document.dart';
import '../registry/block_widget_registry.dart';
import '../registry/markdown_resolvers.dart';
import '../strings.dart';
import '../tokens/markdown_tokens.dart';
import 'inline_spans.dart';

/// Semantic markdown renderer: Column layout with kind-based inter-block gaps.
class MarkdownView extends StatefulWidget {
  const MarkdownView({
    super.key,
    required this.document,
    required this.tokens,
    this.resolvers = const MarkdownResolvers(),
    this.strings = MarkdownStrings.english,
    this.registry,
  });

  final MarkdownDocument document;
  final MarkdownTokens tokens;
  final MarkdownResolvers resolvers;
  final MarkdownStrings strings;
  final BlockWidgetRegistry? registry;

  @override
  State<MarkdownView> createState() => _MarkdownViewState();
}

class _MarkdownViewState extends State<MarkdownView> {
  final List<TapGestureRecognizer> _linkRecognizers = [];

  @override
  void dispose() {
    _disposeRecognizers(_linkRecognizers);
    super.dispose();
  }

  void _disposeRecognizers(List<TapGestureRecognizer> recognizers) {
    for (final recognizer in recognizers) {
      recognizer.dispose();
    }
    recognizers.clear();
  }

  MarkdownResolvers _resolversForBuild() {
    // Retire last frame's recognizers after this build commits so in-flight
    // pointer routes are not disposed mid-gesture.
    if (_linkRecognizers.isNotEmpty) {
      final retiring = List<TapGestureRecognizer>.of(_linkRecognizers);
      _linkRecognizers.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _disposeRecognizers(retiring);
      });
    }

    final onLinkTap = widget.resolvers.onLinkTap;
    if (onLinkTap == null) return widget.resolvers;

    return MarkdownResolvers(
      onLinkTap: onLinkTap,
      resolveImage: widget.resolvers.resolveImage,
      createLinkRecognizer: (href) {
        final recognizer = TapGestureRecognizer()..onTap = () => onLinkTap(href);
        _linkRecognizers.add(recognizer);
        return recognizer;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final blocks = widget.document.blocks;
    if (blocks.isEmpty) return const SizedBox.shrink();

    final resolvers = _resolversForBuild();
    final tokens = widget.tokens;
    final strings = widget.strings;
    final reg = widget.registry ?? BlockWidgetRegistry.builtIn();
    final children = <Widget>[];
    MarkdownBlock? previous;
    var i = 0;

    while (i < blocks.length) {
      final block = blocks[i];

      if (block is ParagraphBlock) {
        var end = i + 1;
        while (end < blocks.length && blocks[end] is ParagraphBlock) {
          end++;
        }
        final run = blocks.sublist(i, end).cast<ParagraphBlock>();

        _addGapIfNeeded(children, previous, block, tokens);
        children.add(
          run.length == 1
              ? buildParagraph(run.first, tokens, resolvers)
              : buildMergedParagraphs(run, tokens, resolvers),
        );
        previous = run.last;
        i = end;
        continue;
      }

      _addGapIfNeeded(children, previous, block, tokens);
      children.add(reg.build(block, tokens, resolvers, strings));
      previous = block;
      i++;
    }

    return MarkdownStringsScope(
      strings: strings,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  void _addGapIfNeeded(
    List<Widget> children,
    MarkdownBlock? previous,
    MarkdownBlock next,
    MarkdownTokens tokens,
  ) {
    if (previous == null) return;
    final gap = gapBetween(previous.kind, next.kind, tokens);
    if (gap > 0) {
      children.add(SizedBox(height: gap));
    }
  }
}
