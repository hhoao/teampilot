import '../../../models/managed_provider.dart';
import '../../cli/cursor/provider/cursor_home_layout.dart';
import '../../io/filesystem.dart';
import '../cli_credential_source.dart';
import '../managed_provider_secret_store.dart';
import 'official_credential_files.dart';

class CursorOfficialSubscriptionAuthReader
    implements OfficialSubscriptionAuthReader {
  CursorOfficialSubscriptionAuthReader({
    required Filesystem fs,
    required String basePath,
    required String Function() homeDirectory,
    CursorHomeLayout? layout,
  }) : _fs = fs,
       _basePath = basePath,
       _homeDirectory = homeDirectory,
       _layout = layout ?? CursorHomeLayout(pathContext: fs.pathContext);

  final Filesystem _fs;
  final String _basePath;
  final String Function() _homeDirectory;
  final CursorHomeLayout _layout;

  @override
  Future<ProviderCredentialScope?> read(ManagedProvider provider) async {
    final isolatedHome = _fs.pathContext.join(
      _basePath,
      'providers',
      'cursor',
      'cursor-account',
      'home',
    );
    final globalHome = _homeDirectory().trim();
    final searches = <({String authPath, String home})>[
      for (final path in _layout.authJsonCandidates(isolatedHome))
        (authPath: path, home: isolatedHome),
      if (globalHome.isNotEmpty)
        for (final path in _layout.globalAuthJsonCandidates(globalHome))
          (authPath: path, home: globalHome),
    ];
    final seen = <String>{};
    for (final search in searches) {
      if (!seen.add(search.authPath)) continue;
      final tokens = await _cursorTokens(search.authPath, search.home);
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
