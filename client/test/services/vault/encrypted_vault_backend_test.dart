import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/models/vault_document.dart';
import 'package:teampilot/models/vault_entry.dart';
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/vault/encrypted_vault_backend.dart';
import 'package:teampilot/services/vault/vault_crypto.dart';
import 'package:teampilot/services/vault/vault_errors.dart';
import '../../support/in_memory_filesystem.dart';

const _document = VaultDocument(
  entries: [VaultEntry(id: '1', type: VaultEntryType.token, title: 't')],
);

void main() {
  const crypto = VaultCrypto(memoryKiB: 256, iterations: 1, parallelism: 1);

  EncryptedVaultBackend buildBackend(InMemoryFilesystem fs) =>
      EncryptedVaultBackend(
        repository: VaultRepository(rootDir: '/root/vault', fs: fs),
        crypto: crypto,
      );

  test('needs initialization before any file exists', () async {
    final backend = buildBackend(
      InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix)),
    );
    expect(await backend.isInitialized, isFalse);
    expect(await backend.load(), isNull);
  });

  test('initialize writes an unlockable file', () async {
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    final backend = buildBackend(fs);

    await backend.initialize(_document, 'pass');
    expect(await backend.isInitialized, isTrue);
    expect(backend.needsUnlock, isFalse);

    backend.lock();
    expect(backend.needsUnlock, isTrue);
    await expectLater(backend.load(), throwsA(isA<VaultLockedException>()));

    await backend.unlock('pass');
    expect(backend.needsUnlock, isFalse);
    expect(await backend.load(), _document);
  });

  test('save updates the file only after unlock', () async {
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    final backend = buildBackend(fs);
    await backend.initialize(_document, 'pass');

    const next = VaultDocument(
      entries: [VaultEntry(id: '2', type: VaultEntryType.login, title: 'x')],
    );
    await backend.save(next);
    backend.lock();
    await backend.unlock('pass');
    expect((await backend.load())?.entries.single.id, '2');
  });

  test('clear archives the file so the backend becomes uninitialized', () async {
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    final backend = buildBackend(fs);
    await backend.initialize(_document, 'pass');
    await backend.clear();
    expect(await backend.isInitialized, isFalse);
    expect(backend.needsUnlock, isFalse);
  });
}
