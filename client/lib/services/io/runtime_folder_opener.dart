import 'dart:io';

import '../host/host_one_shot_runner.dart';
import '../host/host_one_shot_runner_for_context.dart';
import '../remote/remote_os_prober.dart';
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
    HostOneShotRunner Function(RuntimeContext ctx)? oneShotRunnerForContext,
  })  : _localOpener = localOpener ?? SystemFolderOpener(),
        _osProber = osProber ?? const RemoteOsProber(),
        _wslRunner = wslRunner,
        _oneShotRunnerForContext = oneShotRunnerForContext;

  final SystemFolderOpener _localOpener;
  final RemoteOsProber _osProber;
  final WslProcessRunner? _wslRunner;
  final HostOneShotRunner Function(RuntimeContext ctx)? _oneShotRunnerForContext;

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
    final runner = _oneShotRunnerForContext?.call(ctx) ?? _wslOneShotRunner(ctx);
    try {
      final result = await runner.run(
        HostRunRequest(
          executable: 'xdg-open',
          arguments: ['--', path],
        ),
      );
      return result.succeeded;
    } on Object {
      return false;
    }
  }

  HostOneShotRunner _wslOneShotRunner(RuntimeContext ctx) {
    final inject = _wslRunner;
    if (inject != null) {
      return WslHostOneShotRunner(
        distro: ctx.target.wslDistro,
        processRunner: (executable, arguments, {workingDirectory, environment, includeParentEnvironment = true, stdoutEncoding, stderrEncoding}) {
          return inject(executable, arguments);
        },
      );
    }
    return hostOneShotRunnerForContext(ctx);
  }

  Future<bool> _revealSsh(RuntimeContext ctx, String path) async {
    final store = ctx.remoteFileStore;
    if (store == null) return false;

    var remoteOs = ctx.target.remoteOs;
    remoteOs ??= await _osProber.probe(store.runRemoteCommand);

    return store.revealInFileManager(path, remoteOs: remoteOs);
  }
}
