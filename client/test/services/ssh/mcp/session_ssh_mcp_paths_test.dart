import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/ssh/mcp/session_ssh_mcp_paths.dart';

void main() {
  const folder = '/home/alice/proj';
  const folders = [folder];

  group('resolveSessionSshMcpRemoteCwd', () {
    test('uses first folder when cwd is null', () {
      expect(
        resolveSessionSshMcpRemoteCwd(cwd: null, folderPaths: folders),
        folder,
      );
    });

    test('uses first folder when cwd is empty', () {
      expect(
        resolveSessionSshMcpRemoteCwd(cwd: '  ', folderPaths: folders),
        folder,
      );
    });

    test('resolves relative cwd against first folder', () {
      expect(
        resolveSessionSshMcpRemoteCwd(cwd: 'src', folderPaths: folders),
        '/home/alice/proj/src',
      );
    });

    test('allows absolute cwd under folder', () {
      expect(
        resolveSessionSshMcpRemoteCwd(
          cwd: '/home/alice/proj/src',
          folderPaths: folders,
        ),
        '/home/alice/proj/src',
      );
    });

    test('denies parent escape via ..', () {
      expect(
        resolveSessionSshMcpRemoteCwd(
          cwd: '/home/alice/proj/../secret',
          folderPaths: folders,
        ),
        isNull,
      );
    });

    test('returns null when folderPaths is empty', () {
      expect(
        resolveSessionSshMcpRemoteCwd(cwd: '/home/alice/proj', folderPaths: []),
        isNull,
      );
      expect(resolveSessionSshMcpRemoteCwd(cwd: null, folderPaths: []), isNull);
    });
  });

  group('sessionSshMcpRemotePathAllowed', () {
    test('allows absolute path under folder', () {
      expect(
        sessionSshMcpRemotePathAllowed(
          '/home/alice/proj/src/file.txt',
          folders,
        ),
        isTrue,
      );
    });

    test('denies parent escape via ..', () {
      expect(
        sessionSshMcpRemotePathAllowed('/home/alice/proj/../secret', folders),
        isFalse,
      );
    });

    test('rejects relative remote path', () {
      expect(sessionSshMcpRemotePathAllowed('src/file.txt', folders), isFalse);
    });

    test('denies when folderPaths is empty', () {
      expect(
        sessionSshMcpRemotePathAllowed('/home/alice/proj/file.txt', []),
        isFalse,
      );
    });
  });

  group('sessionSshMcpLocalPathAllowed', () {
    const roots = ['/mnt/c/Users/dev/repo'];

    test('allows path under root with usesPosixPaths true', () {
      expect(
        sessionSshMcpLocalPathAllowed(
          '/mnt/c/Users/dev/repo/src/main.dart',
          roots,
          usesPosixPaths: true,
        ),
        isTrue,
      );
    });

    test('denies path outside root', () {
      expect(
        sessionSshMcpLocalPathAllowed(
          '/mnt/c/Users/dev/other/file.txt',
          roots,
          usesPosixPaths: true,
        ),
        isFalse,
      );
    });
  });

  test('sessionSshMcpPosixQuote escapes single quotes', () {
    expect(sessionSshMcpPosixQuote("foo'bar"), contains(r"'\''"));
  });
}
