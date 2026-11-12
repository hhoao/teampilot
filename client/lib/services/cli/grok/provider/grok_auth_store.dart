import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../../utils/logging/logger_utils.dart';
import '../../../io/filesystem.dart';
import '../grok_constants.dart';

/// Grok credential isolation.
///
/// Grok stores OAuth credentials in `$GROK_HOME/auth.json`. A per-session
/// `GROK_HOME` would therefore lose the user's login, so TeamPilot runs
/// `grok login` with an isolated `GROK_HOME`, copies the resulting `auth.json`
/// into a per-provider store, and seeds every session home from it (or from
/// `~/.grok/auth.json` when the provider row was never created). Sessions that
/// refresh their own token keep it until the provider store changes.
class GrokAuthStore {
  GrokAuthStore({
    required this.fs,
    required this.basePath,
    required this.pathContext,
    String? machineHome,
    this.namespace = GrokConstants.authNamespace,
    this.useMachineFallback = true,
  }) : machineHome =
           machineHome ??
           (Platform.environment['HOME'] ??
               Platform.environment['USERPROFILE'] ??
               '');

  final Filesystem fs;
  final String basePath;
  final p.Context pathContext;
  final String machineHome;

  /// Root segment for the login and provider stores (`cli-login/<ns>`,
  /// `providers/<ns>`).
  final String namespace;

  /// Whether an unconfigured provider may seed from `~/.grok/auth.json`.
  final bool useMachineFallback;

  static const authFileName = GrokConstants.authFileName;
  static const markerFileName = GrokConstants.authMarkerFileName;
  static const machineMarkerValue = 'machine';

  String loginRoot(String providerId) =>
      pathContext.join(basePath, 'cli-login', namespace, _safe(providerId));

  String loginHome(String providerId) =>
      pathContext.join(loginRoot(providerId), 'home');
  String loginConfigDir(String providerId) =>
      pathContext.join(loginRoot(providerId), 'config');
  String loginWorkspace(String providerId) =>
      pathContext.join(loginRoot(providerId), 'workspace');
  String loginAuthPath(String providerId) =>
      pathContext.join(loginConfigDir(providerId), authFileName);

  String providerAuthDir(String providerId) =>
      pathContext.join(basePath, 'providers', namespace, _safe(providerId));
  String providerAuthPath(String providerId) =>
      pathContext.join(providerAuthDir(providerId), authFileName);

  String get machineAuthPath =>
      pathContext.join(machineHome, '.grok', authFileName);

  /// Removes a previous attempt's isolated login auth, so the dialog only
  /// reports success for a login completed in this attempt.
  Future<void> clearLoginAuth(String providerId) async {
    for (final path in [
      loginAuthPath(providerId),
      '${loginAuthPath(providerId)}.lock',
    ]) {
      if ((await fs.stat(path)).exists) await fs.removeRecursive(path);
    }
  }

  Future<bool> hasLoginAuth(String providerId) async =>
      _isNonEmptyFile(fs, loginAuthPath(providerId));

  Future<bool> hasProviderAuth(String providerId) async =>
      _isNonEmptyFile(fs, providerAuthPath(providerId));

  /// Copies the isolated login's `auth.json` into the provider store.
  /// Returns false when the login did not complete.
  Future<bool> writeProviderAuthFromLogin(
    String providerId, {
    required String loginConfigDir,
  }) async {
    final source = pathContext.join(loginConfigDir, authFileName);
    final bytes = await fs.readBytes(source);
    if (bytes == null || bytes.isEmpty) return false;
    final target = providerAuthPath(providerId);
    await fs.ensureDir(pathContext.dirname(target));
    await fs.writeBytes(target, bytes);
    restrictFile(target);
    return true;
  }

  /// Imports the user's existing global `~/.grok/auth.json` into the provider
  /// store, so an already-signed-in machine keeps working under isolation.
  Future<bool> importMachineAuth(String providerId) async {
    final bytes = await fs.readBytes(machineAuthPath);
    if (bytes == null || bytes.isEmpty) return false;
    final target = providerAuthPath(providerId);
    await fs.ensureDir(pathContext.dirname(target));
    await fs.writeBytes(target, bytes);
    restrictFile(target);
    return true;
  }

  /// Seeds `<sessionConfigDir>/auth.json` from the provider store (or the
  /// machine login). The first seed records a marker fingerprint of the source
  /// bytes; a later seed keeps a session-refreshed copy while the marker
  /// matches, and reseeds when the provider store changed (re-login).
  Future<bool> seedSessionAuth({
    required String providerId,
    required Filesystem sessionFs,
    required p.Context sessionPathContext,
    required String sessionConfigDir,
  }) async {
    final target = sessionPathContext.join(sessionConfigDir, authFileName);
    final markerPath = sessionPathContext.join(
      sessionConfigDir,
      markerFileName,
    );
    final hasSessionAuth = await _isNonEmptyFile(sessionFs, target);
    final source = await authSourcePath(providerId);
    if (source == null) return hasSessionAuth;
    final sourceBytes = await fs.readBytes(source);
    if (sourceBytes == null || sourceBytes.isEmpty) return hasSessionAuth;
    final marker = _digest(sourceBytes);
    if (hasSessionAuth) {
      final existing = (await sessionFs.readString(markerPath))?.trim() ?? '';
      if (existing.isEmpty || existing == marker) return true;
    }
    await sessionFs.ensureDir(sessionConfigDir);
    await sessionFs.writeBytes(target, sourceBytes);
    await sessionFs.writeString(markerPath, marker);
    restrictFile(target);
    return true;
  }

  /// Path to the `auth.json` source: the per-provider store wins; otherwise
  /// the machine login. Null when neither exists.
  Future<String?> authSourcePath(String providerId) async {
    final providerPath = providerAuthPath(providerId);
    if (await _isNonEmptyFile(fs, providerPath)) return providerPath;
    if ((await fs.stat(providerAuthDir(providerId))).exists) {
      AppLogger.instance.w(
        'grok: provider "$providerId" auth is missing; '
        'not falling back to the machine login',
      );
      return null;
    }
    if (!useMachineFallback || machineHome.isEmpty) return null;
    final machine = machineAuthPath;
    return await _isNonEmptyFile(fs, machine) ? machine : null;
  }

  /// Best-effort `chmod 600` for a credential file copied to a real disk.
  void restrictFile(String path) => _restrict(path);

  static String _digest(List<int> bytes) =>
      sha256.convert(bytes).toString().substring(0, 16);

  static Future<bool> _isNonEmptyFile(Filesystem fs, String path) async {
    final stat = await fs.stat(path);
    if (!stat.isFile) return false;
    return (stat.size ?? 0) > 0 ||
        (await fs.readBytes(path))?.isNotEmpty == true;
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
