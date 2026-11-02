import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../utils/logging/logger_utils.dart';
import '../../../io/filesystem.dart';

/// Qoder credential isolation.
///
/// `qodercli` keeps its login inside `<QODER_CONFIG_DIR>/.auth`
/// (`user` + `machine_id`), so a fresh session config dir cannot
/// authenticate. TeamPilot runs the login with an isolated HOME/config and
/// copies both files into a per-provider store; each session config dir is
/// seeded once from that store (or from `~/.qoder` when the provider row was
/// never created). An already seeded session keeps its own refreshed copy.
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

  /// Seeds `<sessionConfigDir>/.auth` so `session/new` can authenticate.
  ///
  /// An already seeded session keeps its copy: a scoped login may have
  /// refreshed it after materialization. A partial provider row never falls
  /// back to the machine login — that would silently switch accounts.
  Future<bool> seedSessionAuth({
    required String providerId,
    required String sessionConfigDir,
  }) async {
    final target = pathContext.join(sessionConfigDir, '.auth');
    if (await _hasAuthPair(target)) return true;
    final source = await _seedSource(providerId);
    if (source == null) return false;
    await fs.ensureDir(target);
    await _copyAuth(source, target);
    return true;
  }

  Future<String?> _seedSource(String providerId) async {
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
