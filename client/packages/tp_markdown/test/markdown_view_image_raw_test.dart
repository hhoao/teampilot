import 'dart:convert';

import 'package:tp_markdown/tp_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final testImage = MemoryImage(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    ),
  );

  testWidgets('ImageBlock with resolveImage shows Image widget', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            document: const MarkdownDocument(
              blocks: [ImageBlock(src: 'test.png', alt: 'Test')],
            ),
            tokens: MarkdownTokens.test(),
            resolvers: MarkdownResolvers(
              resolveImage: (src) => src == 'test.png' ? testImage : null,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(tester.widget<Image>(find.byType(Image)).image, testImage);
  });

  testWidgets('ImageBlock without resolver shows icon and alt placeholder',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            document: const MarkdownDocument(
              blocks: [ImageBlock(src: 'missing.png', alt: 'Alt text')],
            ),
            tokens: MarkdownTokens.test(),
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.text('Alt text'), findsOneWidget);
  });

  testWidgets('RawLiteral shows source markdown as monospace text',
      (tester) async {
    const raw = '<div>unsafe</div>';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            document: const MarkdownDocument(
              blocks: [RawLiteralBlock(rawMarkdown: raw)],
            ),
            tokens: MarkdownTokens.test(),
          ),
        ),
      ),
    );

    expect(find.text(raw), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('GFM fixture document renders via MarkdownView only', (
    tester,
  ) async {
    const source = '''
# Heading

A paragraph with **bold**.

- list item

```dart
void main() {}
```

| H | V |
| - | - |
| a | b |

![alt](img.png)

<div>raw html</div>
''';

    final doc = compileMarkdown(source);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownView(
            document: doc,
            tokens: MarkdownTokens.test(),
            resolvers: MarkdownResolvers(
              resolveImage: (_) => testImage,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(MarkdownView), findsOneWidget);
  });
}
