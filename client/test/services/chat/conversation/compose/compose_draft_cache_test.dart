import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_draft.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_draft_cache.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_draft_store.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_token_document.dart';

import '../../../../support/in_memory_filesystem.dart';

void main() {
  test('landing draft round-trips by workspaceId', () {
    final cache = ComposeDraftCache();
    expect(cache.landingDraft('w1'), isNull);

    cache.setLandingDraft('w1', ComposeDraft(text: 'hello'));

    expect(cache.landingDraft('w1')?.text, 'hello');
    expect(cache.landingDraft('w2'), isNull);

    cache.clearLandingDraft('w1');
    expect(cache.landingDraft('w1'), isNull);
  });

  test('session draft round-trips by sessionId', () {
    final cache = ComposeDraftCache();
    cache.setSessionDraft('s1', ComposeDraft(text: 'hi'));
    expect(cache.sessionDraft('s1')?.text, 'hi');
    expect(cache.sessionDraft('s2'), isNull);

    cache.clearSessionDraft('s1');
    expect(cache.sessionDraft('s1'), isNull);
  });

  test('landing and session keys are independent', () {
    final cache = ComposeDraftCache();
    cache.setLandingDraft('w1', ComposeDraft(text: 'landing'));
    cache.setSessionDraft('s1', ComposeDraft(text: 'session'));

    expect(cache.landingDraft('w1')?.text, 'landing');
    expect(cache.sessionDraft('s1')?.text, 'session');
    expect(cache.sessionDraft('w1'), isNull);

    cache.clearLandingDraft('w1');
    expect(cache.sessionDraft('s1')?.text, 'session');
  });

  test('writing trimmed-empty text removes the entry', () {
    final cache = ComposeDraftCache();
    cache.setLandingDraft('w1', ComposeDraft(text: 'draft'));
    cache.setLandingDraft('w1', ComposeDraft(text: '   '));
    expect(cache.landingDraft('w1'), isNull);

    cache.setSessionDraft('s1', ComposeDraft(text: 'draft'));
    cache.setSessionDraft('s1', ComposeDraft(text: ''));
    expect(cache.sessionDraft('s1'), isNull);
  });

  test('clear() resets all entries', () {
    final cache = ComposeDraftCache();
    cache.setLandingDraft('w1', ComposeDraft(text: 'a'));
    cache.setSessionDraft('s1', ComposeDraft(text: 'b'));
    cache.clear();
    expect(cache.landingDraft('w1'), isNull);
    expect(cache.sessionDraft('s1'), isNull);
  });

  test(
    'hydration does not replace a draft typed while it was loading',
    () async {
      final fs = InMemoryFilesystem();
      final store = ComposeDraftStore(fs: fs, rootPath: '/tp');
      await store.saveLanding('w1', ComposeDraft(text: 'persisted'));
      await store.saveSession('w1', 's1', ComposeDraft(text: 'persisted session'));
      final cache = ComposeDraftCache(persistentStore: store);
      cache.setLandingDraft('w1', ComposeDraft(text: 'typed while loading'));
      cache.setSessionDraft('s1', ComposeDraft(text: 'typed session while loading'));

      await cache.hydrateLanding(
        'w1',
        shouldSeed: () => false,
        storage: fakeHomeStorage(),
      );
      await cache.hydrateSession(
        'w1',
        's1',
        shouldSeed: () => false,
        storage: fakeHomeStorage(),
      );

      expect(cache.landingDraft('w1')?.text, 'typed while loading');
      expect(cache.sessionDraft('s1')?.text, 'typed session while loading');
    },
  );

  test('token ranges survive the in-memory round-trip', () {
    final cache = ComposeDraftCache();
    cache.setLandingDraft(
      'w1',
      const ComposeDraft(
        text: '@a hi',
        tokens: [
          ComposeToken(
            id: 't',
            kind: ComposeTokenKind.fileReference,
            start: 0,
            end: 2,
            payload: '@a',
          ),
        ],
      ),
    );

    expect(cache.landingDraft('w1')?.text, '@a hi');
    expect(
      cache.landingDraft('w1')?.tokens.single.range,
      const TextRange(start: 0, end: 2),
    );
  });
}
