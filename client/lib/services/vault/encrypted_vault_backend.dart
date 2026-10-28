import 'dart:convert';

import '../../models/vault_document.dart';
import '../../repositories/vault_repository.dart';
import 'credential_backend.dart';
import 'vault_crypto.dart';
import 'vault_errors.dart';

/// 可选后端：主密码加密的 `vault.json`。解锁后文档只驻留内存。
class EncryptedVaultBackend implements CredentialBackend {
  EncryptedVaultBackend({
    required VaultRepository repository,
    VaultCrypto crypto = const VaultCrypto(),
  }) : _repository = repository,
       _crypto = crypto;

  final VaultRepository _repository;
  final VaultCrypto _crypto;
  VaultDocument? _unlocked;

  /// 是否处于“锁定”状态（文件存在但尚未解锁）。
  ///
  /// 与“未初始化”（无文件）区分：`clear()` 归档文件后属于未初始化，
  /// 不需要解锁，因此单独维护该标志而不是用 `_unlocked == null` 推导。
  bool _locked = false;

  /// 主密码只在解锁后短期保留，`lock()` / `clear()` 时清空。
  String? _lastPassphrase;

  @override
  String get kind => 'encrypted';

  @override
  bool get needsUnlock => _locked;

  Future<bool> get isInitialized => _repository.exists();

  @override
  Future<VaultDocument?> load() async {
    final unlocked = _unlocked;
    if (unlocked != null) return unlocked;
    if (!await _repository.exists()) return null;
    throw const VaultLockedException();
  }

  Future<void> unlock(String passphrase) async {
    final raw = await _repository.readRaw();
    if (raw == null) {
      throw const VaultFormatException('vault file missing');
    }
    final VaultDocument document;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const VaultFormatException('not an object');
      document = await _crypto.decrypt(
        VaultEnvelope.fromJson(Map<String, Object?>.from(decoded)),
        passphrase,
      );
    } on VaultException {
      rethrow;
    } on Object {
      throw const VaultFormatException('unreadable vault file');
    }
    _unlocked = document;
    _locked = false;
    _lastPassphrase = passphrase;
  }

  Future<void> initialize(VaultDocument document, String passphrase) async {
    final envelope = await _crypto.encrypt(document, passphrase);
    await _repository.writeRaw(jsonEncode(envelope.toJson()));
    // 回读校验：解不开就不要把用户数据留在半成品文件里。
    final raw = await _repository.readRaw();
    if (raw == null) throw const VaultStorageException('vaultWriteFailed');
    final verified = await _crypto.decrypt(
      VaultEnvelope.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      ),
      passphrase,
    );
    if (verified.entries.length != document.entries.length) {
      throw const VaultStorageException('vaultVerifyFailed');
    }
    _unlocked = document;
    _locked = false;
    _lastPassphrase = passphrase;
  }

  @override
  Future<void> save(VaultDocument document) async {
    if (_unlocked == null) throw const VaultLockedException();
    final envelope = await _crypto.encrypt(document, _lastPassphrase!);
    await _repository.writeRaw(jsonEncode(envelope.toJson()));
    _unlocked = document;
  }

  void lock() {
    _unlocked = null;
    _locked = true;
    _lastPassphrase = null;
  }

  @override
  Future<void> clear() async {
    _unlocked = null;
    _locked = false;
    _lastPassphrase = null;
    await _repository.archive();
  }
}
