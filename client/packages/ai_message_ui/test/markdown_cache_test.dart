import 'package:ai_message_ui/src/parts/text_part_view.dart';
import 'package:ai_message_ui/src/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
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

  group('markdownBodyCacheKey', () {
    final light = ThemeData(brightness: Brightness.light);
    final dark = ThemeData(brightness: Brightness.dark);
    const ai = AiMessageTheme();

    test('same inputs produce identical keys', () {
      final a = markdownBodyCacheKey(
        preparedMarkdown: 'hi',
        theme: light,
        aiTheme: ai,
      );
      final b = markdownBodyCacheKey(
        preparedMarkdown: 'hi',
        theme: light,
        aiTheme: ai,
      );
      expect(a, b);
    });

    test('brightness change yields different style key', () {
      final lightKey = markdownBodyCacheKey(
        preparedMarkdown: 'hi',
        theme: light,
        aiTheme: ai,
      );
      final darkKey = markdownBodyCacheKey(
        preparedMarkdown: 'hi',
        theme: dark,
        aiTheme: ai,
      );
      expect(lightKey, isNot(darkKey));
    });

    test('AiMessageTheme mutedSurface / codeBlockRadius affect key', () {
      final base = markdownBodyCacheKey(
        preparedMarkdown: 'hi',
        theme: light,
        aiTheme: ai,
      );
      final muted = markdownBodyCacheKey(
        preparedMarkdown: 'hi',
        theme: light,
        aiTheme: const AiMessageTheme(mutedSurface: Color(0xFF112233)),
      );
      final radius = markdownBodyCacheKey(
        preparedMarkdown: 'hi',
        theme: light,
        aiTheme: const AiMessageTheme(codeBlockRadius: 4),
      );
      expect(muted, isNot(base));
      expect(radius, isNot(base));
      expect(muted, isNot(radius));
    });

    test('custom markdownStyleSheet uses identity, not default tokens', () {
      final sheet = MarkdownStyleSheet();
      final a = markdownBodyCacheKey(
        preparedMarkdown: 'hi',
        theme: light,
        aiTheme: AiMessageTheme(markdownStyleSheet: sheet),
      );
      final b = markdownBodyCacheKey(
        preparedMarkdown: 'hi',
        theme: dark, // brightness ignored when custom sheet is set
        aiTheme: AiMessageTheme(markdownStyleSheet: sheet),
      );
      expect(a, b);
      final otherSheet = MarkdownStyleSheet();
      final c = markdownBodyCacheKey(
        preparedMarkdown: 'hi',
        theme: light,
        aiTheme: AiMessageTheme(markdownStyleSheet: otherSheet),
      );
      expect(c, isNot(a));
    });

    test('onTapLink identity is part of the key', () {
      void handler(String text, String? href, String title) {}
      final without = markdownBodyCacheKey(
        preparedMarkdown: 'hi',
        theme: light,
        aiTheme: ai,
      );
      final withLink = markdownBodyCacheKey(
        preparedMarkdown: 'hi',
        theme: light,
        aiTheme: ai,
        onTapLink: handler,
      );
      expect(withLink, isNot(without));
      expect(
        withLink,
        markdownBodyCacheKey(
          preparedMarkdown: 'hi',
          theme: light,
          aiTheme: ai,
          onTapLink: handler,
        ),
      );
    });
  });
}
