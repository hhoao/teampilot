import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_draft.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_draft_store.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_token_document.dart';

import '../../../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late String root;

  setUp(() {
    fs = InMemoryFilesystem();
    root = '/tp';
  });

  test('landing draft survives a fresh store instance', () async {
    await ComposeDraftStore(
      fs: fs,
      rootPath: root,
    ).saveLanding('w1', const ComposeDraft(text: 'long prompt'));

    final loaded = await ComposeDraftStore(
      fs: fs,
      rootPath: root,
    ).loadLanding('w1');
    expect(loaded?.text, 'long prompt');
    expect(loaded?.tokens, isEmpty);
  });

  test('session drafts are isolated and cleared independently', () async {
    final store = ComposeDraftStore(fs: fs, rootPath: root);
    await store.saveSession('w1', 's1', const ComposeDraft(text: 'retry me'));
    await store.saveSession('w1', 's2', const ComposeDraft(text: 'other'));
    await store.clearSession('w1', 's1');

    expect(await store.loadSession('w1', 's1'), isNull);
    expect((await store.loadSession('w1', 's2'))?.text, 'other');
  });

  test('concurrent landing and session saves preserve both drafts', () async {
    final fs = _YieldingReadFilesystem();
    final landingStore = ComposeDraftStore(fs: fs, rootPath: root);
    final sessionStore = ComposeDraftStore(fs: fs, rootPath: root);

    await Future.wait([
      landingStore.saveLanding('w1', const ComposeDraft(text: 'landing')),
      sessionStore.saveSession('w1', 's1', const ComposeDraft(text: 'session')),
    ]);

    expect((await landingStore.loadLanding('w1'))?.text, 'landing');
    expect((await landingStore.loadSession('w1', 's1'))?.text, 'session');
  });

  test('trimmed-empty drafts are removed from persistence', () async {
    final store = ComposeDraftStore(fs: fs, rootPath: root);
    await store.saveLanding('w1', const ComposeDraft(text: 'draft'));
    await store.saveSession('w1', 's1', const ComposeDraft(text: 'draft'));

    await store.saveLanding('w1', const ComposeDraft(text: '   '));
    await store.saveSession('w1', 's1', const ComposeDraft(text: '\t'));

    expect(await store.loadLanding('w1'), isNull);
    expect(await store.loadSession('w1', 's1'), isNull);
  });

  test('tokens round-trip with the text', () async {
    final store = ComposeDraftStore(fs: fs, rootPath: root);
    const text = 'see @src/main.dart and /plan';
    await store.saveLanding(
      'w1',
      const ComposeDraft(
        text: text,
        tokens: [
          ComposeToken(
            id: 'a',
            kind: ComposeTokenKind.fileReference,
            start: 4,
            end: 18,
            payload: '@src/main.dart',
          ),
          ComposeToken(
            id: 'b',
            kind: ComposeTokenKind.skill,
            start: 23,
            end: 28,
            payload: '/plan',
          ),
        ],
      ),
    );

    final loaded = await ComposeDraftStore(fs: fs, rootPath: root)
        .loadLanding('w1');
    expect(loaded?.text, text);
    expect(loaded?.tokens.map((token) => token.payload), [
      '@src/main.dart',
      '/plan',
    ]);
    expect(loaded?.tokens.first.range, const TextRange(start: 4, end: 18));
  });

  test('legacy plain-string drafts load without tokens', () async {
    final file = '/tp/workspace/workspaces/w1/compose-drafts.json';
    await fs.ensureDir('/tp');
    await fs.atomicWrite(file, '{"landing":"legacy text","sessions":{}}');

    final loaded = await ComposeDraftStore(fs: fs, rootPath: root)
        .loadLanding('w1');
    expect(loaded?.text, 'legacy text');
    expect(loaded?.tokens, isEmpty);
  });
}

class _YieldingReadFilesystem extends InMemoryFilesystem {
  @override
  Future<String?> readString(String path) async {
    final text = await super.readString(path);
    await Future<void>.delayed(Duration.zero);
    return text;
  }
}
