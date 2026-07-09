import '../../repositories/ssh_credential_store.dart';
import '../github/github_http.dart';

/// Secure storage for GitHub tokens used by Hub publish flows.
class HubPublishCredentialsStore {
  HubPublishCredentialsStore({
    required SecureKeyValueStore kv,
    String? Function()? readEnvToken,
  }) : _kv = kv,
       _readEnvToken = readEnvToken ?? readGithubTokenFromEnvironment;

  static const _tokenKey = 'teampilot.hub_publish.v1.github_token';

  final SecureKeyValueStore _kv;
  final String? Function() _readEnvToken;

  Future<String?> readToken() => _kv.read(_tokenKey);

  Future<void> saveToken(String token) => _kv.write(_tokenKey, token);

  Future<void> clearToken() => _kv.delete(_tokenKey);

  /// Stored token first; otherwise env vars for CI/dev automation.
  Future<String?> resolveToken() async {
    final stored = await readToken();
    if (stored != null && stored.isNotEmpty) return stored;
    // CI/dev fallback when no token saved in secure storage.
    return _readEnvToken();
  }
}
