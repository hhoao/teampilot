import '../storage/runtime_context.dart';
import 'host_one_shot_runner.dart';

/// Picks the runner for the active [RuntimeContext] storage backend.
HostOneShotRunner hostOneShotRunnerForContext(RuntimeContext ctx) {
  return switch (ctx.mode) {
    StorageBackendMode.ssh => RemoteHostOneShotRunner(
      execShell: ctx.remoteFileStore!.execShell,
    ),
    StorageBackendMode.wsl => WslHostOneShotRunner(
      distro: ctx.target.wslDistro,
    ),
    StorageBackendMode.native => LocalHostOneShotRunner(),
  };
}
