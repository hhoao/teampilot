import '../../models/remote_target.dart';
import '../../models/ssh_server_profile.dart';
import '../../repositories/remote_target_repository.dart';
import '../../repositories/ssh_server_profile_repository.dart';
import '../../utils/logging/logger.dart';

class RemoteTargetSync {
  const RemoteTargetSync({required this.targets, required this.servers});

  final RemoteTargetRepository targets;
  final SshServerProfileRepository servers;

  Future<void> push(RemoteTarget target) async {
    await servers.save(
      SshServerProfile(
        id: target.id,
        name: target.name,
        host: target.host,
        port: target.port,
        username: target.username,
        authType: target.authType,
        embeddedTarget: target.embeddedTarget,
        relayUrl: target.relayUrl,
        pairedDesktopId: target.pairedDesktopId,
        updatedAt: target.updatedAt,
      ),
    );
    await targets.save(target.copyWith(pendingSync: false));
  }

  Future<RemoteTarget> pull(RemoteTarget target) async {
    final server = await servers.findById(target.id);
    if (server == null) return target;
    if (server.updatedAt <= target.updatedAt) return target;
    // Build explicitly rather than with copyWith: copyWith's `x ?? this.x`
    // ignores a remote `null`, so a newer server that clears relayUrl or
    // pairedDesktopId would otherwise leave the stale local value. Connection
    // fields come from [server] (including its nulls); every local-only field
    // is carried over untouched from [target] so credentials never sync and
    // pull never clears pendingSync.
    final merged = RemoteTarget(
      id: target.id,
      name: server.name,
      host: server.host,
      port: server.port,
      username: server.username,
      authType: server.authType,
      vaultEntryId: target.vaultEntryId,
      endpoints: target.endpoints,
      hostKeyFingerprints: target.hostKeyFingerprints,
      lastGoodKind: target.lastGoodKind,
      lastHome: target.lastHome,
      lastAppDataRoot: target.lastAppDataRoot,
      embeddedTarget: server.embeddedTarget,
      relayUrl: server.relayUrl,
      pairedDesktopId: server.pairedDesktopId,
      updatedAt: server.updatedAt,
      pendingSync: target.pendingSync,
    );
    await targets.save(merged);
    appLogger.d('[remote-target-sync] pulled ${target.id}');
    return merged;
  }
}
