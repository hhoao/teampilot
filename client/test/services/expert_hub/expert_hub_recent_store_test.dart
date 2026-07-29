import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/expert_hub/builtin_member_templates.dart';
import 'package:teampilot/services/expert_hub/expert_hub_recent_store.dart';
import 'package:teampilot/services/storage/app_storage.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late ExpertHubRecentStore store;

  setUp(() {
    fs = InMemoryFilesystem();
    final paths = AppPaths('/tp');
    store = ExpertHubRecentStore(
      fs: fs,
      pathOverride: paths.memberHubRecentJson,
    );
  });

  test('touch prepends key and dedupes', () async {
    await store.touch('a/b/x');
    await store.touch('a/b/y');

    expect(await store.loadOrderedKeys(), ['a/b/y', 'a/b/x']);

    await store.touch('a/b/x');
    expect(await store.loadOrderedKeys(), ['a/b/x', 'a/b/y']);
  });

  test('touch caps at maxEntries unique keys', () async {
    for (var i = 0; i < 12; i++) {
      await store.touch('key-$i');
    }

    final keys = await store.loadOrderedKeys();
    expect(keys.length, ExpertHubRecentStore.maxEntries);
    expect(keys.first, 'key-11');
    expect(keys.last, 'key-2');
    expect(keys, isNot(contains('key-0')));
    expect(keys, isNot(contains('key-1')));
  });

  test('touch ignores builtin default expert key', () async {
    await store.touch('a/b/x');
    await store.touch(kBuiltinDefaultExpertKey);

    expect(await store.loadOrderedKeys(), ['a/b/x']);
  });

  test('loadOrderedKeys omits builtin default left in legacy files', () async {
    final paths = AppPaths('/tp');
    await fs.ensureDir(paths.memberHubDir);
    await fs.atomicWrite(
      paths.memberHubRecentJson,
      jsonEncode({
        'keys': [kBuiltinDefaultExpertKey, 'a/b/x'],
      }),
    );

    expect(await store.loadOrderedKeys(), ['a/b/x']);
  });
}
