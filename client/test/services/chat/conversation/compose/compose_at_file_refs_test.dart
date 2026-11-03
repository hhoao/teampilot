import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_at_file_refs.dart';
import 'package:teampilot/services/chat/conversation/compose/compose_token_document.dart';
import 'package:teampilot/services/io/local_filesystem.dart';

import '../../../../support/post_frame_test_harness.dart';

void main() {
  group('composeAtFileRefsFromTokens', () {
    test('reads explicit file tokens and ignores other kinds', () {
      const tokens = [
        ComposeToken(
          id: '1',
          kind: ComposeTokenKind.fileReference,
          start: 0,
          end: 16,
          payload: '@src/main.dart',
        ),
        ComposeToken(
          id: '2',
          kind: ComposeTokenKind.skill,
          start: 17,
          end: 24,
          payload: '/commit',
        ),
        ComposeToken(
          id: '3',
          kind: ComposeTokenKind.fileReference,
          start: 25,
          end: 41,
          payload: '@src/main.dart',
        ),
      ];
      final refs = composeAtFileRefsFromTokens(
        tokens: tokens,
        workspaceRoot: '/repo',
        usesPosixPaths: false,
      );
      expect(refs.length, 1);
      expect(refs.single.absolutePath, '/repo/src/main.dart');
      expect(refs.single.displayName, 'main.dart');
    });

    test('typed @ text is not a reference', () {
      expect(
        composeAtFileRefsFromTokens(
          tokens: const [],
          workspaceRoot: '/repo',
          usesPosixPaths: false,
        ),
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
