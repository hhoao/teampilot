import '../../../models/runtime_target.dart';
import '../../../models/ssh_profile.dart';
import '../../ssh/ssh_client_factory.dart';
import '../../storage/runtime_context.dart';
import 'remote_bus_binding_resolver.dart';
import 'remote_bus_mount.dart';
import 'reverse_tunnel.dart';

/// Production [RemoteBusMountFactory] that builds a [RemoteBusMount] over a real
/// SSH reverse tunnel (P3b #1). DI is injected from app_shell; the only piece
/// that needs a live SSH host is `SshReverseTunnel.open()` (on-device smoke).
///
/// For a member's ssh [RuntimeTarget] it: resolves the [SshProfile], gets the
/// pooled [SSHClient], builds an [SshReverseTunnel] factory + remote command
/// runner + filesystem (from the target's [RuntimeContext]) + arch probe, and
/// wires them into a mount sharing the session's bus handler + HTTP port.
RemoteBusMountFactory sshRemoteBusMountFactory({
  required SshClientFactory sshClientFactory,
  required Future<SshProfile?> Function(String profileId) profileById,
  required Future<RuntimeContext> Function(RuntimeTarget target) contextForTarget,
}) {
  return ({required memberTarget, required busServer}) async {
    final profileId = memberTarget.sshProfileId ?? '';
    final profile = await profileById(profileId);
    if (profile == null) {
      throw StateError(
        'No SSH profile "$profileId" for remote member target '
        '"${memberTarget.id}"; cannot open the bus reverse tunnel.',
      );
    }
    final client = await sshClientFactory.clientFor(profile);
    final ctx = await contextForTarget(memberTarget);

    Future<String> run(String command) async {
      final out = await client.run(command);
      return String.fromCharCodes(out).trim();
    }

    return RemoteBusMount(
      handler: busServer.handler,
      httpBusPort: busServer.port,
      tunnelFactory: () => SshReverseTunnel(client),
      remoteFs: ctx.fs,
      remoteRun: run,
      arch: _archFromUname(await run('uname -m')),
    );
  };
}

/// Maps `uname -m` to the relay bundle arch keys (linux-only this round).
String _archFromUname(String unameM) {
  final m = unameM.trim().toLowerCase();
  return switch (m) {
    'x86_64' || 'amd64' => 'linux-x64',
    'aarch64' || 'arm64' => 'linux-arm64',
    _ => m, // unsupported → RelayProvisioner falls back / errors clearly
  };
}
