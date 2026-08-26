import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_draft_store.dart';

import '../../support/in_memory_filesystem.dart';

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
    ).saveLanding('w1', 'long prompt');

    expect(
      await ComposeDraftStore(fs: fs, rootPath: root).loadLanding('w1'),
      'long prompt',
    );
  });

  test('session drafts are isolated and cleared independently', () async {
    final store = ComposeDraftStore(fs: fs, rootPath: root);
    await store.saveSession('w1', 's1', 'retry me');
    await store.saveSession('w1', 's2', 'other');
    await store.clearSession('w1', 's1');

    expect(await store.loadSession('w1', 's1'), isNull);
    expect(await store.loadSession('w1', 's2'), 'other');
  });

  test('concurrent landing and session saves preserve both drafts', () async {
    final fs = _YieldingReadFilesystem();
    final landingStore = ComposeDraftStore(fs: fs, rootPath: root);
    final sessionStore = ComposeDraftStore(fs: fs, rootPath: root);

    await Future.wait([
      landingStore.saveLanding('w1', 'landing'),
      sessionStore.saveSession('w1', 's1', 'session'),
    ]);

    expect(await landingStore.loadLanding('w1'), 'landing');
    expect(await landingStore.loadSession('w1', 's1'), 'session');
  });

  test('trimmed-empty drafts are removed from persistence', () async {
    final store = ComposeDraftStore(fs: fs, rootPath: root);
    await store.saveLanding('w1', 'draft');
    await store.saveSession('w1', 's1', 'draft');

    await store.saveLanding('w1', '   ');
    await store.saveSession('w1', 's1', '\t');

    expect(await store.loadLanding('w1'), isNull);
    expect(await store.loadSession('w1', 's1'), isNull);
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
