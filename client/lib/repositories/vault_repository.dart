import '../services/io/filesystem.dart';
import '../services/storage/home_storage.dart';

/// `<root>/vault/vault.json` 的读写。
///
/// 设备本地保险库用固定 root + fs（`deviceLocalVaultRepository`）；远端业务
/// 保险库用 [VaultRepository.forHome]，其 root/fs 在每次访问时从 [HomeStorage]
/// 现取，因此 home plane 切换后自动指向新主机的 `vault/`。
class VaultRepository {
  VaultRepository({
    required String rootDir,
    required Filesystem fs,
    this.fileName = 'vault.json',
  }) : _rootOverride = rootDir,
       _fsOverride = fs,
       _storage = null;

  /// Home-plane business vault. Uses a distinct filename so it never collides
  /// with the device-local `vault.json` when the home plane falls back to the
  /// native app-data root.
  VaultRepository.forHome(
    HomeStorage storage, {
    this.fileName = 'business.json',
  }) : _rootOverride = null,
       _fsOverride = null,
       _storage = storage;

  final String? _rootOverride;
  final Filesystem? _fsOverride;
  final HomeStorage? _storage;
  final String fileName;

  String get _root => _rootOverride ?? _storage!.paths.vaultDir;
  Filesystem get _fs => _fsOverride ?? _storage!.fs;

  String get vaultFile => _fs.pathContext.join(_root, fileName);
  String get backupFile => _fs.pathContext.join(_root, '$fileName.bak');

  Future<bool> exists() async => (await _fs.stat(vaultFile)).isFile;

  Future<String?> readRaw() async {
    if (!await exists()) return null;
    return _fs.readString(vaultFile);
  }

  Future<void> writeRaw(String content) async {
    await _fs.ensureDir(_root);
    await _fs.atomicWrite(vaultFile, content);
  }

  /// 停用加密后端时把文件移到 `.bak`，保留最近一次可恢复副本。
  Future<void> archive() async {
    if (!await exists()) return;
    final backupExists = (await _fs.stat(backupFile)).isFile;
    if (backupExists) await _fs.removeRecursive(backupFile);
    await _fs.rename(vaultFile, backupFile);
  }
}
