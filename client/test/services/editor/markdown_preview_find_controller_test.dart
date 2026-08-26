import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor/markdown_preview_find_controller.dart';
import 'package:tp_markdown/tp_markdown.dart';

MarkdownDocument doc() => compileMarkdown('# Title\n\nHello **World** hello\n');

void main() {
  test('debounces text input and scans rendered text', () {
    fakeAsync((async) {
      final c = MarkdownPreviewFindController();
      c.openFind();
      c.setDocument(doc());
      c.search('world');
      expect(c.hits, isEmpty); // not yet flushed
      async.elapse(const Duration(milliseconds: 200));
      // Single case-insensitive match spanning the bold run.
      expect(c.hits.length, 1);
      expect(c.activeIndex, 0);
      c.search('hello');
      async.elapse(const Duration(milliseconds: 200));
      // Capitalized + trailing lowercase, case-insensitive across runs.
      expect(c.hits.length, 2);
      c.dispose();
    });
  });

  test('rapid input coalesces into one deferred scan', () {
    fakeAsync((async) {
      final c = MarkdownPreviewFindController();
      c.openFind();
      c.setDocument(doc());
      c.search('hel');
      async.elapse(const Duration(milliseconds: 100));
      expect(c.hits, isEmpty);
      c.search('hello');
      async.elapse(const Duration(milliseconds: 100));
      expect(c.hits, isEmpty); // timer restarted by second keystroke
      async.elapse(const Duration(milliseconds: 100));
      expect(c.hits.length, 2);
      c.dispose();
    });
  });

  test('empty query clears immediately', () {
    fakeAsync((async) {
      final c = MarkdownPreviewFindController();
      c.openFind();
      c.setDocument(doc());
      c.search('hello');
      async.elapse(const Duration(milliseconds: 200));
      expect(c.hits, isNotEmpty);
      c.search('');
      expect(c.hits, isEmpty);
      expect(c.hasError, isFalse);
      c.dispose();
    });
  });

  test('case toggle rescans synchronously', () {
    fakeAsync((async) {
      final c = MarkdownPreviewFindController();
      c.openFind();
      c.setDocument(doc());
      c.search('hello');
      async.elapse(const Duration(milliseconds: 200));
      c.toggleCaseSensitive();
      expect(c.hits.length, 1);
      c.dispose();
    });
  });

  test('invalid regex sets error state instead of throwing', () {
    fakeAsync((async) {
      final c = MarkdownPreviewFindController();
      c.openFind();
      c.setDocument(doc());
      c.toggleRegex();
      c.search('([ ');
      async.elapse(const Duration(milliseconds: 200));
      expect(c.hasError, isTrue);
      expect(c.hits, isEmpty);
      c.dispose();
    });
  });

  test('navigation wraps and clamps', () {
    fakeAsync((async) {
      final c = MarkdownPreviewFindController();
      c.openFind();
      c.setDocument(doc());
      c.search('hello');
      async.elapse(const Duration(milliseconds: 200));
      expect(c.activeIndex, 0);
      c.previous(); // wraps to last
      expect(c.activeIndex, c.hits.length - 1);
      c.next(); // wraps to 0
      expect(c.activeIndex, 0);
      c.select(99);
      expect(c.activeIndex, 0);
      c.dispose();
    });
  });

  test('close resets everything', () {
    fakeAsync((async) {
      final c = MarkdownPreviewFindController();
      c.openFind();
      c.setDocument(doc());
      c.search('hello');
      async.elapse(const Duration(milliseconds: 200));
      c.close();
      expect(c.open, isFalse);
      expect(c.query, isEmpty);
      expect(c.hits, isEmpty);
      expect(c.hasError, isFalse);
      c.dispose();
    });
  });

  test('setDocument while open rescans against new content', () {
    fakeAsync((async) {
      final c = MarkdownPreviewFindController();
      c.openFind();
      c.setDocument(doc());
      c.search('title');
      async.elapse(const Duration(milliseconds: 200));
      expect(c.hits, isNotEmpty);
      c.setDocument(compileMarkdown('nothing relevant\n'));
      expect(c.hits, isEmpty);
      c.dispose();
    });
  });

  test('counterLabel reports active/total and empty without hits', () {
    fakeAsync((async) {
      final c = MarkdownPreviewFindController();
      expect(c.counterLabel(), isEmpty);
      c.openFind();
      c.setDocument(doc());
      c.search('hello');
      async.elapse(const Duration(milliseconds: 200));
      expect(c.counterLabel(), '1/2');
      c.next();
      expect(c.counterLabel(), '2/2');
      c.dispose();
    });
  });

  test('counterLabel shows capped total beyond kMarkdownSearchMaxHits', () {
    fakeAsync((async) {
      final big = compileMarkdown(
        '${List.filled(kMarkdownSearchMaxHits + 500, 'a').join(' ')}\n',
      );
      final c = MarkdownPreviewFindController();
      c.openFind();
      c.setDocument(big);
      c.search('a');
      async.elapse(const Duration(milliseconds: 200));
      expect(c.hits.length, kMarkdownSearchMaxHits);
      expect(c.counterLabel(), '1/$kMarkdownSearchMaxHits+');
      c.dispose();
    });
  });

  test('open setter notifies only on change', () {
    final c = MarkdownPreviewFindController();
    var notifications = 0;
    c.addListener(() => notifications++);
    c.open = true;
    expect(c.open, isTrue);
    c.open = true;
    expect(notifications, 1);
    c.openFind();
    expect(notifications, 1);
    c.dispose();
  });

  test('containerOf resolves hit containers with bounds checks', () {
    fakeAsync((async) {
      final c = MarkdownPreviewFindController();
      expect(
        c.containerOf(const MarkdownSearchHit(container: 0, start: 0, end: 1)),
        isNull,
      ); // no index yet
      c.openFind();
      c.setDocument(doc());
      c.search('hello');
      async.elapse(const Duration(milliseconds: 200));
      final hit = c.hits.first;
      expect(c.containerOf(hit)?.plainText, contains('hello'));
      expect(
        c.containerOf(
          const MarkdownSearchHit(container: 9999, start: 0, end: 1),
        ),
        isNull,
      );
      expect(
        c.containerOf(const MarkdownSearchHit(container: -1, start: 0, end: 1)),
        isNull,
      );
      c.dispose();
    });
  });
}
