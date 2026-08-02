import '../storage/runtime_context.dart';
import 'host_process_starter.dart';

/// Picks the streaming process starter for the active [RuntimeContext] backend.
HostProcessStarter hostProcessStarterForContext(RuntimeContext ctx) {
  return switch (ctx.mode) {
    StorageBackendMode.ssh => RemoteHostProcessStarter(
      startShell: ctx.remoteFileStore!.startShell,
    ),
    StorageBackendMode.wsl => WslHostProcessStarter(
      distro: ctx.target.wslDistro,
    ),
    StorageBackendMode.native => LocalHostProcessStarter(),
  };
}
