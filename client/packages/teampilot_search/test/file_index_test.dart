import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot_search/teampilot_search.dart';

void main() {
  final fixtureRoot = Directory('rust/tests/fixtures/file_index').absolute.path;

  test('builds and fuzzy queries indexed files', () async {
    final index = TpFileIndex();
    addTearDown(index.dispose);

    await index.build(fixtureRoot);
    final hits = index.query('router');

    expect(index.isBuilt, isTrue);
    expect(
      hits.map((hit) => hit.relativePath),
      contains('lib/app_router.dart'),
    );
    expect(
      hits.map((hit) => hit.relativePath),
      isNot(contains(contains('node_modules'))),
    );
  });

  test('queries files by contains mode and directories', () async {
    final index = TpFileIndex();
    addTearDown(index.dispose);

    await index.build(fixtureRoot);

    expect(
      index
          .query('chat', mode: TpFileMatchMode.contains)
          .map((hit) => hit.relativePath),
      contains('lib/chat_cubit.dart'),
    );
    expect(index.queryDirectories('lib'), contains('lib'));
  });

  test('returns large expanded query result sets without clipping', () async {
    final root = await Directory.systemTemp.createTemp('tp-file-index-');
    addTearDown(() => root.delete(recursive: true));
    final index = TpFileIndex();
    addTearDown(index.dispose);

    for (var i = 0; i < 600; i++) {
      await File(
        '${root.path}/expanded-${i.toString().padLeft(4, '0')}-${'x' * 120}.dart',
      ).writeAsString('');
    }

    await index.build(root.path);
    final hits = index.query(
      'expanded',
      mode: TpFileMatchMode.contains,
      limit: 100000,
    );

    expect(hits, hasLength(600));
    expect(index.truncated, isFalse);
  });
}
