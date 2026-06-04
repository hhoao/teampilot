import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../models/ssh_profile.dart';
import '../../models/windows_storage_backend.dart';
import 'app_storage.dart';
import '../io/filesystem.dart';
import '../io/local_filesystem.dart';
import '../io/sftp_filesystem.dart';
import '../io/wsl_filesystem.dart';
import 'remote_file_store.dart';
import 'remote_ssh_storage_paths.dart';
import '../ssh/ssh_client_factory.dart';

enum StorageBackendMode { native, wsl, ssh }

/// Resolved storage backend for all TeamPilot business file I/O.
///
/// Install once at startup via [install]; read globally via [AppStorage].
class RuntimeStorageContext {
  RuntimeStorageContext._({
    required this.mode,
    required this.filesystem,
    required this.home,
    required this.cwd,
    required this.appDataRoot,
    required this.paths,
  });

  final StorageBackendMode mode;
  final Filesystem filesystem;
  final String home;
  final String cwd;
  final String appDataRoot;
  final AppPaths paths;

  bool get usesPosixPaths =>
      mode == StorageBackendMode.wsl || mode == StorageBackendMode.ssh;

  static RuntimeStorageContext? _current;
  static String? _cachedWslHome;
  static String? _cachedWslDistroKey;

  static RuntimeStorageContext get current {
    final ctx = _current;
    if (ctx == null) {
      throw StateError(
        'RuntimeStorageContext.install() must be called before using AppStorage.',
      );
    }
    return ctx;
  }

  static bool get isInstalled => _current != null;

  static Future<RuntimeStorageContext> install({
    required bool isSshMode,
    SshProfile? sshProfile,
    SshClientFactory? sshClientFactory,
    RemoteSshStoragePathResolver? remotePathResolver,
    required String nativeAppDataPath,
    String? nativeHome,
    String? nativeCwd,
    String? wslDistro,
    WindowsStorageBackend? windowsStorageBackend,
  }) async {
    final ctx = await resolve(
      isSshMode: isSshMode,
      sshProfile: sshProfile,
      sshClientFactory: sshClientFactory,
      remotePathResolver: remotePathResolver,
      nativeAppDataPath: nativeAppDataPath,
      nativeHome: nativeHome,
      nativeCwd: nativeCwd,
      wslDistro: wslDistro,
      windowsStorageBackend: windowsStorageBackend,
    );
    _current = ctx;
    AppPathsBootstrapper.syncPaths(ctx.paths);
    return ctx;
  }

  static Future<RuntimeStorageContext> resolve({
    required bool isSshMode,
    SshProfile? sshProfile,
    SshClientFactory? sshClientFactory,
    RemoteSshStoragePathResolver? remotePathResolver,
    required String nativeAppDataPath,
    String? nativeHome,
    String? nativeCwd,
    String? wslDistro,
    WindowsStorageBackend? windowsStorageBackend,
  }) async {
    final useSsh =
        Platform.isAndroid ||
        (isSshMode && sshProfile != null && sshClientFactory != null);

    if (useSsh && sshProfile != null && sshClientFactory != null) {
      return _resolveSsh(
        profile: sshProfile,
        clientFactory: sshClientFactory,
        pathResolver:
            remotePathResolver ??
            RemoteSshStoragePathResolver(clientFactory: sshClientFactory),
      );
    }

    if (Platform.isWindows) {
      final backend = windowsStorageBackend ?? WindowsStorageBackend.native;
      return switch (backend) {
        WindowsStorageBackend.wsl => _resolveWsl(distro: wslDistro),
        WindowsStorageBackend.native => _resolveNative(
          appDataPath: nativeAppDataPath,
          home: nativeHome,
          cwd: nativeCwd,
        ),
      };
    }

    return _resolveNative(
      appDataPath: nativeAppDataPath,
      home: nativeHome,
      cwd: nativeCwd,
    );
  }

  static Future<RuntimeStorageContext> _resolveWsl({String? distro}) async {
    final trimmedDistro = distro?.trim();
    final distroKey = trimmedDistro ?? '';
    final fs = WslFilesystem(
      distro: trimmedDistro == null || trimmedDistro.isEmpty
          ? null
          : trimmedDistro,
    );
    final home = await _queryWslHome(
      distro: trimmedDistro == null || trimmedDistro.isEmpty
          ? null
          : trimmedDistro,
      distroKey: distroKey,
    );
    final appDataRoot = AppPaths.defaultTeampilotAppDataDirForHome(home);
    return RuntimeStorageContext._(
      mode: StorageBackendMode.wsl,
      filesystem: fs,
      home: home,
      cwd: home,
      appDataRoot: appDataRoot,
      paths: AppPaths(appDataRoot),
    );
  }

  static Future<RuntimeStorageContext> _resolveNative({
    required String appDataPath,
    String? home,
    String? cwd,
  }) {
    final root = appDataPath.trim();
    final pathCtx = AppPaths.pathContextForDataRoot(root);
    final fs = LocalFilesystem(pathContext: pathCtx);
    final resolvedHome =
        home?.trim().isNotEmpty == true
            ? home!.trim()
            : (Platform.environment['HOME'] ??
                Platform.environment['USERPROFILE'] ??
                root);
    final resolvedCwd =
        cwd?.trim().isNotEmpty == true ? cwd!.trim() : Directory.current.path;
    return Future.value(
      RuntimeStorageContext._(
        mode: StorageBackendMode.native,
        filesystem: fs,
        home: resolvedHome,
        cwd: resolvedCwd,
        appDataRoot: root,
        paths: AppPaths(root),
      ),
    );
  }

  static Future<RuntimeStorageContext> _resolveSsh({
    required SshProfile profile,
    required SshClientFactory clientFactory,
    required RemoteSshStoragePathResolver pathResolver,
  }) async {
    final paths = await pathResolver.resolve(profile);
    if (paths == null) {
      throw StateError('Failed to resolve remote SSH storage paths.');
    }

    final fileStore = RemoteFileStore(
      profile: profile,
      clientFactory: clientFactory,
    );
    await clientFactory.sftpFor(profile);

    final fs = SftpFilesystem(fileStore);
    return RuntimeStorageContext._(
      mode: StorageBackendMode.ssh,
      filesystem: fs,
      home: paths.home,
      cwd: paths.home,
      appDataRoot: paths.teampilotAppDir,
      paths: AppPaths(paths.teampilotAppDir),
    );
  }

  /// Lightweight check before selecting WSL storage or switching to it.
  static Future<bool> probeWslAvailable({String? distro}) async {
    if (!Platform.isWindows) return false;
    try {
      await _queryWslHome(
        distro: distro?.trim().isEmpty == true ? null : distro?.trim(),
        distroKey: distro?.trim() ?? '',
      );
      return true;
    } on Object {
      return false;
    }
  }

  static Future<String> _queryWslHome({
    String? distro,
    required String distroKey,
  }) async {
    if (_cachedWslHome != null && _cachedWslDistroKey == distroKey) {
      return _cachedWslHome!;
    }
    final args = <String>[];
    final trimmedDistro = distro?.trim();
    if (trimmedDistro != null && trimmedDistro.isNotEmpty) {
      args.addAll(['-d', trimmedDistro]);
    }
    args.addAll(['sh', '-lc', r'printf %s "$HOME"']);
    final result = await Process.run('wsl.exe', args);
    if (result.exitCode != 0) {
      throw StateError(
        'Failed to resolve WSL HOME (${result.exitCode}): ${result.stderr}',
      );
    }
    final home = (result.stdout as String)
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    if (home.isEmpty) {
      throw StateError('WSL HOME resolved to an empty path.');
    }
    _cachedWslHome = home;
    _cachedWslDistroKey = distroKey;
    return home;
  }

  /// Parses `-d distro` from a `wsl ...` executable launch line.
  static String? parseWslDistro(String? executable) {
    final trimmed = executable?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    final parts = trimmed.split(RegExp(r'\s+'));
    for (var i = 0; i < parts.length - 1; i++) {
      if (parts[i] == '-d' || parts[i] == '--distribution') {
        final distro = parts[i + 1].trim();
        return distro.isEmpty ? null : distro;
      }
    }
    return null;
  }

  @visibleForTesting
  static void installForTesting({
    required Filesystem filesystem,
    required AppPaths paths,
    StorageBackendMode mode = StorageBackendMode.native,
    String home = '/home/test',
    String cwd = '/home/test',
  }) {
    _current = RuntimeStorageContext._(
      mode: mode,
      filesystem: filesystem,
      home: home,
      cwd: cwd,
      appDataRoot: paths.basePath,
      paths: paths,
    );
    AppPathsBootstrapper.syncPaths(paths);
  }

  @visibleForTesting
  static void resetForTesting() {
    _current = null;
    _cachedWslHome = null;
    _cachedWslDistroKey = null;
  }
}
