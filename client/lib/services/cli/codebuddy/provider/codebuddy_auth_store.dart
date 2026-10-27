import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../io/filesystem.dart';

/// CodeBuddy credential isolation for TeamPilot.
///
/// The CLI stores its login at
///
/// * Linux:   `<home>/.local/share/CodeBuddyExtension/Data/Public/auth/*.info`
/// * macOS:   `<home>/Library/Application Support/CodeBuddyExtension/...`
/// * Windows: `<home>/AppData/Local/CodeBuddyExtension/...`
///
/// (`home` is `os.homedir()`, not `CODEBUDDY_CONFIG_DIR`.) TeamPilot therefore
/// runs the login TUI with an **isolated HOME** and copies the resulting
/// access token into a per-provider store; sessions get
/// `CODEBUDDY_AUTH_TOKEN` from that store, so the user's global CLI login is
/// neither read nor overwritten.
class CodebuddyAuthStore {
  CodebuddyAuthStore({
    required this.fs,
    required this.basePath,
    required this.pathContext,
  });

  final Filesystem fs;
  final String basePath;
  final p.Context pathContext;

  static const apiKeyEnvKey = 'CODEBUDDY_AUTH_TOKEN';

  /// Per-provider login home: each account keeps its own CLI login state, so
  /// multiple provider rows can hold different accounts without re-entering
  /// credentials on every switch.
  String loginRoot(String providerId) => pathContext.join(
    basePath,
    'cli-login',
    'codebuddy',
    _safeSegment(providerId),
  );

  String loginHome(String providerId) =>
      pathContext.join(loginRoot(providerId), 'home');
  String loginConfigDir(String providerId) =>
      pathContext.join(loginRoot(providerId), 'config');
  String loginWorkspace(String providerId) =>
      pathContext.join(loginRoot(providerId), 'workspace');

  String providerAuthPath(String providerId) => pathContext.join(
    basePath,
    'providers',
    'codebuddy',
    '${_safeSegment(providerId)}.auth.json',
  );

  /// Reads the access token from this provider's isolated login home.
  /// Picks the newest `*.info` under the auth directory.
  Future<Map<String, Object?>?> readLoginAuth(String providerId) async {
    final dir = authDirIn(loginHome(providerId));
    final stat = await fs.stat(dir);
    if (!stat.isDirectory) return null;
    final entries = await fs.listDir(dir);
    ({Map<String, Object?> auth, DateTime? mtime})? newest;
    for (final entry in entries) {
      if (entry.isDirectory || !entry.name.endsWith('.info')) continue;
      final path = pathContext.join(dir, entry.name);
      final parsed = await _readAuthFile(path);
      if (parsed == null) continue;
      final mtime = (await fs.stat(path)).mtime;
      if (newest == null ||
          (mtime != null &&
              (newest.mtime == null || mtime.isAfter(newest.mtime!)))) {
        newest = (auth: parsed, mtime: mtime);
      }
    }
    return newest?.auth;
  }

  /// Creates the per-provider login home/config/workspace and pre-trusts the
  /// workspace, so a fresh CLI boot shows the login flow instead of an
  /// interactive trust prompt.
  Future<void> ensureLoginWorkspace(String providerId) async {
    final workspace = loginWorkspace(providerId);
    final configDir = loginConfigDir(providerId);
    await fs.ensureDir(loginHome(providerId));
    await fs.ensureDir(configDir);
    await fs.ensureDir(workspace);

    final settingsPath = pathContext.join(configDir, 'settings.json');
    var settings = <String, Object?>{};
    final raw = await fs.readString(settingsPath);
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          settings = decoded.map(
            (key, value) => MapEntry(key.toString(), value),
          );
        }
      } on FormatException {
        // Corrupt login settings are replaced below.
      }
    }
    final rawTrusted = settings['trustedDirectories'];
    final trusted = <String>{
      if (rawTrusted is List)
        for (final entry in rawTrusted)
          if (entry.toString().trim().isNotEmpty) entry.toString(),
      workspace,
    };
    settings['trustedDirectories'] = trusted.toList(growable: false);
    await fs.atomicWrite(
      settingsPath,
      const JsonEncoder.withIndent('  ').convert(settings),
    );
  }

  Future<Map<String, Object?>?> readProviderAuth(String providerId) =>
      _readAuthFile(providerAuthPath(providerId));

  /// Copies only what sessions need out of the CLI's auth document.
  Future<bool> writeProviderAuth(
    String providerId,
    Map<String, Object?> login,
  ) async {
    final auth = (login['auth'] as Map?)?.cast<String, Object?>() ?? const {};
    final accessToken = auth['accessToken']?.toString().trim() ?? '';
    if (accessToken.isEmpty) return false;
    final account =
        (login['account'] as Map?)?.cast<String, Object?>() ?? const {};
    final payload = <String, Object?>{
      'accessToken': accessToken,
      'expiresAt': auth['expiresAt'],
      'refreshToken': auth['refreshToken'],
      'domain': auth['domain'],
      'accountNickname': account['nickname'],
    };
    final path = providerAuthPath(providerId);
    await fs.ensureDir(pathContext.dirname(path));
    await fs.atomicWrite(path, jsonEncode(payload));
    _restrictPermissions(path);
    return true;
  }

  /// Valid access token for a provider, or null when missing/expired.
  String? accessTokenFor(Map<String, Object?>? auth) {
    final token = auth?['accessToken']?.toString().trim() ?? '';
    if (token.isEmpty) return null;
    final expiresAt = (auth?['expiresAt'] as num?)?.toInt() ?? 0;
    if (expiresAt > 0) {
      final millis = expiresAt > 1000000000000 ? expiresAt : expiresAt * 1000;
      if (DateTime.now().millisecondsSinceEpoch >= millis - 60 * 1000) {
        return null;
      }
    }
    return token;
  }

  /// Auth directory the CLI uses under [home] on this platform.
  String authDirIn(String home) {
    final extensionRoot = Platform.isMacOS
        ? pathContext.join(
            home,
            'Library',
            'Application Support',
            'CodeBuddyExtension',
          )
        : Platform.isWindows
        ? pathContext.join(home, 'AppData', 'Local', 'CodeBuddyExtension')
        : pathContext.join(home, '.local', 'share', 'CodeBuddyExtension');
    return pathContext.join(extensionRoot, 'Data', 'Public', 'auth');
  }

  Future<Map<String, Object?>?> _readAuthFile(String path) async {
    final raw = await fs.readString(path);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.cast<String, Object?>();
      }
    } on FormatException {
      // Not the credential file.
    }
    return null;
  }

  static String _safeSegment(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return safe.isEmpty ? 'provider' : safe;
  }

  void _restrictPermissions(String path) {
    if (Platform.isWindows) return;
    try {
      if (!File(path).existsSync()) return;
      Process.runSync('chmod', ['600', path]);
    } on Object {
      // Best effort: the app-data dir is already user-scoped.
    }
  }
}
