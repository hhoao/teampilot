import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../../utils/logging/logger_utils.dart';
import '../../../io/filesystem.dart';

/// Qoder credential isolation.
///
/// `qodercli` keeps its login inside `<QODER_CONFIG_DIR>/.auth`
/// (`user` + `machine_id`), so a fresh session config dir cannot
/// authenticate. TeamPilot runs the login with an isolated HOME/config and
/// copies both files into a per-provider store; each session config dir is
/// seeded from that store (or from `~/.qoder` when the provider row was never
/// created). An already seeded session keeps its own refreshed copy unless the
/// recorded source fingerprint shows the provider store changed (re-login).
class QoderAuthStore {
  QoderAuthStore({
    required this.fs,
    required this.basePath,
    required this.pathContext,
    String? machineHome,
  }) : machineHome =
           machineHome ??
           (Platform.environment['HOME'] ??
               Platform.environment['USERPROFILE'] ??
               '');

  final Filesystem fs;
  final String basePath;
  final p.Context pathContext;
  final String machineHome;

  static const userFileName = 'user';
  static const machineIdFileName = 'machine_id';

  /// Fingerprint of the source files that seeded a session `.auth`. Compared
  /// on later seeds so a re-login (new source bytes) reseeds while an
  /// in-session token refresh of the session copy is preserved.
  static const markerFileName = '.qoder-provider';

  /// Marker prefix used when the machine `~/.qoder` login was the source.
  static const machineMarkerValue = 'machine';

  /// Removes a previous attempt's isolated login `.auth`, so the dialog only
  /// reports success for a login completed in this attempt.
  Future<void> clearLoginAuth(String providerId) async {
    final authDir = pathContext.join(loginConfigDir(providerId), '.auth');
    if ((await fs.stat(authDir)).exists) await fs.removeRecursive(authDir);
  }

  /// Best-effort `chmod 600` for a credential file copied to a real disk.
  void restrictFile(String path) => _restrict(path);

  String loginRoot(String providerId) =>
      pathContext.join(basePath, 'cli-login', 'qoder', _safe(providerId));

  String loginHome(String providerId) =>
      pathContext.join(loginRoot(providerId), 'home');
  String loginConfigDir(String providerId) =>
      pathContext.join(loginRoot(providerId), 'config');
  String loginWorkspace(String providerId) =>
      pathContext.join(loginRoot(providerId), 'workspace');

  String providerAuthDir(String providerId) =>
      pathContext.join(basePath, 'providers', 'qoder', _safe(providerId));

  Future<bool> hasProviderAuth(String providerId) =>
      _hasAuthPair(providerAuthDir(providerId));

  /// Copies the isolated login's `.auth/{user,machine_id}` into the provider
  /// store. Returns false when the login did not complete.
  Future<bool> writeProviderAuthFromLogin(
    String providerId, {
    required String loginConfigDir,
  }) async {
    final source = pathContext.join(loginConfigDir, '.auth');
    if (!await _hasAuthPair(source)) return false;
    final target = providerAuthDir(providerId);
    await fs.ensureDir(target);
    await _copyAuth(source, target);
    return true;
  }

  /// Seeds `<sessionConfigDir>/.auth` from [authSourceDir].
  ///
  /// The first seed records a [markerFileName] fingerprint of the source
  /// bytes. Later seeds keep the session copy when the marker matches (a
  /// scoped login may have refreshed it) or when no marker exists
  /// (legacy/preexisting session). A different marker means the provider store
  /// changed (re-login or provider switch) and is reseeded.
  Future<bool> seedSessionAuth({
    required String providerId,
    required String sessionConfigDir,
  }) async {
    final target = pathContext.join(sessionConfigDir, '.auth');
    final hasSessionAuth = await _hasAuthPair(target);
    final source = await authSourceDir(providerId);
    if (source == null) return hasSessionAuth;
    final marker = await markerFor(providerId: providerId, sourceDir: source);
    if (hasSessionAuth) {
      final existing = await _readMarker(target);
      if (existing == null || existing == marker) return true;
    }
    await fs.ensureDir(target);
    await _copyAuth(source, target);
    await _writeMarker(target, marker);
    return true;
  }

  /// Directory holding BOTH `.auth` files for [providerId].
  ///
  /// The per-provider store wins when it is complete; otherwise the machine
  /// login `~/.qoder/.auth`. Null when neither holds the pair — a partial
  /// provider row never falls back to the machine login — or when the home is
  /// unknown.
  Future<String?> authSourceDir(String providerId) async {
    final providerDir = providerAuthDir(providerId);
    if ((await fs.stat(providerDir)).exists) {
      if (await _hasAuthPair(providerDir)) return providerDir;
      AppLogger.instance.w(
        'qoder: provider "$providerId" auth is incomplete; '
        'not falling back to the machine login',
      );
      return null;
    }
    if (machineHome.isEmpty) return null;
    final machineAuth = pathContext.join(machineHome, '.qoder', '.auth');
    return await _hasAuthPair(machineAuth) ? machineAuth : null;
  }

  /// Marker value for a seed sourced from [sourceDir].
  ///
  /// `<providerId>:<sha256-12>` for the provider store, `machine:<sha256-12>`
  /// for the machine fallback. Hashing the source bytes means a re-login on
  /// the same provider row changes the marker and reseeds existing sessions.
  Future<String> markerFor({
    required String providerId,
    required String sourceDir,
  }) async {
    final digest = await _sourceFingerprint(sourceDir);
    final id = providerId.trim();
    if (id.isEmpty || sourceDir != providerAuthDir(providerId)) {
      return '$machineMarkerValue:$digest';
    }
    return '$id:$digest';
  }

  Future<String> _sourceFingerprint(String authDir) async {
    final bytes = <int>[];
    for (final name in const [userFileName, machineIdFileName]) {
      bytes.addAll(
        await fs.readBytes(pathContext.join(authDir, name)) ?? const <int>[],
      );
      // Separator so moving bytes between the two files changes the digest.
      bytes.add(0);
    }
    return sha256.convert(bytes).toString().substring(0, 12);
  }

  Future<String?> _readMarker(String authDir) async {
    final raw = await fs.readString(pathContext.join(authDir, markerFileName));
    final value = raw?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  Future<void> _writeMarker(String authDir, String marker) =>
      fs.writeString(pathContext.join(authDir, markerFileName), marker);

  Future<bool> _hasAuthPair(String dir) async =>
      (await fs.stat(pathContext.join(dir, userFileName))).isFile &&
      (await fs.stat(pathContext.join(dir, machineIdFileName))).isFile;

  Future<void> _copyAuth(String source, String target) async {
    for (final name in const [userFileName, machineIdFileName]) {
      final dst = pathContext.join(target, name);
      await fs.copyFile(pathContext.join(source, name), dst);
      _restrict(dst);
    }
  }

  void _restrict(String path) {
    if (Platform.isWindows) return;
    try {
      if (!File(path).existsSync()) return;
      Process.runSync('chmod', ['600', path]);
    } on Object {
      // Best effort.
    }
  }

  static String _safe(String value) {
    final safe = value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (safe.isEmpty || safe == '.' || safe == '..') return 'provider';
    return safe;
  }
}
