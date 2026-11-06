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
    await servers.save(SshServerProfile(
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
    ));
    await targets.save(target.copyWith(pendingSync: false));
  }

  Future<RemoteTarget> pull(RemoteTarget target) async {
    final server = await servers.findById(target.id);
    if (server == null) return target;
    if (server.updatedAt <= target.updatedAt) return target;
    final merged = target.copyWith(
      name: server.name,
      host: server.host,
      port: server.port,
      username: server.username,
      authType: server.authType,
      embeddedTarget: server.embeddedTarget,
      relayUrl: server.relayUrl,
      pairedDesktopId: server.pairedDesktopId,
      updatedAt: server.updatedAt,
    );
    await targets.save(merged);
    appLogger.d('[remote-target-sync] pulled ${target.id}');
    return merged;
  }
}
