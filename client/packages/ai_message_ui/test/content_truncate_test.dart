import 'package:ai_message_ui/src/markdown/ir/markdown_document.dart';
import 'package:ai_message_ui/src/markdown/content_truncate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('claudeAligned budget clips large tables', () {
    final doc = MarkdownDocument(
      blocks: [
        TableBlock(
          headers: const [
            InlineDocument(runs: [TextRun('A')]),
            InlineDocument(runs: [TextRun('B')]),
          ],
          rows: [
            for (var r = 0; r < 20; r++)
              [
                InlineDocument(runs: [TextRun('r$r-a')]),
                InlineDocument(runs: [TextRun('r$r-b')]),
              ],
          ],
        ),
      ],
    );
    final result = truncateMessageContent(doc);
    expect(result.wasTruncated, isTrue);
    final table = result.document.blocks.single as TableBlock;
    expect(table.rows.length, ContentCollapseBudget.claudeAligned.maxTableRows);
  });

  test('short doc unchanged', () {
    final doc = MarkdownDocument(
      blocks: [ParagraphBlock(runs: [TextRun('hi')])],
    );
    final result = truncateMessageContent(doc);
    expect(result.wasTruncated, isFalse);
    expect(identical(result.document, doc), isTrue);
  });
}
