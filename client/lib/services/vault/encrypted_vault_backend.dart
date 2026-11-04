import 'dart:convert';
import 'dart:typed_data';

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

  /// 主密码派生出的密钥只在解锁期间驻留内存；锁定/停用时清空。
  ///
  /// 每个保存操作复用该密钥，避免每次写入都重跑 Argon2id（~1s/次）。
  Uint8List? _key;
  Uint8List? _salt;

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
    final Uint8List key;
    final VaultEnvelope envelope;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const VaultFormatException('not an object');
      envelope = VaultEnvelope.fromJson(Map<String, Object?>.from(decoded));
      key = await _crypto.deriveKey(passphrase, envelope.salt);
      document = await _crypto.decryptWithKey(envelope, key);
    } on VaultException {
      rethrow;
    } on Object {
      throw const VaultFormatException('unreadable vault file');
    }
    _unlocked = document;
    _locked = false;
    _key = key;
    _salt = envelope.salt;
  }

  Future<void> initialize(VaultDocument document, String passphrase) async {
    final salt = VaultCrypto.newSalt();
    final key = await _crypto.deriveKey(passphrase, salt);
    final envelope = await _crypto.encryptWithKey(document, key, salt);
    await _repository.writeRaw(jsonEncode(envelope.toJson()));
    // 回读校验：解不开就不要把用户数据留在半成品文件里。
    final raw = await _repository.readRaw();
    if (raw == null) throw const VaultStorageException('vaultWriteFailed');
    final verified = await _crypto.decryptWithKey(
      VaultEnvelope.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      ),
      key,
    );
    if (verified.entries.length != document.entries.length) {
      throw const VaultStorageException('vaultVerifyFailed');
    }
    _unlocked = document;
    _locked = false;
    _key = key;
    _salt = salt;
  }

  @override
  Future<void> save(VaultDocument document) async {
    if (_unlocked == null) throw const VaultLockedException();
    final key = _key;
    final salt = _salt;
    if (key == null || salt == null) {
      throw const VaultLockedException();
    }
    final envelope = await _crypto.encryptWithKey(document, key, salt);
    await _repository.writeRaw(jsonEncode(envelope.toJson()));
    _unlocked = document;
  }

  void lock() {
    _unlocked = null;
    _locked = true;
    _key = null;
    _salt = null;
  }

  @override
  Future<void> clear() async {
    _unlocked = null;
    _locked = false;
    _key = null;
    _salt = null;
    await _repository.archive();
  }
}
