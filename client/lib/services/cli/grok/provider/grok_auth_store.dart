import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../io/filesystem.dart';
import '../grok_constants.dart';

/// Grok login-home and provider-directory path helpers.
///
/// Credentials themselves are owned by `OAuthCredentialAuthority`: ACP seats
/// receive a lease through `GrokCredentialAdapter` and headless one-shots
/// receive an access-token-only `auth.json`. This class only locates the
/// isolated login and provider directories.
class GrokAuthStore {
  GrokAuthStore({
    required this.fs,
    required this.basePath,
    required this.pathContext,
    String? machineHome,
    this.namespace = GrokConstants.authNamespace,
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

  static const authFileName = GrokConstants.authFileName;

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

  /// Best-effort `chmod 600` for a credential file copied to a real disk.
  void restrictFile(String path) => _restrict(path);

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
