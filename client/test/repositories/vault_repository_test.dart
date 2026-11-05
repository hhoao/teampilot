import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:teampilot/repositories/vault_repository.dart';
import 'package:teampilot/services/storage/app_paths.dart';
import '../support/in_memory_filesystem.dart';

void main() {
  test('app paths expose the vault file and backup', () {
    final paths = AppPaths('/root');
    expect(paths.vaultDir, p.join('/root', 'vault'));
    expect(paths.vaultFile, p.join('/root', 'vault', 'vault.json'));
    expect(
      paths.vaultBackupFile,
      p.join('/root', 'vault', 'vault.json.bak'),
    );
  });

  test('writes atomically and archives to the backup path', () async {
    final fs = InMemoryFilesystem(pathContext: p.Context(style: p.Style.posix));
    final repo = VaultRepository(rootDir: '/root/vault', fs: fs);

    expect(await repo.exists(), isFalse);
    await repo.writeRaw('{"v":1}');
    expect(await repo.exists(), isTrue);
    expect(await repo.readRaw(), '{"v":1}');

    await repo.archive();
    expect(await repo.exists(), isFalse);
    expect(await fs.readString(p.join('/root/vault', 'vault.json.bak')),
        '{"v":1}');
  });
}
