import '../../repositories/ssh_credential_store.dart';
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
  }) : _kv = kv,
       _readEnvToken = readEnvToken ?? readGithubTokenFromEnvironment;

  static const _tokenKey = 'teampilot.github.v1.token';
  static const _loginKey = 'teampilot.github.v1.login';
  static const _sourceKey = 'teampilot.github.v1.source';
  static const _legacyTokenKey = 'teampilot.hub_publish.v1.github_token';

  final SecureKeyValueStore _kv;
  final String? Function() _readEnvToken;
  var _legacyMigrated = false;

  Future<void> saveOAuth({required String token, required String login}) async {
    await _kv.write(_tokenKey, token);
    await _kv.write(_loginKey, login);
    await _kv.write(_sourceKey, GithubCredentialSource.oauth.name);
  }

  Future<void> savePat(String token, {String? login}) async {
    await _kv.write(_tokenKey, token);
    await _kv.write(_sourceKey, GithubCredentialSource.pat.name);
    if (login != null) {
      await _kv.write(_loginKey, login);
    } else {
      await _kv.delete(_loginKey);
    }
  }

  Future<void> clearStored() async {
    await _kv.delete(_tokenKey);
    await _kv.delete(_loginKey);
    await _kv.delete(_sourceKey);
  }

  Future<GithubCredentialsSnapshot?> readStored() async {
    await migrateLegacyHubPublishTokenIfNeeded();

    final token = await _kv.read(_tokenKey);
    if (token == null || token.isEmpty) return null;

    final login = await _kv.read(_loginKey);
    final sourceRaw = await _kv.read(_sourceKey);
    final source = _parseSource(sourceRaw);

    return GithubCredentialsSnapshot(
      token: token,
      login: login?.isEmpty == true ? null : login,
      source: source,
    );
  }

  /// Stored token first; otherwise env vars for CI/dev automation.
  Future<String?> resolveToken() async {
    final stored = await readStored();
    if (stored != null && stored.token.isNotEmpty) return stored.token;
    return _readEnvToken();
  }

  Future<void> migrateLegacyHubPublishTokenIfNeeded() async {
    if (_legacyMigrated) return;

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

  GithubCredentialSource? _parseSource(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return GithubCredentialSource.values.asNameMap()[raw];
  }
}
