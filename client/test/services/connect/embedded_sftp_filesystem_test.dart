@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/protocol.dart' show SftpFileAttrs, SftpFileOpenMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tp_sshd/tp_sshd.dart';

import 'package:teampilot/services/connect/embedded_sftp_filesystem.dart';

void main() {
  late Directory root;
  late EmbeddedSftpFilesystem sftp;

  setUp(() {
    root = Directory.systemTemp.createTempSync('tp_sftp');
    sftp = EmbeddedSftpFilesystem(pathContext: p.posix, homePath: root.path);
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('realpath resolves . and .. lexically', () async {
    expect(await sftp.realpath('/a/../b/./c'), '/b/c');
  });

  test('stat/openFile round trip with sizes and modes', () async {
    File(p.join(root.path, 'f.txt')).writeAsStringSync('hello');
    final attrs = await sftp.stat(p.join(root.path, 'f.txt'));
    expect(attrs.size, 5);
    expect(attrs.isFile, isTrue);
  });

  test('openFile write/read at offsets', () async {
    final handle = await sftp.openFile(
      p.join(root.path, 'w.bin'),
      SftpFileOpenMode.write | SftpFileOpenMode.create,
      null,
    );
    await handle.write(0, Uint8List.fromList([1, 2, 3]));
    await handle.write(6, Uint8List.fromList([7]));
    await handle.close();
    final reader = await sftp.openFile(
      p.join(root.path, 'w.bin'),
      SftpFileOpenMode.read,
      null,
    );
    expect(await reader.read(0, 3), [1, 2, 3]);
    expect(await reader.read(4, 3), [0, 0, 7]);
    await reader.close();
  });

  test('openFile exclusive on existing path throws FileExists', () {
    File(p.join(root.path, 'e')).writeAsStringSync('');
    expect(
      sftp.openFile(
        p.join(root.path, 'e'),
        SftpFileOpenMode.create | SftpFileOpenMode.exclusive,
        null,
      ),
      throwsA(isA<SftpFileExistsException>()),
    );
  });

  test('openFile without create on missing path throws NoSuchFile', () {
    expect(
      sftp.openFile(p.join(root.path, 'missing'), SftpFileOpenMode.read, null),
      throwsA(isA<SftpNoSuchFileException>()),
    );
  });

  test('mkdir/rmdir/unlink/rename and the typed errno mapping', () async {
    final dir = p.join(root.path, 'd');
    await sftp.mkdir(dir, SftpFileAttrs());
    await expectLater(
      sftp.mkdir(dir, SftpFileAttrs()),
      throwsA(isA<SftpFileExistsException>()),
    );
    await expectLater(
      sftp.unlink(dir),
      throwsA(isA<SftpFileSystemException>()), // is a directory
    );
    await sftp.rmdir(dir);
    await expectLater(sftp.stat(dir), throwsA(isA<SftpNoSuchFileException>()));
  });

  test('openDir lists entries with names and attrs', () async {
    File(p.join(root.path, 'a')).writeAsStringSync('x');
    Directory(p.join(root.path, 'b')).createSync();
    final listing = await sftp.openDir(root.path);
    final names = await listing.read();
    expect(names.map((n) => n.filename), containsAll(['a', 'b']));
    expect(names.firstWhere((n) => n.filename == 'b').attr.isDirectory, isTrue);
    expect(await listing.read(), isEmpty); // exhausted
    await listing.close();
  });

  test(
    'windows context: leading-slash resolves under home, drive paths pass through',
    () async {
      final win = EmbeddedSftpFilesystem(
        pathContext: p.windows,
        homePath: r'C:\Users\u',
      );
      expect(win.resolveForTest(r'/docs/x'), r'C:\Users\u\docs\x');
      expect(win.resolveForTest(r'C:/temp/x'), r'C:\temp\x');
    },
  );
}
