import 'package:ai_message_ui/src/parts/text_part_view.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('same key reuses entry — debugLength stays 1', () {
    final cache = MarkdownBodyCache();
    final a = cache.getOrCreate('hello|default', () => const SizedBox());
    final b = cache.getOrCreate('hello|default', () => const SizedBox());
    expect(identical(a, b), isTrue);
    expect(cache.debugLength, 1);
  });

  test('different text keys create separate entries', () {
    final cache = MarkdownBodyCache();
    cache.getOrCreate('one|default', () => const SizedBox());
    cache.getOrCreate('two|default', () => const SizedBox());
    expect(cache.debugLength, 2);
  });

  test('evicts oldest when over maxEntries', () {
    final cache = MarkdownBodyCache(maxEntries: 2);
    cache.getOrCreate('a|default', () => const SizedBox());
    cache.getOrCreate('b|default', () => const SizedBox());
    cache.getOrCreate('c|default', () => const SizedBox());
    expect(cache.debugLength, 2);
    // Oldest key 'a' should be gone; rebuilding returns a new widget.
    final rebuilt = cache.getOrCreate('a|default', () => const Text('new'));
    expect(cache.debugLength, 2);
    expect(rebuilt, isA<Text>());
  });
}
