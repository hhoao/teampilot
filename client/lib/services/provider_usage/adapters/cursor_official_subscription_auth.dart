import '../../../models/managed_provider.dart';
import '../../cli/cursor/provider/cursor_home_layout.dart';
import '../../io/filesystem.dart';
import '../cli_credential_source.dart';
import '../managed_provider_usage_adapter.dart';
import 'official_credential_files.dart';

class CursorOfficialSubscriptionAuthReader
    implements OfficialSubscriptionAuthReader {
  CursorOfficialSubscriptionAuthReader({
    required Filesystem fs,
    required String basePath,
    CursorHomeLayout? layout,
  }) : _fs = fs,
       _basePath = basePath,
       _layout = layout ?? CursorHomeLayout(pathContext: fs.pathContext);

  final Filesystem _fs;
  final String _basePath;
  final CursorHomeLayout _layout;

  @override
  Future<ProviderCredentialScope?> read(ManagedProvider provider) async {
    final isolatedHome = _fs.pathContext.join(
      _basePath,
      'providers',
      'cursor',
      provider.id.trim(),
      'home',
    );
    for (final authPath in _layout.authJsonCandidates(isolatedHome)) {
      final tokens = await _cursorTokens(authPath, isolatedHome);
      if (tokens != null) {
        return ManagedProviderAccessTokenScope(
          accessToken: tokens.accessToken,
          accountId: tokens.userId,
        );
      }
    }
    missingOfficialCredential();
  }

  Future<({String accessToken, String? userId})?> _cursorTokens(
    String authPath,
    String home,
  ) async {
    final json = await readOfficialCredentialJson(_fs, authPath);
    final access = '${json?['accessToken'] ?? ''}'.trim();
    if (access.isEmpty) return null;
    final fromAuth = '${json?['userId'] ?? ''}'.trim();
    if (fromAuth.isNotEmpty) {
      return (accessToken: access, userId: fromAuth);
    }
    final cliConfig = await readOfficialCredentialJson(
      _fs,
      _layout.cliConfig(home),
    );
    final authInfo = cliConfig?['authInfo'];
    final fromCli = authInfo is Map ? '${authInfo['userId'] ?? ''}'.trim() : '';
    return (
      accessToken: access,
      userId: fromCli.isEmpty ? null : fromCli,
    );
  }
}
