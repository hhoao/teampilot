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
}
