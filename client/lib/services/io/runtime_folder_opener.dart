import 'dart:io';

import '../../models/runtime_target.dart';
import '../remote/remote_os_prober.dart';
import '../storage/remote_file_store.dart';
import '../storage/runtime_context.dart';
import 'system_folder_opener.dart';

typedef WslProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Opens a directory in the OS file manager for a [RuntimeContext] — local,
/// WSL, or SSH (runs `xdg-open` / `open` / `explorer` on the remote host).
class RuntimeFolderOpener {
  RuntimeFolderOpener({
    SystemFolderOpener? localOpener,
    RemoteOsProber? osProber,
    WslProcessRunner? wslRunner,
  })  : _localOpener = localOpener ?? SystemFolderOpener(),
        _osProber = osProber ?? const RemoteOsProber(),
        _wslRunner = wslRunner ?? Process.run;

  final SystemFolderOpener _localOpener;
  final RemoteOsProber _osProber;
  final WslProcessRunner _wslRunner;

  Future<bool> reveal({
    required String path,
    RuntimeContext? workContext,
  }) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return false;

    final ctx = workContext;
    if (ctx == null) {
      await _localOpener.reveal(trimmed);
      return true;
    }

    return switch (ctx.mode) {
      StorageBackendMode.native => () async {
        await _localOpener.reveal(trimmed);
        return true;
      }(),
      StorageBackendMode.wsl => _revealWsl(ctx, trimmed),
      StorageBackendMode.ssh => _revealSsh(ctx, trimmed),
    };
  }

  Future<bool> _revealWsl(RuntimeContext ctx, String path) async {
    final distro = ctx.target.wslDistro?.trim();
    final args = <String>[
      if (distro != null && distro.isNotEmpty) ...['-d', distro],
      'xdg-open',
      '--',
      path,
    ];
    try {
      final result = await _wslRunner('wsl.exe', args);
      return result.exitCode == 0;
    } on Object {
      return false;
    }
  }

  Future<bool> _revealSsh(RuntimeContext ctx, String path) async {
    final store = ctx.remoteFileStore;
    if (store == null) return false;

    var remoteOs = ctx.target.remoteOs;
    remoteOs ??= await _osProber.probe(store.runRemoteCommand);

    return store.revealInFileManager(path, remoteOs: remoteOs);
  }
}
