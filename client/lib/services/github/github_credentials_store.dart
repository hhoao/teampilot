import '../../repositories/ssh_credential_store.dart';
import '../../utils/logging/logger_utils.dart';
import '../vault/credential_capture.dart';
import '../vault/vault_service.dart';
import '../vault/vault_unlock_gate.dart';
import 'github_http.dart';

enum GithubCredentialSource { oauth, pat }

class GithubCredentialsSnapshot {
  const GithubCredentialsSnapshot({
    required this.token,
    this.login,
    this.source,
  });

  final String token;
  final String? login;
  final GithubCredentialSource? source;
}

/// Secure storage for GitHub credentials (OAuth and PAT).
class GithubCredentialsStore {
  GithubCredentialsStore({
    required SecureKeyValueStore kv,
    String? Function()? readEnvToken,
    VaultService? vault,
    VaultCredentialCapture? vaultCapture,
    Future<bool> Function()? ensureVaultUnlocked,
  }) : assert(vaultCapture == null || vault != null),
       _kv = kv,
       _readEnvToken = readEnvToken ?? readGithubTokenFromEnvironment,
       _vault = vault,
       _vaultCapture = vaultCapture,
       _ensureVaultUnlocked = ensureVaultUnlocked;

  static const _tokenKey = 'teampilot.github.v1.token';
  static const _loginKey = 'teampilot.github.v1.login';
  static const _sourceKey = 'teampilot.github.v1.source';
  static const _vaultEntryKey = 'teampilot.github.v1.vault_entry';
  static const _legacyTokenKey = 'teampilot.hub_publish.v1.github_token';

  final SecureKeyValueStore _kv;
  final String? Function() _readEnvToken;
  final VaultService? _vault;
  final VaultCredentialCapture? _vaultCapture;
  final Future<bool> Function()? _ensureVaultUnlocked;
  var _legacyMigrated = false;

  Future<void> saveOAuth({required String token, required String login}) async {
    if (await _captureVault(
      token: token,
      login: login,
      source: GithubCredentialSource.oauth.name,
    )) {
      return;
    }
    await _kv.write(_tokenKey, token);
    await _kv.write(_loginKey, login);
    await _kv.write(_sourceKey, GithubCredentialSource.oauth.name);
  }

  Future<void> savePat(String token, {String? login}) async {
    if (await _captureVault(
      token: token,
      login: login ?? '',
      source: GithubCredentialSource.pat.name,
    )) {
      return;
    }
    await _kv.write(_tokenKey, token);
    await _kv.write(_sourceKey, GithubCredentialSource.pat.name);
    if (login != null) {
      await _kv.write(_loginKey, login);
    } else {
      await _kv.delete(_loginKey);
    }
  }

  Future<bool> _captureVault({
    required String token,
    required String login,
    required String source,
  }) async {
    final capture = _vaultCapture;
    if (capture == null) return false;
    final unlock = _ensureVaultUnlocked;
    if (unlock != null && !await unlock()) {
      throw const VaultSaveBlockedException();
    }
    final result = await capture.captureGithub(
      token: token,
      login: login,
      source: source,
    );
    try {
      await _kv.write(_vaultEntryKey, result.entryId);
    } on Object {
      try {
        await capture.rollback(result);
      } on Object catch (error, stackTrace) {
        AppLogger.instance.w(
          '[vault] github capture rollback failed: ${error.runtimeType}',
          stackTrace: stackTrace,
        );
      }
      rethrow;
    }
    await _clearLegacy();
    return true;
  }

  /// Vault entry id this store points at, or null when no pointer is stored.
  Future<String?> storedVaultEntryId() async {
    final pointer = (await _kv.read(_vaultEntryKey))?.trim() ?? '';
    return pointer.isEmpty ? null : pointer;
  }

  /// Deletes the legacy plaintext token keys without touching the vault entry.
  ///
  /// Used by the one-shot importer to drop a copy left behind by a partial
  /// pass once the vault pointer is known to resolve.
  Future<void> clearLegacyCopy() async {
    await _clearLegacy();
  }

  Future<void> clearStored() async {
    final pointer = (await _kv.read(_vaultEntryKey))?.trim() ?? '';
    if (pointer.isNotEmpty && _vault != null) {
      final unlock = _ensureVaultUnlocked;
      if (unlock != null && !await unlock()) {
        throw const VaultSaveBlockedException();
      }
      await _vault.delete(pointer);
    }
    await _kv.delete(_vaultEntryKey);
    await _clearLegacy();
  }

  Future<GithubCredentialsSnapshot?> readStored() async {
    await migrateLegacyHubPublishTokenIfNeeded();

    final pointer = (await _kv.read(_vaultEntryKey))?.trim() ?? '';
    if (pointer.isNotEmpty) {
      try {
        final entry = await _vault?.get(pointer);
        if (entry != null) {
          final token = entry.fields['token'] ?? '';
          if (token.isEmpty) return null;
          final sourceRaw = entry.fields['source'];
          final login = entry.fields['login'] ?? '';
          return GithubCredentialsSnapshot(
            token: token,
            login: login.isEmpty ? null : login,
            source: _parseSource(sourceRaw),
          );
        }
      } on Object {
        // Locked or unavailable vault: fall through to the legacy keys.
      }
    }

    final token = await _kv.read(_tokenKey);
    if (token == null || token.isEmpty) return null;
    await _migrateLegacyTokenToVault(token);
    return _legacySnapshot();
  }

  /// Stored token first; otherwise env vars for CI/dev automation.
  Future<String?> resolveToken() async {
    final stored = await readStored();
    if (stored != null && stored.token.isNotEmpty) return stored.token;
    return _readEnvToken();
  }

  Future<void> migrateLegacyHubPublishTokenIfNeeded() async {
    if (_legacyMigrated) return;

    final pointer = (await _kv.read(_vaultEntryKey))?.trim() ?? '';
    if (pointer.isNotEmpty) {
      final vault = _vault;
      if (vault == null) {
        _legacyMigrated = true;
        return;
      }
      try {
        final entry = await vault.get(pointer);
        if (entry != null) {
          // A resolvable vault entry is authoritative; the legacy hub token is
          // a superseded duplicate.
          await _kv.delete(_legacyTokenKey);
          _legacyMigrated = true;
          return;
        }
      } on Object {
        // Locked/unavailable: keep the legacy token for a later pass.
        return;
      }
    }

    final vault = _vault;
    if (vault != null && !vault.isUnlocked) return;

    final legacy = await _kv.read(_legacyTokenKey);
    if (legacy == null || legacy.isEmpty) {
      _legacyMigrated = true;
      return;
    }

    final existing = await _kv.read(_tokenKey);
    if (existing == null || existing.isEmpty) {
      await savePat(legacy);
    }
    await _kv.delete(_legacyTokenKey);
    _legacyMigrated = true;
  }

  Future<void> _migrateLegacyTokenToVault(String token) async {
    final capture = _vaultCapture;
    final vault = _vault;
    if (capture == null || vault == null || !vault.isUnlocked) return;
    try {
      final login = await _kv.read(_loginKey) ?? '';
      final source = await _kv.read(_sourceKey) ?? '';
      final result = await capture.captureGithub(
        token: token,
        login: login,
        source: source,
      );
      await _kv.write(_vaultEntryKey, result.entryId);
    } on Object catch (error, stackTrace) {
      AppLogger.instance.w(
        '[vault] github migration deferred: ${error.runtimeType}',
        stackTrace: stackTrace,
      );
    }
  }

  Future<GithubCredentialsSnapshot?> _legacySnapshot() async {
    final token = await _kv.read(_tokenKey);
    if (token == null || token.isEmpty) return null;

    final login = await _kv.read(_loginKey);
    final sourceRaw = await _kv.read(_sourceKey);
    return GithubCredentialsSnapshot(
      token: token,
      login: login?.isEmpty == true ? null : login,
      source: _parseSource(sourceRaw),
    );
  }

  Future<void> _clearLegacy() async {
    await _kv.delete(_tokenKey);
    await _kv.delete(_loginKey);
    await _kv.delete(_sourceKey);
  }

  GithubCredentialSource? _parseSource(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return GithubCredentialSource.values.asNameMap()[raw];
  }
}
