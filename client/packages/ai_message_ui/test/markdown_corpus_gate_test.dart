import 'dart:io';

import 'package:ai_message_ui/src/markdown/content_compiler.dart';
import 'package:ai_message_ui/src/markdown/ir/markdown_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    clearMessageContentCache();
  });

  Directory corpusDirectory() {
    final candidates = [
      Directory('test/fixtures/markdown_corpus'),
      Directory('packages/ai_message_ui/test/fixtures/markdown_corpus'),
    ];
    for (final dir in candidates) {
      if (dir.existsSync()) return dir;
    }
    fail(
      'markdown corpus directory not found '
      '(looked under ${candidates.map((d) => d.path).join(', ')})',
    );
  }

  int countUnsupported(MarkdownBlock block) {
    var count = block is RawLiteralBlock ? 1 : 0;
    switch (block) {
      case BlockquoteBlock(:final blocks):
        for (final child in blocks) {
          count += countUnsupported(child);
        }
      case ListBlock(:final items):
        for (final item in items) {
          for (final child in item.children) {
            count += countUnsupported(child);
          }
        }
      case _:
        break;
    }
    return count;
  }

  int unsupportedInDocument(MarkdownDocument doc) {
    var total = 0;
    for (final block in doc.blocks) {
      total += countUnsupported(block);
    }
    return total;
  }

  test('corpus gate: ≥95% of fixtures compile with zero unsupported', () {
    final dir = corpusDirectory();
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.md'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    expect(files, hasLength(greaterThanOrEqualTo(20)));

    var clean = 0;
    for (final file in files) {
      final markdown = file.readAsStringSync();
      final doc = compileMarkdown(markdown);
      if (unsupportedInDocument(doc) == 0) {
        clean++;
      }
    }

    final ratio = clean / files.length;
    expect(
      ratio,
      greaterThanOrEqualTo(0.95),
      reason:
          'expected ≥95% zero-unsupported; got '
          '${(ratio * 100).toStringAsFixed(1)}% ($clean/${files.length})',
    );
  });

  test('identical prepared markdown returns identical cached document', () {
    const markdown = '## Cached heading\n\nHello **world**.';
    final first = compileMarkdown(markdown);
    final second = compileMarkdown(markdown);
    expect(identical(first, second), isTrue);
    expect(messageContentCacheHits, 1);
    expect(messageContentCacheLength, 1);
  });
}
