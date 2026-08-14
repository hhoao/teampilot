import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot_search/src/fallback_search_engine.dart';
import 'package:teampilot_search/src/search_file_reader.dart';
import 'package:teampilot_search/teampilot_search.dart';

class MemoryReader implements SearchFileReader {
  MemoryReader(this.tree);

  /// path -> list of lines
  final Map<String, List<String>> tree;

  /// Paths that behave unreadable: `listDir` yields [] for directories,
  /// `readLines` yields null for files.
  Set<String> unreadable = {};

  @override
  Future<List<SearchDirEntry>> listDir(String path) async {
    if (unreadable.contains(path)) return [];
    final entries = <SearchDirEntry>[];
    final seen = <String>{};
    for (final p in tree.keys) {
      if (!p.startsWith('$path/')) continue;
      final rel = p.substring(path.length + 1);
      final parts = rel.split('/');
      if (parts.length == 1) {
        if (seen.add(p)) {
          entries.add(SearchDirEntry(name: parts[0], isDirectory: false, size: null));
        }
      } else {
        final dir = '$path/${parts[0]}';
        if (seen.add(dir)) {
          entries.add(SearchDirEntry(name: parts[0], isDirectory: true, size: null));
        }
      }
    }
    return entries;
  }

  @override
  Future<List<String>?> readLines(String path) async {
    if (unreadable.contains(path)) return null;
    final lines = tree[path];
    if (lines == null) return null;
    if (lines.any((l) => l.contains('\u0000'))) return null;
    return lines;
  }
}

void main() {
  late MemoryReader reader;

  setUp(() {
    reader = MemoryReader({
      '/root/a.dart': ['hello world', 'foo hello'],
      '/root/b.txt': ['no match'],
      '/root/sub/c.rs': ['HELLO upper'],
      '/root/.hidden/x.dart': ['hello hidden'],
      '/root/node_modules/pkg.js': ['hello dep'],
      '/root/build/out.js': ['hello build'],
      '/root/bin.dat': ['\u0000hello\u0000'],
    });
  });

  test('walks tree, skips hidden/ignored dirs, matches case-insensitive',
      () async {
    final matches = await fallbackSearch(
      reader,
      '/root',
      const TpSearchOptions(pattern: 'hello'),
    ).toList();
    expect(matches.map((m) => m.relativePath), ['a.dart', 'a.dart', 'sub/c.rs']);
  });

  test('regex + include/exclude globs + maxResults', () async {
    final matches = await fallbackSearch(
      reader,
      '/root',
      const TpSearchOptions(
        pattern: 'h[e]llo',
        filesToInclude: ['*.dart'],
        maxResults: 1,
      ),
    ).toList();
    expect(matches.length, 1);
    expect(matches.single.relativePath, 'a.dart');
  });

  test('smart case', () async {
    final matches = await fallbackSearch(
      reader,
      '/root',
      const TpSearchOptions(pattern: 'HELLO', smartCase: true),
    ).toList();
    expect(matches.single.relativePath, 'sub/c.rs');
  });

  test('binary file (NUL byte) skipped', () async {
    final matches = await fallbackSearch(
      reader,
      '/root',
      const TpSearchOptions(pattern: 'hello', filesToInclude: ['bin.dat']),
    ).toList();
    expect(matches, isEmpty);
  });

  test('unreadable file skipped, unreadable dir skipped', () async {
    final reader2 = MemoryReader({
      '/root/ok.dart': ['hello ok'],
      '/root/boom.dart': ['hello boom'],
    })..unreadable = {'/root/boom.dart', '/root/locked'};
    reader2.tree['/root/locked'] = ['hello locked'];
    final matches = await fallbackSearch(
      reader2,
      '/root',
      const TpSearchOptions(pattern: 'hello'),
    ).toList();
    expect(matches.map((m) => m.relativePath), ['ok.dart']);
  });

  test('invalid regex -> error event', () async {
    await expectLater(
      fallbackSearch(reader, '/root', const TpSearchOptions(pattern: '[unclosed')).toList(),
      throwsA(isA<FormatException>()),
    );
  });

  test('line too long -> match without text', () async {
    final huge = 'start${'x' * 2000000}end';
    final reader2 = MemoryReader({'/root/huge.txt': [huge]});
    final matches = await fallbackSearch(
      reader2,
      '/root',
      const TpSearchOptions(pattern: 'end'),
    ).toList();
    expect(matches.single.lineText, isEmpty);
  });
}
