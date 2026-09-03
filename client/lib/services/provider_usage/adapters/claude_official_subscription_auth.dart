import '../../../models/managed_provider.dart';
import '../../io/filesystem.dart';
import '../managed_provider_usage_adapter.dart';
import 'official_credential_files.dart';
import '../cli_credential_source.dart';

class ClaudeOfficialSubscriptionAuthReader
    implements OfficialSubscriptionAuthReader {
  ClaudeOfficialSubscriptionAuthReader({
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
      'claude',
      provider.id.trim(),
      '.credentials.json',
    );
    final json = await readOfficialCredentialJson(_fs, path);
    final token = _claudeAccessToken(json);
    if (token != null) {
      return ManagedProviderAccessTokenScope(accessToken: token);
    }
    missingOfficialCredential();
  }

  String? _claudeAccessToken(Map<String, Object?>? json) {
    final oauth = json?['claudeAiOauth'];
    if (oauth is! Map) return null;
    final token = '${oauth['accessToken'] ?? ''}'.trim();
    return token.isEmpty ? null : token;
  }
}
