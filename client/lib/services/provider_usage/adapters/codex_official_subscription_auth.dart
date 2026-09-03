import '../../../models/managed_provider.dart';
import '../../io/filesystem.dart';
import '../cli_credential_source.dart';
import '../managed_provider_usage_adapter.dart';
import 'official_credential_files.dart';

class CodexOfficialSubscriptionAuthReader
    implements OfficialSubscriptionAuthReader {
  CodexOfficialSubscriptionAuthReader({
    required Filesystem fs,
    required String basePath,
  }) : _fs = fs,
       _basePath = basePath;

  final Filesystem _fs;
  final String _basePath;

  @override
  Future<ProviderCredentialScope?> read(ManagedProvider provider) async {
    final path = _fs.pathContext.join(
      _basePath,
      'providers',
      'codex',
      provider.id.trim(),
      'auth.json',
    );
    final json = await readOfficialCredentialJson(_fs, path);
    final tokens = _codexTokens(json);
    if (tokens != null) {
      return ManagedProviderAccessTokenScope(
        accessToken: tokens.accessToken,
        accountId: tokens.accountId,
      );
    }
    missingOfficialCredential();
  }

  ({String accessToken, String? accountId})? _codexTokens(
    Map<String, Object?>? json,
  ) {
    if (json == null) return null;
    final mode = json['auth_mode']?.toString().trim();
    if (mode != null && mode.isNotEmpty && mode != 'chatgpt') return null;
    final rawTokens = json['tokens'];
    final tokens = rawTokens is Map
        ? rawTokens.map((key, value) => MapEntry(key.toString(), value))
        : const <String, Object?>{};
    final access = '${tokens['access_token'] ?? json['access_token'] ?? ''}'
        .trim();
    if (access.isEmpty) return null;
    final account = '${tokens['account_id'] ?? json['account_id'] ?? ''}'
        .trim();
    return (accessToken: access, accountId: account.isEmpty ? null : account);
  }
}
