import 'package:tp_markdown/tp_markdown.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(clearMessageContentCache);

  test('same markdown reuses identical cached document', () {
    final a = compileMarkdown('hello **world**');
    final b = compileMarkdown('hello **world**');
    expect(identical(a, b), isTrue);
    expect(messageContentCacheHits, 1);
    expect(messageContentCacheLength, 1);
  });

  test('different markdown creates separate cache entries', () {
    compileMarkdown('one');
    compileMarkdown('two');
    expect(messageContentCacheLength, 2);
    expect(messageContentCacheHits, 0);
  });

  test('evicts oldest when over maxEntries (256)', () {
    for (var i = 0; i < 256; i++) {
      compileMarkdown('slot-$i');
    }
    expect(messageContentCacheLength, 256);

    compileMarkdown('slot-overflow');
    expect(messageContentCacheLength, 256);

    // Oldest key 'slot-0' should be gone; compiling it is a miss then insert.
    final beforeHits = messageContentCacheHits;
    compileMarkdown('slot-0');
    expect(messageContentCacheHits, beforeHits);
    expect(messageContentCacheLength, 256);
  });
}
