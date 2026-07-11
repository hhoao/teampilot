import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/editor_platform/document_session.dart';
import 'package:teampilot/services/editor_platform/document_session_token_provider.dart';
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

  test('tokensForLine maps TokenSpan to CodeTokenSpan', () async {
    final pool = FakeTsWorkerPool();
    final session = newSession(pool);
    addTearDown(session.dispose);
    final provider = DocumentSessionTokenProvider(session);
    addTearDown(provider.dispose);

    await session.open(path: 'a.json', text: '{"a": "b"}');
    await session.colorizeAfterOpen(viewportEndLine: 0);

    final spans = provider.tokensForLine(0);
    final sessionSpans = session.tokensForLine(0);
    expect(spans, isNotEmpty);
    expect(spans.length, sessionSpans.length);
    for (var i = 0; i < spans.length; i++) {
      expect(spans[i].start, sessionSpans[i].start);
      expect(spans[i].length, sessionSpans[i].length);
      expect(spans[i].scope, sessionSpans[i].scope);
    }
  });

  test('tokensForLine returns empty for untokenized line', () async {
    final pool = FakeTsWorkerPool();
    final session = newSession(pool);
    addTearDown(session.dispose);
    final provider = DocumentSessionTokenProvider(session);
    addTearDown(provider.dispose);

    await session.open(path: 'a.unknown', text: '{"a": "b"}');

    expect(provider.tokensForLine(0), isEmpty);
  });

  test('forwards session notifications to provider listeners', () async {
    final pool = FakeTsWorkerPool();
    final session = newSession(pool);
    addTearDown(session.dispose);
    final provider = DocumentSessionTokenProvider(session);
    addTearDown(provider.dispose);

    var notified = 0;
    provider.addListener(() => notified++);

    await session.open(path: 'a.json', text: '{"a": "b"}');
    await session.colorizeAfterOpen(viewportEndLine: 0);

    expect(notified, greaterThan(0));
  });

  test('dispose stops forwarding notifications from the session', () async {
    final pool = FakeTsWorkerPool();
    final session = newSession(pool);
    addTearDown(session.dispose);
    final provider = DocumentSessionTokenProvider(session);

    var notified = 0;
    provider.addListener(() => notified++);
    provider.dispose();

    await session.open(path: 'a.json', text: '{"a": "b"}');
    await session.colorizeAfterOpen(viewportEndLine: 0);

    expect(notified, 0);
  });
}
