import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tp_markdown/src/render/highlight_context.dart';
import 'package:tp_markdown/src/tokens/markdown_tokens.dart';

void main() {
  group('MarkdownPathStep equality', () {
    test('same fields equal, different not', () {
      expect(const ListItemStep(1), const ListItemStep(1));
      expect(const ListItemStep(1), isNot(const ListItemStep(2)));
      expect(const ChildStep(0), isNot(const ListItemStep(0)));
      expect(
        const TableCellStep(0, 1),
        const TableCellStep(0, 1),
      );
    });
  });

  group('MarkdownTokens.matchHighlight', () {
    final tokens = MarkdownTokens.test();
    test('keeps base glyph metrics, swaps background', () {
      final base = tokens.body;
      final inactive = tokens.matchHighlight(base, active: false);
      final active = tokens.matchHighlight(base, active: true);
      expect(inactive.backgroundColor, tokens.matchHighlightColor);
      expect(active.backgroundColor, tokens.matchHighlightActiveColor);
      expect(active.backgroundColor, isNot(inactive.backgroundColor));
      expect(inactive.fontSize, base.fontSize);
      expect(inactive.fontFamily, base.fontFamily);
    });
  });

  group('lookup context', () {
    test('returns registered ranges for exact path', () {
      final ctx = _MapContext({
        (
          3,
          const [ListItemStep(0)],
        ): const MarkdownContainerHighlights(ranges: [TextRange(start: 0, end: 4)]),
      });
      expect(
        ctx.forContainer(3, const [ListItemStep(0)])?.ranges,
        hasLength(1),
      );
      expect(ctx.forContainer(3, const [ListItemStep(1)]), isNull);
      expect(ctx.forContainer(4, const []), isNull);
    });
  });
}

class _MapContext implements MarkdownHighlightContext {
  _MapContext(this.entries);
  final Map<(int, List<MarkdownPathStep>), MarkdownContainerHighlights> entries;

  @override
  MarkdownContainerHighlights? forContainer(
    int blockIndex,
    List<MarkdownPathStep> path,
  ) =>
      entries[(blockIndex, path)];
}
