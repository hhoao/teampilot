import '../services/io/filesystem.dart';

/// `<root>/vault/vault.json` 的读写。
///
/// 始终使用设备本地 root（见 `deviceLocalVaultRepository`），因此这里直接
/// 接收 root + fs，不依赖 HomeStorage。
class VaultRepository {
  VaultRepository({required String rootDir, required Filesystem fs})
    : _root = rootDir,
      _fs = fs;

  final String _root;
  final Filesystem _fs;

  String get vaultFile => _fs.pathContext.join(_root, 'vault.json');
  String get backupFile => _fs.pathContext.join(_root, 'vault.json.bak');

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
