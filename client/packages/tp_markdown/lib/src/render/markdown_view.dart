import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../ir/markdown_block_kind.dart';
import '../ir/markdown_document.dart';
import '../registry/block_widget_registry.dart';
import '../registry/markdown_resolvers.dart';
import '../strings.dart';
import '../tokens/markdown_tokens.dart';
import 'highlight_context.dart';
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
    this.highlights,
    this.blockIndex = 0,
    this.basePath = const [],
  });

  final MarkdownDocument document;
  final MarkdownTokens tokens;
  final MarkdownResolvers resolvers;
  final MarkdownStrings strings;
  final BlockWidgetRegistry? registry;

  /// Resolves per-container highlight ranges for this document's blocks.
  final MarkdownHighlightContext? highlights;

  /// Top-level index reported by blocks of this view when it renders nested
  /// content ([basePath] non-empty); nested views reuse the parent's index
  /// while nesting extends [basePath]. Root views (empty [basePath]) address
  /// each block by its own top-level slot instead.
  final int blockIndex;
  final List<MarkdownPathStep> basePath;

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

    Widget wrapHorizontal(MarkdownBlockKind kind, Widget child) {
      final m = tokens.marginOf(kind);
      if (m.left == 0 && m.right == 0) return child;
      return Padding(
        padding: EdgeInsets.only(left: m.left, right: m.right),
        child: child,
      );
    }

    while (i < blocks.length) {
      final block = blocks[i];
      // Container address of the block rendered at loop slot i. Root views
      // (empty basePath) address each block by its own top-level slot, matching
      // MarkdownSearchIndex's projection; nested views report the inherited
      // (blockIndex, basePath) pair — their callers hand over exactly one
      // fully-extended base per container.
      final isNested = widget.basePath.isNotEmpty;
      final containerIndex = isNested ? widget.blockIndex : i;
      final containerPath =
          isNested ? widget.basePath : const <MarkdownPathStep>[];

      if (block is ParagraphBlock) {
        var end = i + 1;
        while (end < blocks.length && blocks[end] is ParagraphBlock) {
          end++;
        }
        final run = blocks.sublist(i, end).cast<ParagraphBlock>();

        _addGapIfNeeded(children, previous, block, tokens);
        final perParagraph = [
          for (var k = 0; k < run.length; k++)
            widget.highlights?.forContainer(containerIndex + k, containerPath),
        ];
        children.add(
          wrapHorizontal(
            MarkdownBlockKind.paragraph,
            run.length == 1
                ? buildParagraph(run.first, tokens, resolvers,
                    highlights: perParagraph[0])
                : buildMergedParagraphs(run, tokens, resolvers,
                    highlights: perParagraph),
          ),
        );
        previous = run.last;
        i = end;
        continue;
      }

      _addGapIfNeeded(children, previous, block, tokens);
      children.add(
        wrapHorizontal(
          block.kind,
          reg.build(
            block,
            tokens,
            resolvers,
            strings,
            highlights: widget.highlights,
            blockIndex: containerIndex,
            basePath: containerPath,
          ),
        ),
      );
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
