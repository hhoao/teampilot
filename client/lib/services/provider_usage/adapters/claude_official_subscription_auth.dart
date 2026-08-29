import '../../../models/managed_provider.dart';
import '../../io/filesystem.dart';
import '../managed_provider_secret_store.dart';
import 'official_credential_files.dart';
import '../cli_credential_source.dart';

class ClaudeOfficialSubscriptionAuthReader
    implements OfficialSubscriptionAuthReader {
  ClaudeOfficialSubscriptionAuthReader({
    required Filesystem fs,
    required String basePath,
    required String Function() homeDirectory,
  }) : _fs = fs,
       _basePath = basePath,
       _homeDirectory = homeDirectory;

  final Filesystem _fs;
  final String _basePath;
  final String Function() _homeDirectory;

  @override
  Future<ProviderCredentialScope?> read(ManagedProvider provider) async {
    final paths = [
      _fs.pathContext.join(
        _basePath,
        'providers',
        'claude',
        'claude-official',
        '.credentials.json',
      ),
      _fs.pathContext.join(
        _homeDirectory().trim(),
        '.claude',
        '.credentials.json',
      ),
    ];
    for (final path in paths) {
      final json = await readOfficialCredentialJson(_fs, path);
      final token = _claudeAccessToken(json);
      if (token != null) {
        return ManagedProviderAccessTokenScope(accessToken: token);
      }
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
