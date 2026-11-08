import '../models/ssh_profile.dart';
import '../models/ssh_server_profile.dart';
import 'ssh_profile_repository.dart';
import 'ssh_server_profile_repository.dart';

/// [SshProfileRepository] over the shared home-plane server catalog.
///
/// Reads merge the plane's own `remote-targets.json` with the synced
/// `ssh_profiles/profiles.json`; writes go to the projection, the record every
/// device paired to the plane shares. Profile selection stays a device concern,
/// so it is never persisted on the plane.
///
/// This is what the "SSH servers" settings surface binds to, which keeps that
/// page showing the plane's servers rather than this device's targets.
class PlaneSshProfileRepository extends SshProfileRepository {
  PlaneSshProfileRepository({
    required super.storage,
    required SshServerProfileRepository servers,
  }) : _servers = servers;

  final SshServerProfileRepository _servers;

  @override
  Future<List<SshProfile>> loadAll() async => [
    for (final server in await _servers.loadAll()) _toProfile(server),
  ];

  @override
  Future<SshProfile?> findById(String profileId) async {
    for (final profile in await loadAll()) {
      if (profile.id == profileId) return profile;
    }
    return null;
  }

  @override
  Future<void> save(SshProfile profile) => _servers.save(_toServer(profile));

  @override
  Future<void> saveAll(List<SshProfile> profiles) async {
    for (final profile in profiles) {
      await _servers.save(_toServer(profile));
    }
  }

  @override
  Future<void> delete(String profileId) => _servers.delete(profileId);

  @override
  Future<String> loadSelectedProfileId() async => '';

  @override
  Future<void> saveSelectedProfileId(String profileId) async {}

  static SshProfile _toProfile(SshServerProfile server) => SshProfile(
    id: server.id,
    name: server.name,
    host: server.host,
    port: server.port,
    username: server.username,
    authType: server.authType,
    createdAt: server.updatedAt,
    updatedAt: server.updatedAt,
    embeddedTarget: server.embeddedTarget,
    relayUrl: server.relayUrl,
    pairedDesktopId: server.pairedDesktopId,
  );

  static SshServerProfile _toServer(SshProfile profile) => SshServerProfile(
    id: profile.id,
    name: profile.name,
    host: profile.host,
    port: profile.port,
    username: profile.username,
    authType: profile.authType,
    embeddedTarget: profile.embeddedTarget,
    relayUrl: profile.relayUrl,
    pairedDesktopId: profile.pairedDesktopId,
    updatedAt: profile.updatedAt,
  );
}
