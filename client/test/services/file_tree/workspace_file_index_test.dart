import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/file_tree/workspace_file_index.dart';
import 'package:teampilot/services/file_tree/workspace_file_search.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  group('WorkspaceFileIndex', () {
    late InMemoryFilesystem fs;
    const root = '/workspace';

    setUp(() async {
      fs = InMemoryFilesystem();
      await fs.writeString('$root/lib/app_router.dart', '');
      await fs.writeString('$root/lib/chat_cubit.dart', '');
      await fs.writeString('$root/lib/widgets/router_guard.dart', '');
      await fs.writeString('$root/README.md', '');
      await fs.writeString('$root/.git/config', '');
      await fs.writeString('$root/node_modules/pkg/router.dart', '');
      await fs.writeString('$root/.hidden_file.dart', '');
    });

    test('returns nothing before the first build', () async {
      final index = WorkspaceFileIndex(fs: fs, root: root);
      expect(await index.query('router'), isEmpty);
      expect(index.isReady, isFalse);
    });

    test('builds once and serves fuzzy queries from the cache', () async {
      final index = WorkspaceFileIndex(fs: fs, root: root);
      await index.ensureFresh();
      expect(index.isReady, isTrue);
      expect(index.usedRustBackend, isFalse);

      // First query hits the same built index again without rebuilding.
      await index.ensureFresh();
      expect(index.size, greaterThan(0));

      final names = (await index.query(
        'router',
      )).map((m) => m.relativePath).toList();
      expect(
        names,
        containsAll(['lib/app_router.dart', 'lib/widgets/router_guard.dart']),
      );
      expect(names, isNot(contains('node_modules/pkg/router.dart')));
      expect(names.any((p) => p.startsWith('.git')), isFalse);
    });

    test(
      'ranks basename prefix matches above directory-only matches',
      () async {
        final index = WorkspaceFileIndex(fs: fs, root: root);
        await index.ensureFresh();
        final results = await index.query('router_guard');
        expect(results.first.relativePath, 'lib/widgets/router_guard.dart');
      },
    );

    test('fuzzy subsequence matches across path separators', () async {
      final index = WorkspaceFileIndex(fs: fs, root: root);
      await index.ensureFresh();
      // 'ppro' is a subsequence of 'lib/app_router.dart' but of nothing else
      // in the fixture.
      final results = await index.query('ppro');
      expect(results, hasLength(1));
      expect(results.single.name, 'app_router.dart');
    });

    test('contains mode matches file name case-insensitively', () async {
      final index = WorkspaceFileIndex(fs: fs, root: root);
      await index.ensureFresh();
      final names = (await index.query(
        'CHAT',
        mode: WorkspaceFileMatchMode.contains,
      )).map((m) => m.name).toList();
      expect(names, ['chat_cubit.dart']);
    });

    test('skips hidden entries even when queried by name', () async {
      final index = WorkspaceFileIndex(fs: fs, root: root);
      await index.ensureFresh();
      expect(await index.query('hidden'), isEmpty);
      expect(await index.query('.hidden'), isEmpty);
    });

    test('empty query yields no matches', () async {
      final index = WorkspaceFileIndex(fs: fs, root: root);
      await index.ensureFresh();
      expect(await index.query('   '), isEmpty);
    });

    test('caps fuzzy results at the limit', () async {
      for (var i = 0; i < 5; i++) {
        await fs.writeString('$root/match_$i.txt', '');
      }
      final index = WorkspaceFileIndex(
        fs: fs,
        root: root,
        limits: const WorkspaceFileSearchLimits(maxResults: 3),
      );
      await index.ensureFresh();
      expect(await index.query('match_'), hasLength(3));
    });

    test('invalidate drops the cache and rebuilds on demand', () async {
      final index = WorkspaceFileIndex(fs: fs, root: root);
      await index.ensureFresh();
      await fs.writeString('$root/lib/brand_new.dart', '');
      index.invalidate();
      await index.ensureFresh();
      expect(
        (await index.query('brand_new')).map((m) => m.relativePath),
        contains('lib/brand_new.dart'),
      );
    });

    test(
      'queryDirectories matches directory basenames for compose drilling',
      () async {
        final index = WorkspaceFileIndex(fs: fs, root: root);
        await index.ensureFresh();

        expect(
          await index.queryDirectories('widgets'),
          contains('lib/widgets'),
        );
        expect(await index.queryDirectories('widgets'), isNot(contains('lib')));

        // Blank query yields nothing.
        expect(await index.queryDirectories('   '), isEmpty);
        // Unbuilt index yields nothing.
        expect(
          await WorkspaceFileIndex(
            fs: fs,
            root: root,
          ).queryDirectories('widgets'),
          isEmpty,
        );
      },
    );

    test('resolves local roots on the worker isolate', () async {
      final dir = Directory.systemTemp.createTempSync('tp_ws_index_');
      addTearDown(() => dir.deleteSync(recursive: true));
      Directory('${dir.path}/lib').createSync();
      File('${dir.path}/lib/app_router.dart').writeAsStringSync('');
      File('${dir.path}/README.md').writeAsStringSync('');

      final index = WorkspaceFileIndex(fs: LocalFilesystem(), root: dir.path);
      addTearDown(index.dispose);
      await index.ensureFresh();
      expect(index.usedRustBackend, isTrue);

      final paths = (await index.query('router')).map((m) => m.relativePath);
      expect(paths, contains('lib/app_router.dart'));
      expect(await index.queryDirectories('lib'), contains('lib'));

      // Invalidation tears the worker down; the next build starts a fresh one.
      index.invalidate();
      await index.ensureFresh();
      expect(index.usedRustBackend, isTrue);
      expect(await index.query('readme'), isNotEmpty);
      // The rust backend reports its entry count too (not just the walk).
      expect(index.size, 2);
    });

    test('keeps serving the previous snapshot while it rebuilds', () async {
      final dir = Directory.systemTemp.createTempSync('tp_ws_index_swap_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/before.txt').writeAsStringSync('');

      final index = WorkspaceFileIndex(fs: LocalFilesystem(), root: dir.path);
      addTearDown(index.dispose);
      await index.ensureFresh();
      expect(await index.query('before'), isNotEmpty);

      var revision = 0;
      index.revision.addListener(() => revision++);

      File('${dir.path}/after.txt').writeAsStringSync('');
      final rebuild = index.refresh();
      // The rebuilt snapshot is swapped in only once the build finishes, so a
      // query issued meanwhile is answered by the previous index rather than
      // queueing behind (or racing) the rescan.
      expect(await index.query('before'), isNotEmpty);
      await rebuild;

      expect(await index.query('after'), isNotEmpty);
      expect(index.size, 2);
      expect(revision, greaterThan(0));
    });

    test('respects maxIndexEntries during the build walk', () async {
      await fs.writeString('$root/a/one.txt', '');
      await fs.writeString('$root/b/two.txt', '');
      final index = WorkspaceFileIndex(
        fs: fs,
        root: root,
        limits: const WorkspaceFileSearchLimits(maxIndexEntries: 2),
      );
      await index.ensureFresh();
      // The build walk stops after 2 entries scanned, so only a subset is
      // indexed — the query must not crash and must only see indexed files.
      final results = await index.query('txt');
      expect(results.length, lessThanOrEqualTo(2));
    });
  });

  group('fuzzyMatchScore', () {
    test('rejects non-subsequence queries', () {
      expect(fuzzyMatchScore('lib/app_router.dart', 'zzz'), -1);
      expect(fuzzyMatchScore('lib/app_router.dart', 'router'), isNot(-1));
    });

    test('prefers boundary-start and basename matches', () {
      final segmentBoundary = fuzzyMatchScore('lib/chat_cubit.dart', 'chat');
      final midWord = fuzzyMatchScore('lib/notch_at_bottom.dart', 'chat');
      expect(segmentBoundary, greaterThan(midWord));

      final basenamePrefix = fuzzyMatchScore('src/settings_page.dart', 'set');
      final deepMid = fuzzyMatchScore('settings/src/page.dart', 'set');
      expect(basenamePrefix, greaterThan(deepMid));
    });

    test('prefers consecutive runs over scattered matches', () {
      final consecutive = fuzzyMatchScore('lib/chat_cubit.dart', 'chat');
      final scattered = fuzzyMatchScore('lib/c_h_a_t.dart', 'chat');
      expect(consecutive, greaterThan(scattered));
    });
  });

  group('WorkspaceFileIndexRegistry', () {
    test('reuses the same index for the same root', () async {
      final fs = InMemoryFilesystem();
      const root = '/ws';
      await fs.writeString('$root/file_a.dart', '');

      final registry = WorkspaceFileIndexRegistry();
      final first = registry.indexFor(root, fs);
      final second = registry.indexFor(root, fs);
      expect(identical(first, second), isTrue);

      await first.ensureFresh();
      expect(await first.query('file_a'), hasLength(1));

      registry.remove(root);
      expect(identical(registry.indexFor(root, fs), first), isFalse);
    });
  });
}
