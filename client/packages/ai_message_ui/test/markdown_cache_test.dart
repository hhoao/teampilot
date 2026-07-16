import 'package:ai_message_ui/src/markdown/content_compiler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(clearMessageContentCache);

  test('same markdown reuses identical cached document', () {
    final a = compileMessageContent('hello **world**');
    final b = compileMessageContent('hello **world**');
    expect(identical(a, b), isTrue);
    expect(messageContentCacheHits, 1);
    expect(messageContentCacheLength, 1);
  });

  test('different markdown creates separate cache entries', () {
    compileMessageContent('one');
    compileMessageContent('two');
    expect(messageContentCacheLength, 2);
    expect(messageContentCacheHits, 0);
  });

  test('evicts oldest when over maxEntries (64)', () {
    for (var i = 0; i < 64; i++) {
      compileMessageContent('slot-$i');
    }
    expect(messageContentCacheLength, 64);

    compileMessageContent('slot-overflow');
    expect(messageContentCacheLength, 64);

    // Oldest key 'slot-0' should be gone; compiling it is a miss then insert.
    final beforeHits = messageContentCacheHits;
    compileMessageContent('slot-0');
    expect(messageContentCacheHits, beforeHits);
    expect(messageContentCacheLength, 64);
  });
}
