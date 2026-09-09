import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/compose/compose_at_file_refs.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

import '../../support/post_frame_test_harness.dart';

void main() {
  group('parseComposeAtFileRefs', () {
    test('parses relative and absolute @ refs', () {
      final refs = parseComposeAtFileRefs(
        'see @src/main.dart and @/tmp/Attachments/a.png please',
        workspaceRoot: '/repo',
                                           usesPosixPaths: false,
      );
      expect(refs.map((r) => r.absolutePath).toList(), [
        '/repo/src/main.dart',
        '/tmp/Attachments/a.png',
      ]);
      expect(refs.map((r) => r.displayName).toList(), [
        'main.dart',
        'a.png',
      ]);
    });

    test('ignores /skill tokens and email-like @', () {
      final refs = parseComposeAtFileRefs(
        'user@host /commit @docs/readme.md',
        workspaceRoot: '/repo',
                                           usesPosixPaths: false,
      );
      expect(refs.single.absolutePath, '/repo/docs/readme.md');
    });

    test('dedupes by path key keeping first order', () {
      final refs = parseComposeAtFileRefs(
        '@src/a.dart hello @src/a.dart @src/b.dart',
        workspaceRoot: '/repo',
                                           usesPosixPaths: false,
      );
      expect(refs.map((r) => r.displayName).toList(), ['a.dart', 'b.dart']);
    });

    test('empty or skills-only yields empty', () {
      expect(
        parseComposeAtFileRefs('/commit /review', workspaceRoot: '/repo', usesPosixPaths: false, ),
        isEmpty,
      );
    });
  });

  group('filesystemForComposeAtFileOpen', () {
    test('Attachments path uses LocalFilesystem', () {
      final fs = filesystemForComposeAtFileOpen(
        '/home/user/Documents/TeamPilot/Attachments/paste.png',
        workspaceFilesystem: LocalFilesystem(),
      );
      expect(fs, isA<LocalFilesystem>());
    });

    test('workspace path uses the provided workspace filesystem', () {
      setUpTestAppStorage();
      addTearDown(tearDownTestAppStorage);

      final fs = filesystemForComposeAtFileOpen(
        '/repo/src/a.dart',
        workspaceFilesystem: testHomeStorage.fs,
      );
      expect(fs, same(testHomeStorage.fs));
    });
  });
}
