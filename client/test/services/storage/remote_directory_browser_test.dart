import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/services/io/filesystem.dart';
import 'package:teampilot/services/storage/remote_directory_browser.dart';

/// Minimal POSIX fake: lets a test set a `resolveSymlink('.')` home and a map of
/// directory contents. Only the methods [RemoteDirectoryBrowser] touches are
/// meaningful; the rest throw.
class _FakeFilesystem implements Filesystem {
  _FakeFilesystem({required this.home, required this.entries});

  final String home;

  /// dir path -> child entries.
  final Map<String, List<FsDirEntry>> entries;

  @override
  final p.Context pathContext = p.Context(style: p.Style.posix);

  @override
  Future<String?> resolveSymlink(String path) async =>
      path == '.' ? home : path;

  @override
  Future<FsStat> stat(String path) async {
    if (entries.containsKey(path)) {
      return const FsStat(kind: FsEntityKind.directory);
    }
    return const FsStat(kind: FsEntityKind.notFound);
  }

  @override
  Future<List<FsDirEntry>> listDir(String path) async =>
      entries[path] ?? const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  group('RemoteDirectoryBrowser.resolveInitial', () {
    late _FakeFilesystem fs;
    late RemoteDirectoryBrowser browser;

    setUp(() {
      fs = _FakeFilesystem(home: '/home/alice', entries: {});
      browser = RemoteDirectoryBrowser(fs);
    });

    test('empty input resolves to remote home via resolveSymlink(".")',
        () async {
      expect(await browser.resolveInitial(''), '/home/alice');
      expect(await browser.resolveInitial(null), '/home/alice');
    });

    test('"~" and "." resolve to remote home', () async {
      expect(await browser.resolveInitial('~'), '/home/alice');
      expect(await browser.resolveInitial('.'), '/home/alice');
    });

    test('"~/sub" expands against the resolved home', () async {
      expect(await browser.resolveInitial('~/work/ws'), '/home/alice/work/ws');
    });

    test('absolute posix path is normalized without Windows mangling',
        () async {
      expect(await browser.resolveInitial('/srv//data/'), '/srv/data');
      expect(await browser.resolveInitial('/a/b/../c'), '/a/c');
    });
  });

  group('RemoteDirectoryBrowser.list', () {
    test('returns only directories, sorted, parent computed', () async {
      final fs = _FakeFilesystem(
        home: '/home/alice',
        entries: {
          '/home/alice': const [
            FsDirEntry(name: 'zeta', isDirectory: true),
            FsDirEntry(name: 'Alpha', isDirectory: true),
            FsDirEntry(name: 'readme.md', isDirectory: false),
            FsDirEntry(name: 'mid', isDirectory: true),
          ],
        },
      );
      final browser = RemoteDirectoryBrowser(fs);

      final listing = await browser.list('/home/alice');
      expect(listing.path, '/home/alice');
      expect(listing.parent, '/home');
      expect(listing.directories, ['Alpha', 'mid', 'zeta']);
    });

    test('hidden directories excluded by default, included when asked',
        () async {
      final fs = _FakeFilesystem(
        home: '/root',
        entries: {
          '/root': const [
            FsDirEntry(name: '.git', isDirectory: true),
            FsDirEntry(name: 'src', isDirectory: true),
          ],
        },
      );
      final browser = RemoteDirectoryBrowser(fs);

      expect((await browser.list('/root')).directories, ['src']);
      expect(
        (await browser.list('/root', includeHidden: true)).directories,
        ['.git', 'src'],
      );
    });

    test('parent is null at the filesystem root', () async {
      final fs = _FakeFilesystem(
        home: '/',
        entries: {
          '/': const [FsDirEntry(name: 'etc', isDirectory: true)],
        },
      );
      final browser = RemoteDirectoryBrowser(fs);

      final listing = await browser.list('/');
      expect(listing.parent, isNull);
      expect(listing.directories, ['etc']);
    });

    test('throws when the path is not a directory', () async {
      final fs = _FakeFilesystem(home: '/home', entries: {});
      final browser = RemoteDirectoryBrowser(fs);

      expect(
        () => browser.list('/nope'),
        throwsA(isA<RemoteDirectoryBrowserException>()),
      );
    });

    test('child joins with backend path semantics', () {
      final fs = _FakeFilesystem(home: '/home', entries: {});
      final browser = RemoteDirectoryBrowser(fs);
      expect(browser.child('/home/alice', 'work'), '/home/alice/work');
    });
  });
}
