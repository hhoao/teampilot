import 'package:ai_message_ui/src/markdown/content_ir.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paragraph and table block kinds round-trip equality', () {
    const doc = MessageContentDocument(
      blocks: [
        ParagraphBlock(
          runs: [
            TextRun('Hello '),
            StrongRun(children: [TextRun('world')]),
            TextRun('!'),
          ],
        ),
        TableBlock(
          headers: [
            InlineDocument(runs: [TextRun('Name')]),
            InlineDocument(runs: [TextRun('Value')]),
          ],
          rows: [
            [
              InlineDocument(runs: [TextRun('foo')]),
              InlineDocument(
                runs: [
                  StrongRun(children: [TextRun('bar')]),
                ],
              ),
            ],
          ],
        ),
      ],
    );

    expect(doc.blocks, hasLength(2));
    expect(doc.blocks[0], isA<ParagraphBlock>());
    expect(doc.blocks[1], isA<TableBlock>());

    final paragraph = doc.blocks[0] as ParagraphBlock;
    expect(paragraph.runs[0], isA<TextRun>());
    expect((paragraph.runs[0] as TextRun).text, 'Hello ');
    expect(paragraph.runs[1], isA<StrongRun>());
    expect(paragraph.runs[2], isA<TextRun>());

    final table = doc.blocks[1] as TableBlock;
    expect(table.headers, hasLength(2));
    expect(table.headers[0].runs.single, isA<TextRun>());
    expect(table.rows, hasLength(1));
    expect(table.rows.single[1].runs.single, isA<StrongRun>());

    const copy = MessageContentDocument(blocks: [
      ParagraphBlock(
        runs: [
          TextRun('Hello '),
          StrongRun(children: [TextRun('world')]),
          TextRun('!'),
        ],
      ),
      TableBlock(
        headers: [
          InlineDocument(runs: [TextRun('Name')]),
          InlineDocument(runs: [TextRun('Value')]),
        ],
        rows: [
          [
            InlineDocument(runs: [TextRun('foo')]),
            InlineDocument(
              runs: [
                StrongRun(children: [TextRun('bar')]),
              ],
            ),
          ],
        ],
      ),
    ]);
    expect(copy, equals(doc));
    expect(copy.hashCode, doc.hashCode);
  });

  test('non-const equal table blocks satisfy hash contract', () {
    final headersA = [
      InlineDocument(runs: [TextRun('Name')]),
      InlineDocument(runs: [TextRun('Value')]),
    ];
    final rowsA = [
      [
        InlineDocument(runs: [TextRun('foo')]),
        InlineDocument(
          runs: [StrongRun(children: [TextRun('bar')])],
        ),
      ],
    ];
    final docA = MessageContentDocument(
      blocks: [TableBlock(headers: headersA, rows: rowsA)],
    );

    final headersB = [
      InlineDocument(runs: [TextRun('Name')]),
      InlineDocument(runs: [TextRun('Value')]),
    ];
    final rowsB = [
      [
        InlineDocument(runs: [TextRun('foo')]),
        InlineDocument(
          runs: [StrongRun(children: [TextRun('bar')])],
        ),
      ],
    ];
    final docB = MessageContentDocument(
      blocks: [TableBlock(headers: headersB, rows: rowsB)],
    );

    expect(docA, equals(docB));
    expect(docA.hashCode, docB.hashCode);
  });

  test('inline run kinds are distinguishable', () {
    const runs = <InlineRun>[
      TextRun('plain'),
      StrongRun(children: [TextRun('bold')]),
      EmphasisRun(children: [TextRun('italic')]),
      StrikeRun(children: [TextRun('strike')]),
      CodeRun('inline'),
      LinkRun(url: 'https://example.com', children: [TextRun('link')]),
      LinkRun(
        url: 'https://example.com',
        title: 'Example',
        children: [TextRun('titled')],
      ),
    ];

    expect(runs[0], isA<TextRun>());
    expect(runs[1], isA<StrongRun>());
    expect(runs[2], isA<EmphasisRun>());
    expect(runs[3], isA<StrikeRun>());
    expect(runs[4], isA<CodeRun>());
    expect(runs[5], isA<LinkRun>());
    expect((runs[6] as LinkRun).title, 'Example');
  });

  test('other block kinds round-trip equality', () {
    const doc = MessageContentDocument(
      blocks: [
        HeadingBlock(level: 2, runs: [TextRun('Title')]),
        ListBlock(
          ordered: true,
          items: [
            ContentListItem(
              runs: [TextRun('one')],
              children: [
                ParagraphBlock(runs: [TextRun('nested')]),
              ],
            ),
            ContentListItem(
              runs: [TextRun('task')],
              isTaskChecked: true,
            ),
          ],
        ),
        BlockquoteBlock(
          blocks: [ParagraphBlock(runs: [TextRun('quoted')])],
        ),
        HorizontalRuleBlock(),
        CodeBlock(language: 'dart', text: 'void main() {}'),
        UnsupportedBlock(rawMarkdown: '![img](x.png)'),
      ],
    );

    expect(doc.blocks[0], isA<HeadingBlock>());
    expect((doc.blocks[0] as HeadingBlock).level, 2);
    expect(doc.blocks[1], isA<ListBlock>());
    expect((doc.blocks[1] as ListBlock).ordered, isTrue);
    expect((doc.blocks[1] as ListBlock).items[1].isTaskChecked, isTrue);
    expect(doc.blocks[2], isA<BlockquoteBlock>());
    expect(doc.blocks[3], isA<HorizontalRuleBlock>());
    expect(doc.blocks[4], isA<CodeBlock>());
    expect(doc.blocks[5], isA<UnsupportedBlock>());

    final copy = MessageContentDocument(
      blocks: [
        HeadingBlock(level: 2, runs: [TextRun('Title')]),
        ListBlock(
          ordered: true,
          items: [
            ContentListItem(
              runs: [TextRun('one')],
              children: [
                ParagraphBlock(runs: [TextRun('nested')]),
              ],
            ),
            ContentListItem(
              runs: [TextRun('task')],
              isTaskChecked: true,
            ),
          ],
        ),
        BlockquoteBlock(
          blocks: [ParagraphBlock(runs: [TextRun('quoted')])],
        ),
        HorizontalRuleBlock(),
        CodeBlock(language: 'dart', text: 'void main() {}'),
        UnsupportedBlock(rawMarkdown: '![img](x.png)'),
      ],
    );
    expect(copy, equals(doc));
    expect(copy.hashCode, doc.hashCode);
  });
}
