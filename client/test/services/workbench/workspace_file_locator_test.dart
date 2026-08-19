import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/workbench/workspace_file_locator.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  const locator = WorkspaceFileLocator();

  test('relative path hits the first search base that contains the file', () async {
    final fs = InMemoryFilesystem()
      ..files['/session/src/foo.dart'] = 'session'
      ..files['/workspace/src/foo.dart'] = 'workspace';

    final found = await locator.locate(
      rawPath: 'src/foo.dart',
      fs: fs,
      searchBases: const ['/session', '/workspace'],
    );

    expect(found, '/session/src/foo.dart');
  });

  test('falls back to a later search base when missing in earlier ones', () async {
    final fs = InMemoryFilesystem()..files['/workspace/src/foo.dart'] = 'ok';

    final found = await locator.locate(
      rawPath: 'src/foo.dart',
      fs: fs,
      searchBases: const ['/session', '/workspace'],
    );

    expect(found, '/workspace/src/foo.dart');
  });

  test('absolute path is used as-is when it exists', () async {
    final fs = InMemoryFilesystem()..files['/abs/path.dart'] = 'ok';

    final found = await locator.locate(
      rawPath: '/abs/path.dart',
      fs: fs,
      searchBases: const ['/session'],
    );

    expect(found, '/abs/path.dart');
  });

  test('missing path returns null', () async {
    final fs = InMemoryFilesystem();

    final found = await locator.locate(
      rawPath: 'missing.dart',
      fs: fs,
      searchBases: const ['/session', '/workspace'],
    );

    expect(found, isNull);
  });
}
