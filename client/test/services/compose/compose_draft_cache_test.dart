import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_draft_cache.dart';
import 'package:teampilot/services/compose/compose_draft_store.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  test('landing draft round-trips by workspaceId', () {
    final cache = ComposeDraftCache();
    expect(cache.landingDraft('w1'), isNull);

    cache.setLandingDraft('w1', 'hello');

    expect(cache.landingDraft('w1'), 'hello');
    expect(cache.landingDraft('w2'), isNull);

    cache.clearLandingDraft('w1');
    expect(cache.landingDraft('w1'), isNull);
  });

  test('session draft round-trips by sessionId', () {
    final cache = ComposeDraftCache();
    cache.setSessionDraft('s1', 'hi');
    expect(cache.sessionDraft('s1'), 'hi');
    expect(cache.sessionDraft('s2'), isNull);

    cache.clearSessionDraft('s1');
    expect(cache.sessionDraft('s1'), isNull);
  });

  test('landing and session keys are independent', () {
    final cache = ComposeDraftCache();
    cache.setLandingDraft('w1', 'landing');
    cache.setSessionDraft('s1', 'session');

    expect(cache.landingDraft('w1'), 'landing');
    expect(cache.sessionDraft('s1'), 'session');
    expect(cache.sessionDraft('w1'), isNull);

    cache.clearLandingDraft('w1');
    expect(cache.sessionDraft('s1'), 'session');
  });

  test('writing trimmed-empty text removes the entry', () {
    final cache = ComposeDraftCache();
    cache.setLandingDraft('w1', 'draft');
    cache.setLandingDraft('w1', '   ');
    expect(cache.landingDraft('w1'), isNull);

    cache.setSessionDraft('s1', 'draft');
    cache.setSessionDraft('s1', '');
    expect(cache.sessionDraft('s1'), isNull);
  });

  test('clear() resets all entries', () {
    final cache = ComposeDraftCache();
    cache.setLandingDraft('w1', 'a');
    cache.setSessionDraft('s1', 'b');
    cache.clear();
    expect(cache.landingDraft('w1'), isNull);
    expect(cache.sessionDraft('s1'), isNull);
  });

  test(
    'hydration does not replace a draft typed while it was loading',
    () async {
      final fs = InMemoryFilesystem();
      final store = ComposeDraftStore(fs: fs, rootPath: '/tp');
      await store.saveLanding('w1', 'persisted');
      await store.saveSession('w1', 's1', 'persisted session');
      final cache = ComposeDraftCache(persistentStore: store);
      cache.setLandingDraft('w1', 'typed while loading');
      cache.setSessionDraft('s1', 'typed session while loading');

      await cache.hydrateLanding('w1', shouldSeed: () => false);
      await cache.hydrateSession('w1', 's1', shouldSeed: () => false);

      expect(cache.landingDraft('w1'), 'typed while loading');
      expect(cache.sessionDraft('s1'), 'typed session while loading');
    },
  );
}
