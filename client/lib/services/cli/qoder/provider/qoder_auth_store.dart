import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../io/filesystem.dart';

/// Qoder credential isolation.
///
/// `qodercli` keeps its login inside `<QODER_CONFIG_DIR>/.auth`
/// (`user` + `machine_id`), so a fresh session config dir cannot
/// authenticate. TeamPilot runs the login with an isolated HOME/config and
/// copies both files into a per-provider store; each session config dir is
/// seeded from that store (or from `~/.qoder` when no provider account
/// exists).
class QoderAuthStore {
  QoderAuthStore({
    required this.fs,
    required this.basePath,
    required this.pathContext,
    String? machineHome,
  }) : machineHome = machineHome ??
            (Platform.environment['HOME'] ??
                Platform.environment['USERPROFILE'] ??
                '');

  final Filesystem fs;
  final String basePath;
  final p.Context pathContext;
  final String machineHome;

  static const configDirEnvKey = 'QODER_CONFIG_DIR';
  static const userFileName = 'user';
  static const machineIdFileName = 'machine_id';

  String loginRoot(String providerId) =>
      pathContext.join(basePath, 'cli-login', 'qoder', _safe(providerId));

  String loginHome(String providerId) =>
      pathContext.join(loginRoot(providerId), 'home');
  String loginConfigDir(String providerId) =>
      pathContext.join(loginRoot(providerId), 'config');
  String loginWorkspace(String providerId) =>
      pathContext.join(loginRoot(providerId), 'workspace');

  String providerAuthDir(String providerId) => pathContext.join(
    basePath,
    'providers',
    'qoder',
    _safe(providerId),
  );

  Future<bool> hasProviderAuth(String providerId) async {
    final dir = providerAuthDir(providerId);
    return (await fs.stat(pathContext.join(dir, userFileName))).isFile &&
        (await fs.stat(pathContext.join(dir, machineIdFileName))).isFile;
  }

  /// Copies the isolated login's `.auth/{user,machine_id}` into the provider
  /// store. Returns false when the login did not complete.
  Future<bool> writeProviderAuthFromLogin(
    String providerId, {
    required String loginConfigDir,
  }) async {
    final source = pathContext.join(loginConfigDir, '.auth');
    final target = providerAuthDir(providerId);
    for (final name in const [userFileName, machineIdFileName]) {
      if (!(await fs.stat(pathContext.join(source, name))).isFile) return false;
    }
    await fs.ensureDir(target);
    for (final name in const [userFileName, machineIdFileName]) {
      final dst = pathContext.join(target, name);
      await fs.copyFile(pathContext.join(source, name), dst);
      _restrict(dst);
    }
    return true;
  }

  /// Seeds `<sessionConfigDir>/.auth` so `session/new` can authenticate.
  Future<bool> seedSessionAuth({
    required String providerId,
    required String sessionConfigDir,
  }) async {
    final source = await hasProviderAuth(providerId)
        ? providerAuthDir(providerId)
        : pathContext.join(machineHome, '.qoder', '.auth');
    if (!(await fs.stat(pathContext.join(source, userFileName))).isFile) {
      return false;
    }
    final target = pathContext.join(sessionConfigDir, '.auth');
    await fs.ensureDir(target);
    for (final name in const [userFileName, machineIdFileName]) {
      final src = pathContext.join(source, name);
      if (!(await fs.stat(src)).isFile) continue;
      final dst = pathContext.join(target, name);
      await fs.copyFile(src, dst);
      _restrict(dst);
    }
    return true;
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
    return safe.isEmpty ? 'provider' : safe;
  }
}
