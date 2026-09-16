@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teampilot/services/connect/authorized_keys_file.dart';

import '../../support/in_memory_filesystem.dart';

void main() {
  late InMemoryFilesystem fs;
  late List<String> chmoded;
  late AuthorizedKeysFile keys;

  const home = '/home/alice';
  const keyA = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGZha2VrZXlh phone-a';
  const keyAComment = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGZha2VrZXlh other';
  const keyB = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGZha2VrZXli phone-b';

  setUp(() {
    fs = InMemoryFilesystem();
    chmoded = [];
    keys = AuthorizedKeysFile(
      fs: fs,
      homePath: home,
      chmod600: (path) async => chmoded.add(path),
    );
  });

  test('authorize creates the file, chmod 600, and appends the line', () async {
    await keys.authorize(keyA);
    expect(await fs.readString('$home/.ssh/authorized_keys'), '$keyA\n');
    expect(chmoded, ['$home/.ssh/authorized_keys']);
  });

  test('authorize is a no-op when the key blob is already present', () async {
    await fs.ensureDir('$home/.ssh');
    await fs.atomicWrite('$home/.ssh/authorized_keys', '$keyAComment\n');
    await keys.authorize(keyA);
    expect(await fs.readString('$home/.ssh/authorized_keys'), '$keyAComment\n');
    expect(chmoded, isEmpty);
  });

  test('revoke removes matching blobs and leaves others', () async {
    await fs.ensureDir('$home/.ssh');
    await fs.atomicWrite('$home/.ssh/authorized_keys', '$keyA\n$keyB\n');
    await keys.revoke(keyAComment);
    expect(await fs.readString('$home/.ssh/authorized_keys'), '$keyB\n');
    expect(chmoded, ['$home/.ssh/authorized_keys']);
  });

  test(
    'authorize throws on a malformed blob and leaves the file unchanged',
    () async {
      await fs.ensureDir('$home/.ssh');
      await fs.atomicWrite('$home/.ssh/authorized_keys', '$keyA\n');

      await expectLater(
        keys.authorize('ssh-ed25519 !!!not-base64!!! phone'),
        throwsA(isA<FormatException>()),
      );

      expect(await fs.readString('$home/.ssh/authorized_keys'), '$keyA\n');
      expect(chmoded, isEmpty);
    },
  );

  test('authorize throws when publicKey contains a newline', () async {
    await expectLater(
      keys.authorize('$keyA\nssh-ed25519 AAAA extra'),
      throwsA(isA<FormatException>()),
    );
    expect(await fs.readString('$home/.ssh/authorized_keys'), isNull);
  });
}
