import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:teampilot/services/editor_platform/document_session.dart';
import 'package:teampilot/services/editor_platform/editor_viewport_token_binder.dart';
import 'package:teampilot/services/editor_platform/language_registry.dart';

import 'fake_ts_worker.dart';

/// Minimal [IParagraph] test double: [EditorViewportTokenBinder] only reads
/// [CodeLineRenderParagraph.index], so every other member is an unused stub.
class _FakeParagraph implements IParagraph {
  @override
  double get width => 0;

  @override
  double get height => 0;

  @override
  double get preferredLineHeight => 0;

  @override
  bool get trucated => false;

  @override
  int get length => 0;

  @override
  int get lineCount => 1;

  @override
  void draw(Canvas canvas, Offset offset) {}

  @override
  TextPosition getPosition(Offset offset) => const TextPosition(offset: 0);

  @override
  TextRange getWord(Offset offset) => TextRange.empty;

  @override
  InlineSpan? getSpanForPosition(TextPosition position) => null;

  @override
  TextRange getRangeForSpan(InlineSpan span) => TextRange.empty;

  @override
  TextRange getLineBoundary(TextPosition position) => TextRange.empty;

  @override
  Offset? getOffset(TextPosition position) => null;

  @override
  List<Rect> getRangeRects(TextRange range) => const <Rect>[];
}

/// Builds one [CodeLineRenderParagraph] per line index, in the given order
/// (re-editor does not guarantee paragraphs are sorted by index).
List<CodeLineRenderParagraph> _paragraphsAt(List<int> indices) {
  return indices
      .map(
        (index) => CodeLineRenderParagraph(
          index: index,
          paragraph: _FakeParagraph(),
          offset: Offset.zero,
          chunkParent: false,
          chunkLongText: false,
        ),
      )
      .toList();
}

void main() {
  DocumentSession newSession(FakeTsWorkerPool pool) {
    return DocumentSession(
      registry: LanguageRegistry.builtins(),
      pool: pool,
      // Fake worker ignores the query source; bypass rootBundle.
      highlightsLoader: (_) async => '(string) @string',
    );
  }

  // 30 lines, each with a quoted string the fake worker captures, so
  // `tokensForLine` reveals exactly which lines were queried.
  final text = List.generate(30, (i) => '{"k$i": "v$i"}').join('\n');

  test('requests tokens for the visible paragraph range', () async {
    final pool = FakeTsWorkerPool();
    final session = newSession(pool);
    addTearDown(session.dispose);
    await session.open(path: 'a.json', text: text);

    final notifier = CodeIndicatorValueNotifier(null);
    final binder = EditorViewportTokenBinder(
      session: session,
      notifier: notifier,
    );
    addTearDown(binder.dispose);

    notifier.value = CodeIndicatorValue(paragraphs: _paragraphsAt([20, 10]));
    await pumpEventQueue();

    // Every line in the [10, 20] band was queried and colored...
    for (var line = 10; line <= 20; line++) {
      expect(session.tokensForLine(line), isNotEmpty, reason: 'line $line');
    }
    // ...but nothing outside the band was touched.
    expect(session.tokensForLine(5), isEmpty);
    expect(session.tokensForLine(25), isEmpty);
    expect(pool.queryCount, 1);
  });

  test('constructor requests tokens for an already-set indicator value', () async {
    final pool = FakeTsWorkerPool();
    final session = newSession(pool);
    addTearDown(session.dispose);
    await session.open(path: 'a.json', text: text);

    final notifier = CodeIndicatorValueNotifier(
      CodeIndicatorValue(paragraphs: _paragraphsAt([3, 7])),
    );
    final binder = EditorViewportTokenBinder(
      session: session,
      notifier: notifier,
    );
    addTearDown(binder.dispose);
    await pumpEventQueue();

    expect(session.tokensForLine(3), isNotEmpty);
    expect(session.tokensForLine(7), isNotEmpty);
    expect(pool.queryCount, 1);
  });

  test('does not re-request when the visible band is unchanged', () async {
    // autoRespond: false so the first query's tokens stay uncached — a
    // spurious re-fire would show up as a second query, not be hidden by
    // DocumentSession's own already-cached-lines dedupe.
    final pool = FakeTsWorkerPool(autoRespond: false);
    final session = newSession(pool);
    addTearDown(session.dispose);
    await session.open(path: 'a.json', text: text);

    final notifier = CodeIndicatorValueNotifier(null);
    final binder = EditorViewportTokenBinder(
      session: session,
      notifier: notifier,
    );
    addTearDown(binder.dispose);

    notifier.value = CodeIndicatorValue(paragraphs: _paragraphsAt([10, 20]));
    expect(pool.queryCount, 1);

    // A different paragraph list (a mid paragraph now renders too) so the
    // notifier does fire, but the band's min/max is still 10..20.
    notifier.value = CodeIndicatorValue(
      paragraphs: _paragraphsAt([10, 15, 20]),
    );
    expect(pool.queryCount, 1);

    // A genuinely new band still fires.
    notifier.value = CodeIndicatorValue(paragraphs: _paragraphsAt([12, 22]));
    expect(pool.queryCount, 2);
  });

  test('dispose stops listening for indicator changes', () async {
    final pool = FakeTsWorkerPool(autoRespond: false);
    final session = newSession(pool);
    addTearDown(session.dispose);
    await session.open(path: 'a.json', text: text);

    final notifier = CodeIndicatorValueNotifier(null);
    final binder = EditorViewportTokenBinder(
      session: session,
      notifier: notifier,
    );

    notifier.value = CodeIndicatorValue(paragraphs: _paragraphsAt([10, 20]));
    expect(pool.queryCount, 1);

    binder.dispose();

    notifier.value = CodeIndicatorValue(paragraphs: _paragraphsAt([0, 5]));
    expect(pool.queryCount, 1);
  });
}
