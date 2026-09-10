@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:test/test.dart';
import 'package:tp_sshd/tp_sshd.dart';

import 'dual_test_utils.dart';
import 'memory_sftp_filesystem.dart';

void main() {
  late MemorySftpFileSystem fs;

  setUp(() => fs = MemorySftpFileSystem());

  Future<(SSHClient, SSHServer)> connect() => startDualPair(
        hostKeyPair: testHostKey,
        authenticate: (_) async => true,
        clientIdentities: [testDeviceKey],
        sftpFileSystem: fs,
      );

  test('subsystem request for sftp is served when a filesystem is configured',
      () async {
    final (client, server) = await connect();
    final controller = await openClientSessionChannel(client);
    expect(await controller.sendSubsystem('sftp'), isTrue);

    client.close();
    await server.close();
  });

  test('subsystem request for an unknown name is refused', () async {
    final (client, server) = await connect();
    final controller = await openClientSessionChannel(client);
    expect(await controller.sendSubsystem('not-sftp'), isFalse);

    client.close();
    await server.close();
  });

  test('mkdir / write / read / stat / list round trip', () async {
    final (client, server) = await connect();
    final sftp = await client.sftp();
    await sftp.mkdir('/demo');
    final file = await sftp.open(
      '/demo/hello.txt',
      mode: SftpFileOpenMode.write | SftpFileOpenMode.create,
    );
    await file.writeBytes(Uint8List.fromList('hello tp_sshd'.codeUnits));
    await file.close();

    final attrs = await sftp.stat('/demo/hello.txt');
    expect(attrs.size, 13);

    final reader = await sftp.open('/demo/hello.txt');
    final readBack = await reader.readBytes();
    await reader.close();
    expect(String.fromCharCodes(readBack), 'hello tp_sshd');

    final names = await sftp.listdir('/demo');
    expect(names.map((n) => n.filename), contains('hello.txt'));
    client.close();
    await server.close();
  });

  test('rename, remove, rmdir', () async {
    final (client, server) = await connect();
    final sftp = await client.sftp();
    await sftp.mkdir('/a');
    final f = await sftp.open(
      '/a/x',
      mode: SftpFileOpenMode.write | SftpFileOpenMode.create,
    );
    await f.writeBytes(Uint8List.fromList([1, 2, 3]));
    await f.close();
    await sftp.rename('/a/x', '/a/y');
    await sftp.remove('/a/y');
    await sftp.rmdir('/a');
    await expectLater(sftp.stat('/a/y'), throwsA(anything));
    client.close();
    await server.close();
  });

  test('missing file returns SSH_FX_NO_SUCH_FILE status, not a crash',
      () async {
    final (client, server) = await connect();
    final sftp = await client.sftp();
    await expectLater(sftp.stat('/nope'), throwsA(isA<SftpStatusError>()));
    client.close();
    await server.close();
  });

  // The in-memory listing is one-shot and returns the whole directory in a
  // single batch, so a directory big enough to encode over the 256 KiB SFTP
  // packet limit forces the server to page: every NAME packet must stay
  // under the limit (the fork's client destroys the channel otherwise), and
  // the client's listdir loop must still see every entry across the batches
  // until the EOF status ends it.
  test(
      'large directory is served as multiple READDIR batches under the packet limit',
      () async {
    const entryCount = 6000;
    fs.createDirectory('/big');
    for (var i = 0; i < entryCount; i++) {
      fs.createFile('/big/dir-entry-$i');
    }
    // The whole-directory NAME packet would be far over the limit; without
    // paging the channel dies and listdir never completes.
    final (client, server) = await connect();
    final sftp = await client.sftp();
    final names = await sftp.listdir('/big');
    // A set both checks membership cheaply and, compared against the raw
    // count, proves no entry was served twice across the batches.
    final filenames = names.map((n) => n.filename).toSet();
    expect(names.length, entryCount + 2);
    expect(filenames.length, entryCount + 2);
    expect(filenames, containsAll(const ['.', '..']));
    for (var i = 0; i < entryCount; i++) {
      expect(filenames, contains('dir-entry-$i'));
    }
    client.close();
    await server.close();
  });
}
