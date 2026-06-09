import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/file_tree/project_file_search.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  group('searchProjectFiles', () {
    late InMemoryFilesystem fs;
    const root = '/project';

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

    test('matches file names case-insensitively across subdirectories', () async {
      final result = await searchProjectFiles(
        fs: fs,
        root: root,
        query: 'ROUTER',
      );

      final names = result.matches.map((m) => m.name).toList();
      expect(names, containsAll(['app_router.dart', 'router_guard.dart']));
      expect(result.truncated, isFalse);
    });

    test('skips ignored directories and hidden entries', () async {
      final result = await searchProjectFiles(
        fs: fs,
        root: root,
        query: 'router',
      );

      final paths = result.matches.map((m) => m.path).toList();
      expect(paths, isNot(contains('$root/node_modules/pkg/router.dart')));
      expect(paths.any((p) => p.contains('/.git/')), isFalse);
    });

    test('does not match hidden files even by name', () async {
      final result = await searchProjectFiles(
        fs: fs,
        root: root,
        query: 'hidden',
      );
      expect(result.matches, isEmpty);
    });

    test('returns relative paths from the search root', () async {
      final result = await searchProjectFiles(
        fs: fs,
        root: root,
        query: 'router_guard',
      );
      expect(result.matches.single.relativePath, 'lib/widgets/router_guard.dart');
    });

    test('empty query yields no matches', () async {
      final result = await searchProjectFiles(fs: fs, root: root, query: '  ');
      expect(result.matches, isEmpty);
      expect(result.truncated, isFalse);
    });

    test('flags truncation when result cap is reached', () async {
      for (var i = 0; i < 5; i++) {
        await fs.writeString('$root/match_$i.txt', '');
      }
      final result = await searchProjectFiles(
        fs: fs,
        root: root,
        query: 'match_',
        limits: const ProjectFileSearchLimits(maxResults: 3),
      );
      expect(result.matches, hasLength(3));
      expect(result.truncated, isTrue);
    });
  });
}
