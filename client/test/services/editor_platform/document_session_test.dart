import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor_platform/document_session.dart';
import 'package:teampilot/services/editor_platform/language_registry.dart';

import 'fake_ts_worker.dart';

void main() {
  DocumentSession newSession(FakeTsWorkerPool pool) {
    return DocumentSession(
      registry: LanguageRegistry.builtins(),
      pool: pool,
      // Fake worker ignores the query source; bypass rootBundle.
      highlightsLoader: (_) async => '(string) @string',
    );
  }

  test('open json colors viewport without waiting full file', () async {
    final pool = FakeTsWorkerPool();
    final session = newSession(pool);
    addTearDown(session.dispose);

    await session.open(path: 'a.json', text: '{"hello": "world"}\n' * 200);
    await session.colorizeAfterOpen(viewportEndLine: 5);

    expect(session.tokensForLine(0), isNotEmpty);
    // A far-off line is not colored yet: the background fill was fired but not
    // awaited, so opening did not block on the whole file.
    expect(session.tokensForLine(150), isEmpty);
  });

  test('background fill eventually colors the rest of the file', () async {
    final pool = FakeTsWorkerPool();
    final session = newSession(pool);
    addTearDown(session.dispose);

    await session.open(path: 'a.json', text: '{"hello": "world"}\n' * 50);
    await session.colorizeAfterOpen(viewportEndLine: 5);
    await pumpEventQueue();

    expect(session.tokensForLine(40), isNotEmpty);
  });

  test('applyEdit invalidates and refreshes dirty line', () async {
    final pool = FakeTsWorkerPool();
    final session = newSession(pool);
    addTearDown(session.dispose);

    await session.open(path: 'a.json', text: '{"a": "b"}');
    await session.colorizeAfterOpen(viewportEndLine: 0);

    final before = session.tokensForLine(0);
    expect(before, isNotEmpty);
    // value string is `"b"` → length 3 including quotes.
    expect(before.any((s) => s.length == 3), isTrue);

    // Insert before the closing quote of the value: {"a": "b"} → {"a": "bXYZ"}.
    session.applyEdit(codeUnitStart: 8, codeUnitDeleteCount: 0, insert: 'XYZ');
    await session.ensureTokensForLines(
      0,
      0,
      awaitResult: true,
      highPriority: true,
    );

    final after = session.tokensForLine(0);
    expect(after, isNotEmpty);
    // value string is now `"bXYZ"` → length 6 including quotes.
    expect(after.any((s) => s.length == 6), isTrue);
  });

  test('drops stale query reply after a newer edit', () async {
    final pool = FakeTsWorkerPool(autoRespond: false);
    final session = newSession(pool);
    addTearDown(session.dispose);

    await session.open(path: 'a.json', text: '{"a": "b"}\n{"c": "d"}');

    // Query line 0 (not high priority → does not pin the viewport), reply queued.
    await session.ensureTokensForLines(0, 0);

    // Edit line 1 only: bumps editSeq and enqueues a refresh for line 1, but not
    // line 0. The line-0 reply is now stale.
    session.applyEdit(codeUnitStart: 19, codeUnitDeleteCount: 0, insert: 'X');

    pool.deliverPending();
    await pumpEventQueue();

    // Stale line-0 reply was dropped; the fresh line-1 reply was applied.
    expect(session.tokensForLine(0), isEmpty);
    expect(session.tokensForLine(1), isNotEmpty);
  });

  test('unknown extension opens as plain text with no tokens', () async {
    final pool = FakeTsWorkerPool();
    final session = newSession(pool);
    addTearDown(session.dispose);

    await session.open(path: 'a.unknown', text: '{"a": "b"}');
    await session.colorizeAfterOpen(viewportEndLine: 0);

    expect(session.hasHighlighting, isFalse);
    expect(session.tokensForLine(0), isEmpty);
    expect(pool.handles, isEmpty);
  });
}
