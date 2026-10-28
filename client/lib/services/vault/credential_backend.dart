// client/lib/services/vault/credential_backend.dart
import '../../models/vault_document.dart';

abstract interface class CredentialBackend {
  String get kind;
  bool get needsUnlock;

  /// 无文档返回 null；存在但锁定抛 [VaultLockedException]。
  Future<VaultDocument?> load();

  Future<void> save(VaultDocument document);

  /// 删除（钥匙串）或归档（加密文件）本后端持有的文档。
  Future<void> clear();
}
