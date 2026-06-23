import 'dart:io';

import '../../models/runtime_target.dart';
import '../../models/ssh_profile.dart';
import '../io/local_filesystem.dart';
import '../io/sftp_filesystem.dart';
import '../io/wsl_filesystem.dart';
import '../ssh/ssh_client_factory.dart';
import 'app_storage.dart';
import 'remote_file_store.dart';
import 'remote_ssh_storage_paths.dart';
import 'runtime_context.dart';

/// Materializes a [RuntimeContext] for a [RuntimeTarget]. This is the platform
/// branch logic extracted from the old global resolve(), with
/// the input changed from scattered flags to a concrete target.
class RuntimeContextResolver {
  RuntimeContextResolver({
    this.sshClientFactory,
    this.remotePathResolver,
    required this.nativeAppDataPath,
    this.nativeHome,
    this.nativeCwd,
  });

  final SshClientFactory? sshClientFactory;
  final RemoteSshStoragePathResolver? remotePathResolver;
  final String nativeAppDataPath;
  final String? nativeHome;
  final String? nativeCwd;

  static String? _cachedWslHome;
  static String? _cachedWslDistroKey;

  Future<RuntimeContext> resolve(
    RuntimeTarget target, {
    SshProfile? sshProfile,
  }) async {
    final useSsh =
        Platform.isAndroid ||
        (target.kind == RuntimeKind.ssh &&
            sshProfile != null &&
            sshClientFactory != null);

    if (useSsh && sshProfile != null && sshClientFactory != null) {
      return _resolveSsh(
        target,
        profile: sshProfile,
        clientFactory: sshClientFactory!,
        pathResolver:
            remotePathResolver ??
            RemoteSshStoragePathResolver(clientFactory: sshClientFactory!),
      );
    }

    if (Platform.isWindows && target.kind == RuntimeKind.wsl) {
      return _resolveWsl(target);
    }

    return _resolveNative(target);
  }

  Future<RuntimeContext> _resolveNative(RuntimeTarget target) {
    final root = nativeAppDataPath.trim();
    final pathCtx = AppPaths.pathContextForDataRoot(root);
    final fs = LocalFilesystem(pathContext: pathCtx);
    final resolvedHome = nativeHome?.trim().isNotEmpty == true
        ? nativeHome!.trim()
        : (Platform.environment['HOME'] ??
              Platform.environment['USERPROFILE'] ??
              root);
    final resolvedCwd = nativeCwd?.trim().isNotEmpty == true
        ? nativeCwd!.trim()
        : Directory.current.path;
    return Future.value(
      RuntimeContext(
        target: target,
        filesystem: fs,
        home: resolvedHome,
        cwd: resolvedCwd,
        appDataRoot: root,
        paths: AppPaths(root),
      ),
    );
  }

  Future<RuntimeContext> _resolveWsl(RuntimeTarget target) async {
    final trimmedDistro = target.wslDistro?.trim();
    final distroKey = trimmedDistro ?? '';
    final distro = trimmedDistro == null || trimmedDistro.isEmpty
        ? null
        : trimmedDistro;
    final fs = WslFilesystem(distro: distro);
    final home = await _queryWslHome(distro: distro, distroKey: distroKey);
    final appDataRoot = AppPaths.defaultTeampilotAppDataDirForHome(home);
    return RuntimeContext(
      target: target,
      filesystem: fs,
      home: home,
      cwd: home,
      appDataRoot: appDataRoot,
      paths: AppPaths(appDataRoot),
    );
  }

  Future<RuntimeContext> _resolveSsh(
    RuntimeTarget target, {
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
    return RuntimeContext(
      target: target,
      filesystem: fs,
      home: paths.home,
      cwd: paths.home,
      appDataRoot: paths.teampilotAppDir,
      paths: AppPaths(paths.teampilotAppDir),
    );
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
}
