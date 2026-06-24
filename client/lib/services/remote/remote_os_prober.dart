import '../../models/runtime_target.dart';
import '../team_bus/remote/relay_provisioner.dart' show RemoteCommandRunner;

/// P3e §3: detect a freshly-connected SSH host's OS family so the rest of the
/// remote stack can branch (relay selection, symlink→copy inheritance, login
/// shell / path semantics). The result is cached on `RuntimeTarget.remoteOs`,
/// so this runs once per connect, not per command.
///
/// Detection is order-sensitive and side-effect free (read-only probes):
/// 1. `uname -s` — any non-empty answer means a POSIX shell (Linux/Darwin/BSD).
/// 2. `echo %OS%` — Windows `cmd` expands `%OS%` to `Windows_NT`.
/// 3. `ver` — Windows reports a `Microsoft Windows [Version …]` banner.
/// 4. Fallback: POSIX (the overwhelmingly common remote, and the safe default
///    since the POSIX paths are the most exercised).
class RemoteOsProber {
  const RemoteOsProber();

  Future<RemoteOs> probe(RemoteCommandRunner run) async {
    final uname = (await run('uname -s')).trim();
    if (uname.isNotEmpty) return RemoteOs.posix;

    final osVar = (await run('echo %OS%')).trim().toLowerCase();
    if (osVar.contains('windows')) return RemoteOs.windows;

    final ver = (await run('ver')).trim().toLowerCase();
    if (ver.contains('windows')) return RemoteOs.windows;

    return RemoteOs.posix;
  }
}
